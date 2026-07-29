import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';
import 'package:parchesepop/orientation_policy.dart';

const _portrait = Size(390, 844);
const _landscape = Size(844, 390);

Future<void> _resize(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
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

  _expectSquareInside(tester, board, _portrait);
  final hudRect = tester.getRect(hud);
  expect(hudRect.left, greaterThanOrEqualTo(0));
  expect(hudRect.right, lessThanOrEqualTo(_portrait.width));
  expect(hudRect.bottom, lessThanOrEqualTo(_portrait.height));
  expect(tester.takeException(), isNull);
}

void _expectLandscapeLayout(WidgetTester tester) {
  final board = find.byKey(const ValueKey('game-board'));
  final rail = find.byKey(const ValueKey('game-side-rail'));

  expect(board, findsOneWidget);
  expect(rail, findsOneWidget);
  expect(find.byKey(const ValueKey('game-side-layout')), findsOneWidget);
  expect(find.byKey(const ValueKey('game-rail-control')), findsOneWidget);
  expect(find.byKey(const ValueKey('portrait-game-hud')), findsNothing);
  expect(find.byKey(const ValueKey('game-quick-bar')), findsOneWidget);

  _expectSquareInside(tester, board, _landscape);
  final boardRect = tester.getRect(board);
  final railRect = tester.getRect(rail);
  expect(boardRect.right, lessThan(railRect.left));
  expect(railRect.right, lessThanOrEqualTo(_landscape.width));
  expect(railRect.bottom, lessThanOrEqualTo(_landscape.height));
  expect(tester.takeException(), isNull);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    binding.platformDispatcher.localeTestValue = const Locale('es');
  });

  tearDown(() {
    binding.platformDispatcher.clearLocaleTestValue();
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
    _expectLandscapeLayout(tester);

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
      _expectLandscapeLayout(tester);

      await _resize(tester, _portrait);
      expect(tester.state(find.byType(GameScreen)), same(initialState));
      expect(engine.currentPlayer.tokens.first.progress, 7);
      _expectPortraitLayout(tester);

      await _resize(tester, _landscape);
      expect(tester.state(find.byType(GameScreen)), same(initialState));
      expect(engine.currentPlayer.tokens.first.progress, 7);
      _expectLandscapeLayout(tester);
    },
  );
}
