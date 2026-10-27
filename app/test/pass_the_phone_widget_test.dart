import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impostor_app/widgets/pass_the_phone_widget.dart';

void main() {
  testWidgets('PassThePhoneWidget renders player name and handles confirmation',
      (tester) async {
    bool confirmed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PassThePhoneWidget(
            playerName: 'Charlie',
            subtitle: 'Reveal your secret role in private.',
            onConfirmed: () {
              confirmed = true;
            },
          ),
        ),
      ),
    );

    // Verify interstitial instructions and target player
    expect(find.text('Pass the phone to'), findsOneWidget);
    expect(find.text('Charlie'), findsOneWidget);
    expect(find.text('Reveal your secret role in private.'), findsOneWidget);

    // Verify confirmation button
    final confirmBtnFinder = find.widgetWithText(ElevatedButton, 'I am Charlie');
    expect(confirmBtnFinder, findsOneWidget);

    // Tap confirmation button
    await tester.tap(confirmBtnFinder);
    await tester.pump();

    // Verify callback was fired
    expect(confirmed, isTrue);
  });
}
