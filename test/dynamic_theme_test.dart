import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/cosmetic_visuals.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';
import 'package:parchesepop/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _iPhone14Portrait = Size(390, 844);
const _iPhone14Landscape = Size(844, 390);

void _useViewport(WidgetTester tester, Size size) {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
  addTearDown(() {
    tester.view
      ..resetDevicePixelRatio()
      ..resetPhysicalSize();
  });
}

Widget _reducedMotionApp({required Widget child, required Size size}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size, disableAnimations: true),
      child: child,
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('ThemeScenePainter accepts and distinguishes all six theme specs', () {
    const expectedThemeIds = {
      'theme_default',
      'theme_neon_rush',
      'theme_golden_night',
      'theme_tropical_splash',
      'theme_celestial_carnival',
      'theme_velvet_lounge',
    };
    expect(themeVisualSpecs.keys.toSet(), expectedThemeIds);

    final specs = themeVisualSpecs.values.toList(growable: false);
    expect(specs, hasLength(6));
    expect(specs.map((spec) => spec.motif).toSet(), hasLength(6));
    expect(
      specs
          .map(
            (spec) => (
              spec.sceneSkyColor,
              spec.sceneGroundColor,
              spec.scenePrimaryColor,
              spec.sceneSecondaryColor,
              spec.sceneGlowColor,
            ),
          )
          .toSet(),
      hasLength(6),
    );

    for (var index = 0; index < specs.length; index++) {
      final spec = specs[index];
      final painter = ThemeScenePainter(theme: spec, progress: .42);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);

      expect(painter.theme, same(spec));
      expect(
        () => painter.paint(canvas, const ui.Size(180, 120)),
        returnsNormally,
      );
      recorder.endRecording();

      final otherSpec = specs[(index + 1) % specs.length];
      expect(
        ThemeScenePainter(
          theme: otherSpec,
          progress: .42,
        ).shouldRepaint(painter),
        isTrue,
      );
    }
  });

  testWidgets('the shop renders the animated scene for a theme card', (
    tester,
  ) async {
    _useViewport(tester, _iPhone14Portrait);
    final wallet = await WalletController.create(initialBalance: 10000);
    addTearDown(wallet.dispose);

    await tester.pumpWidget(
      _reducedMotionApp(
        size: _iPhone14Portrait,
        child: ShopScreen(wallet: wallet, showTestCoinControls: false),
      ),
    );
    await tester.pump();

    const themeId = 'theme_neon_rush';
    final scene = find.byKey(const ValueKey('shop-theme-scene-$themeId'));
    expect(scene, findsOneWidget);
    final customPaint = tester.widget<CustomPaint>(scene);
    expect(customPaint.painter, isA<ThemeScenePainter>());
    expect((customPaint.painter! as ThemeScenePainter).theme.id, themeId);
    expect(tester.takeException(), isNull);
  });

  testWidgets('GameScreen uses the equipped theme for its full backdrop', (
    tester,
  ) async {
    _useViewport(tester, _iPhone14Landscape);
    SharedPreferences.setMockInitialValues({
      'parchesepop.wallet.owned.v1': ['theme_velvet_lounge'],
      'parchesepop.wallet.equipped.v1.theme': 'theme_velvet_lounge',
    });
    final wallet = await WalletController.create();
    final engine = GameEngine(mode: GameMode.chaos);
    addTearDown(wallet.dispose);
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      _reducedMotionApp(
        size: _iPhone14Landscape,
        child: GameScreen(
          opponent: 'CPU • Fácil',
          mode: GameMode.chaos,
          gameEngine: engine,
          wallet: wallet,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    const themeId = 'theme_velvet_lounge';
    final backdrop = find.byKey(const ValueKey('game-theme-backdrop-$themeId'));
    expect(backdrop, findsOneWidget);
    final customPaint = tester.widget<CustomPaint>(backdrop);
    final painter = customPaint.painter! as ThemeScenePainter;
    expect(painter.theme.id, themeId);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion leaves theme previews settled', (tester) async {
    _useViewport(tester, _iPhone14Portrait);
    final wallet = await WalletController.create(initialBalance: 10000);
    addTearDown(wallet.dispose);

    await tester.pumpWidget(
      _reducedMotionApp(
        size: _iPhone14Portrait,
        child: ShopScreen(wallet: wallet, showTestCoinControls: false),
      ),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 3),
    );

    final scene = find.byKey(
      const ValueKey('shop-theme-scene-theme_neon_rush'),
    );
    expect(scene, findsOneWidget);
    final painter =
        tester.widget<CustomPaint>(scene).painter! as ThemeScenePainter;
    final settledProgress = painter.progress;
    await tester.pump(const Duration(seconds: 10));
    final painterAfterTime =
        tester.widget<CustomPaint>(scene).painter! as ThemeScenePainter;
    expect(painterAfterTime.progress, settledProgress);
    expect(tester.takeException(), isNull);
  });
}
