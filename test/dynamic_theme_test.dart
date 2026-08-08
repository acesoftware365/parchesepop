import 'dart:ui' as ui;
import 'dart:typed_data';

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

Future<Uint8List> _renderBoardPreview(String themeId) async {
  const side = 180;
  final engine = GameEngine(mode: GameMode.traditional);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  shopThemeBoardPreviewPainter(
    engine: engine,
    themeId: themeId,
    progress: .38,
    compactPhone: true,
  ).paint(canvas, const ui.Size.square(180));
  final picture = recorder.endRecording();
  final image = await picture.toImage(side, side);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  engine.dispose();
  return data!.buffer.asUint8List();
}

double _regionDifferenceRatio(
  Uint8List first,
  Uint8List second, {
  required int left,
  required int top,
  required int right,
  required int bottom,
  int width = 180,
}) {
  var changed = 0;
  var total = 0;
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final offset = (y * width + x) * 4;
      final delta =
          (first[offset] - second[offset]).abs() +
          (first[offset + 1] - second[offset + 1]).abs() +
          (first[offset + 2] - second[offset + 2]).abs();
      if (delta > 24) changed++;
      total++;
    }
  }
  return changed / total;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('ThemeScenePainter accepts and distinguishes all ten theme specs', () {
    const expectedThemeIds = {
      'theme_default',
      'theme_neon_rush',
      'theme_golden_night',
      'theme_tropical_splash',
      'theme_celestial_carnival',
      'theme_velvet_lounge',
      'theme_cosmic_realms_red',
      'theme_cosmic_realms_yellow',
      'theme_cosmic_realms_blue',
      'theme_cosmic_realms_green',
    };
    expect(themeVisualSpecs.keys.toSet(), expectedThemeIds);

    final specs = themeVisualSpecs.values.toList(growable: false);
    expect(specs, hasLength(10));
    expect(specs.map((spec) => spec.motif).toSet(), ThemeMotif.values.toSet());
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
      hasLength(10),
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

  testWidgets('the shop renders a neutral scene and the real match board', (
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

    const themeId = 'theme_cosmic_realms_blue';
    final scene = find.byKey(const ValueKey('shop-theme-scene-$themeId'));
    expect(scene, findsOneWidget);
    final customPaint = tester.widget<CustomPaint>(scene);
    expect(customPaint.painter, isA<ThemeScenePainter>());
    expect(
      (customPaint.painter! as ThemeScenePainter).theme,
      same(defaultThemeVisualSpec),
    );

    final board = find.byKey(const ValueKey('shop-theme-board-$themeId'));
    expect(board, findsOneWidget);
    final previewEngine = GameEngine(mode: GameMode.traditional);
    addTearDown(previewEngine.dispose);
    final expectedPainter = shopThemeBoardPreviewPainter(
      engine: previewEngine,
      themeId: themeId,
    );
    expect(
      tester.widget<CustomPaint>(board).painter.runtimeType,
      expectedPainter.runtimeType,
    );
    final boardSize = tester.getSize(board);
    expect(boardSize.width, closeTo(boardSize.height, .1));
    expect(boardSize.shortestSide, greaterThan(110));
    expect(tester.takeException(), isNull);
  });

  test(
    'real board previews make every Cosmic local sector visibly unique',
    () async {
      const cosmicIds = [
        'theme_cosmic_realms_red',
        'theme_cosmic_realms_yellow',
        'theme_cosmic_realms_blue',
        'theme_cosmic_realms_green',
      ];
      final classic = await _renderBoardPreview('theme_default');
      final cosmic = <String, Uint8List>{};
      for (final id in cosmicIds) {
        final rendered = await _renderBoardPreview(id);
        cosmic[id] = rendered;
        expect(
          _regionDifferenceRatio(
            classic,
            rendered,
            left: 0,
            top: 90,
            right: 120,
            bottom: 180,
          ),
          greaterThan(.12),
          reason: '$id must visibly style the real red/local board sector.',
        );
      }
      for (var first = 0; first < cosmicIds.length; first++) {
        for (var second = first + 1; second < cosmicIds.length; second++) {
          expect(
            _regionDifferenceRatio(
              cosmic[cosmicIds[first]]!,
              cosmic[cosmicIds[second]]!,
              left: 0,
              top: 90,
              right: 120,
              bottom: 180,
            ),
            greaterThan(.06),
            reason:
                '${cosmicIds[first]} and ${cosmicIds[second]} need distinct previews.',
          );
        }
      }
    },
  );

  test(
    'only the local goal triangle follows the selected Cosmic theme',
    () async {
      const cosmicIds = [
        'theme_cosmic_realms_red',
        'theme_cosmic_realms_yellow',
        'theme_cosmic_realms_blue',
        'theme_cosmic_realms_green',
      ];
      final classic = await _renderBoardPreview('theme_default');
      final cosmic = <String, Uint8List>{};

      for (final id in cosmicIds) {
        final rendered = await _renderBoardPreview(id);
        cosmic[id] = rendered;
        expect(
          _regionDifferenceRatio(
            classic,
            rendered,
            left: 81,
            top: 84,
            right: 84,
            bottom: 96,
          ),
          greaterThan(.20),
          reason: '$id must style the red/local goal triangle.',
        );
        for (final untouchedRegion in const [
          (left: 84, top: 81, right: 96, bottom: 84),
          (left: 96, top: 84, right: 99, bottom: 96),
          (left: 84, top: 96, right: 96, bottom: 99),
        ]) {
          expect(
            _regionDifferenceRatio(
              classic,
              rendered,
              left: untouchedRegion.left,
              top: untouchedRegion.top,
              right: untouchedRegion.right,
              bottom: untouchedRegion.bottom,
            ),
            lessThan(.02),
            reason: '$id must not repaint another player\'s goal triangle.',
          );
        }
      }

      for (var first = 0; first < cosmicIds.length; first++) {
        for (var second = first + 1; second < cosmicIds.length; second++) {
          expect(
            _regionDifferenceRatio(
              cosmic[cosmicIds[first]]!,
              cosmic[cosmicIds[second]]!,
              left: 81,
              top: 84,
              right: 84,
              bottom: 96,
            ),
            greaterThan(.035),
            reason:
                '${cosmicIds[first]} and ${cosmicIds[second]} need distinct local goal triangles.',
          );
        }
      }
    },
  );

  test('each board-center triangle resolves only its owner theme', () {
    const themes = {
      PlayerColor.red: 'theme_cosmic_realms_red',
      PlayerColor.green: 'theme_cosmic_realms_green',
      PlayerColor.yellow: 'theme_cosmic_realms_yellow',
      PlayerColor.blue: 'theme_cosmic_realms_blue',
    };

    for (final entry in themes.entries) {
      expect(
        boardCenterThemeForPlayerThemeIds(themes, entry.key).id,
        entry.value,
      );
    }
    expect(
      boardCenterThemeForPlayerThemeIds(const {}, PlayerColor.red),
      same(defaultThemeVisualSpec),
    );
  });

  test('shop theme preview limits the product to the red/local side', () {
    const themeId = 'theme_celestial_carnival';

    expect(
      shopThemePreviewThemeForPlayer(themeId, PlayerColor.red).id,
      themeId,
    );
    for (final color in const [
      PlayerColor.blue,
      PlayerColor.yellow,
      PlayerColor.green,
    ]) {
      expect(
        shopThemePreviewThemeForPlayer(themeId, color),
        same(defaultThemeVisualSpec),
        reason: 'Only the local red side should preview the purchased theme.',
      );
    }
  });

  testWidgets('GameScreen limits the equipped theme to the local red side', (
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
    final board = tester.widget<GameBoardMockup>(find.byType(GameBoardMockup));
    expect(board.playerThemeIds, {PlayerColor.red: themeId});
    expect(board.resolvedPlayerThemeIds[PlayerColor.red], themeId);
    expect(
      board.resolvedPlayerThemeIds.keys.where(
        (color) => color != PlayerColor.red,
      ),
      isEmpty,
    );

    final backdrop = find.byKey(
      const ValueKey('game-theme-backdrop-theme_default'),
    );
    expect(backdrop, findsOneWidget);
    final customPaint = tester.widget<CustomPaint>(backdrop);
    final painter = customPaint.painter! as ThemeScenePainter;
    expect(painter.theme.id, defaultThemeVisualSpec.id);
    expect(
      find.byKey(const ValueKey('game-theme-backdrop-$themeId')),
      findsNothing,
      reason: 'A local theme must not replace the shared game backdrop.',
    );
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
      const ValueKey('shop-theme-scene-theme_cosmic_realms_green'),
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
