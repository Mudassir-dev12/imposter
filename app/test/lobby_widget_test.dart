import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impostor_app/models/protocol_models.dart';
import 'package:impostor_app/screens/lobby_screen.dart';
import 'package:impostor_app/state/game_providers.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets(
    'LobbyScreen displays room code, players, and start button state',
    (tester) async {
      const stateWith2Players = RoomStateModel(
        roomCode: 'ABCD',
        phase: 'LOBBY',
        players: [
          PlayerSummary(
            id: 'p1',
            name: 'Alice',
            score: 0,
            isHost: true,
            connected: true,
          ),
          PlayerSummary(
            id: 'p2',
            name: 'Bob',
            score: 0,
            isHost: false,
            connected: true,
          ),
        ],
        settings: GameSettingsModel(),
        myId: 'p1',
        roundIndex: 1,
        clues: [],
        hasConfirmedRole: false,
        voteProgress: VoteProgressModel(votedCount: 0, total: 2),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roomStateProvider.overrideWith(
              (ref) => Stream.value(stateWith2Players),
            ),
          ],
          child: const MaterialApp(home: LobbyScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // Verify room code is shown large
      expect(find.text('ABCD'), findsOneWidget);

      // Verify QR Code is shown for host
      expect(find.byType(QrImageView), findsOneWidget);

      // Verify players are shown
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('HOST'), findsOneWidget);

      // With 2 players, cannot start yet (need at least 3)
      expect(
        find.text('Need at least 3 players to start game'),
        findsOneWidget,
      );
      final startButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Start Game'),
      );
      expect(startButton.onPressed, isNull); // disabled
    },
  );

  testWidgets(
    'LobbyScreen enables Start Game button when 3 or more players are present',
    (tester) async {
      const stateWith3Players = RoomStateModel(
        roomCode: 'WXYZ',
        phase: 'LOBBY',
        players: [
          PlayerSummary(
            id: 'p1',
            name: 'Alice',
            score: 0,
            isHost: true,
            connected: true,
          ),
          PlayerSummary(
            id: 'p2',
            name: 'Bob',
            score: 0,
            isHost: false,
            connected: true,
          ),
          PlayerSummary(
            id: 'p3',
            name: 'Charlie',
            score: 0,
            isHost: false,
            connected: true,
          ),
        ],
        settings: GameSettingsModel(),
        myId: 'p1',
        roundIndex: 1,
        clues: [],
        hasConfirmedRole: false,
        voteProgress: VoteProgressModel(votedCount: 0, total: 3),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roomStateProvider.overrideWith(
              (ref) => Stream.value(stateWith3Players),
            ),
          ],
          child: const MaterialApp(home: LobbyScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // With 3 players, can start
      expect(find.text('Need at least 3 players to start game'), findsNothing);
      final startButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Start Game'),
      );
      expect(startButton.onPressed, isNotNull); // enabled!
    },
  );
}
