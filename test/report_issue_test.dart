import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:parchesepop/main.dart';

import 'package:parchesepop/report_issue.dart';

void main() {
  const device = PlayerReportDeviceContext(
    appVersion: '2.2.1+16',
    operatingSystem: 'iOS 18.6',
    device: 'iPhone 13',
  );

  test('report mailto contains recipient, reason, player, and diagnostics', () {
    final uri = buildPlayerReportMailto(
      reason: PlayerReportReason.gameTampering,
      playerName: 'Player One',
      description: 'La ficha saltó varias casillas.',
      deviceContext: device,
      modeLabel: 'Quick Table',
    );

    expect(uri.scheme, 'mailto');
    expect(uri.path, 'sales@liisgo.com');
    expect(uri.queryParameters['subject'], contains('alteración'));
    final body = uri.queryParameters['body']!;
    expect(body, contains('Jugador reportado: Player One'));
    expect(body, contains('Versión de la app: 2.2.1+16'));
    expect(body, contains('Sistema operativo: iOS 18.6'));
    expect(body, contains('Dispositivo: iPhone 13'));
    expect(body, contains('Modo: Quick Table'));
    expect(body, contains('La ficha saltó varias casillas.'));
    expect(body, isNot(contains('roomCode')));
    expect(body, isNot(contains('password')));
  });

  test('technical reports allow an empty player name', () {
    final body = buildPlayerReportEmail(
      reason: PlayerReportReason.technicalIssue,
      playerName: '',
      description: '',
      deviceContext: device,
    );

    expect(PlayerReportReason.technicalIssue.requiresPlayerName, isFalse);
    expect(body, contains('Jugador reportado: No indicado'));
    expect(body, contains('No se añadió una descripción adicional.'));
  });

  test('player-safety categories require an identified player', () {
    expect(
      PlayerReportReason.values
          .where((reason) => reason.requiresPlayerName)
          .map((reason) => reason.label),
      containsAll(<String>[
        'Nombre inapropiado',
        'Trampa o alteración del juego',
        'Acoso o mensajes inapropiados',
      ]),
    );
  });

  testWidgets('privacy policies exposes the report entry point', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PoliciesScreen()));

    expect(find.byKey(const ValueKey('report-player-button')), findsOneWidget);
    expect(find.text('Reportar jugador o problema'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('report-player-button')));
    await tester.pumpAndSettle();
    expect(find.byType(ReportIssueScreen), findsOneWidget);
  });
}
