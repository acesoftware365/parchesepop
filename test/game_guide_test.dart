import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_guide.dart';

void main() {
  testWidgets('traditional guide contains the complete core rules', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(const MaterialApp(home: GameGuideScreen()));
    await tester.pumpAndSettle();

    expect(find.text('CÓMO JUGAR'), findsOneWidget);
    expect(find.text('TRADICIONAL'), findsOneWidget);
    expect(find.text('CAOS'), findsOneWidget);
    expect(find.text('Salir con un 5'), findsOneWidget);
    expect(find.text('Usar los dos dados'), findsOneWidget);
    expect(
      find.textContaining('pulsa TODOS para avanzar la suma'),
      findsOneWidget,
    );
    expect(find.text('Capturas y bono +20'), findsOneWidget);
    expect(find.text('Barreras'), findsOneWidget);
    expect(find.text('Dobles'), findsOneWidget);
    expect(find.text('Tu entrada y pasillo'), findsOneWidget);
    expect(find.text('Meta, +10 y victoria'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('guide explains every local and online play mode', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(const MaterialApp(home: GameGuideScreen()));
    await tester.pumpAndSettle();

    for (final id in const ['quick-table', 'play-cpu', 'pass-and-play']) {
      expect(find.byKey(ValueKey('guide-mode-$id')), findsOneWidget);
    }
    final scrollable = find.byKey(const ValueKey('game-guide-scroll'));
    final passAndPlay = find.byKey(const ValueKey('guide-mode-pass-and-play'));
    await tester.ensureVisible(passAndPlay);
    await tester.drag(scrollable, const Offset(0, 120));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(passAndPlay));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('guide-summary-passAndPlay')),
      findsOneWidget,
    );
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Pasa el teléfono'), findsWidgets);
    expect(find.text('Un turno a la vez'), findsOneWidget);

    final playModes = find.byKey(const ValueKey('guide-play-modes'));
    for (var index = 0; index < 30 && playModes.evaluate().isEmpty; index++) {
      await tester.drag(scrollable, const Offset(0, -500));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(playModes, findsOneWidget);
    for (final id in const [
      'quick-pop',
      'quick-table',
      'play-cpu',
      'pass-and-play',
    ]) {
      expect(find.byKey(ValueKey('guide-play-mode-$id')), findsOneWidget);
    }
    expect(find.textContaining('Partida casual online'), findsOneWidget);
    expect(find.text('Crea una sala o entra con un código.'), findsOneWidget);
    expect(find.textContaining('inteligencia artificial'), findsOneWidget);
    expect(find.textContaining('pasando el dispositivo'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
    'chaos guide explains automatic shield and accumulating hidden traps',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(const MaterialApp(home: GameGuideScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('CAOS'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('guide-summary-chaos')), findsOneWidget);
      expect(find.text('Cristales sorpresa'), findsOneWidget);
      expect(find.text('Poderes automáticos'), findsOneWidget);
      expect(find.text('Un solo espacio'), findsNothing);
      expect(find.text('Trampas ocultas'), findsOneWidget);
      expect(
        find.textContaining(
          RegExp(r'escudo.+automáticamente', caseSensitive: false),
        ),
        findsWidgets,
      );
      expect(
        find.textContaining(
          RegExp(r'(varias.+trampas|trampas.+varias)', caseSensitive: false),
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets('Quick Pop guide describes its two-token rules without a 5', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      const MaterialApp(
        home: GameGuideScreen(initialMode: GameGuideMode.quickPop),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('guide-summary-quickPop')),
      findsOneWidget,
    );
    expect(find.text('Quick Pop'), findsOneWidget);
    expect(find.text('2 FICHAS'), findsOneWidget);
    expect(find.text('Empieza de inmediato'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Sin 5 de salida'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Sin 5 de salida'), findsOneWidget);
    expect(find.text('Salir con un 5'), findsNothing);
    expect(
      find.textContaining('Gana quien coloque primero sus 4'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });

  for (final effect in const [
    ('shield', 'Escudo', '¡PROTEGIDO!'),
    ('turbo', 'Turbo', '¡TURBO!'),
    ('glue', 'Pegamento', 'TURNO PERDIDO'),
    ('setback', 'Retroceso', 'RETROCESO −6'),
    ('prison', 'Cárcel', '¡A LA CÁRCEL!'),
    ('bomb', 'Bomba', '¡BUM! A LA CÁRCEL'),
  ]) {
    testWidgets('power lab plays a complete ${effect.$2} demonstration', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: TrapPowerLab())),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(ValueKey('guide-effect-${effect.$1}')),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text(effect.$3), findsOneWidget);
      expect(find.text('Demostración: ${effect.$2}'), findsOneWidget);

      await tester.pump(
        TrapPowerLab.demoDuration + const Duration(milliseconds: 100),
      );
      await tester.pump();
      expect(
        find.text('Efecto completado · toca para repetir'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
  }

  testWidgets('power lab can play all six effects in sequence', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: TrapPowerLab())),
      ),
    );
    await tester.pumpAndSettle();

    final playAll = find.byKey(const ValueKey('guide-play-all'));
    await tester.ensureVisible(playAll);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('guide-effect-stage'))).width,
      greaterThan(300),
    );
    await tester.tap(playAll);
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('Secuencia 1 de 6 · Escudo'), findsOneWidget);

    await tester.pump(
      TrapPowerLab.demoDuration + const Duration(milliseconds: 20),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Secuencia 2 de 6 · Turbo'), findsOneWidget);
    expect(find.text('Detener'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('trap screen sequence contains only the four real traps', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(const MaterialApp(home: TrapPowerLabScreen()));
    await tester.pumpAndSettle();

    expect(find.text('TRAMPAS Y ANIMACIONES'), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-effect-glue')), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-effect-setback')), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-effect-prison')), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-effect-bomb')), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-effect-shield')), findsNothing);
    expect(find.byKey(const ValueKey('guide-effect-turbo')), findsNothing);

    final playAll = find.byKey(const ValueKey('guide-play-all'));
    await tester.ensureVisible(playAll);
    await tester.pumpAndSettle();
    await tester.tap(playAll);
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('Secuencia 1 de 4 · Pegamento'), findsOneWidget);

    await tester.pump(
      TrapPowerLab.demoDuration + const Duration(milliseconds: 20),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Secuencia 2 de 4 · Retroceso'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('trap animations remain usable in iPhone landscape', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(844, 390));
    await tester.pumpWidget(const MaterialApp(home: TrapPowerLabScreen()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('trap-power-lab-scroll')), findsOneWidget);
    expect(find.byKey(const ValueKey('trap-lab-hero')), findsOneWidget);
    expect(find.byKey(const ValueKey('trap-lab-back')), findsOneWidget);
    final stage = find.byKey(const ValueKey('guide-effect-stage'));
    await tester.ensureVisible(stage);
    await tester.pumpAndSettle();
    expect(stage, findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('guide remains usable in iPhone landscape', (tester) async {
    await tester.binding.setSurfaceSize(const Size(844, 390));
    await tester.pumpWidget(
      const MaterialApp(
        home: GameGuideScreen(initialMode: GameGuideMode.chaos),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('game-guide-scroll')), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-hero')), findsOneWidget);
    expect(find.byKey(const ValueKey('show-power-lab')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });
}
