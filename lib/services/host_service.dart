import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';
import 'package:serious_python/serious_python.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'host_control_client.dart';
import 'network_ip_helper.dart';

export 'host_control_client.dart' show ServerStatus, ControlChannelException;

/// Top-level callback required by flutter_foreground_task.
@pragma('vm:entry-point')
void startForegroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(ImpostorHostTaskHandler());
}

/// TaskHandler for keeping the foreground notification alive while hosting.
class ImpostorHostTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // When notification is dismissed or foreground service destroyed,
    // send best-effort STOP to prevent zombie Python server listening on network.
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('control_token');
      final port = prefs.getInt('control_port') ?? HostService.defaultControlPort;
      if (token != null && token.isNotEmpty) {
        final client = HostControlClient(port: port, token: token);
        await client.stopServer(timeout: const Duration(seconds: 2));
      }
    } catch (e) {
      debugPrint('ImpostorHostTaskHandler onDestroy cleanup error: $e');
    }
  }
}

class HostService with WidgetsBindingObserver {
  static final HostService _instance = HostService._internal();
  factory HostService() => _instance;

  HostService._internal() {
    _initLifecycleObserver();
  }

  static const int defaultPort = 8765;
  static const int defaultControlPort = 8766;

  bool _supervisorLaunched = false;
  bool _isSupervisorStarting = false;
  String? _controlToken;
  int _controlPort = defaultControlPort;
  HostControlClient? _controlClient;

  bool _isHostingActive = false;
  String? _lastResolvedHostIp;

  bool get isHostingActive => _isHostingActive;
  String? get lastResolvedHostIp => _lastResolvedHostIp;
  int get controlPort => _controlPort;
  String? get controlToken => _controlToken;

  void _initLifecycleObserver() {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // Best-effort cleanup when app is destroyed/detached
      debugPrint('App detached: sending best-effort STOP to embedded server');
      stopHosting(isBestEffortOnAppDetached: true);
    }
  }

  @visibleForTesting
  void setControlClientForTesting(HostControlClient client) {
    _controlClient = client;
    _supervisorLaunched = true;
  }

  @visibleForTesting
  void setSupervisorLaunchedForTesting(bool launched) {
    _supervisorLaunched = launched;
  }

  /// Initializes the foreground service notification settings.
  static void initForegroundTask() {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'impostor_server_channel',
        channelName: 'Impostor Server Service',
        channelDescription: 'Persistent notification when hosting an Impostor game room',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Checks if a TCP port is currently accepting connections on 127.0.0.1.
  Future<bool> isPortReachable({
    int port = defaultPort,
    String host = '127.0.0.1',
    Duration timeout = const Duration(milliseconds: 300),
  }) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _generateSecureToken() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Launches the Python supervisor once per process if not already running.
  Future<void> ensureSupervisorRunning({int controlPort = defaultControlPort}) async {
    if (_controlClient != null && await isPortReachable(port: controlPort)) {
      _supervisorLaunched = true;
      return;
    }

    if (_isSupervisorStarting) {
      await _waitForPort(port: controlPort, label: 'Control channel');
      return;
    }

    _isSupervisorStarting = true;
    _controlPort = controlPort;

    try {
      // 1. Check if supervisor is already alive in this process
      final alreadyUp = await isPortReachable(port: controlPort);
      if (alreadyUp && _controlToken != null) {
        _controlClient = HostControlClient(port: controlPort, token: _controlToken!);
        _supervisorLaunched = true;
        return;
      }

      // 2. Generate random auth token
      final token = _generateSecureToken();
      _controlToken = token;

      // Persist token for foreground task handler
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('control_token', token);
        await prefs.setInt('control_port', controlPort);
      } catch (e) {
        debugPrint('Could not persist control token: $e');
      }

      // Purge stale flet extract cache
      try {
        final supportDir = await getApplicationSupportDirectory();
        final fletDir = Directory('${supportDir.path}/flet');
        if (await fletDir.exists()) {
          await fletDir.delete(recursive: true);
        }
      } catch (e) {
        debugPrint('Notice: could not clear flet cache: $e');
      }

      // Launch Python supervisor in background thread (at most once per process)
      if (!_supervisorLaunched) {
        _supervisorLaunched = true;
        SeriousPython.run(
          'assets/app.zip',
          appFileName: 'server/embedded_entry.py',
          environmentVariables: {
            'RUN_SUPERVISOR_ON_IMPORT': '1',
            'EMBEDDED_CONTROL_PORT': '$controlPort',
            'EMBEDDED_CONTROL_TOKEN': token,
          },
        ).catchError((err) {
          debugPrint('SeriousPython supervisor error: $err');
          return err.toString();
        });
      }

      // Poll until supervisor control port is listening
      await _waitForPort(port: controlPort, label: 'Control channel', timeoutSeconds: 15);
      _controlClient = HostControlClient(port: controlPort, token: token);
    } finally {
      _isSupervisorStarting = false;
    }
  }

  /// Sends START command over the control channel and verifies the game port is open.
  Future<void> ensureServerRunning({
    int port = defaultPort,
    int controlPort = defaultControlPort,
  }) async {
    // 1. Ensure supervisor is running
    await ensureSupervisorRunning(controlPort: controlPort);

    // 2. Check if game port is already open
    if (await isPortReachable(port: port)) {
      return;
    }

    // 3. Issue START command via control channel
    final client = _controlClient!;
    await client.startServer(port);

    // 4. Poll until game server port accepts connections
    await _waitForPort(port: port, label: 'Game server', timeoutSeconds: 10);
  }

  /// Gracefully stops GameServer via control channel and verifies port is closed.
  Future<void> stopServer({int port = defaultPort}) async {
    if (_controlClient == null) {
      if (!await isPortReachable(port: port)) {
        return; // Already stopped
      }
      // If port is open but we have no control client, try adopting saved token
      try {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('control_token');
        if (token != null) {
          _controlClient = HostControlClient(port: _controlPort, token: token);
        }
      } catch (_) {}
    }

    if (_controlClient != null) {
      try {
        await _controlClient!.stopServer(timeout: const Duration(seconds: 4));
      } catch (e) {
        debugPrint('Warning: control channel stopServer error: $e');
      }
    }

    // Verify game port is completely closed
    final closed = await _waitForPortClosed(port: port, timeoutSeconds: 4);
    if (!closed) {
      debugPrint('CRITICAL: Game server port $port refused to close within timeout.');
      await _lastResortFallback();
    }
  }

  /// Queries supervisor for live server status.
  Future<ServerStatus> getStatus() async {
    if (_controlClient == null) {
      return ServerStatus.stopped();
    }
    try {
      return await _controlClient!.getStatus();
    } catch (_) {
      return ServerStatus.stopped();
    }
  }

  Future<void> _waitForPort({
    required int port,
    required String label,
    int timeoutSeconds = 12,
  }) async {
    final startTime = DateTime.now();
    const interval = Duration(milliseconds: 250);

    while (DateTime.now().difference(startTime).inSeconds < timeoutSeconds) {
      if (await isPortReachable(port: port)) {
        return;
      }
      await Future.delayed(interval);
    }

    throw TimeoutException('$label did not open port $port within $timeoutSeconds seconds.');
  }

  Future<bool> _waitForPortClosed({
    required int port,
    int timeoutSeconds = 4,
  }) async {
    final startTime = DateTime.now();
    const interval = Duration(milliseconds: 150);

    while (DateTime.now().difference(startTime).inSeconds < timeoutSeconds) {
      if (!await isPortReachable(port: port)) {
        return true;
      }
      await Future.delayed(interval);
    }

    return !await isPortReachable(port: port);
  }

  /// Last-resort fallback: stops foreground service and terminates the process
  /// if Python control channel is unreachable or port cannot be released.
  Future<void> _lastResortFallback() async {
    debugPrint('Invoking last-resort fallback to kill process and prevent zombie socket server.');
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    exit(1);
  }

  /// Resolves device's host IP for other players to connect.
  Future<String?> resolveHostIp() async {
    final ip = await NetworkIpHelper.resolveHostIp();
    if (ip != null) {
      _lastResolvedHostIp = ip;
    }
    return ip;
  }

  /// Activates foreground service notification and wakelock when hosting.
  Future<void> startHosting({
    required String roomCode,
    required String hostIp,
    int port = defaultPort,
  }) async {
    _isHostingActive = true;
    _lastResolvedHostIp = hostIp;

    try {
      await WakelockPlus.enable();
    } catch (e) {
      debugPrint('Wakelock error: $e');
    }

    try {
      final status = await FlutterForegroundTask.checkNotificationPermission();
      if (status != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    } catch (e) {
      debugPrint('Notification permission error: $e');
    }

    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'Impostor server running',
          notificationText: 'Room $roomCode • ws://$hostIp:$port',
        );
      } else {
        await FlutterForegroundTask.startService(
          serviceId: 8765,
          notificationTitle: 'Impostor server running',
          notificationText: 'Room $roomCode • ws://$hostIp:$port',
          notificationIcon: null,
          notificationInitialRoute: '/',
          callback: startForegroundTaskCallback,
        );
      }
    } catch (e) {
      debugPrint('Foreground service error: $e');
    }
  }

  /// Stops game server, releases port, stops foreground service, and releases wakelock.
  Future<void> stopHosting({
    int port = defaultPort,
    bool isBestEffortOnAppDetached = false,
  }) async {
    _isHostingActive = false;

    // 1. Gracefully stop GameServer and verify port is closed
    try {
      await stopServer(port: port);
    } catch (e) {
      debugPrint('Error stopping server during stopHosting: $e');
      if (!isBestEffortOnAppDetached) {
        await _lastResortFallback();
      }
    }

    // 2. Stop foreground service
    try {
      await FlutterForegroundTask.stopService();
    } catch (e) {
      debugPrint('Foreground task stop error: $e');
    }

    // 3. Disable Wakelock
    try {
      await WakelockPlus.disable();
    } catch (e) {
      debugPrint('Wakelock disable error: $e');
    }
  }
}
