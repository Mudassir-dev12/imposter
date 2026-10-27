import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Model representing current GameServer status reported by Python supervisor.
class ServerStatus {
  final bool running;
  final int? port;
  final int rooms;
  final int connections;

  const ServerStatus({
    required this.running,
    this.port,
    required this.rooms,
    required this.connections,
  });

  factory ServerStatus.stopped() => const ServerStatus(
        running: false,
        port: null,
        rooms: 0,
        connections: 0,
      );

  factory ServerStatus.fromJson(Map<String, dynamic> json) {
    return ServerStatus(
      running: json['running'] as bool? ?? false,
      port: json['port'] as int?,
      rooms: json['rooms'] as int? ?? 0,
      connections: json['connections'] as int? ?? 0,
    );
  }

  @override
  String toString() =>
      'ServerStatus(running: $running, port: $port, rooms: $rooms, connections: $connections)';
}

class ControlChannelException implements Exception {
  final String message;
  const ControlChannelException(this.message);

  @override
  String toString() => 'ControlChannelException: $message';
}

/// Client for communicating with the embedded Python supervisor over local loopback.
class HostControlClient {
  final String host;
  final int port;
  final String token;

  HostControlClient({
    this.host = '127.0.0.1',
    required this.port,
    required this.token,
  });

  /// Sends a command to the control channel with authentication and returns response line.
  Future<String> sendCommand(
    String command, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      // Send AUTH followed by command
      socket.write('AUTH $token\n$command\n');
      await socket.flush();

      final completer = Completer<String>();
      final buffer = StringBuffer();
      late StreamSubscription<List<int>> sub;

      sub = socket.listen(
        (data) {
          buffer.write(utf8.decode(data, allowMalformed: true));
          while (buffer.toString().contains('\n')) {
            final current = buffer.toString();
            final newlineIndex = current.indexOf('\n');
            final line = current.substring(0, newlineIndex).trim();
            buffer.clear();
            buffer.write(current.substring(newlineIndex + 1));

            if (line.isEmpty) continue;
            if (line == 'OK AUTHENTICATED') continue;

            if (!completer.isCompleted) {
              completer.complete(line);
              sub.cancel();
              break;
            }
          }
        },
        onError: (err) {
          if (!completer.isCompleted) completer.completeError(err);
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.completeError(
              const SocketException('Control connection closed before response received'),
            );
          }
        },
      );

      final resp = await completer.future.timeout(timeout);
      if (resp.startsWith('ERROR ')) {
        throw ControlChannelException(resp.substring('ERROR '.length));
      }
      return resp;
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  /// Queries the supervisor for live GameServer status.
  Future<ServerStatus> getStatus({Duration timeout = const Duration(seconds: 2)}) async {
    final resp = await sendCommand('STATUS', timeout: timeout);
    const prefix = 'OK STATUS ';
    if (resp.startsWith(prefix)) {
      final jsonStr = resp.substring(prefix.length).trim();
      final decoded = json.decode(jsonStr) as Map<String, dynamic>;
      return ServerStatus.fromJson(decoded);
    }
    throw ControlChannelException('Invalid STATUS response format: $resp');
  }

  /// Sends START command to spawn GameServer on 0.0.0.0:gamePort.
  Future<void> startServer(int gamePort, {Duration timeout = const Duration(seconds: 5)}) async {
    final resp = await sendCommand('START $gamePort', timeout: timeout);
    if (!resp.startsWith('OK STARTED') && !resp.startsWith('OK ALREADY_RUNNING')) {
      throw ControlChannelException('START failed: $resp');
    }
  }

  /// Sends STOP command to gracefully shut down GameServer and release port.
  Future<void> stopServer({Duration timeout = const Duration(seconds: 5)}) async {
    final resp = await sendCommand('STOP', timeout: timeout);
    if (!resp.startsWith('OK STOPPED') && !resp.startsWith('OK ALREADY_STOPPED')) {
      throw ControlChannelException('STOP failed: $resp');
    }
  }

  /// Optional: Requests the supervisor event loop to terminate.
  Future<void> quitSupervisor({Duration timeout = const Duration(seconds: 2)}) async {
    await sendCommand('QUIT', timeout: timeout);
  }
}
