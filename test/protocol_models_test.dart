import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:impostor_app/models/protocol_models.dart';

void main() {
  group('Protocol Models from PROTOCOL.md', () {
    test('parses room_joined example exactly', () {
      const jsonStr = '''
      {
        "code": "ABCD",
        "player_id": "p_1_3491",
        "token": "tok_582914",
        "is_host": true
      }
      ''';
      final jsonMap = json.decode(jsonStr) as Map<String, dynamic>;
      final model = RoomJoinedModel.fromJson(jsonMap);

      expect(model.code, 'ABCD');
      expect(model.playerId, 'p_1_3491');
      expect(model.token, 'tok_582914');
      expect(model.isHost, true);
    });

    test('parses innocent crew room_state example exactly', () {
      const jsonStr = '''
      {
        "room_code": "ABCD",
        "phase": "CLUE_ROUND",
        "players": [
          {"id": "p_1_3491", "name": "Alice", "score": 0, "is_host": true, "connected": true},
          {"id": "p_2_1842", "name": "Bob", "score": 0, "is_host": false, "connected": true},
          {"id": "p_3_5914", "name": "Charlie", "score": 0, "is_host": false, "connected": true}
        ],
        "settings": {
          "clue_rounds": 2,
          "impostor_count": 1,
          "category": "Animals",
          "discussion_timer_seconds": 90,
          "impostor_sees_category": true,
          "turn_timer_seconds": 30,
          "voting_timer_seconds": 60,
          "role_reveal_timer_seconds": 45
        },
        "my_id": "p_1_3491",
        "my_role": "CREW",
        "my_word": "Elephant",
        "category": "Animals",
        "round_index": 1,
        "clues": [
          {"player_id": "p_1_3491", "word": "Gray", "round_index": 1, "timestamp": 1729761234.5}
        ],
        "current_turn_player_id": "p_2_1842",
        "deadline_epoch_ms": 1729761264500,
        "has_confirmed_role": true,
        "vote_progress": {"voted_count": 0, "total": 3},
        "votes": null,
        "impostor_ids": null,
        "caught_impostor_id": null,
        "round_result": null
      }
      ''';
      final jsonMap = json.decode(jsonStr) as Map<String, dynamic>;
      final model = RoomStateModel.fromJson(jsonMap);

      expect(model.roomCode, 'ABCD');
      expect(model.phase, 'CLUE_ROUND');
      expect(model.players.length, 3);
      expect(model.isCrew, true);
      expect(model.isImpostor, false);
      expect(model.myWord, 'Elephant');
      expect(model.category, 'Animals');
      expect(model.clues.length, 1);
      expect(model.clues.first.word, 'Gray');
      expect(model.currentTurnPlayerId, 'p_2_1842');
      expect(model.isMyTurn, false);
      expect(model.deadlineEpochMs, 1729761264500);
      expect(model.impostorIds, isNull);
    });

    test('parses impostor room_state example exactly (no secret word)', () {
      const jsonStr = '''
      {
        "room_code": "ABCD",
        "phase": "CLUE_ROUND",
        "players": [
          {"id": "p_1_3491", "name": "Alice", "score": 0, "is_host": true, "connected": true},
          {"id": "p_2_1842", "name": "Bob", "score": 0, "is_host": false, "connected": true}
        ],
        "settings": {
          "clue_rounds": 2,
          "impostor_count": 1,
          "category": "Animals"
        },
        "my_id": "p_2_1842",
        "my_role": "IMPOSTOR",
        "my_word": null,
        "category": "Animals",
        "round_index": 1,
        "clues": [],
        "current_turn_player_id": "p_2_1842",
        "deadline_epoch_ms": 1729761264500,
        "has_confirmed_role": true,
        "vote_progress": {"voted_count": 0, "total": 2}
      }
      ''';
      final jsonMap = json.decode(jsonStr) as Map<String, dynamic>;
      final model = RoomStateModel.fromJson(jsonMap);

      expect(model.isImpostor, true);
      expect(model.isCrew, false);
      expect(model.myWord, isNull);
      expect(model.category, 'Animals');
      expect(model.isMyTurn, true);
    });

    test('parses clue_posted example exactly', () {
      const jsonStr = '''
      {
        "player_id": "p_1_3491",
        "word": "Gray",
        "round_index": 1,
        "timestamp": 1729761234.5
      }
      ''';
      final jsonMap = json.decode(jsonStr) as Map<String, dynamic>;
      final model = CluePostedModel.fromJson(jsonMap);

      expect(model.playerId, 'p_1_3491');
      expect(model.word, 'Gray');
      expect(model.roundIndex, 1);
      expect(model.timestamp, 1729761234.5);
    });

    test('parses room_closed example exactly', () {
      const jsonStr = '''
      {
        "reason": "Host disconnected. Room has closed."
      }
      ''';
      final jsonMap = json.decode(jsonStr) as Map<String, dynamic>;
      final model = RoomClosedModel.fromJson(jsonMap);

      expect(model.reason, 'Host disconnected. Room has closed.');
    });

    test('parses error message example exactly', () {
      const jsonStr = '''
      {
        "code": "ROOM_NOT_FOUND",
        "message": "Room 'ABCD' does not exist."
      }
      ''';
      final jsonMap = json.decode(jsonStr) as Map<String, dynamic>;
      final model = ErrorMessageModel.fromJson(jsonMap);

      expect(model.code, 'ROOM_NOT_FOUND');
      expect(model.message, "Room 'ABCD' does not exist.");
    });
  });
}
