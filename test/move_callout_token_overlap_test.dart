import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';

const _iphone17Viewport = Size(402, 874);

void _useIphone17Viewport(WidgetTester tester) {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = _iphone17Viewport;
  addTearDown(() {
    debugDefaultTargetPlatformOverride = null;
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });
}

Offset _boardCellGlobalPosition(WidgetTester tester, Offset logicalCell) {
  final plane = tester.renderObject<RenderBox>(
    find.byKey(const ValueKey('game-board-hit-plane')),
  );
  const gutter = .08;
  final cell = plane.size.width / (20 + gutter * 2);
  final inset = gutter * cell;
  return plane.localToGlobal(
    Offset(inset + logicalCell.dx * cell, inset + logicalCell.dy * cell),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a move bubble leaves another selectable piece uncovered', (
    tester,
  ) async {
    _useIphone17Viewport(tester);
    final engine = GameEngine(mode: GameMode.traditional);
    final selected = engine.currentPlayer.tokens[0]..progress = 0;
    final covered = engine.currentPlayer.tokens[1]..progress = 7;
    engine
      ..hasRolled = true
      ..dice = const [2, 3]
      ..message = 'Choose a piece.';
    engine.remainingDice.addAll(const [2, 3]);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Easy', gameEngine: engine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(
      _boardCellGlobalPosition(tester, engine.tokenCell(selected)!),
    );
    await tester.pump();

    final coveringCallout = find.byKey(
      const ValueKey('board-move-callout-token-0-all'),
    );
    final coveredTokenCenter = _boardCellGlobalPosition(
      tester,
      engine.tokenCell(covered)!,
    );
    expect(coveringCallout, findsOneWidget);
    expect(
      tester.getRect(coveringCallout).contains(coveredTokenCenter),
      isFalse,
      reason: 'Move bubbles should prefer open board space over a piece.',
    );

    await tester.tapAt(coveredTokenCenter);
    await tester.pump();

    expect(selected.progress, 0, reason: 'The selected piece must not move.');
    expect(covered.progress, 7, reason: 'A selection tap must not move it.');
    expect(
      find.byKey(const ValueKey('board-move-callout-token-1-die-2')),
      findsOneWidget,
      reason: 'The covered piece should replace the current selection.',
    );
    expect(engine.remainingDice, const [2, 3]);

    engine.gameOver = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    engine.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a piece below an unavoidable crowded bubble receives the tap', (
    tester,
  ) async {
    _useIphone17Viewport(tester);
    final engine = GameEngine(mode: GameMode.traditional);
    final selected = engine.currentPlayer.tokens[0]..progress = 41;
    engine.currentPlayer.tokens[1].progress = 34;
    engine.currentPlayer.tokens[2].progress = 0;
    final covered = engine.currentPlayer.tokens[3]..progress = 50;
    engine
      ..hasRolled = true
      ..dice = const [2, 3]
      ..message = 'Choose a piece.';
    engine.remainingDice.addAll(const [2, 3]);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Easy', gameEngine: engine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(
      _boardCellGlobalPosition(tester, engine.tokenCell(selected)!),
    );
    await tester.pump();

    final unavoidableCallout = find.byKey(
      const ValueKey('board-move-callout-token-0-all'),
    );
    final coveredTokenCenter = _boardCellGlobalPosition(
      tester,
      engine.tokenCell(covered)!,
    );
    expect(unavoidableCallout, findsOneWidget);
    expect(
      tester.getRect(unavoidableCallout).contains(coveredTokenCenter),
      isTrue,
      reason: 'This crowded arrangement exercises the tap-through fallback.',
    );

    await tester.tapAt(coveredTokenCenter);
    await tester.pump();

    expect(selected.progress, 41, reason: 'The ALL move must not execute.');
    expect(covered.progress, 50, reason: 'A selection tap must not move it.');
    expect(
      find.byKey(const ValueKey('board-move-callout-token-3-die-2')),
      findsOneWidget,
      reason: 'The piece below the bubble should become selected.',
    );
    expect(engine.remainingDice, const [2, 3]);

    engine.gameOver = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    engine.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
