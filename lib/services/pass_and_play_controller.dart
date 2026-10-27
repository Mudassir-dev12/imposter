import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/protocol_models.dart';
import 'game_client.dart';
import 'host_service.dart';

/// Orchestrates an offline Pass & Play game session on a single device.
///
/// Connects one local [GameClient] per player to the embedded Python server
/// over 127.0.0.1. Reuses the full Python game engine, rules, and secrecy filters
/// with zero duplicated game logic in Dart.
class PassAndPlayController extends ChangeNotifier {
  final List<String> playerNames;
  final GameSettingsModel settings;
  final HostService _hostService;
  final GameClient Function()? clientFactory;

  final List<GameClient> _clients = [];
  final List<StreamSubscription> _subscriptions = [];

  String? _roomCode;
  int _activePrivatePlayerIndex = 0;
  bool _isPrivateContentRevealed = false;
  bool _isInitializing = false;
  bool _isDisposed = false;
  String? _errorMessage;

  PassAndPlayController({
    required this.playerNames,
    required this.settings,
    HostService? hostService,
    this.clientFactory,
  }) : _hostService = hostService ?? HostService();

  // Getters
  List<GameClient> get clients => List.unmodifiable(_clients);
  int get activePrivatePlayerIndex => _activePrivatePlayerIndex;
  bool get isPrivateContentRevealed => _isPrivateContentRevealed;
  bool get isInitializing => _isInitializing;
  String? get errorMessage => _errorMessage;
  String? get roomCode => _roomCode;

  /// Returns the room state from the primary/host client (or active client).
  RoomStateModel? get primaryState {
    if (_clients.isEmpty) return null;
    return _clients[0].state;
  }

  /// Current game phase string reported by the server.
  String get currentPhase => primaryState?.phase ?? 'LOBBY';

  bool get isRoleReveal => currentPhase == 'ROLE_REVEAL';
  bool get isClueRound => currentPhase == 'CLUE_ROUND';
  bool get isDiscussion => currentPhase == 'DISCUSSION';
  bool get isVoting => currentPhase == 'VOTING';
  bool get isImpostorGuess => currentPhase == 'IMPOSTOR_GUESS';
  bool get isResult =>
      currentPhase == 'RESULT' ||
      currentPhase == 'ROUND_END' ||
      currentPhase == 'GAME_OVER';

  /// Current active private player's name.
  String get activePrivatePlayerName {
    if (_activePrivatePlayerIndex >= 0 &&
        _activePrivatePlayerIndex < playerNames.length) {
      return playerNames[_activePrivatePlayerIndex];
    }
    return '';
  }

  /// Current active private player's client.
  GameClient? get activePrivateClient {
    if (_activePrivatePlayerIndex >= 0 &&
        _activePrivatePlayerIndex < _clients.length) {
      return _clients[_activePrivatePlayerIndex];
    }
    return null;
  }

  /// Active private player's filtered room state (enforcing engine secrecy).
  RoomStateModel? get activePrivateState => activePrivateClient?.state;

  /// Returns client corresponding to a player ID.
  GameClient? clientForId(String playerId) {
    for (final c in _clients) {
      if (c.state?.myId == playerId) return c;
    }
    return null;
  }

  /// Returns player name corresponding to a player ID.
  String playerNameForId(String playerId) {
    for (int i = 0; i < _clients.length; i++) {
      if (_clients[i].state?.myId == playerId) {
        return playerNames[i];
      }
    }
    final player =
        primaryState?.players.where((p) => p.id == playerId).firstOrNull;
    return player?.name ?? playerId;
  }

  /// Index of the caught impostor for the IMPOSTOR_GUESS phase.
  int get caughtImpostorIndex {
    final caughtId = primaryState?.caughtImpostorId;
    if (caughtId == null) return 0;
    for (int i = 0; i < _clients.length; i++) {
      if (_clients[i].state?.myId == caughtId) return i;
    }
    return 0;
  }

  /// Starts the embedded server on loopback, creates room, joins all local players,
  /// and starts the game.
  Future<void> startSession({
    String serverUrl = 'ws://127.0.0.1:8765',
    bool startEmbeddedServer = true,
  }) async {
    _isInitializing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (startEmbeddedServer) {
        // Ensure Python supervisor and GameServer are listening on 127.0.0.1:8765
        await _hostService.ensureServerRunning();
      }

      // 1. Connect host player (player 0) and create room
      final hostClient = clientFactory != null ? clientFactory!() : GameClient();
      _clients.add(hostClient);
      await hostClient.connect(serverUrl);
      await hostClient.createRoom(playerNames[0], settings: settings);

      // Wait until room code is available
      final completer = Completer<String>();
      late StreamSubscription sub;
      sub = hostClient.stateStream.listen((state) {
        if (state.roomCode.isNotEmpty && !completer.isCompleted) {
          completer.complete(state.roomCode);
        }
      });
      _roomCode = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Room creation timed out'),
      );
      await sub.cancel();

      // 2. Connect and join remaining players
      for (int i = 1; i < playerNames.length; i++) {
        final client = clientFactory != null ? clientFactory!() : GameClient();
        _clients.add(client);
        await client.connect(serverUrl);
        await client.joinRoom(_roomCode!, playerNames[i]);
      }

      // Wait until all players are registered in room state
      final allJoinedCompleter = Completer<void>();
      late StreamSubscription joinSub;
      joinSub = hostClient.stateStream.listen((state) {
        if (state.players.length >= playerNames.length &&
            !allJoinedCompleter.isCompleted) {
          allJoinedCompleter.complete();
        }
      });
      await allJoinedCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Player join timed out'),
      );
      await joinSub.cancel();

      // 3. Listen to state updates from all clients
      for (int i = 0; i < _clients.length; i++) {
        final client = _clients[i];
        final s = client.stateStream.listen((state) {
          _onClientStateUpdated(client, state);
        });
        _subscriptions.add(s);
      }

      // 4. Start game
      await hostClient.startGame();
      _activePrivatePlayerIndex = 0;
      _isPrivateContentRevealed = false;
    } catch (e) {
      _errorMessage = e.toString();
      debugPrint('PassAndPlayController startup error: $e');
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  void _onClientStateUpdated(GameClient client, RoomStateModel state) {
    if (_isDisposed) return;

    // Check if phase transitioned to VOTING and reset private index
    if (state.phase == 'VOTING' &&
        _activePrivatePlayerIndex >= playerNames.length) {
      _activePrivatePlayerIndex = 0;
      _isPrivateContentRevealed = false;
    }

    notifyListeners();
  }

  // =========================================================================
  // Privacy Safety Controls
  // =========================================================================

  /// Immediately hides private content. Called when app is paused/backgrounded,
  /// or when device orientation changes.
  void lockPrivateContent() {
    if (_isPrivateContentRevealed) {
      _isPrivateContentRevealed = false;
      notifyListeners();
    }
  }

  /// Reveals private content after player presses "I am &lt;Name&gt;".
  void revealPrivateContent() {
    _isPrivateContentRevealed = true;
    notifyListeners();
  }

  // =========================================================================
  // Phase Interactions
  // =========================================================================

  /// Confirms role seen for current private player, then advances to next player.
  Future<void> confirmRoleSeen() async {
    final client = activePrivateClient;
    if (client == null) return;

    await client.confirmRoleSeen();

    if (_activePrivatePlayerIndex + 1 < _clients.length) {
      _activePrivatePlayerIndex++;
      _isPrivateContentRevealed = false;
    } else {
      // All confirmed; server will transition to CLUE_ROUND
      _activePrivatePlayerIndex = 0;
      _isPrivateContentRevealed = false;
    }
    notifyListeners();
  }

  /// Ends the active player's turn in spoken_clues mode.
  Future<void> endTurn() async {
    final activeId = primaryState?.currentTurnPlayerId;
    if (activeId == null) return;

    final activeClient = clientForId(activeId);
    if (activeClient != null) {
      await activeClient.endTurn();
    }
  }

  /// Skips the discussion phase.
  Future<void> skipDiscussion() async {
    if (_clients.isNotEmpty) {
      await _clients[0].skipDiscussion();
    }
  }

  /// Submits a secret vote for the current private player, then advances to next voter.
  Future<void> castVote(String? targetId) async {
    final client = activePrivateClient;
    if (client == null) return;

    await client.castVote(targetId);

    // Advance to next player
    final nextIndex = _activePrivatePlayerIndex + 1;
    _activePrivatePlayerIndex = nextIndex;
    _isPrivateContentRevealed = false;
    notifyListeners();
  }

  /// Submits the impostor's guess during IMPOSTOR_GUESS phase.
  Future<void> submitImpostorGuess(String word) async {
    final caughtId = primaryState?.caughtImpostorId;
    if (caughtId == null) return;

    final caughtClient = clientForId(caughtId);
    if (caughtClient != null) {
      await caughtClient.submitImpostorGuess(word);
    }
  }

  /// Starts a new round with the same players and cumulative scores.
  Future<void> playAgain() async {
    if (_clients.isNotEmpty) {
      await _clients[0].playAgain();
      _activePrivatePlayerIndex = 0;
      _isPrivateContentRevealed = false;
      notifyListeners();
    }
  }

  /// Cleans up all connections and shuts down the embedded server.
  Future<void> disposeSession({bool stopEmbeddedServer = true}) async {
    _isDisposed = true;
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();

    for (final c in _clients) {
      c.dispose();
    }
    _clients.clear();

    if (stopEmbeddedServer) {
      await _hostService.stopServer();
    }
  }

  @override
  void dispose() {
    disposeSession();
    super.dispose();
  }
}
