import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:impostor_app/services/game_client.dart';
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

  group('GameClient with Fake WebSocket', () {
    test('connects and receives room_joined frame', () async {
      final incomingController = StreamController<dynamic>.broadcast();
      final mockSink = MockWebSocketSink();

      final client = GameClient(
        channelFactory: (uri) {
          return FakeWebSocketChannel(incomingController.stream, mockSink);
        },
      );

      await client.connect('127.0.0.1:8765');
      expect(client.status, ConnectionStatus.connected);

      // Simulate server sending room_joined
      final joinedCompleter = Completer<void>();
      final sub = client.roomJoinedStream.listen((model) {
        expect(model.code, 'WXYZ');
        expect(model.playerId, 'p_1_1111');
        expect(model.token, 'tok_123');
        expect(model.isHost, true);
        joinedCompleter.complete();
      });

      incomingController.add(
        json.encode({
          'type': 'room_joined',
          'data': {
            'code': 'WXYZ',
            'player_id': 'p_1_1111',
            'token': 'tok_123',
            'is_host': true,
          },
        }),
      );

      await joinedCompleter.future;
      await sub.cancel();
      client.dispose();
    });

    test('sends formatted client action frames with request id', () async {
      final incomingController = StreamController<dynamic>.broadcast();
      final mockSink = MockWebSocketSink();

      final client = GameClient(
        channelFactory: (uri) {
          return FakeWebSocketChannel(incomingController.stream, mockSink);
        },
      );

      await client.connect('127.0.0.1:8765');

      // Test submit clue
      await client.submitClue('Elephant');
      expect(mockSink.sentMessages.length, 1);
      final sent = json.decode(mockSink.sentMessages.first as String);
      expect(sent['type'], 'submit_clue');
      expect(sent['data']['word'], 'Elephant');
      expect(sent['id'], startsWith('req_'));

      // Test cast vote
      await client.castVote('p_2_2222');
      expect(mockSink.sentMessages.length, 2);
      final sentVote = json.decode(mockSink.sentMessages[1] as String);
      expect(sentVote['type'], 'cast_vote');
      expect(sentVote['data']['target_id'], 'p_2_2222');

      client.dispose();
    });

    test('emits error stream when server sends error frame', () async {
      final incomingController = StreamController<dynamic>.broadcast();
      final mockSink = MockWebSocketSink();

      final client = GameClient(
        channelFactory: (uri) {
          return FakeWebSocketChannel(incomingController.stream, mockSink);
        },
      );

      await client.connect('127.0.0.1:8765');

      final errCompleter = Completer<void>();
      final sub = client.errorStream.listen((err) {
        expect(err.code, 'NOT_YOUR_TURN');
        expect(err.message, 'It is not your turn.');
        errCompleter.complete();
      });

      incomingController.add(
        json.encode({
          'type': 'error',
          'data': {'code': 'NOT_YOUR_TURN', 'message': 'It is not your turn.'},
        }),
      );

      await errCompleter.future;
      await sub.cancel();
      client.dispose();
    });
  });
}
