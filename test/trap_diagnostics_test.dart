import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';

void main() {
  const traps = <BoardTrap>[
    BoardTrap(owner: PlayerColor.red, type: PowerUp.setbackTrap, loopIndex: 3),
    BoardTrap(owner: PlayerColor.green, type: PowerUp.bomb, loopIndex: 20),
    BoardTrap(owner: PlayerColor.yellow, type: PowerUp.glueTrap, loopIndex: 37),
    BoardTrap(owner: PlayerColor.blue, type: PowerUp.prisonTrap, loopIndex: 54),
  ];

  test('a release build can never enable trap diagnostics', () {
    expect(
      resolveTrapDiagnosticsVisibility(isDebugBuild: false, requested: true),
      isFalse,
    );
    expect(
      resolveTrapDiagnosticsVisibility(isDebugBuild: true, requested: true),
      isTrue,
    );
    expect(
      resolveTrapDiagnosticsVisibility(isDebugBuild: true, requested: false),
      isFalse,
    );
  });

  testWidgets('test mode reveals every trap and uses its owner color', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1180, 820));
    final engine = GameEngine(mode: GameMode.chaos);
    engine.traps
      ..clear()
      ..addAll(traps);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'CPU • Fácil',
          gameEngine: engine,
          showAllTestTraps: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey('trap-diagnostics-strip')),
      findsOneWidget,
    );
    for (final trap in traps) {
      expect(
        find.byKey(
          ValueKey(
            'debug-trap-${trap.owner.name}-${trap.type.name}-${trap.loopIndex}',
          ),
        ),
        findsOneWidget,
      );
    }

    final customPaint =
        find
                .descendant(
                  of: find.byType(GameBoardMockup),
                  matching: find.byType(CustomPaint),
                )
                .evaluate()
                .single
                .widget
            as CustomPaint;
    final dynamic painter = customPaint.painter;
    final displayed = List<BoardTrap>.from(
      painter.displayedTraps as List<BoardTrap>,
    );
    expect(displayed, orderedEquals(traps));
    expect(painter.trapOwnerColor(traps[0]) as Color, PopColors.red);
    expect(painter.trapOwnerColor(traps[1]) as Color, PopColors.green);
    expect(painter.trapOwnerColor(traps[2]) as Color, PopColors.yellow);
    expect(painter.trapOwnerColor(traps[3]) as Color, PopColors.blue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    engine.dispose();
  });

  testWidgets('normal mode keeps rival traps hidden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1180, 820));
    final engine = GameEngine(mode: GameMode.chaos);
    engine.traps
      ..clear()
      ..addAll(traps);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'CPU • Fácil',
          gameEngine: engine,
          showAllTestTraps: false,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('trap-diagnostics-strip')), findsNothing);
    final customPaint =
        find
                .descendant(
                  of: find.byType(GameBoardMockup),
                  matching: find.byType(CustomPaint),
                )
                .evaluate()
                .single
                .widget
            as CustomPaint;
    final dynamic painter = customPaint.painter;
    final displayed = List<BoardTrap>.from(
      painter.displayedTraps as List<BoardTrap>,
    );
    expect(displayed, hasLength(1));
    expect(displayed.single.owner, PlayerColor.red);
    expect(displayed.single.type, PowerUp.setbackTrap);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    engine.dispose();
  });
}
