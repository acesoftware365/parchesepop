import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';
import 'package:parchesepop/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _useViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
}

double _cameraScale(WidgetTester tester) => tester
    .widget<Transform>(
      find.byKey(const ValueKey('mobile-board-camera-transform')),
    )
    .transform
    .storage[0];

const _navigatorKey = ValueKey('mobile-board-navigator');
const _windowKey = ValueKey('mobile-board-navigator-window');

Offset _navigatorPoint(WidgetTester tester, Offset normalized) {
  final rect = tester.getRect(find.byKey(_navigatorKey));
  return rect.topLeft +
      Offset(rect.width * normalized.dx, rect.height * normalized.dy);
}

void _expectWindowAt(
  WidgetTester tester, {
  required Offset focus,
  required bool fullBoard,
}) {
  final navigator = tester.getRect(find.byKey(_navigatorKey));
  final expected = mobileBoardViewportRectForTesting(
    size: navigator.size,
    focus: focus,
    fullBoard: fullBoard,
  ).deflate(3).shift(navigator.topLeft);
  final actual = tester.getRect(find.byKey(_windowKey));

  expect(actual.left, closeTo(expected.left, 1));
  expect(actual.top, closeTo(expected.top, 1));
  expect(actual.width, closeTo(expected.width, 1));
  expect(actual.height, closeTo(expected.height, 1));
}

void _expectFullBoard(WidgetTester tester) {
  expect(_cameraScale(tester), closeTo(1, .001));
  _expectWindowAt(tester, focus: const Offset(.5, .5), fullBoard: true);
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

  test('mobile viewport stays inside the miniature at every edge', () {
    const size = Size.square(180);
    final topLeft = mobileBoardViewportRectForTesting(
      size: size,
      focus: Offset.zero,
    );
    final bottomRight = mobileBoardViewportRectForTesting(
      size: size,
      focus: const Offset(1, 1),
    );

    expect(topLeft.left, closeTo(0, .001));
    expect(topLeft.top, closeTo(0, .001));
    expect(bottomRight.right, closeTo(size.width, .001));
    expect(bottomRight.bottom, closeTo(size.height, .001));
    expect(topLeft.width, closeTo(90, .001));
    expect(
      mobileBoardViewportRectForTesting(
        size: size,
        focus: Offset.zero,
        fullBoard: true,
      ),
      Offset.zero & size,
    );
  });

  testWidgets('phone viewer zooms only while a finger touches the minimap', (
    tester,
  ) async {
    _useViewport(tester, const Size(390, 844));
    final engine = GameEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(_navigatorKey), findsOneWidget);
    expect(find.byType(GameBoardMockup), findsOneWidget);
    _expectFullBoard(tester);

    const firstFocus = Offset(.78, .28);
    final finger = await tester.startGesture(
      _navigatorPoint(tester, firstFocus),
    );
    await tester.pump();

    expect(_cameraScale(tester), closeTo(2.0, .001));
    _expectWindowAt(tester, focus: firstFocus, fullBoard: false);
    final manualWindow = tester.getRect(find.byKey(_windowKey));
    final navigator = tester.getRect(find.byKey(_navigatorKey));
    expect(manualWindow.width, lessThan(navigator.width * .60));
    expect(manualWindow.center.dx, greaterThan(navigator.center.dx));
    expect(manualWindow.center.dy, lessThan(navigator.center.dy));

    const secondFocus = Offset(.30, .72);
    await finger.moveTo(_navigatorPoint(tester, secondFocus));
    await tester.pump();
    final movedWindow = tester.getRect(find.byKey(_windowKey));
    expect(_cameraScale(tester), closeTo(2.0, .001));
    expect(movedWindow.center.dx, lessThan(manualWindow.center.dx));
    expect(movedWindow.center.dy, greaterThan(manualWindow.center.dy));
    _expectWindowAt(tester, focus: secondFocus, fullBoard: false);

    await finger.up();
    await tester.pump();
    _expectFullBoard(tester);

    await tester.tapAt(_navigatorPoint(tester, const Offset(.25, .75)));
    await tester.pump();
    _expectFullBoard(tester);

    expect(
      find.byKey(const ValueKey('mobile-board-follow-token')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('mobile-board-full-view')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the move phase keeps the HUD and board stable when cancelled', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    _useViewport(tester, const Size(402, 707));
    final engine = GameEngine();
    final wallet = await WalletController.create();
    engine.currentPlayer.tokens.first.progress = 0;
    engine.hasRolled = true;
    engine.dice = const [2, 3];
    engine.remainingDice.addAll(const [2, 3]);
    addTearDown(engine.dispose);
    addTearDown(wallet.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'CPU • Fácil',
          gameEngine: engine,
          wallet: wallet,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final boardFinder = find.byKey(const ValueKey('game-board'));
    final hudFinder = find.byKey(const ValueKey('portrait-game-hud'));
    final boardBefore = tester.getRect(boardFinder);
    final hudBefore = tester.getRect(hudFinder);
    expect(boardBefore.width, closeTo(402, 1));
    expect(boardBefore.height, closeTo(402, 1));
    expect(hudBefore.bottom, lessThanOrEqualTo(707));
    expect(hudFinder, findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile-board-navigator')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-hud-hidden-for-action')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('game-content-area')),
        matching: find.byType(Scrollable),
      ),
      findsNothing,
    );

    final tokenCell = GameEngine.loop.first;
    final tokenPosition = _boardCellGlobalPosition(tester, tokenCell);
    expect(boardBefore.contains(tokenPosition), isTrue);
    final tokenPrompt = find.byKey(
      const ValueKey('board-token-choice-callout'),
    );
    expect(tokenPrompt, findsOneWidget);
    await tester.tap(tokenPrompt);
    await tester.pump();

    final callouts = find.byKey(const ValueKey('board-move-callout-layer'));
    expect(callouts, findsOneWidget);
    expect(
      find.descendant(of: boardFinder, matching: callouts),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('token-move-popup')), findsNothing);
    expect(hudFinder, findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile-board-navigator')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-hud-hidden-for-action')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('game-content-area')),
        matching: find.byType(Scrollable),
      ),
      findsNothing,
    );
    final boardDuringChoice = tester.getRect(boardFinder);
    final hudDuringChoice = tester.getRect(hudFinder);
    expect(boardDuringChoice.left, closeTo(boardBefore.left, .5));
    expect(boardDuringChoice.top, closeTo(boardBefore.top, .5));
    expect(boardDuringChoice.width, closeTo(boardBefore.width, .5));
    expect(boardDuringChoice.height, closeTo(boardBefore.height, .5));
    expect(hudDuringChoice.left, closeTo(hudBefore.left, .5));
    expect(hudDuringChoice.top, closeTo(hudBefore.top, .5));
    expect(hudDuringChoice.width, closeTo(hudBefore.width, .5));
    expect(hudDuringChoice.height, closeTo(hudBefore.height, .5));
    final navigatorGesture = await tester.startGesture(
      _navigatorPoint(tester, const Offset(.72, .28)),
    );
    await tester.pump();
    expect(_cameraScale(tester), closeTo(2, .001));
    await navigatorGesture.up();
    await tester.pump();
    _expectFullBoard(tester);
    expect(callouts, findsOneWidget);
    final remainingBeforeDisabledDiceTap = [...engine.remainingDice];
    final progressBeforeDisabledDiceTap =
        engine.currentPlayer.tokens.first.progress;
    final semantics = tester.ensureSemantics();
    try {
      for (final key in const [
        ValueKey('dice-roll-target'),
        ValueKey('die-slot-0'),
        ValueKey('die-slot-1'),
      ]) {
        expect(
          tester.getSemantics(find.byKey(key)),
          containsSemantics(
            hasEnabledState: true,
            isEnabled: false,
            hasTapAction: false,
          ),
        );
      }
    } finally {
      semantics.dispose();
    }
    await tester.tap(find.byKey(const ValueKey('die-slot-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('die-slot-1')));
    await tester.pump();
    expect(engine.remainingDice, remainingBeforeDisabledDiceTap);
    expect(
      engine.currentPlayer.tokens.first.progress,
      progressBeforeDisabledDiceTap,
    );
    expect(callouts, findsOneWidget);
    for (final key in const [
      ValueKey('move-choice-2'),
      ValueKey('move-choice-3'),
      ValueKey('move-choice-all'),
    ]) {
      final choiceRect = tester.getRect(find.byKey(key));
      expect(choiceRect.width, greaterThanOrEqualTo(48));
      expect(choiceRect.height, greaterThanOrEqualTo(48));
      expect(boardDuringChoice.inflate(1).contains(choiceRect.topLeft), isTrue);
      expect(
        boardDuringChoice.inflate(1).contains(choiceRect.bottomRight),
        isTrue,
      );
    }

    await tester.tapAt(_boardCellGlobalPosition(tester, const Offset(10, 10)));
    await tester.pump();

    expect(callouts, findsNothing);
    expect(hudFinder, findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile-board-navigator')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-hud-hidden-for-action')),
      findsNothing,
    );
    final boardAfterCancel = tester.getRect(boardFinder);
    final hudAfterCancel = tester.getRect(hudFinder);
    expect(boardAfterCancel.left, closeTo(boardBefore.left, .5));
    expect(boardAfterCancel.top, closeTo(boardBefore.top, .5));
    expect(boardAfterCancel.width, closeTo(boardBefore.width, .5));
    expect(boardAfterCancel.height, closeTo(boardBefore.height, .5));
    expect(hudAfterCancel.left, closeTo(hudBefore.left, .5));
    expect(hudAfterCancel.top, closeTo(hudBefore.top, .5));
    expect(hudAfterCancel.width, closeTo(hudBefore.width, .5));
    expect(hudAfterCancel.height, closeTo(hudBefore.height, .5));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('game-content-area')),
        matching: find.byType(Scrollable),
      ),
      findsNothing,
    );
    expect(engine.remainingDice, const [2, 3]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('START 5 keeps the large board for the remaining die', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    _useViewport(tester, const Size(402, 707));
    final engine = GameEngine(mode: GameMode.chaos);
    final wallet = await WalletController.create();
    final token = engine.currentPlayer.tokens.first;
    engine.currentPlayer.inventory = PowerUp.boost;
    engine.hasRolled = true;
    engine.dice = const [5, 2];
    engine.remainingDice.addAll(const [5, 2]);
    addTearDown(engine.dispose);
    addTearDown(wallet.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'CPU • Fácil',
          mode: GameMode.chaos,
          gameEngine: engine,
          wallet: wallet,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final boardFinder = find.byKey(const ValueKey('game-board'));
    final boardBeforeSelection = tester.getRect(boardFinder);
    expect(boardBeforeSelection.width, closeTo(402, 1));
    expect(boardBeforeSelection.height, closeTo(402, 1));
    expect(find.byKey(const ValueKey('portrait-game-hud')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile-board-navigator')),
      findsOneWidget,
    );
    final itemAction = find.byKey(const ValueKey('item-action'));
    expect(tester.widget<OutlinedButton>(itemAction).onPressed, isNotNull);

    final tokenCell = displayTokenCellsForTesting(
      engine,
      compactPhone: true,
    )[token]!;
    await tester.tapAt(_boardCellGlobalPosition(tester, tokenCell));
    await tester.pump();

    final startChoice = find.byKey(
      const ValueKey('board-move-callout-token-0-die-5'),
    );
    expect(startChoice, findsOneWidget);
    expect(tester.widget<OutlinedButton>(itemAction).onPressed, isNull);
    final boardWithStartChoice = tester.getRect(boardFinder);
    expect(boardWithStartChoice.width, closeTo(boardBeforeSelection.width, .5));
    expect(
      boardWithStartChoice.height,
      closeTo(boardBeforeSelection.height, .5),
    );

    await tester.tap(startChoice);
    await tester.pump();

    expect(token.progress, 0);
    expect(engine.remainingDice, const [2]);
    expect(find.byKey(const ValueKey('portrait-game-hud')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile-board-navigator')),
      findsOneWidget,
    );
    expect(tester.widget<OutlinedButton>(itemAction).onPressed, isNotNull);
    final boardAfterStart = tester.getRect(boardFinder);
    expect(boardAfterStart.width, closeTo(boardBeforeSelection.width, .5));
    expect(boardAfterStart.height, closeTo(boardBeforeSelection.height, .5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a trap alert floats over the board without resizing it', (
    tester,
  ) async {
    _useViewport(tester, const Size(402, 707));
    final engine = GameEngine(mode: GameMode.chaos);
    const trapIndex = 26;
    engine.traps.add(
      const BoardTrap(
        owner: PlayerColor.green,
        type: PowerUp.prisonTrap,
        loopIndex: trapIndex,
      ),
    );
    final token = engine.currentPlayer.tokens.first..progress = trapIndex - 1;
    engine.hasRolled = true;
    engine.dice = const [1, 5];
    engine.remainingDice.addAll(const [1, 5]);
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'CPU • Fácil',
          mode: GameMode.chaos,
          gameEngine: engine,
          showAllTestTraps: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final boardFinder = find.byKey(const ValueKey('game-board'));
    final boardBeforeTrap = tester.getRect(boardFinder);
    expect(find.byKey(const ValueKey('trap-diagnostics-strip')), findsNothing);

    expect(engine.moveToken(token, die: 1), isTrue);
    await tester.pump();

    final alert = find.byKey(const ValueKey('trap-alert-banner'));
    expect(alert, findsOneWidget);
    expect(find.descendant(of: boardFinder, matching: alert), findsOneWidget);
    final boardDuringTrap = tester.getRect(boardFinder);
    expect(boardDuringTrap.width, closeTo(boardBeforeTrap.width, .5));
    expect(boardDuringTrap.height, closeTo(boardBeforeTrap.height, .5));

    await tester.pump(const Duration(milliseconds: 2201));
    expect(alert, findsNothing);
    final boardAfterTrap = tester.getRect(boardFinder);
    expect(boardAfterTrap.width, closeTo(boardBeforeTrap.width, .5));
    expect(boardAfterTrap.height, closeTo(boardBeforeTrap.height, .5));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'short iPhone layout keeps dice upper left and minimap upper right',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      _useViewport(tester, const Size(402, 707));
      final engine = GameEngine(mode: GameMode.chaos);
      final wallet = await WalletController.create();
      engine.currentPlayer.tokens.first.progress = 0;
      addTearDown(engine.dispose);
      addTearDown(wallet.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            opponent: 'CPU • Fácil',
            mode: GameMode.chaos,
            gameEngine: engine,
            wallet: wallet,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final content = find.byKey(const ValueKey('game-content-area'));
      final board = tester.getRect(find.byKey(const ValueKey('game-board')));
      final hud = tester.getRect(
        find.byKey(const ValueKey('portrait-game-hud')),
      );
      final diceColumn = tester.getRect(
        find.byKey(const ValueKey('portrait-dice-column')),
      );
      final minimapColumn = tester.getRect(
        find.byKey(const ValueKey('portrait-minimap-column')),
      );

      expect(
        find.descendant(of: content, matching: find.byType(Scrollable)),
        findsNothing,
      );
      expect((board.width - board.height).abs(), lessThanOrEqualTo(.5));
      expect(board.width, closeTo(402, 1));
      expect(diceColumn.left, lessThan(minimapColumn.left));
      expect(diceColumn.top, closeTo(minimapColumn.top, .5));
      expect(hud.bottom, lessThanOrEqualTo(707));
      expect(
        find.byKey(const ValueKey('dice-roll-target')).hitTestable(),
        findsOne,
      );
      expect(find.byKey(_navigatorKey).hitTestable(), findsOne);
      expect(find.byKey(const ValueKey('roll-action')), findsNothing);
      expect(find.text('⚡ CAOS'), findsNothing);
      expect(find.byKey(const ValueKey('game-mode-indicator')), findsOneWidget);
      final cosmeticsButton = find.byKey(
        const ValueKey('game-owned-cosmetics-button'),
      );
      expect(cosmeticsButton.hitTestable(), findsOneWidget);
      expect(tester.getSize(cosmeticsButton), const Size.square(44));

      final initialRollSerial = engine.rollSerial;
      await tester.tap(find.byKey(const ValueKey('dice-roll-target')));
      await tester.pump();
      expect(engine.rollSerial, initialRollSerial + 1);
      expect(find.byKey(const ValueKey('portrait-game-hud')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mobile-hud-hidden-for-action')),
        findsNothing,
      );
      final boardAfterRoll = tester.getRect(
        find.byKey(const ValueKey('game-board')),
      );
      expect(boardAfterRoll.left, closeTo(board.left, .5));
      expect(boardAfterRoll.top, closeTo(board.top, .5));
      expect(boardAfterRoll.width, closeTo(board.width, .5));
      expect(boardAfterRoll.height, closeTo(board.height, .5));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tapping a board callout executes that exact move', (
    tester,
  ) async {
    _useViewport(tester, const Size(390, 844));
    final engine = GameEngine();
    final token = engine.currentPlayer.tokens.first..progress = 0;
    engine.hasRolled = true;
    engine.dice = const [1, 6];
    engine.remainingDice.addAll(const [1, 6]);
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tapAt(_boardCellGlobalPosition(tester, GameEngine.loop.first));
    await tester.pump();

    final allDiceCallout = find.byKey(
      const ValueKey('board-move-callout-token-0-all'),
    );
    expect(allDiceCallout, findsOneWidget);
    expect(find.byKey(const ValueKey('move-choice-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('move-choice-6')), findsOneWidget);
    expect(find.byKey(const ValueKey('move-choice-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('portrait-game-hud')), findsOneWidget);

    await tester.tap(allDiceCallout);
    await tester.pump();

    expect(token.progress, 7);
    expect(engine.remainingDice, isEmpty);
    expect(
      find.byKey(const ValueKey('board-move-callout-layer')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('portrait-game-hud')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile-hud-hidden-for-action')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    engine.gameOver = true;
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('right-hand roll guide stays visible and never blocks dice', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      settingsRollGuideKey: true,
      settingsDiceHandKey: DiceHandPreference.right.name,
    });
    _useViewport(tester, const Size(402, 707));
    final engine = GameEngine();

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('dice-roll-guide')), findsNothing);

    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byKey(const ValueKey('dice-roll-guide')), findsOneWidget);
    expect(find.byKey(const ValueKey('dice-roll-guide-right')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('dice-roll-target')).hitTestable(),
      findsOne,
    );

    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(const ValueKey('dice-roll-guide-right')), findsOneWidget);

    final initialRollSerial = engine.rollSerial;
    await tester.tap(find.byKey(const ValueKey('dice-roll-target')));
    await tester.pump();
    expect(engine.rollSerial, initialRollSerial + 1);
    expect(find.byKey(const ValueKey('dice-roll-guide')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    engine.dispose();
  });

  testWidgets('left-hand preference mirrors the roll guide', (tester) async {
    SharedPreferences.setMockInitialValues({
      settingsRollGuideKey: true,
      settingsDiceHandKey: DiceHandPreference.left.name,
    });
    _useViewport(tester, const Size(402, 707));
    final engine = GameEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const ValueKey('dice-roll-guide-left')), findsOneWidget);
    expect(find.byKey(const ValueKey('dice-roll-guide-right')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled roll guide never appears', (tester) async {
    SharedPreferences.setMockInitialValues({settingsRollGuideKey: false});
    _useViewport(tester, const Size(402, 707));
    final engine = GameEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const ValueKey('dice-roll-guide')), findsNothing);
    expect(
      find.byKey(const ValueKey('dice-roll-target')).hitTestable(),
      findsOne,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion uses a static roll cue', (tester) async {
    SharedPreferences.setMockInitialValues({
      settingsRollGuideKey: true,
      settingsDiceHandKey: DiceHandPreference.left.name,
    });
    _useViewport(tester, const Size(402, 707));
    final engine = GameEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(402, 707),
            disableAnimations: true,
          ),
          child: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.byKey(const ValueKey('dice-roll-guide-static-left')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('dice-roll-guide')),
        matching: find.byType(TweenAnimationBuilder<double>),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('active match reloads the selected hand after Settings closes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      settingsRollGuideKey: true,
      settingsDiceHandKey: DiceHandPreference.right.name,
    });
    _useViewport(tester, const Size(402, 707));
    final engine = GameEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    await tester.tap(find.byKey(const ValueKey('game-settings-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-dice-hand-left')),
    );
    await tester.tap(find.byKey(const ValueKey('settings-dice-hand-left')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.ensureVisible(find.byKey(const ValueKey('settings-back')));
    await tester.tap(find.byKey(const ValueKey('settings-back')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byKey(const ValueKey('dice-roll-guide-left')), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getString(settingsDiceHandKey),
      DiceHandPreference.left.name,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a legal five guides a jailed piece without blocking its selection',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        settingsRollGuideKey: true,
        settingsDiceHandKey: DiceHandPreference.right.name,
      });
      _useViewport(tester, const Size(390, 844));
      final engine = GameEngine(mode: GameMode.traditional);
      addTearDown(engine.dispose);
      engine.hasRolled = true;
      engine.dice = [5, 2];
      engine.remainingDice.addAll([5, 2]);
      final guidedToken = engine.currentPlayer.tokens[1];

      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.byKey(const ValueKey('token-choice-guide')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('token-choice-guide-right')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('token-choice-guide-target-1')),
        findsOneWidget,
      );

      await tester.tapAt(
        _boardCellGlobalPosition(
          tester,
          displayTokenCellsForTesting(engine, compactPhone: true)[guidedToken]!,
        ),
      );
      await tester.pump();

      expect(guidedToken.inNest, isTrue);
      expect(
        find.byKey(const ValueKey('board-move-callout-layer')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('token-move-popup')), findsNothing);
      expect(find.byKey(const ValueKey('move-choice-5')), findsOneWidget);
      expect(find.byKey(const ValueKey('portrait-game-hud')), findsOneWidget);
      expect(find.byKey(_navigatorKey), findsOneWidget);
      expect(find.byKey(const ValueKey('token-choice-guide')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a spent or blocked five never shows the token guide', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({settingsRollGuideKey: true});
    _useViewport(tester, const Size(390, 844));
    final spentEngine = GameEngine(mode: GameMode.traditional);
    addTearDown(spentEngine.dispose);
    spentEngine.hasRolled = true;
    spentEngine.dice = [5, 2];
    spentEngine.remainingDice.add(2);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', gameEngine: spentEngine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const ValueKey('token-choice-guide')), findsNothing);

    final blockedEngine = GameEngine(mode: GameMode.traditional);
    addTearDown(blockedEngine.dispose);
    blockedEngine.currentPlayer.tokens[0].progress = 0;
    blockedEngine.currentPlayer.tokens[1].progress = 0;
    blockedEngine.hasRolled = true;
    blockedEngine.dice = [5, 3];
    blockedEngine.remainingDice.addAll([5, 3]);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', gameEngine: blockedEngine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      blockedEngine.canMove(blockedEngine.currentPlayer.tokens[2], 5),
      isFalse,
    );
    expect(find.byKey(const ValueKey('token-choice-guide')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion keeps the left token guide static', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      settingsRollGuideKey: true,
      settingsDiceHandKey: DiceHandPreference.left.name,
    });
    _useViewport(tester, const Size(390, 844));
    final engine = GameEngine(mode: GameMode.traditional);
    addTearDown(engine.dispose);
    engine.hasRolled = true;
    engine.dice = [5, 2];
    engine.remainingDice.addAll([5, 2]);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            disableAnimations: true,
          ),
          child: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      find.byKey(const ValueKey('token-choice-guide-static-left')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('token-choice-guide-target-0')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('token-choice-guide')),
        matching: find.byType(AnimatedBuilder),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled roll guide never points at a jailed piece', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({settingsRollGuideKey: false});
    _useViewport(tester, const Size(390, 844));
    final engine = GameEngine(mode: GameMode.traditional);
    addTearDown(engine.dispose);
    engine.hasRolled = true;
    engine.dice = [5, 2];
    engine.remainingDice.addAll([5, 2]);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const ValueKey('token-choice-guide')), findsNothing);
    expect(engine.legalDiceFor(engine.currentPlayer.tokens.first), contains(5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('canceling a minimap touch always restores the full board', (
    tester,
  ) async {
    _useViewport(tester, const Size(390, 844));
    final engine = GameEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final finger = await tester.startGesture(
      _navigatorPoint(tester, const Offset(.70, .35)),
    );
    await tester.pump();
    expect(_cameraScale(tester), closeTo(2.0, .001));

    await finger.moveTo(_navigatorPoint(tester, const Offset(.35, .70)));
    await tester.pump();
    expect(_cameraScale(tester), closeTo(2.0, .001));

    await finger.cancel();
    await tester.pump();

    _expectFullBoard(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('viewer is exclusive to compact portrait phones', (tester) async {
    final engine = GameEngine();
    addTearDown(engine.dispose);

    Future<void> expectViewer(Size size, bool visible) async {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: size),
            child: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const ValueKey('mobile-board-navigator')),
        visible ? findsOneWidget : findsNothing,
      );
      expect(find.byType(GameBoardMockup), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    addTearDown(() => tester.binding.setSurfaceSize(null));
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await expectViewer(const Size(390, 844), true);
      await expectViewer(const Size(844, 390), false);
      await expectViewer(const Size(600, 960), false);

      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await expectViewer(const Size(390, 844), false);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
