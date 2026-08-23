import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/app_language.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';

const _iphone17Viewport = Size(402, 874);

void _usePhoneViewport(WidgetTester tester, {Size size = _iphone17Viewport}) {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
  addTearDown(() {
    debugDefaultTargetPlatformOverride = null;
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });
}

Future<void> _tapBoardCell(WidgetTester tester, Offset cell) async {
  final board = find.byKey(const ValueKey('game-board'));
  final rect = tester.getRect(board);
  final boardWidget = tester.widget<GameBoardMockup>(
    find.byType(GameBoardMockup),
  );
  final frameGutterCells = boardWidget.compactPhone ? .08 : .26;
  final boardCell = rect.width / (20 + frameGutterCells * 2);
  final inset = boardCell * frameGutterCells;
  await tester.tapAt(
    Offset(
      rect.left + inset + boardCell * cell.dx,
      rect.top + inset + boardCell * cell.dy,
    ),
  );
  await tester.pump();
}

GameToken _placeOnGlobal(
  GameEngine engine,
  PlayerColor color,
  int tokenIndex,
  int globalIndex,
) {
  final player = engine.players.firstWhere(
    (candidate) => candidate.color == color,
  );
  return player.tokens[tokenIndex]
    ..progress =
        (globalIndex - GameEngine.startOffset[color]!) % GameEngine.loopLength;
}

Finder get _killLabels => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith('move-choice-kill-');
});

Finder get _boardCallouts => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> &&
      key.value.startsWith('board-move-callout-token-');
});

void _expectCalloutsAccessibleAndInsideBoard(WidgetTester tester) {
  final boardRect = tester.getRect(find.byKey(const ValueKey('game-board')));
  final calloutElements = _boardCallouts.evaluate().toList();
  expect(calloutElements, isNotEmpty);

  for (final element in calloutElements) {
    final callout = find.byElementPredicate(
      (candidate) => identical(candidate, element),
    );
    final rect = tester.getRect(callout);
    expect(
      rect.width,
      greaterThanOrEqualTo(48),
      reason: '${element.widget.key} must remain a 48-point touch target.',
    );
    expect(
      rect.height,
      greaterThanOrEqualTo(48),
      reason: '${element.widget.key} must remain a 48-point touch target.',
    );
    expect(
      boardRect.contains(rect.topLeft),
      isTrue,
      reason: '${element.widget.key} starts outside the visible board.',
    );
    expect(
      boardRect.contains(rect.bottomRight),
      isTrue,
      reason: '${element.widget.key} ends outside the visible board.',
    );
  }
}

Future<void> _disposeGame(WidgetTester tester, GameEngine engine) async {
  engine.gameOver = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  engine.dispose();
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    binding.platformDispatcher.localeTestValue = const Locale('en');
  });
  tearDown(() {
    binding.platformDispatcher.clearLocaleTestValue();
  });

  testWidgets(
    'Quick Pop capture shows steps, KILL BLUE, and accessible semantics',
    (tester) async {
      _usePhoneViewport(tester);
      final semantics = tester.ensureSemantics();
      final language = AppLanguageController();
      addTearDown(language.dispose);

      final engine = GameEngine(matchFormat: MatchFormat.quickPop);
      final mover = engine.currentPlayer.tokens.first..progress = 1;
      engine.currentPlayer.tokens.last.progress = 12;
      _placeOnGlobal(engine, PlayerColor.blue, 0, 3);
      _placeOnGlobal(engine, PlayerColor.blue, 1, 26);
      engine
        ..hasRolled = true
        ..dice = const <int>[2, 6]
        ..message = 'You rolled 2 and 6.';
      engine.remainingDice.addAll(const <int>[2, 6]);

      await tester.pumpWidget(
        AppLanguageScope(
          controller: language,
          child: MaterialApp(
            locale: const Locale('en'),
            home: GameScreen(
              opponent: 'Quick Pop • CPU Normal',
              gameEngine: engine,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final board = find.byKey(const ValueKey('game-board'));
      final hud = find.byType(GameControlPanel);
      final boardRectBefore = tester.getRect(board);
      final hudRectBefore = tester.getRect(hud);

      await _tapBoardCell(tester, engine.tokenCell(mover)!);

      expect(find.byKey(const ValueKey('move-choice-2')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('move-choice-kill-blue')),
        findsOneWidget,
      );
      expect(find.text('2'), findsWidgets);
      expect(find.text('STEPS'), findsWidgets);
      expect(find.text('KILL BLUE'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Move piece 1, 2 steps and capture the blue piece',
        ),
        findsOneWidget,
      );
      semantics.dispose();

      _expectCalloutsAccessibleAndInsideBoard(tester);
      expect(tester.getRect(board), boardRectBefore);
      expect(tester.getRect(hud), hudRectBefore);
      expect(tester.takeException(), isNull);

      await _disposeGame(tester, engine);
    },
  );

  testWidgets('ALL shows KILL YELLOW only on its capture destination', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final semantics = tester.ensureSemantics();
    final language = AppLanguageController();
    addTearDown(language.dispose);

    final engine = GameEngine(matchFormat: MatchFormat.quickPop);
    final mover = engine.currentPlayer.tokens.first..progress = 0;
    engine.currentPlayer.tokens.last.progress = 12;
    _placeOnGlobal(engine, PlayerColor.yellow, 0, 5);
    _placeOnGlobal(engine, PlayerColor.yellow, 1, 28);
    engine
      ..hasRolled = true
      ..dice = const <int>[2, 3]
      ..message = 'You rolled 2 and 3.';
    engine.remainingDice.addAll(const <int>[2, 3]);

    await tester.pumpWidget(
      AppLanguageScope(
        controller: language,
        child: MaterialApp(
          locale: const Locale('en'),
          home: GameScreen(
            opponent: 'Quick Pop • CPU Normal',
            gameEngine: engine,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await _tapBoardCell(tester, engine.tokenCell(mover)!);

    final allCallout = find.byKey(
      ValueKey('board-move-callout-token-${mover.id}-all'),
    );
    expect(allCallout, findsOneWidget);
    expect(
      find.descendant(of: allCallout, matching: find.text('ALL')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: allCallout, matching: find.text('KILL YELLOW')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Move piece 1 using both dice, 5 steps total and capture the yellow piece',
      ),
      findsOneWidget,
    );
    semantics.dispose();
    expect(_killLabels, findsOneWidget);
    _expectCalloutsAccessibleAndInsideBoard(tester);
    expect(tester.takeException(), isNull);

    await _disposeGame(tester, engine);
  });

  testWidgets('ordinary move callouts never show a KILL label', (tester) async {
    _usePhoneViewport(tester);
    final semantics = tester.ensureSemantics();
    final language = AppLanguageController();
    addTearDown(language.dispose);

    final engine = GameEngine(matchFormat: MatchFormat.quickPop);
    final mover = engine.currentPlayer.tokens.first..progress = 8;
    engine.currentPlayer.tokens.last.progress = 20;
    engine
      ..hasRolled = true
      ..dice = const <int>[2, 3]
      ..message = 'You rolled 2 and 3.';
    engine.remainingDice.addAll(const <int>[2, 3]);

    await tester.pumpWidget(
      AppLanguageScope(
        controller: language,
        child: MaterialApp(
          locale: const Locale('en'),
          home: GameScreen(
            opponent: 'Quick Pop • CPU Normal',
            gameEngine: engine,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final boardRectBefore = tester.getRect(
      find.byKey(const ValueKey('game-board')),
    );
    final hudRectBefore = tester.getRect(find.byType(GameControlPanel));
    await _tapBoardCell(tester, engine.tokenCell(mover)!);

    expect(find.byKey(const ValueKey('move-choice-2')), findsOneWidget);
    expect(find.bySemanticsLabel('Move piece 1, 2 steps'), findsOneWidget);
    semantics.dispose();
    expect(_killLabels, findsNothing);
    expect(find.textContaining('KILL'), findsNothing);
    _expectCalloutsAccessibleAndInsideBoard(tester);
    expect(
      tester.getRect(find.byKey(const ValueKey('game-board'))),
      boardRectBefore,
    );
    expect(tester.getRect(find.byType(GameControlPanel)), hudRectBefore);
    expect(tester.takeException(), isNull);

    await _disposeGame(tester, engine);
  });

  testWidgets('safe landing callout shows a star and SAFE label', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final semantics = tester.ensureSemantics();
    final language = AppLanguageController();
    addTearDown(language.dispose);

    final engine = GameEngine(matchFormat: MatchFormat.quickPop);
    final mover = engine.currentPlayer.tokens.first..progress = 3;
    engine.currentPlayer.tokens.last.progress = 20;
    engine
      ..hasRolled = true
      ..dice = const <int>[4, 2]
      ..message = 'You rolled 4 and 2.';
    engine.remainingDice.addAll(const <int>[4, 2]);

    await tester.pumpWidget(
      AppLanguageScope(
        controller: language,
        child: MaterialApp(
          locale: const Locale('en'),
          home: GameScreen(
            opponent: 'Quick Pop • CPU Normal',
            gameEngine: engine,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await _tapBoardCell(tester, engine.tokenCell(mover)!);

    expect(find.byKey(const ValueKey('move-choice-4')), findsOneWidget);
    expect(find.byKey(const ValueKey('move-choice-safe-4')), findsOneWidget);
    expect(find.text('SAFE'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Move piece 1, 4 steps and land on a safe square'),
      findsOneWidget,
    );
    _expectCalloutsAccessibleAndInsideBoard(tester);
    expect(tester.takeException(), isNull);

    semantics.dispose();
    await _disposeGame(tester, engine);
  });

  testWidgets('home-entry capture identifies the blue piece before moving', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final semantics = tester.ensureSemantics();
    final language = AppLanguageController();
    addTearDown(language.dispose);

    final engine = GameEngine(matchFormat: MatchFormat.quickPop);
    final mover = engine.currentPlayer.tokens.first
      ..progress = GameEngine.commonPathLength - 2;
    engine.currentPlayer.tokens.last.progress = 12;
    final entry = GameEngine.homeEntryOffset[PlayerColor.red]!;
    _placeOnGlobal(engine, PlayerColor.blue, 0, entry);
    _placeOnGlobal(engine, PlayerColor.blue, 1, 26);
    engine
      ..hasRolled = true
      ..dice = const <int>[5, 2]
      ..message = 'You rolled 5 and 2.';
    engine.remainingDice.addAll(const <int>[5, 2]);

    await tester.pumpWidget(
      AppLanguageScope(
        controller: language,
        child: MaterialApp(
          locale: const Locale('en'),
          home: GameScreen(
            opponent: 'Quick Pop • CPU Normal',
            gameEngine: engine,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await _tapBoardCell(tester, engine.tokenCell(mover)!);

    expect(find.byKey(const ValueKey('move-choice-5')), findsOneWidget);
    expect(find.text('CAPTURE'), findsOneWidget);
    expect(find.text('KILL BLUE'), findsOneWidget);
    expect(find.byKey(const ValueKey('move-choice-kill-blue')), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Capture the blue piece blocking the home entry with 5',
      ),
      findsOneWidget,
    );
    semantics.dispose();
    _expectCalloutsAccessibleAndInsideBoard(tester);
    expect(tester.takeException(), isNull);

    await _disposeGame(tester, engine);
  });

  testWidgets(
    'captura amarilla usa KILL AMARILLO y semántica femenina en español',
    (tester) async {
      _usePhoneViewport(tester);
      binding.platformDispatcher.localeTestValue = const Locale('es');
      final semantics = tester.ensureSemantics();
      final language = AppLanguageController();
      addTearDown(language.dispose);

      final engine = GameEngine(matchFormat: MatchFormat.quickPop);
      final mover = engine.currentPlayer.tokens.first..progress = 1;
      engine.currentPlayer.tokens.last.progress = 12;
      _placeOnGlobal(engine, PlayerColor.yellow, 0, 3);
      _placeOnGlobal(engine, PlayerColor.yellow, 1, 28);
      engine
        ..hasRolled = true
        ..dice = const <int>[2, 6]
        ..message = 'Sacaste 2 y 6.';
      engine.remainingDice.addAll(const <int>[2, 6]);

      await tester.pumpWidget(
        AppLanguageScope(
          controller: language,
          child: MaterialApp(
            locale: const Locale('es'),
            supportedLocales: const <Locale>[Locale('es'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: GameScreen(
              opponent: 'Quick Pop • CPU Normal',
              gameEngine: engine,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await _tapBoardCell(tester, engine.tokenCell(mover)!);

      expect(
        find.byKey(const ValueKey('move-choice-kill-yellow')),
        findsOneWidget,
      );
      expect(find.text('KILL AMARILLO'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Mover ficha 1, 2 pasos y capturar la ficha amarilla',
        ),
        findsOneWidget,
      );
      semantics.dispose();
      expect(tester.takeException(), isNull);

      await _disposeGame(tester, engine);
    },
  );

  testWidgets('landscape popup shows KILL BLUE and capture semantics', (
    tester,
  ) async {
    _usePhoneViewport(tester, size: const Size(844, 390));
    final semantics = tester.ensureSemantics();
    final language = AppLanguageController();
    addTearDown(language.dispose);

    final engine = GameEngine(matchFormat: MatchFormat.quickPop);
    final mover = engine.currentPlayer.tokens.first..progress = 1;
    engine.currentPlayer.tokens.last.progress = 12;
    _placeOnGlobal(engine, PlayerColor.blue, 0, 3);
    _placeOnGlobal(engine, PlayerColor.blue, 1, 26);
    engine
      ..hasRolled = true
      ..dice = const <int>[2, 6]
      ..message = 'You rolled 2 and 6.';
    engine.remainingDice.addAll(const <int>[2, 6]);

    await tester.pumpWidget(
      AppLanguageScope(
        controller: language,
        child: MaterialApp(
          locale: const Locale('en'),
          home: GameScreen(
            opponent: 'Quick Pop • CPU Normal',
            gameEngine: engine,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await _tapBoardCell(tester, engine.tokenCell(mover)!);

    final popup = find.byKey(const ValueKey('token-move-popup'));
    expect(find.byKey(const ValueKey('game-side-layout')), findsOneWidget);
    expect(popup, findsOneWidget);
    expect(
      find.descendant(
        of: popup,
        matching: find.byKey(const ValueKey('popup-move-choice-kill-blue-2')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: popup, matching: find.text('KILL BLUE')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: popup,
        matching: find.bySemanticsLabel(
          'Move piece 1, 2 steps and capture the blue piece',
        ),
      ),
      findsOneWidget,
    );
    semantics.dispose();
    expect(tester.takeException(), isNull);

    await _disposeGame(tester, engine);
  });

  testWidgets('portrait capture callout performs its semantic tap action', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final semantics = tester.ensureSemantics();
    final language = AppLanguageController();
    addTearDown(language.dispose);

    final engine = GameEngine(matchFormat: MatchFormat.quickPop);
    final mover = engine.currentPlayer.tokens.first..progress = 1;
    engine.currentPlayer.tokens.last.progress = 12;
    final target = _placeOnGlobal(engine, PlayerColor.blue, 0, 3);
    _placeOnGlobal(engine, PlayerColor.blue, 1, 26);
    engine
      ..hasRolled = true
      ..dice = const <int>[2, 6]
      ..message = 'You rolled 2 and 6.';
    engine.remainingDice.addAll(const <int>[2, 6]);

    await tester.pumpWidget(
      AppLanguageScope(
        controller: language,
        child: MaterialApp(
          locale: const Locale('en'),
          home: GameScreen(
            opponent: 'Quick Pop • CPU Normal',
            gameEngine: engine,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await _tapBoardCell(tester, engine.tokenCell(mover)!);

    const captureLabel = 'Move piece 1, 2 steps and capture the blue piece';
    final captureAction = find.semantics.byLabel(captureLabel);
    expect(captureAction, findsOne);
    expect(captureAction, containsSemantics(hasTapAction: true));

    tester.semantics.tap(captureAction);
    await tester.pump();

    expect(mover.progress, 3);
    // Captured Quick Pop pieces return to base under rules version 2.
    expect(target.progress, -1);
    expect(target.inNest, isTrue);
    expect(engine.remainingDice, containsAllInOrder(<int>[6, 20]));
    expect(
      engine.eventHistory.where((event) => event.type == GameEventType.capture),
      hasLength(1),
    );
    expect(find.byKey(const ValueKey('move-choice-kill-blue')), findsNothing);
    semantics.dispose();
    expect(tester.takeException(), isNull);

    await _disposeGame(tester, engine);
  });

  testWidgets('capture halo stays static when reduced motion is enabled', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final language = AppLanguageController();
    addTearDown(language.dispose);

    final engine = GameEngine(matchFormat: MatchFormat.quickPop);
    final mover = engine.currentPlayer.tokens.first..progress = 1;
    engine.currentPlayer.tokens.last.progress = 12;
    final target = _placeOnGlobal(engine, PlayerColor.blue, 0, 3);
    _placeOnGlobal(engine, PlayerColor.blue, 1, 26);
    engine
      ..hasRolled = true
      ..dice = const <int>[2, 6]
      ..message = 'You rolled 2 and 6.';
    engine.remainingDice.addAll(const <int>[2, 6]);

    await tester.pumpWidget(
      AppLanguageScope(
        controller: language,
        child: MaterialApp(
          locale: const Locale('en'),
          home: MediaQuery(
            data: const MediaQueryData(
              size: _iphone17Viewport,
              disableAnimations: true,
            ),
            child: Center(
              child: SizedBox.square(
                dimension: 360,
                child: GameBoardMockup(engine: engine, selectedToken: mover),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    dynamic boardPainter() {
      final paint = find.descendant(
        of: find.byType(GameBoardMockup),
        matching: find.byType(CustomPaint),
      );
      return (paint.evaluate().single.widget as CustomPaint).painter;
    }

    final dynamic painterBefore = boardPainter();
    final previews = List<MoveDestinationPreview>.from(
      painterBefore.movePreviews as List<MoveDestinationPreview>,
    );
    expect(
      previews.any((preview) => identical(preview.captureTarget, target)),
      isTrue,
      reason: 'The board must be rendering a real capture-target halo.',
    );
    final pulseBefore = painterBefore.pulse as double;
    expect(pulseBefore, .5);
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pump(const Duration(seconds: 2));

    final dynamic painterAfter = boardPainter();
    expect(painterAfter.pulse as double, pulseBefore);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);

    await _disposeGame(tester, engine);
  });
}
