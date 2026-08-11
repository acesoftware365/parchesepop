import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/main.dart';

void main() {
  testWidgets(
    'unconfirmed human settlement replaces the CPU countdown with recovery UI',
    (tester) async {
      var returned = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 340,
                child: QuickPopOnlineSearchStatusPanel(
                  status: 'No pudimos confirmar la partida online.',
                  secondsRemaining: 0,
                  openingMatch: false,
                  settlementUnavailable: true,
                  onExit: () => returned = true,
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('quick-pop-reconnect-icon')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('quick-pop-settlement-unavailable-help')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('quick-pop-countdown')), findsNothing);
      expect(
        find.text('Luego jugarás contra CPU automáticamente'),
        findsNothing,
      );
      expect(find.text('VOLVER'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('quick-pop-search-exit')));
      await tester.pump();

      expect(returned, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
