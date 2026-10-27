import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impostor_app/screens/home_screen.dart';
import 'package:impostor_app/screens/join_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'HomeScreen renders title, name input, and Play on Wi-Fi button',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: HomeScreen())),
      );

      await tester.pumpAndSettle();

      expect(find.text('IMPOSTOR'), findsOneWidget);
      expect(find.text('A Social Word Deduction Game'), findsOneWidget);
      expect(find.text('Play on Wi-Fi'), findsOneWidget);
      expect(find.text('Pass & Play (1 Phone)'), findsOneWidget);
    },
  );

  testWidgets(
    'JoinScreen renders Scan QR Code button and manual input fields',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: JoinScreen(
              playerName: 'Player1',
              serverAddress: '192.168.1.5:8765',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Scan QR Code'), findsOneWidget);
      expect(find.byIcon(Icons.qr_code_scanner_rounded), findsOneWidget);
      expect(find.text('ROOM CODE'), findsOneWidget);
      expect(find.text('HOST ADDRESS (IP:PORT)'), findsOneWidget);
    },
  );
}
