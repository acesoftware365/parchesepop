import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/cosmetic_visuals.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';
import 'package:parchesepop/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _iPhone14Portrait = Size(390, 844);
const _iPhone14Landscape = Size(844, 390);

const _replacementThemes = {
  'theme_celestial_carnival': (
    name: 'Arcade Retro',
    motif: 'retro',
    price: 1350,
    rarity: CosmeticRarity.epic,
  ),
  'theme_velvet_lounge': (
    name: 'Aurora Ártica',
    motif: 'aurora',
    price: 1500,
    rarity: CosmeticRarity.legendary,
  ),
};

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

Future<Uint8List> _renderScene(
  ThemeVisualSpec spec, {
  required double progress,
}) async {
  const size = ui.Size(180, 120);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  ThemeScenePainter(theme: spec, progress: progress).paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'replacement themes keep purchase IDs but remove mushrooms and Niagara',
    () {
      const rejectedWords = [
        'hongo',
        'mushroom',
        'catarata',
        'niágara',
        'niagara',
      ];

      for (final entry in _replacementThemes.entries) {
        final id = entry.key;
        final expectation = entry.value;
        final product = walletCatalog.singleWhere((item) => item.id == id);
        final spec = themeVisualSpecs[id];

        expect(product.id, id);
        expect(product.name, expectation.name);
        expect(product.price, expectation.price);
        expect(product.rarity, expectation.rarity);
        expect(spec, isNotNull);
        expect(spec!.id, id);
        expect(spec.motif.name, expectation.motif);
        expect(themeVisualSpecFor(id), same(spec));
        expect(supportedThemeStyleIds, contains(id));

        final searchableText = '${product.name} ${product.description}'
            .toLowerCase();
        for (final rejectedWord in rejectedWords) {
          expect(
            searchableText,
            isNot(contains(rejectedWord)),
            reason: '$id must not retain the rejected $rejectedWord identity.',
          );
        }
      }
    },
  );

  test('replacement theme scenes are visually distinct and animated', () async {
    final renderedAtRest = <String, Uint8List>{};

    for (final id in _replacementThemes.keys) {
      final spec = themeVisualSpecs[id]!;
      final firstFrame = await _renderScene(spec, progress: .12);
      final laterFrame = await _renderScene(spec, progress: .63);
      renderedAtRest[id] = firstFrame;

      expect(
        listEquals(firstFrame, laterFrame),
        isFalse,
        reason: '$id must visibly animate instead of only requesting repaints.',
      );
      expect(
        ThemeScenePainter(
          theme: spec,
          progress: .63,
        ).shouldRepaint(ThemeScenePainter(theme: spec, progress: .12)),
        isTrue,
      );
    }

    expect(
      listEquals(
        renderedAtRest['theme_celestial_carnival'],
        renderedAtRest['theme_velvet_lounge'],
      ),
      isFalse,
      reason: 'Arcade Retro and Aurora Ártica need separate scene identities.',
    );
  });

  testWidgets('archived replacement themes are hidden from the current shop', (
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
    await tester.pumpAndSettle();

    final filters = find.byKey(const ValueKey('shop-filters'));
    final themesFilter = find.descendant(
      of: filters,
      matching: find.text('Temas'),
    );
    expect(themesFilter, findsOneWidget);
    await tester.tap(themesFilter);
    await tester.pumpAndSettle();

    for (final entry in _replacementThemes.entries) {
      final id = entry.key;
      expect(find.text(entry.value.name), findsNothing);
      expect(find.byKey(ValueKey('shop-preview-$id')), findsNothing);
      expect(find.byKey(ValueKey('shop-preview-button-$id')), findsNothing);
      expect(find.byKey(ValueKey('shop-theme-scene-$id')), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  for (final entry in _replacementThemes.entries) {
    final id = entry.key;
    testWidgets('$id restores from the wallet and reaches GameScreen', (
      tester,
    ) async {
      _useViewport(tester, _iPhone14Landscape);
      SharedPreferences.setMockInitialValues({
        'parchesepop.wallet.owned.v1': [id],
        'parchesepop.wallet.equipped.v1.theme': id,
      });
      final wallet = await WalletController.create();
      final engine = GameEngine(mode: GameMode.chaos);

      expect(wallet.isOwned(id), isTrue);
      expect(wallet.equippedProductId(CosmeticCategory.theme), id);

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
      await tester.pump(const Duration(milliseconds: 120));

      final board = tester.widget<GameBoardMockup>(
        find.byType(GameBoardMockup),
      );
      expect(board.playerThemeIds, {PlayerColor.red: id});
      expect(board.resolvedPlayerThemeIds[PlayerColor.red], id);
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
      final paint = tester.widget<CustomPaint>(backdrop);
      expect(paint.painter, isA<ThemeScenePainter>());
      expect(
        (paint.painter! as ThemeScenePainter).theme.id,
        defaultThemeVisualSpec.id,
      );
      expect(find.byKey(ValueKey('game-theme-backdrop-$id')), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      engine.dispose();
      wallet.dispose();
    });
  }
}
