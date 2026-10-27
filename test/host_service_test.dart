import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:impostor_app/services/host_control_client.dart';
import 'package:impostor_app/services/host_service.dart';

/// In-process fake control server simulating the Python supervisor.
class FakeSupervisorServer {
  final String validToken;
  ServerSocket? _server;
  ServerSocket? _dummyGameSocket;
  int get controlPort => _server?.port ?? 0;
  bool isGameRunning = false;
  int? boundGamePort;

  FakeSupervisorServer({required this.validToken});

  Future<void> start() async {
    _server = await ServerSocket.bind('127.0.0.1', 0);
    _server!.listen(_handleConnection);
  }

  Future<void> stop() async {
    await _closeGameSocket();
    await _server?.close();
  }

  Future<void> _closeGameSocket() async {
    if (_dummyGameSocket != null) {
      await _dummyGameSocket!.close();
      _dummyGameSocket = null;
    }
    isGameRunning = false;
    boundGamePort = null;
  }

  void _handleConnection(Socket client) {
    bool authenticated = false;
    final buffer = StringBuffer();

    client.listen((data) async {
      buffer.write(utf8.decode(data, allowMalformed: true));
      while (buffer.toString().contains('\n')) {
        final current = buffer.toString();
        final newlineIndex = current.indexOf('\n');
        final line = current.substring(0, newlineIndex).trim();
        buffer.clear();
        buffer.write(current.substring(newlineIndex + 1));

        if (line.isEmpty) continue;

        final parts = line.split(' ');
        final cmd = parts[0].toUpperCase();

        if (cmd == 'AUTH') {
          if (parts.length < 2 || parts[1] != validToken) {
            client.write('ERROR UNAUTHORIZED\n');
            await client.flush();
            client.destroy();
            return;
          }
          authenticated = true;
          if (parts.length > 2) {
            final subCmd = parts[2].toUpperCase();
            final subArg = parts.length > 3 ? parts[3] : null;
            await _executeCommand(client, subCmd, subArg);
          } else {
            client.write('OK AUTHENTICATED\n');
            await client.flush();
          }
          continue;
        }

        if (!authenticated) {
          client.write('ERROR UNAUTHORIZED\n');
          await client.flush();
          client.destroy();
          return;
        }

        final arg = parts.length > 1 ? parts[1] : null;
        await _executeCommand(client, cmd, arg);
      }
    });
  }

  Future<void> _executeCommand(Socket client, String cmd, String? arg) async {
    if (cmd == 'START') {
      final port = int.tryParse(arg ?? '8765') ?? 8765;
      await _closeGameSocket();
      _dummyGameSocket = await ServerSocket.bind('127.0.0.1', port);
      isGameRunning = true;
      boundGamePort = port;
      client.write('OK STARTED $port\n');
      await client.flush();
    } else if (cmd == 'STOP') {
      await _closeGameSocket();
      client.write('OK STOPPED\n');
      await client.flush();
    } else if (cmd == 'STATUS') {
      final payload = json.encode({
        'running': isGameRunning,
        'port': boundGamePort,
        'rooms': isGameRunning ? 1 : 0,
        'connections': isGameRunning ? 2 : 0,
      });
      client.write('OK STATUS $payload\n');
      await client.flush();
    } else {
      client.write('ERROR UNKNOWN_COMMAND\n');
      await client.flush();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HostControlClient', () {
    late FakeSupervisorServer fakeSupervisor;
    const testToken = 'unit_test_token_abcdef';

    setUp(() async {
      fakeSupervisor = FakeSupervisorServer(validToken: testToken);
      await fakeSupervisor.start();
    });

    tearDown(() async {
      await fakeSupervisor.stop();
    });

    test('authenticates and executes START, STATUS, STOP commands', () async {
      final client = HostControlClient(
        port: fakeSupervisor.controlPort,
        token: testToken,
      );

      // 1. Initial status is stopped
      var status = await client.getStatus();
      expect(status.running, isFalse);
      expect(status.port, isNull);
      expect(status.rooms, equals(0));

      // 2. Start game on dynamic port
      final ephemeralPort = await _findUnusedPort();
      await client.startServer(ephemeralPort);

      // Verify status shows running
      status = await client.getStatus();
      expect(status.running, isTrue);
      expect(status.port, equals(ephemeralPort));
      expect(status.rooms, equals(1));
      expect(status.connections, equals(2));

      // 3. Stop game server
      await client.stopServer();
      status = await client.getStatus();
      expect(status.running, isFalse);
    });

    test('rejects commands when token is invalid', () async {
      final client = HostControlClient(
        port: fakeSupervisor.controlPort,
        token: 'wrong_invalid_token',
      );

      expect(
        () => client.getStatus(),
        throwsA(isA<ControlChannelException>().having(
          (e) => e.message,
          'message',
          contains('UNAUTHORIZED'),
        )),
      );
    });
  });

  group('HostService State Machine with Fake Control Channel', () {
    late FakeSupervisorServer fakeSupervisor;
    const testToken = 'state_machine_token_123';
    late HostService hostService;

    setUp(() async {
      fakeSupervisor = FakeSupervisorServer(validToken: testToken);
      await fakeSupervisor.start();

      hostService = HostService();
      final client = HostControlClient(
        port: fakeSupervisor.controlPort,
        token: testToken,
      );
      hostService.setControlClientForTesting(client);
    });

    tearDown(() async {
      await fakeSupervisor.stop();
    });

    test('ensureServerRunning opens port and stopServer closes port', () async {
      final gamePort = await _findUnusedPort();

      // Check port is initially closed
      expect(await hostService.isPortReachable(port: gamePort), isFalse);

      // Start server via HostService
      await hostService.ensureServerRunning(
        port: gamePort,
        controlPort: fakeSupervisor.controlPort,
      );

      // Verify port is open
      expect(await hostService.isPortReachable(port: gamePort), isTrue);

      // Verify live status
      final status = await hostService.getStatus();
      expect(status.running, isTrue);
      expect(status.port, equals(gamePort));

      // Stop server via HostService and verify port is closed
      await hostService.stopServer(port: gamePort);
      expect(await hostService.isPortReachable(port: gamePort), isFalse);

      final statusStopped = await hostService.getStatus();
      expect(statusStopped.running, isFalse);
    });

    test('stopServer is idempotent when server is already stopped', () async {
      final gamePort = await _findUnusedPort();

      // Ensure stopped
      await hostService.stopServer(port: gamePort);
      expect(await hostService.isPortReachable(port: gamePort), isFalse);

      // Calling stop again does not throw
      await hostService.stopServer(port: gamePort);
      expect(await hostService.isPortReachable(port: gamePort), isFalse);
    });
  });
}

Future<int> _findUnusedPort() async {
  final socket = await ServerSocket.bind('127.0.0.1', 0);
  final port = socket.port;
  await socket.close();
  return port;
}
