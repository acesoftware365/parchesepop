import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';

void _putCurrentPlayerOneMoveFromFinishing(GameEngine engine) {
  final player = engine.currentPlayer;
  for (var tokenId = 0; tokenId < player.tokens.length - 1; tokenId++) {
    player.tokens[tokenId].progress = GameEngine.finishProgress;
  }
  player.tokens.last.progress = GameEngine.finishProgress - 1;
  engine
    ..hasRolled = true
    ..dice = const [1, 2];
  engine.remainingDice
    ..clear()
    ..addAll(const [1, 2]);
}

GameEngine _completedMatch() {
  final engine = GameEngine();
  _putCurrentPlayerOneMoveFromFinishing(engine);
  expect(engine.moveToken(engine.currentPlayer.tokens.last, die: 1), isTrue);
  expect(engine.canContinueAfterWinner, isTrue);
  expect(engine.continueAfterWinner(), isTrue);

  for (final expectedColor in const [PlayerColor.green, PlayerColor.yellow]) {
    expect(engine.currentPlayer.color, expectedColor);
    _putCurrentPlayerOneMoveFromFinishing(engine);
    expect(engine.moveToken(engine.currentPlayer.tokens.last, die: 1), isTrue);
  }

  expect(engine.gameOver, isTrue);
  expect(engine.standingsComplete, isTrue);
  return engine;
}

GameEngine _matchWithOnlyFirstPlaceDecided() {
  final engine = GameEngine();
  _putCurrentPlayerOneMoveFromFinishing(engine);
  expect(engine.moveToken(engine.currentPlayer.tokens.last, die: 1), isTrue);
  expect(engine.gameOver, isTrue);
  expect(engine.canContinueAfterWinner, isTrue);
  expect(engine.standingsComplete, isFalse);
  return engine;
}

void main() {
  testWidgets(
    'first winner stays on the result screen while other places are pending',
    (tester) async {
      final engine = _matchWithOnlyFirstPlaceDecided();
      addTearDown(engine.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(opponent: 'Online', gameEngine: engine),
          routes: {
            '/home': (_) => const Scaffold(
              body: SizedBox(key: ValueKey('home-route-marker')),
            ),
          },
        ),
      );

      await tester.pump(const Duration(milliseconds: 1800));
      expect(
        find.byKey(const ValueKey('victory-continue-watching')),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 6));

      expect(find.byType(GameScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('home-route-marker')), findsNothing);
      expect(
        find.byKey(const ValueKey('victory-continue-watching')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'complete standings stay visible for five seconds then return home',
    (tester) async {
      final engine = _completedMatch();
      addTearDown(engine.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(opponent: 'Online', gameEngine: engine),
          routes: {
            '/home': (_) => const Scaffold(
              body: SizedBox(key: ValueKey('home-route-marker')),
            ),
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 1800));

      expect(find.byKey(const ValueKey('final-ranking')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-route-marker')), findsNothing);

      await tester.pump(const Duration(milliseconds: 4900));
      expect(find.byKey(const ValueKey('final-ranking')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-route-marker')), findsNothing);

      await tester.pump(const Duration(milliseconds: 101));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('home-route-marker')), findsOneWidget);
      expect(find.byType(GameScreen), findsNothing);
    },
  );

  testWidgets('spectator mode offers an explicit exit to the home route', (
    tester,
  ) async {
    final engine = _matchWithOnlyFirstPlaceDecided();
    addTearDown(engine.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'Online',
          gameEngine: engine,
          cpuThinkDelayProvider: () => const Duration(seconds: 10),
        ),
        routes: {
          '/home': (_) => const Scaffold(
            body: SizedBox(key: ValueKey('home-route-marker')),
          ),
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.tap(find.byKey(const ValueKey('victory-continue-watching')));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('spectator-bar')), findsOneWidget);
    final exitButton = find.byKey(const ValueKey('spectator-exit-button'));
    expect(exitButton.hitTestable(), findsOneWidget);

    await tester.tap(exitButton);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-route-marker')), findsOneWidget);
    expect(find.byType(GameScreen), findsNothing);
    await tester.pump(const Duration(seconds: 10));
  });
}
