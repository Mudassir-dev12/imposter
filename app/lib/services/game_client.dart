import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/constants.dart';
import '../models/protocol_models.dart';

enum ConnectionStatus { disconnected, connecting, connected, reconnecting }

typedef ChannelFactory = WebSocketChannel Function(Uri uri);

class GameClient {
  final ChannelFactory _channelFactory;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _manualDisconnect = false;
  int _reqIdCounter = 0;

  // Connection metadata
  String? _serverAddress;
  String? _currentRoomCode;
  String? _currentPlayerId;
  String? _currentToken;
  bool _isHost = false;
  RoomStateModel? _latestRoomState;

  // Stream Controllers
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _roomStateController = StreamController<RoomStateModel?>.broadcast();
  final _roomJoinedController = StreamController<RoomJoinedModel>.broadcast();
  final _errorController = StreamController<ErrorMessageModel>.broadcast();
  final _cluePostedController = StreamController<CluePostedModel>.broadcast();
  final _roomClosedController = StreamController<RoomClosedModel>.broadcast();

  ConnectionStatus _status = ConnectionStatus.disconnected;

  GameClient({ChannelFactory? channelFactory})
    : _channelFactory =
          channelFactory ?? ((uri) => WebSocketChannel.connect(uri));

  ConnectionStatus get status => _status;
  String? get serverAddress => _serverAddress;
  String? get currentRoomCode => _currentRoomCode;
  String? get currentPlayerId => _currentPlayerId;
  String? get currentToken => _currentToken;
  bool get isHost => _isHost;
  RoomStateModel? get latestRoomState => _latestRoomState;
  RoomStateModel? get state => _latestRoomState;

  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  Stream<RoomStateModel?> get roomStateStream => _roomStateController.stream;
  Stream<RoomStateModel> get stateStream =>
      _roomStateController.stream.where((s) => s != null).cast<RoomStateModel>();
  Stream<RoomJoinedModel> get roomJoinedStream => _roomJoinedController.stream;
  Stream<ErrorMessageModel> get errorStream => _errorController.stream;
  Stream<CluePostedModel> get cluePostedStream => _cluePostedController.stream;
  Stream<RoomClosedModel> get roomClosedStream => _roomClosedController.stream;

  void _setStatus(ConnectionStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      _statusController.add(newStatus);
    }
  }

  String _nextReqId() => 'req_${++_reqIdCounter}';

  /// Connect to the specified WebSocket server (e.g. "192.168.1.10:8765" or "10.0.2.2:8765").
  Future<void> connect(String serverAddress) async {
    _serverAddress = serverAddress;
    _manualDisconnect = false;
    _reconnectAttempts = 0;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefServerAddress, serverAddress);

    await _initSocket();
  }

  Future<void> _initSocket() async {
    if (_status == ConnectionStatus.connected) return;

    if (_status != ConnectionStatus.reconnecting) {
      _setStatus(ConnectionStatus.connecting);
    }

    // Format URI: add ws:// if missing
    var rawAddress = _serverAddress ?? AppConstants.defaultServerAddress;
    if (!rawAddress.startsWith('ws://') && !rawAddress.startsWith('wss://')) {
      rawAddress = 'ws://$rawAddress';
    }

    try {
      final uri = Uri.parse(rawAddress);
      _channel = _channelFactory(uri);

      // Await connection handshake
      await _channel!.ready;

      _channelSub = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: true,
      );

      _setStatus(ConnectionStatus.connected);
      _reconnectAttempts = 0;
      _startPingTimer();

      // If we have saved credentials, auto-rejoin
      if (_currentRoomCode != null &&
          _currentPlayerId != null &&
          _currentToken != null) {
        await rejoin(_currentRoomCode!, _currentPlayerId!, _currentToken!);
      }
    } catch (e) {
      debugPrint('[GameClient] Connection failed: $e');
      _handleDisconnect();
      rethrow;
    }
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      sendJson('ping', {});
    });
  }

  void _onMessage(dynamic raw) {
    try {
      final jsonMap = json.decode(raw as String) as Map<String, dynamic>;
      final type = jsonMap['type'] as String?;
      final data = jsonMap['data'] as Map<String, dynamic>? ?? {};

      switch (type) {
        case 'room_joined':
          final model = RoomJoinedModel.fromJson(data);
          _currentRoomCode = model.code;
          _currentPlayerId = model.playerId;
          _currentToken = model.token;
          _isHost = model.isHost;
          _saveSessionCredentials();
          _roomJoinedController.add(model);
          break;

        case 'room_state':
          final model = RoomStateModel.fromJson(data);
          _latestRoomState = model;
          _roomStateController.add(model);
          break;

        case 'clue_posted':
          final model = CluePostedModel.fromJson(data);
          _cluePostedController.add(model);
          break;

        case 'room_closed':
          final model = RoomClosedModel.fromJson(data);
          _latestRoomState = null;
          _clearSessionCredentials();
          _roomStateController.add(null);
          _roomClosedController.add(model);
          break;

        case 'error':
          final model = ErrorMessageModel.fromJson(data);
          _errorController.add(model);
          break;

        case 'pong':
          // Heartbeat response
          break;
      }
    } catch (e) {
      debugPrint('[GameClient] Error parsing message: $e');
    }
  }

  void _onError(dynamic error) {
    debugPrint('[GameClient] WebSocket error: $error');
    _handleDisconnect();
  }

  void _onDone() {
    debugPrint('[GameClient] WebSocket closed');
    _handleDisconnect();
  }

  void _handleDisconnect() {
    _pingTimer?.cancel();
    _channelSub?.cancel();
    _channelSub = null;
    _channel = null;

    if (_manualDisconnect) {
      _setStatus(ConnectionStatus.disconnected);
      return;
    }

    // If we were in a room, attempt exponential backoff reconnection
    if (_currentRoomCode != null && _currentPlayerId != null) {
      _setStatus(ConnectionStatus.reconnecting);
      _scheduleReconnect();
    } else {
      _setStatus(ConnectionStatus.disconnected);
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    // Exponential backoff: 1s, 2s, 4s, max 10s + jitter
    final backoffSec = min(10, pow(2, _reconnectAttempts - 1).toInt());
    final delay = Duration(seconds: backoffSec);

    debugPrint(
      '[GameClient] Scheduling reconnect attempt $_reconnectAttempts in $delay',
    );
    _reconnectTimer = Timer(delay, () {
      _initSocket();
    });
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    await _channelSub?.cancel();
    await _channel?.sink.close();
    _channelSub = null;
    _channel = null;
    _setStatus(ConnectionStatus.disconnected);
  }

  Future<void> sendJson(
    String type,
    Map<String, dynamic> data, {
    String? id,
  }) async {
    if (_status != ConnectionStatus.connected || _channel == null) {
      debugPrint('[GameClient] Cannot send $type: client is not connected');
      return;
    }

    final payload = {
      'type': type,
      if (id != null) 'id': id else 'id': _nextReqId(),
      'data': data,
    };
    _channel!.sink.add(json.encode(payload));
  }

  // =========================================================================
  // Game Actions
  // =========================================================================

  Future<void> createRoom(String name, {GameSettingsModel? settings}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefPlayerName, name);

    await sendJson('create_room', {
      'name': name,
      if (settings != null) 'settings': settings.toJson(),
    });
  }

  Future<void> joinRoom(String code, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefPlayerName, name);

    await sendJson('join_room', {
      'code': code.toUpperCase().trim(),
      'name': name.trim(),
    });
  }

  Future<void> rejoin(String code, String playerId, String token) async {
    await sendJson('rejoin', {
      'code': code.toUpperCase().trim(),
      'player_id': playerId,
      'token': token,
    });
  }

  Future<void> updateSettings(GameSettingsModel settings) async {
    await sendJson('update_settings', {'settings': settings.toJson()});
  }

  Future<void> startGame() async {
    await sendJson('start_game', {});
  }

  Future<void> confirmRoleSeen() async {
    await sendJson('confirm_role_seen', {});
  }

  Future<void> submitClue(String word) async {
    await sendJson('submit_clue', {'word': word.trim()});
  }

  Future<void> endTurn() async {
    await sendJson('end_turn', {});
  }

  Future<void> skipDiscussion() async {
    await sendJson('skip_discussion', {});
  }

  Future<void> castVote(String? targetId) async {
    await sendJson('cast_vote', {'target_id': targetId});
  }

  Future<void> submitImpostorGuess(String word) async {
    await sendJson('impostor_guess', {'word': word.trim()});
  }

  Future<void> playAgain() async {
    await sendJson('play_again', {});
  }

  Future<void> kickPlayer(String targetPlayerId) async {
    await sendJson('kick_player', {'player_id': targetPlayerId});
  }

  Future<void> leaveRoom() async {
    await sendJson('leave', {});
    _clearSessionCredentials();
    _currentRoomCode = null;
    _currentPlayerId = null;
    _currentToken = null;
    _isHost = false;
    _latestRoomState = null;
    _roomStateController.add(null);
  }

  // =========================================================================
  // Persistence Helpers
  // =========================================================================

  Future<void> _saveSessionCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_currentRoomCode != null) {
      await prefs.setString(AppConstants.prefLastRoomCode, _currentRoomCode!);
    }
    if (_currentPlayerId != null) {
      await prefs.setString(AppConstants.prefLastPlayerId, _currentPlayerId!);
    }
    if (_currentToken != null) {
      await prefs.setString(AppConstants.prefLastToken, _currentToken!);
    }
  }

  Future<void> _clearSessionCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.prefLastRoomCode);
    await prefs.remove(AppConstants.prefLastPlayerId);
    await prefs.remove(AppConstants.prefLastToken);
  }

  Future<bool> tryRestoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(AppConstants.prefLastRoomCode);
    final playerId = prefs.getString(AppConstants.prefLastPlayerId);
    final token = prefs.getString(AppConstants.prefLastToken);
    final address =
        prefs.getString(AppConstants.prefServerAddress) ??
        AppConstants.defaultServerAddress;

    if (code != null && playerId != null && token != null) {
      _currentRoomCode = code;
      _currentPlayerId = playerId;
      _currentToken = token;
      await connect(address);
      return true;
    }
    return false;
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _channelSub?.cancel();
    _channel?.sink.close();
    _statusController.close();
    _roomStateController.close();
    _roomJoinedController.close();
    _errorController.close();
    _cluePostedController.close();
    _roomClosedController.close();
  }
}
