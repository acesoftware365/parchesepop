import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_analytics.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';
import 'package:parchesepop/tutorial_controller.dart';
import 'package:parchesepop/tutorial_scenario.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int attempts = 40,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(condition(), isTrue, reason: 'Condition was not reached in time.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('six short lessons execute real deterministic engine actions', () {
    final scenario = TutorialGameScenario.create(step: TutorialStep.firstRoll);
    final engine = scenario.engine;
    addTearDown(engine.dispose);

    expect(scenario.allowsRoll(TutorialStep.firstRoll), isTrue);
    engine.roll();
    expect(engine.dice, const <int>[5, 2]);
    expect(engine.eventHistory.last.type, GameEventType.roll);

    scenario.prepareFor(TutorialStep.releaseToken);
    var token = scenario.expectedToken(TutorialStep.releaseToken)!;
    expect(token.inNest, isTrue);
    expect(engine.canMove(token, 5), isTrue);
    expect(engine.moveToken(token, die: 5), isTrue);
    expect(token.progress, 0);
    expect(engine.eventHistory.last.type, GameEventType.departure);

    scenario.prepareFor(TutorialStep.chooseMove);
    token = scenario.expectedToken(TutorialStep.chooseMove)!;
    expect(engine.moveToken(token, die: 2), isTrue);
    expect(token.progress, 2);
    expect(engine.eventHistory.last.type, GameEventType.move);

    scenario.prepareFor(TutorialStep.safeSquare);
    token = scenario.expectedToken(TutorialStep.safeSquare)!;
    expect(engine.moveToken(token, die: 2), isTrue);
    expect(token.progress, 7);
    expect(engine.loopIndex(PlayerColor.red, token.progress), 7);
    expect(
      GameEngine.safeLoopIndices,
      contains(engine.loopIndex(PlayerColor.red, token.progress)),
    );

    scenario.prepareFor(TutorialStep.capture);
    token = scenario.expectedToken(TutorialStep.capture)!;
    final green = engine.players
        .firstWhere((player) => player.color == PlayerColor.green)
        .tokens
        .first;
    expect(engine.loopIndex(green.owner, green.progress), 10);
    expect(engine.moveToken(token, die: 3), isTrue);
    expect(token.progress, 10);
    expect(green.inNest, isTrue);
    expect(engine.remainingDice, contains(20));
    expect(
      engine.eventHistory.map((event) => event.type),
      contains(GameEventType.capture),
    );

    scenario.prepareFor(TutorialStep.reachHome);
    token = scenario.expectedToken(TutorialStep.reachHome)!;
    expect(token.progress, GameEngine.finishProgress - 1);
    expect(engine.moveToken(token, die: 1), isTrue);
    expect(token.finished, isTrue);
    expect(engine.gameOver, isFalse);
    expect(
      engine.eventHistory.map((event) => event.type),
      contains(GameEventType.goal),
    );
  });

  test('every resumed lesson exposes only its intended tutorial action', () {
    for (final step in TutorialController.orderedSteps) {
      final scenario = TutorialGameScenario.create(step: step);
      final engine = scenario.engine;

      if (step == TutorialStep.firstRoll) {
        expect(scenario.allowsRoll(step), isTrue);
        expect(scenario.expectedToken(step), isNull);
      } else {
        final token = scenario.expectedToken(step)!;
        final die = scenario.expectedDie(step)!;
        expect(scenario.allowsRoll(step), isFalse);
        expect(scenario.allowsToken(step, token), isTrue);
        expect(scenario.allowsMove(step, token, die), isTrue);
        expect(engine.canMove(token, die), isTrue);
        expect(scenario.allowsMove(step, token, die + 1), isFalse);
        final otherToken = engine.currentPlayer.tokens.firstWhere(
          (candidate) => candidate.id != token.id,
        );
        expect(scenario.allowsToken(step, otherToken), isFalse);
      }
      engine.dispose();
    }
  });

  testWidgets('phone tutorial completes all six steps without a CPU turn', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final tutorial = await TutorialController.create(
        analytics: const NoopGameAnalytics(),
      );
      addTearDown(tutorial.dispose);
      await tutorial.start();

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: GameScreen(
              opponent: 'Tutorial • CPU Fácil',
              tutorial: tutorial,
              guidedTutorial: true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final boardBefore = tester.getRect(
        find.byKey(const ValueKey('game-board')),
      );
      await tester.tap(find.byKey(const ValueKey('dice-roll-target')));
      await _pumpUntil(
        tester,
        () => tutorial.currentStep == TutorialStep.releaseToken,
      );
      await _pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('board-token-choice-callout'))
            .evaluate()
            .isNotEmpty,
      );
      expect(find.text('1 dado disponible'), findsNothing);
      final resultDecoration =
          tester
                  .widget<Container>(find.byKey(const ValueKey('dice-group')))
                  .decoration!
              as BoxDecoration;
      expect(resultDecoration.gradient, isNull);
      expect(resultDecoration.border, isNull);

      for (final expected in const <(TutorialStep, int)>[
        (TutorialStep.releaseToken, 5),
        (TutorialStep.chooseMove, 2),
        (TutorialStep.safeSquare, 2),
        (TutorialStep.capture, 3),
        (TutorialStep.reachHome, 1),
      ]) {
        expect(
          find.byKey(const ValueKey('board-token-choice-callout')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('board-token-choice-callout')),
        );
        await tester.pump();
        final choice = find.byKey(ValueKey('move-choice-${expected.$2}'));
        expect(choice.hitTestable(), findsOneWidget);
        await tester.tap(choice);
        await _pumpUntil(
          tester,
          () =>
              tutorial.lifecycle == TutorialLifecycle.completed ||
              (tutorial.currentStep != expected.$1 &&
                  find
                      .byKey(const ValueKey('board-token-choice-callout'))
                      .evaluate()
                      .isNotEmpty),
        );
      }

      expect(tutorial.lifecycle, TutorialLifecycle.completed);
      await _pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('tutorial-complete-card'))
            .evaluate()
            .isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 900));
      expect(
        find.byKey(const ValueKey('tutorial-complete-card')),
        findsOneWidget,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('game-board'))),
        boardBefore,
      );
      final engine = tester
          .widget<GameBoardMockup>(find.byType(GameBoardMockup))
          .engine;
      expect(engine.currentPlayer.color, PlayerColor.red);
      expect(engine.turnNumber, 1);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('guided tutorial preserves an existing match checkpoint', (
    tester,
  ) async {
    const checkpoint = '{"real":"match"}';
    SharedPreferences.setMockInitialValues(<String, Object>{
      'active_match_checkpoint': checkpoint,
    });
    final tutorial = await TutorialController.create(
      analytics: const NoopGameAnalytics(),
    );
    addTearDown(tutorial.dispose);
    await tutorial.start();

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'Tutorial • CPU Fácil',
          tutorial: tutorial,
          guidedTutorial: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('active_match_checkpoint'), checkpoint);
    await tester.tap(find.byKey(const ValueKey('tutorial-skip')));
    await tester.pump();
    expect(preferences.getString('active_match_checkpoint'), checkpoint);
    expect(tutorial.lifecycle, TutorialLifecycle.skipped);
  });
}
