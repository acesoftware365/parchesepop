import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/main.dart';
import 'package:parchesepop/quick_pop_online_diagnostics.dart';

void main() {
  test(
    'diagnostic log preserves numbered console steps and Firebase details',
    () {
      final log = QuickPopDiagnosticLog(
        startedAt: DateTime.utc(2026, 8, 20, 22, 0),
      );
      log.add(
        elapsedMilliseconds: 1250,
        step: 'FIREBASE_CONNECTION',
        state: QuickPopDiagnosticState.success,
        detail: 'connected uid=uid_a',
      );
      log.add(
        elapsedMilliseconds: 2400,
        step: 'QUEUE_TICKET_CREATED',
        state: QuickPopDiagnosticState.error,
        detail: 'Permission denied',
        code: 'permission-denied',
        path: 'onlineV2/quickQueues/traditional_quickPop/uid_a',
      );

      final text = log.toConsole(device: 'ipad-pro-13', appVersion: '2.2.4+57');

      expect(text, contains('Version: 2.2.4+57'));
      expect(text, contains('[01] 01.25s  OK      FIREBASE_CONNECTION'));
      expect(text, contains('[02] 02.40s  ERROR   QUEUE_TICKET_CREATED'));
      expect(text, contains('code=permission-denied'));
      expect(
        text,
        contains('path=onlineV2/quickQueues/traditional_quickPop/uid_a'),
      );

      final gameText = log.toConsole(
        device: 'ipad-pro-13',
        appVersion: '2.2.4+57',
        title: 'PARCHIS POP GAME DEBUG',
        protocol: 'Quick Pop match',
        searchWindow: 'n/a',
      );
      expect(gameText, startsWith('PARCHIS POP GAME DEBUG'));
      expect(gameText, contains('Protocol: Quick Pop match'));
    },
  );

  testWidgets('diagnostic panel exposes the copy action and numbered rows', (
    tester,
  ) async {
    var copied = false;
    final entries = <QuickPopDiagnosticEntry>[
      const QuickPopDiagnosticEntry(
        number: 1,
        elapsedMilliseconds: 100,
        step: 'PLAY_ONLINE_PRESSED',
        state: QuickPopDiagnosticState.success,
        detail: 'protocol=quickPop',
      ),
      const QuickPopDiagnosticEntry(
        number: 2,
        elapsedMilliseconds: 800,
        step: 'WAITING_FOR_PLAYERS',
        state: QuickPopDiagnosticState.waiting,
        detail: 'players=1/4',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickPopOnlineSearchStatusPanel(
            status: 'Buscando un jugador online…',
            secondsRemaining: 14,
            openingMatch: false,
            settlementUnavailable: false,
            diagnosticEntries: entries,
            onCopyDiagnostics: () async => copied = true,
            onExit: () {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('quick-pop-diagnostic-log')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('quick-pop-diagnostic-step-1')),
      findsOneWidget,
    );
    expect(find.text('COPIAR'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('quick-pop-copy-diagnostics')));
    await tester.pump();
    expect(copied, isTrue);
  });

  testWidgets('CPU fallback waits for one explicit green start action', (
    tester,
  ) async {
    var started = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickPopOnlineSearchStatusPanel(
            status: 'No encontramos un rival online.',
            secondsRemaining: 0,
            openingMatch: false,
            settlementUnavailable: false,
            cpuFallbackReady: true,
            onStartCpu: () => started += 1,
            onExit: () {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('quick-pop-cpu-ready-icon')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('quick-pop-cpu-ready-help')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('quick-pop-countdown')), findsNothing);
    expect(find.byKey(const ValueKey('quick-pop-start-cpu')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('quick-pop-start-cpu')));
    await tester.pump();
    expect(started, 1);
    expect(tester.takeException(), isNull);
  });
}
