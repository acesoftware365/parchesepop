import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';
import 'package:parchesepop/orientation_policy.dart';

const _portrait = Size(390, 844);
const _landscape = Size(844, 390);
const _bannerConstrainedLandscape = Size(750, 307);
const _macLandscape = Size(760, 620);

Future<void> _resize(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
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

void _expectSquareInside(WidgetTester tester, Finder finder, Size viewport) {
  final rect = tester.getRect(finder);
  expect((rect.width - rect.height).abs(), lessThanOrEqualTo(.5));
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(viewport.width));
  expect(rect.bottom, lessThanOrEqualTo(viewport.height));
}

void _expectPortraitLayout(WidgetTester tester) {
  final board = find.byKey(const ValueKey('game-board'));
  final hud = find.byKey(const ValueKey('portrait-game-hud'));

  expect(board, findsOneWidget);
  expect(hud, findsOneWidget);
  expect(find.byKey(const ValueKey('game-side-layout')), findsNothing);
  expect(find.byKey(const ValueKey('game-side-rail')), findsNothing);
  expect(find.byKey(const ValueKey('game-quick-bar')), findsOneWidget);
  expect(find.byKey(const ValueKey('phone-landscape-layout')), findsNothing);
  expect(find.byKey(const ValueKey('phone-landscape-game-hud')), findsNothing);
  expect(find.byKey(const ValueKey('phone-landscape-tab-dock')), findsNothing);

  _expectSquareInside(tester, board, _portrait);
  final hudRect = tester.getRect(hud);
  expect(hudRect.left, greaterThanOrEqualTo(0));
  expect(hudRect.right, lessThanOrEqualTo(_portrait.width));
  expect(hudRect.bottom, lessThanOrEqualTo(_portrait.height));
  expect(tester.takeException(), isNull);
}

void _expectPhoneLandscapeLayout(
  WidgetTester tester, {
  Size viewport = _landscape,
}) {
  final board = find.byKey(const ValueKey('game-board'));
  final layout = find.byKey(const ValueKey('phone-landscape-layout'));
  final hud = find.byKey(const ValueKey('phone-landscape-game-hud'));
  final dock = find.byKey(const ValueKey('phone-landscape-tab-dock'));

  expect(board, findsOneWidget);
  expect(layout, findsOneWidget);
  expect(hud, findsOneWidget);
  expect(dock, findsOneWidget);
  expect(find.byKey(const ValueKey('portrait-game-hud')), findsNothing);
  expect(find.byKey(const ValueKey('game-quick-bar')), findsOneWidget);

  _expectSquareInside(tester, board, viewport);
  final layoutRect = tester.getRect(layout);
  final boardRect = tester.getRect(board);
  final hudRect = tester.getRect(hud);
  final dockRect = tester.getRect(dock);

  expect(layoutRect.left, greaterThanOrEqualTo(0));
  expect(layoutRect.top, greaterThanOrEqualTo(0));
  expect(layoutRect.right, lessThanOrEqualTo(viewport.width));
  expect(layoutRect.bottom, lessThanOrEqualTo(viewport.height));

  expect(hudRect.left, greaterThanOrEqualTo(boardRect.right));
  expect(hudRect.top, greaterThanOrEqualTo(0));
  expect(hudRect.right, lessThanOrEqualTo(viewport.width));
  expect(hudRect.bottom, lessThanOrEqualTo(viewport.height));
  expect(hudRect.width, greaterThan(hudRect.height));

  expect(dockRect.left, greaterThanOrEqualTo(boardRect.right));
  expect(dockRect.top, greaterThanOrEqualTo(0));
  expect(dockRect.right, lessThanOrEqualTo(_landscape.width));
  expect(dockRect.bottom, lessThanOrEqualTo(_landscape.height));

  final quickBar = find.byKey(const ValueKey('game-quick-bar'));
  final quickActions = find.descendant(
    of: quickBar,
    matching: find.byType(IconButton),
  );
  if (quickActions.evaluate().isNotEmpty) {
    for (final action in quickActions.evaluate()) {
      final actionRect = tester.getRect(find.byWidget(action.widget));
      expect(
        actionRect.width,
        greaterThanOrEqualTo(40),
        reason: 'Landscape quick actions need a 40px touch target.',
      );
      expect(
        actionRect.height,
        greaterThanOrEqualTo(40),
        reason: 'Landscape quick actions need a 40px touch target.',
      );
    }
  }
  expect(tester.takeException(), isNull);
}

void _expectMacLandscapeLayout(WidgetTester tester) {
  final board = find.byKey(const ValueKey('game-board'));
  final rail = find.byKey(const ValueKey('game-side-rail'));

  expect(board, findsOneWidget);
  expect(rail, findsOneWidget);
  expect(find.byKey(const ValueKey('game-side-layout')), findsOneWidget);
  expect(find.byKey(const ValueKey('game-rail-control')), findsOneWidget);
  expect(find.byKey(const ValueKey('portrait-game-hud')), findsNothing);
  expect(find.byKey(const ValueKey('game-quick-bar')), findsOneWidget);
  expect(find.byKey(const ValueKey('phone-landscape-layout')), findsNothing);
  expect(find.byKey(const ValueKey('phone-landscape-game-hud')), findsNothing);
  expect(find.byKey(const ValueKey('phone-landscape-tab-dock')), findsNothing);

  _expectSquareInside(tester, board, _macLandscape);
  final boardRect = tester.getRect(board);
  final railRect = tester.getRect(rail);
  expect(boardRect.right, lessThan(railRect.left));
  expect(railRect.right, lessThanOrEqualTo(_macLandscape.width));
  expect(railRect.bottom, lessThanOrEqualTo(_macLandscape.height));
  expect(tester.takeException(), isNull);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    binding.platformDispatcher.localeTestValue = const Locale('es');
  });

  tearDown(() {
    binding.platformDispatcher.clearLocaleTestValue();
    debugDefaultTargetPlatformOverride = null;
  });

  test('the app allows portrait and both landscape directions', () {
    expect(
      supportedAppOrientations,
      containsAll(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    expect(supportedAppOrientations, hasLength(3));
  });

  testWidgets('compact board artwork is limited to phones on iOS and Android', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<void> expectProfile({
      required Size size,
      required TargetPlatform platform,
      required bool compact,
      EdgeInsets safePadding = EdgeInsets.zero,
    }) async {
      final engine = GameEngine();
      debugDefaultTargetPlatformOverride = platform;
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: size, padding: safePadding),
            child: GameScreen(opponent: 'CPU • Normal', gameEngine: engine),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester
            .widget<GameBoardMockup>(find.byType(GameBoardMockup))
            .compactPhone,
        compact,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      engine.dispose();
      debugDefaultTargetPlatformOverride = null;
    }

    await expectProfile(
      size: _portrait,
      platform: TargetPlatform.iOS,
      compact: true,
    );
    await expectProfile(
      size: _portrait,
      platform: TargetPlatform.android,
      compact: true,
    );
    await expectProfile(
      size: const Size(600, 960),
      platform: TargetPlatform.iOS,
      compact: false,
    );
    await expectProfile(
      size: const Size(960, 600),
      platform: TargetPlatform.android,
      compact: false,
      safePadding: const EdgeInsets.only(bottom: 120),
    );
    await expectProfile(
      size: _portrait,
      platform: TargetPlatform.macOS,
      compact: false,
    );
    await expectProfile(
      size: _portrait,
      platform: TargetPlatform.windows,
      compact: false,
    );
  });

  testWidgets('the active game survives portrait-landscape-portrait rotation', (
    tester,
  ) async {
    final engine = GameEngine(mode: GameMode.chaos);
    engine.currentPlayer.tokens.first.progress = 4;
    addTearDown(engine.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.binding.setSurfaceSize(_portrait);
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'CPU • Fácil',
          mode: GameMode.chaos,
          gameEngine: engine,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));

    final initialState = tester.state(find.byType(GameScreen));
    _expectPortraitLayout(tester);

    await _resize(tester, _landscape);
    expect(tester.state(find.byType(GameScreen)), same(initialState));
    expect(engine.currentPlayer.tokens.first.progress, 4);
    _expectPhoneLandscapeLayout(tester);

    await _resize(tester, _portrait);
    expect(tester.state(find.byType(GameScreen)), same(initialState));
    expect(engine.currentPlayer.tokens.first.progress, 4);
    _expectPortraitLayout(tester);
  });

  testWidgets(
    'the active game survives landscape-portrait-landscape rotation',
    (tester) async {
      final engine = GameEngine();
      engine.currentPlayer.tokens.first.progress = 7;
      addTearDown(engine.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.binding.setSurfaceSize(_landscape);
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(opponent: 'CPU • Normal', gameEngine: engine),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));

      final initialState = tester.state(find.byType(GameScreen));
      _expectPhoneLandscapeLayout(tester);

      await _resize(tester, _portrait);
      expect(tester.state(find.byType(GameScreen)), same(initialState));
      expect(engine.currentPlayer.tokens.first.progress, 7);
      _expectPortraitLayout(tester);

      await _resize(tester, _landscape);
      expect(tester.state(find.byType(GameScreen)), same(initialState));
      expect(engine.currentPlayer.tokens.first.progress, 7);
      _expectPhoneLandscapeLayout(tester);
    },
  );

  testWidgets('mac-sized landscape keeps the established side rail layout', (
    tester,
  ) async {
    final engine = GameEngine();
    addTearDown(engine.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.binding.setSurfaceSize(_macLandscape);
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Normal', gameEngine: engine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));

    _expectMacLandscapeLayout(tester);
  });

  testWidgets(
    'banner-constrained phone landscape keeps the horizontal game console',
    (tester) async {
      final engine = GameEngine(mode: GameMode.chaos);
      addTearDown(engine.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.binding.setSurfaceSize(_bannerConstrainedLandscape);
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            opponent: 'CPU • Normal',
            mode: GameMode.chaos,
            gameEngine: engine,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));

      _expectPhoneLandscapeLayout(
        tester,
        viewport: _bannerConstrainedLandscape,
      );
      final board = tester.getRect(find.byKey(const ValueKey('game-board')));
      final rail = tester.getRect(find.byKey(const ValueKey('game-side-rail')));
      final playerStrip = tester.getRect(
        find.byKey(const ValueKey('landscape-player-strip')),
      );
      expect(board.height, closeTo(_bannerConstrainedLandscape.height, .5));
      expect(playerStrip.left, greaterThanOrEqualTo(rail.left));
      expect(playerStrip.right, lessThanOrEqualTo(rail.right));
      expect(playerStrip.bottom, lessThanOrEqualTo(rail.bottom));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'landscape move choices float over the console without shrinking it',
    (tester) async {
      final engine = GameEngine();
      engine.currentPlayer.tokens.first.progress = 0;
      engine.hasRolled = true;
      engine.dice = const [2, 3];
      engine.remainingDice.addAll(const [2, 3]);
      addTearDown(engine.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.binding.setSurfaceSize(_bannerConstrainedLandscape);
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(opponent: 'CPU • Normal', gameEngine: engine),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));

      final railFinder = find.byKey(const ValueKey('game-side-rail'));
      final railBefore = tester.getRect(railFinder);
      await _tapBoardCell(tester, GameEngine.loop.first);

      final popup = find.byKey(const ValueKey('token-move-popup'));
      expect(popup, findsOneWidget);
      final popupRect = tester.getRect(popup);
      final railAfter = tester.getRect(railFinder);
      final dock = tester.getRect(
        find.byKey(const ValueKey('phone-landscape-tab-dock')),
      );
      expect(railAfter, railBefore);
      expect(popupRect.left, greaterThanOrEqualTo(railAfter.left));
      expect(popupRect.right, lessThanOrEqualTo(dock.left));
      expect(popupRect.bottom, lessThanOrEqualTo(railAfter.bottom));
      expect(tester.takeException(), isNull);
    },
  );
}
