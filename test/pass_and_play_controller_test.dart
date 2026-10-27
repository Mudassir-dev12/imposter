import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:impostor_app/models/protocol_models.dart';
import 'package:impostor_app/services/game_client.dart';
import 'package:impostor_app/services/pass_and_play_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class MockWebSocketSink implements WebSocketSink {
  final List<dynamic> sentMessages = [];
  final Completer<void> _doneCompleter = Completer<void>();

  @override
  void add(dynamic data) {
    sentMessages.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream stream) async {
    await for (final item in stream) {
      sentMessages.add(item);
    }
  }

  @override
  Future close([int? closeCode, String? closeReason]) async {
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }

  @override
  Future get done => _doneCompleter.future;
}

class FakeWebSocketChannel extends StreamChannelMixin
    implements WebSocketChannel {
  final Stream _stream;
  final WebSocketSink _sink;

  FakeWebSocketChannel(this._stream, this._sink);

  @override
  Stream get stream => _stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future.value();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PassAndPlayController 3-Player Game Lifecycle', () {
    test('Runs 3-player game from lobby to results with fake WebSocket clients',
        () async {
      final inControllers = <StreamController<dynamic>>[
        StreamController<dynamic>.broadcast(),
        StreamController<dynamic>.broadcast(),
        StreamController<dynamic>.broadcast(),
      ];
      final sinks = <MockWebSocketSink>[
        MockWebSocketSink(),
        MockWebSocketSink(),
        MockWebSocketSink(),
      ];

      int clientIndex = 0;
      final controller = PassAndPlayController(
        playerNames: ['Alice', 'Bob', 'Charlie'],
        settings: const GameSettingsModel(
          spokenClues: true,
          turnTimerSeconds: 0,
          category: 'Animals',
        ),
        clientFactory: () {
          final idx = clientIndex++;
          return GameClient(
            channelFactory: (uri) =>
                FakeWebSocketChannel(inControllers[idx].stream, sinks[idx]),
          );
        },
      );

      // Start session asynchronously
      final sessionFuture = controller.startSession(
        serverUrl: 'ws://127.0.0.1:8765',
        startEmbeddedServer: false,
      );

      // Give event loop time to process connect & create_room
      await Future.delayed(const Duration(milliseconds: 20));

      // 1. Respond to Alice (host) create_room
      inControllers[0].add(json.encode({
        'type': 'room_joined',
        'data': {
          'code': 'TEST',
          'player_id': 'p1',
          'token': 'tok1',
          'is_host': true,
        },
      }));
      inControllers[0].add(json.encode({
        'type': 'room_state',
        'data': {
          'room_code': 'TEST',
          'phase': 'LOBBY',
          'players': [
            {'id': 'p1', 'name': 'Alice', 'score': 0, 'is_host': true, 'connected': true},
          ],
          'settings': {'spoken_clues': true, 'turn_timer_seconds': 0, 'category': 'Animals'},
          'my_id': 'p1',
        },
      }));

      await Future.delayed(const Duration(milliseconds: 20));

      // 2. Respond to Bob and Charlie join_room
      inControllers[1].add(json.encode({
        'type': 'room_joined',
        'data': {
          'code': 'TEST',
          'player_id': 'p2',
          'token': 'tok2',
          'is_host': false,
        },
      }));
      inControllers[2].add(json.encode({
        'type': 'room_joined',
        'data': {
          'code': 'TEST',
          'player_id': 'p3',
          'token': 'tok3',
          'is_host': false,
        },
      }));

      final lobby3State = {
        'room_code': 'TEST',
        'phase': 'LOBBY',
        'players': [
          {'id': 'p1', 'name': 'Alice', 'score': 0, 'is_host': true, 'connected': true},
          {'id': 'p2', 'name': 'Bob', 'score': 0, 'is_host': false, 'connected': true},
          {'id': 'p3', 'name': 'Charlie', 'score': 0, 'is_host': false, 'connected': true},
        ],
        'settings': {'spoken_clues': true, 'turn_timer_seconds': 0, 'category': 'Animals'},
      };

      inControllers[0].add(json.encode({
        'type': 'room_state',
        'data': {...lobby3State, 'my_id': 'p1'},
      }));

      // Session initialization completes
      await sessionFuture;
      expect(controller.roomCode, 'TEST');
      expect(controller.clients.length, 3);
      expect(controller.currentPhase, 'LOBBY');

      // 3. Test Safety & Privacy Lock
      controller.revealPrivateContent();
      expect(controller.isPrivateContentRevealed, isTrue);
      controller.lockPrivateContent();
      expect(controller.isPrivateContentRevealed, isFalse);

      // 4. Move to ROLE_REVEAL phase
      void broadcastPhase(String phase, {Map<String, dynamic>? extra}) {
        final base = {
          'room_code': 'TEST',
          'phase': phase,
          'players': [
            {'id': 'p1', 'name': 'Alice', 'score': 0, 'is_host': true, 'connected': true},
            {'id': 'p2', 'name': 'Bob', 'score': 0, 'is_host': false, 'connected': true},
            {'id': 'p3', 'name': 'Charlie', 'score': 0, 'is_host': false, 'connected': true},
          ],
          'settings': {'spoken_clues': true, 'turn_timer_seconds': 0, 'category': 'Animals'},
          ...?extra,
        };

        inControllers[0].add(json.encode({
          'type': 'room_state',
          'data': {...base, 'my_id': 'p1', 'my_role': 'CREW', 'my_word': 'Lion'},
        }));
        inControllers[1].add(json.encode({
          'type': 'room_state',
          'data': {...base, 'my_id': 'p2', 'my_role': 'IMPOSTOR', 'category': 'Animals'},
        }));
        inControllers[2].add(json.encode({
          'type': 'room_state',
          'data': {...base, 'my_id': 'p3', 'my_role': 'CREW', 'my_word': 'Lion'},
        }));
      }

      broadcastPhase('ROLE_REVEAL');
      await Future.delayed(const Duration(milliseconds: 20));

      expect(controller.currentPhase, 'ROLE_REVEAL');
      expect(controller.isRoleReveal, isTrue);
      expect(controller.activePrivatePlayerName, 'Alice');

      // Alice confirms role seen -> passes to Bob
      await controller.confirmRoleSeen();
      expect(controller.activePrivatePlayerName, 'Bob');
      expect(controller.isPrivateContentRevealed, isFalse);

      // Bob confirms role seen -> passes to Charlie
      await controller.confirmRoleSeen();
      expect(controller.activePrivatePlayerName, 'Charlie');

      // Charlie confirms role seen -> server starts CLUE_ROUND
      await controller.confirmRoleSeen();

      // 5. CLUE_ROUND with spoken clues
      broadcastPhase('CLUE_ROUND', extra: {
        'current_turn_player_id': 'p1',
        'round_index': 1,
      });
      await Future.delayed(const Duration(milliseconds: 20));

      expect(controller.currentPhase, 'CLUE_ROUND');
      expect(controller.isClueRound, isTrue);

      // Alice ends turn with spoken clue
      await controller.endTurn();
      final lastAliceMsg = json.decode(sinks[0].sentMessages.last as String);
      expect(lastAliceMsg['type'], 'end_turn');

      // 6. DISCUSSION phase
      broadcastPhase('DISCUSSION');
      await Future.delayed(const Duration(milliseconds: 20));
      expect(controller.currentPhase, 'DISCUSSION');
      expect(controller.isDiscussion, isTrue);

      // Host skips discussion
      await controller.skipDiscussion();
      final lastSkipMsg = json.decode(sinks[0].sentMessages.last as String);
      expect(lastSkipMsg['type'], 'skip_discussion');

      // 7. VOTING phase (Private)
      broadcastPhase('VOTING');
      await Future.delayed(const Duration(milliseconds: 20));
      expect(controller.currentPhase, 'VOTING');
      expect(controller.isVoting, isTrue);

      // Alice votes for Bob (p2)
      await controller.castVote('p2');
      final aliceVoteMsg = json.decode(sinks[0].sentMessages.last as String);
      expect(aliceVoteMsg['type'], 'cast_vote');
      expect(aliceVoteMsg['data']['target_id'], 'p2');
      expect(controller.activePrivatePlayerName, 'Bob');

      // 8. RESULT phase
      broadcastPhase('RESULT', extra: {
        'round_result': {
          'outcome': 'CREW_WIN',
          'secret_word': 'Lion',
          'category': 'Animals',
          'impostor_ids': ['p2'],
          'votes': {'p1': 'p2', 'p2': 'p1', 'p3': 'p2'},
          'clues': [],
          'score_delta': {'p1': 100, 'p2': 0, 'p3': 100},
          'scores': {'p1': 100, 'p2': 0, 'p3': 100},
        },
      });
      await Future.delayed(const Duration(milliseconds: 20));

      expect(controller.isResult, isTrue);
      expect(controller.primaryState?.roundResult?.outcome, 'CREW_WIN');

      // Cleanup session
      await controller.disposeSession();
      for (final c in inControllers) {
        await c.close();
      }
    });
  });
}
