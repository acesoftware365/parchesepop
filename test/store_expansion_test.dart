import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/cosmetic_visuals.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';
import 'package:parchesepop/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _iPhone14Portrait = Size(390, 844);
const _iPhone14Landscape = Size(844, 390);

Future<WalletController> _pumpShop(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(_iPhone14Portrait);
  final wallet = await WalletController.create(initialBalance: 10000);
  await tester.pumpWidget(
    MaterialApp(home: ShopScreen(wallet: wallet, showTestCoinControls: false)),
  );
  await tester.pumpAndSettle();
  return wallet;
}

Future<void> _selectShopFilter(WidgetTester tester, String label) async {
  final filters = find.byKey(const ValueKey('shop-filters'));
  Finder filter() => find.descendant(of: filters, matching: find.text(label));

  for (var attempt = 0; attempt < 5 && filter().evaluate().isEmpty; attempt++) {
    await tester.drag(filters, const Offset(-140, 0));
    await tester.pumpAndSettle();
  }
  for (var attempt = 0; attempt < 5 && filter().evaluate().isEmpty; attempt++) {
    await tester.drag(filters, const Offset(140, 0));
    await tester.pumpAndSettle();
  }

  final target = filter();
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'iPhone 14 exposes visible featured products and every shop category',
    (tester) async {
      final wallet = await _pumpShop(tester);
      addTearDown(wallet.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final featured = shopCatalog
          .where((product) => product.featured)
          .toList(growable: false);
      expect(walletCatalog, hasLength(37));
      expect(shopCatalog, hasLength(32));
      expect(featured, hasLength(9));
      expect(find.byType(Card), findsNWidgets(featured.length));
      for (final product in featured) {
        expect(
          find.byKey(ValueKey('shop-preview-${product.id}')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);

      final seenProductIds = <String>{};
      const filters = <CosmeticCategory, String>{
        CosmeticCategory.theme: 'Temas',
        CosmeticCategory.dice: 'Dados',
        CosmeticCategory.tokens: 'Fichas',
        CosmeticCategory.avatar: 'Avatares',
      };

      for (final entry in filters.entries) {
        await _selectShopFilter(tester, entry.value);
        final products = shopCatalog
            .where((product) => product.category == entry.key)
            .toList(growable: false);

        expect(find.byType(Card), findsNWidgets(products.length));
        for (final product in products) {
          final preview = find.byKey(ValueKey('shop-preview-${product.id}'));
          expect(preview, findsOneWidget);
          expect(
            find.byKey(ValueKey('shop-action-${product.id}')),
            findsOneWidget,
          );
          seenProductIds.add(product.id);
        }
        expect(
          tester.takeException(),
          isNull,
          reason: '${entry.value} must render without overflow.',
        );
      }

      expect(seenProductIds, shopCatalog.map((product) => product.id).toSet());
    },
  );

  testWidgets('every product card CTA is at least 44 points tall', (
    tester,
  ) async {
    final wallet = await _pumpShop(tester);
    addTearDown(wallet.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const filters = ['Temas', 'Dados', 'Fichas', 'Avatares'];
    for (final label in filters) {
      await _selectShopFilter(tester, label);
      final category = switch (label) {
        'Temas' => CosmeticCategory.theme,
        'Dados' => CosmeticCategory.dice,
        'Fichas' => CosmeticCategory.tokens,
        _ => CosmeticCategory.avatar,
      };
      final products = shopCatalog.where(
        (product) => product.category == category,
      );

      for (final product in products) {
        final action = find.byKey(ValueKey('shop-action-${product.id}'));
        expect(action, findsOneWidget);
        expect(
          tester.getSize(action).height,
          greaterThanOrEqualTo(44),
          reason: '${product.id} must keep a comfortable touch target.',
        );
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('large preview and purchase dialog fit an iPhone 14', (
    tester,
  ) async {
    final wallet = await _pumpShop(tester);
    addTearDown(wallet.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _selectShopFilter(tester, 'Temas');

    const productId = 'theme_cosmic_realms_yellow';
    final previewButton = find.byKey(
      const ValueKey('shop-preview-button-$productId'),
    );
    expect(previewButton, findsOneWidget);
    final compactBoard = find.byKey(
      const ValueKey('shop-theme-board-$productId'),
    );
    expect(compactBoard, findsOneWidget);
    final compactBoardSize = tester.getSize(compactBoard);
    await tester.tap(previewButton);
    await tester.pumpAndSettle();

    final previewDialog = find.byKey(
      const ValueKey('shop-large-preview-$productId'),
    );
    expect(previewDialog, findsOneWidget);
    final previewRect = tester.getRect(previewDialog);
    expect(previewRect.left, greaterThanOrEqualTo(0));
    expect(previewRect.top, greaterThanOrEqualTo(0));
    expect(previewRect.right, lessThanOrEqualTo(_iPhone14Portrait.width));
    expect(previewRect.bottom, lessThanOrEqualTo(_iPhone14Portrait.height));
    expect(
      find.byKey(const ValueKey('shop-preview-action-$productId')),
      findsOneWidget,
    );
    final largeBoard = find.byKey(
      const ValueKey('shop-theme-board-$productId-large'),
    );
    expect(largeBoard, findsOneWidget);
    final largeBoardSize = tester.getSize(largeBoard);
    expect(largeBoardSize.width, closeTo(largeBoardSize.height, .1));
    expect(
      largeBoardSize.shortestSide,
      greaterThan(compactBoardSize.shortestSide),
    );

    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shop-action-$productId')));
    await tester.pumpAndSettle();

    final confirm = find.byKey(const ValueKey('shop-confirm-purchase'));
    expect(confirm, findsOneWidget);
    expect(tester.getSize(confirm).height, greaterThanOrEqualTo(56));
    expect(confirm.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'new theme dice tokens and avatar purchase equip and reach GameScreen',
    (tester) async {
      await tester.binding.setSurfaceSize(_iPhone14Landscape);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final wallet = await WalletController.create(initialBalance: 10000);
      const themeId = 'theme_cosmic_realms_blue';
      const diceId = 'dice_ocean_pearl';
      const tokenId = 'tokens_crystal';
      const avatarId = 'avatar_comet';

      for (final productId in [themeId, diceId, tokenId, avatarId]) {
        expect(await wallet.purchase(productId), PurchaseResult.purchased);
        expect(await wallet.equip(productId), EquipResult.equipped);
      }

      final engine = GameEngine(mode: GameMode.chaos);
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            opponent: 'CPU • Normal',
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
      final controls = tester.widget<GameControlPanel>(
        find.byType(GameControlPanel),
      );
      final selectedTheme = themeVisualSpecFor(themeId);

      expect(board.resolvedPlayerThemeIds[PlayerColor.red], selectedTheme.id);
      expect(
        themeVisualSpecFor(board.resolvedPlayerThemeIds[PlayerColor.red]),
        same(selectedTheme),
      );
      expect(
        board.resolvedPlayerThemeIds.keys.where(
          (color) => color != PlayerColor.red,
        ),
        isEmpty,
        reason: 'A local purchase must only decorate the local red side.',
      );
      expect(controls.diceId, diceId);
      expect(
        board.tokenStyleIds,
        containsPair(PlayerColor.red, 'tokens_cosmic_realms_blue'),
      );
      expect(wallet.equippedProductId(CosmeticCategory.tokens), tokenId);
      expect(wallet.equippedProductId(CosmeticCategory.avatar), avatarId);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      engine.dispose();
      wallet.dispose();
    },
  );

  testWidgets('new token and avatar previews expose unique stable keys', (
    tester,
  ) async {
    final wallet = await _pumpShop(tester);
    addTearDown(wallet.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const newTokenIds = ['tokens_crystal', 'tokens_rocket', 'tokens_crown'];
    const newAvatarIds = ['avatar_comet', 'avatar_axolotl', 'avatar_toucan'];

    await _selectShopFilter(tester, 'Fichas');
    final tokenKeys = <ValueKey<String>>{
      for (final id in newTokenIds)
        for (var index = 0; index < 4; index++)
          ValueKey('shop-token-$id-$index'),
    };
    expect(tokenKeys, hasLength(newTokenIds.length * 4));
    for (final key in tokenKeys) {
      expect(find.byKey(key), findsOneWidget);
    }

    await _selectShopFilter(tester, 'Avatares');
    final avatarKeys = <ValueKey<String>>{
      for (final id in newAvatarIds) ValueKey('shop-avatar-$id'),
    };
    expect(avatarKeys, hasLength(newAvatarIds.length));
    for (final key in avatarKeys) {
      expect(find.byKey(key), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
