import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/app_language.dart';
import 'package:parchesepop/cosmetic_visuals.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';
import 'package:parchesepop/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _iPhone14Portrait = Size(390, 844);
const _iPhone14Landscape = Size(844, 390);

const _matchingThemeTokens = <String, String>{
  'theme_default': 'tokens_default',
  'theme_neon_rush': 'tokens_neon_pulse',
  'theme_golden_night': 'tokens_solar_scarab',
  'theme_tropical_splash': 'tokens_jungle_totem',
  'theme_celestial_carnival': 'tokens_pixel_blaster',
  'theme_velvet_lounge': 'tokens_aurora_shard',
  'theme_cosmic_realms_red': 'tokens_cosmic_realms_red',
  'theme_cosmic_realms_yellow': 'tokens_cosmic_realms_yellow',
  'theme_cosmic_realms_blue': 'tokens_cosmic_realms_blue',
  'theme_cosmic_realms_green': 'tokens_cosmic_realms_green',
};

const _premiumTokenProducts =
    <String, ({String name, int price, CosmeticRarity rarity})>{
      'tokens_neon_pulse': (
        name: 'Fichas Pulso Neón',
        price: 650,
        rarity: CosmeticRarity.rare,
      ),
      'tokens_solar_scarab': (
        name: 'Fichas Escarabajo Solar',
        price: 700,
        rarity: CosmeticRarity.epic,
      ),
      'tokens_jungle_totem': (
        name: 'Fichas Tótem Selvático',
        price: 650,
        rarity: CosmeticRarity.rare,
      ),
      'tokens_pixel_blaster': (
        name: 'Fichas Pixel Blaster',
        price: 725,
        rarity: CosmeticRarity.epic,
      ),
      'tokens_aurora_shard': (
        name: 'Fichas Fragmento Aurora',
        price: 800,
        rarity: CosmeticRarity.legendary,
      ),
    };

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

  expect(filter(), findsOneWidget);
  await tester.ensureVisible(filter());
  await tester.pumpAndSettle();
  await tester.tap(filter());
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('theme token collection keeps exact catalog and registry parity', () {
    final catalogTokenProducts = walletCatalog
        .where((product) => product.category == CosmeticCategory.tokens)
        .toList(growable: false);
    final catalogTokenIds = catalogTokenProducts
        .map((product) => product.id)
        .toSet();

    const bundledTokenIds = {
      'tokens_cosmic_realms_red',
      'tokens_cosmic_realms_yellow',
      'tokens_cosmic_realms_blue',
      'tokens_cosmic_realms_green',
    };
    final expectedVisualIds = {...catalogTokenIds, ...bundledTokenIds};
    expect(tokenVisualSpecs.keys.toSet(), expectedVisualIds);
    expect(supportedTokenStyleIds, expectedVisualIds);
    expect(bundledTokenStyleIdByThemeId.values.toSet(), bundledTokenIds);
    expect(
      catalogTokenIds,
      containsAll(_premiumTokenProducts.keys),
      reason: 'Every premium board theme needs its separately sellable piece.',
    );

    for (final entry in _premiumTokenProducts.entries) {
      final products = catalogTokenProducts.where(
        (product) => product.id == entry.key,
      );
      expect(products, hasLength(1), reason: '${entry.key} must be stable');
      final product = products.single;
      expect(product.name, entry.value.name);
      expect(product.price, entry.value.price);
      expect(product.rarity, entry.value.rarity);
      expect(product.category, CosmeticCategory.tokens);

      final visual = tokenVisualSpecs[entry.key];
      expect(visual, isNotNull);
      expect(visual!.id, entry.key);
      expect(tokenVisualSpecFor(entry.key), same(visual));
    }
  });

  test('premium themes have distinct coordinated token visuals', () {
    expect(matchingTokenStyleIdByThemeId, _matchingThemeTokens);
    expect(
      matchingTokenStyleIdByThemeId.keys.toSet(),
      themeVisualSpecs.keys.toSet(),
    );
    expect(
      matchingTokenStyleIdByThemeId.values.toSet(),
      hasLength(_matchingThemeTokens.length),
      reason: 'No two board themes may silently share the same companion.',
    );

    for (final entry in _matchingThemeTokens.entries) {
      expect(matchingTokenStyleIdForTheme(entry.key), entry.value);
      expect(matchingThemeStyleIdForToken(entry.value), entry.key);
    }
    expect(matchingTokenStyleIdForTheme(null), isNull);
    expect(matchingTokenStyleIdForTheme('missing'), isNull);
    expect(matchingThemeStyleIdForToken(null), isNull);
    expect(matchingThemeStyleIdForToken('missing'), isNull);

    final premiumSpecs = _premiumTokenProducts.keys
        .map((id) => tokenVisualSpecs[id]!)
        .toList(growable: false);
    expect(
      premiumSpecs.map((spec) => spec.motif).toSet(),
      hasLength(premiumSpecs.length),
    );
    expect(
      premiumSpecs
          .map(
            (spec) => (
              spec.detailColor,
              spec.highlightColor,
              spec.outlineColor,
              spec.glowColor,
              spec.stageColor,
            ),
          )
          .toSet(),
      hasLength(premiumSpecs.length),
    );

    for (final entry in _matchingThemeTokens.entries.skip(1)) {
      final theme = themeVisualSpecs[entry.key]!;
      final token = tokenVisualSpecs[entry.value]!;
      expect(
        token.stageColor,
        theme.gameBackgroundColor,
        reason: '${entry.value} must look native to ${entry.key}.',
      );
      expect(token.detailColor.a, greaterThan(0));
      expect(token.highlightColor.a, greaterThan(0));
      expect(token.outlineColor.a, greaterThan(0));
      expect(token.glowColor.a, greaterThan(0));
    }
  });

  testWidgets(
    'store previews show every companion in all four preserved team colors',
    (tester) async {
      final wallet = await _pumpShop(tester);
      addTearDown(wallet.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _selectShopFilter(tester, 'Fichas');
      const teamColors = [
        PopColors.blue,
        PopColors.yellow,
        PopColors.red,
        PopColors.green,
      ];
      for (final tokenId in _premiumTokenProducts.keys) {
        expect(find.byKey(ValueKey('shop-preview-$tokenId')), findsOneWidget);
        expect(
          find.byKey(ValueKey('shop-preview-button-$tokenId')),
          findsOneWidget,
        );
        for (var index = 0; index < teamColors.length; index++) {
          final token = find.byKey(ValueKey('shop-token-$tokenId-$index'));
          expect(token, findsOneWidget);
          final paintedContainers = find.descendant(
            of: token,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration! as BoxDecoration).gradient
                      is LinearGradient,
            ),
          );
          expect(paintedContainers, findsOneWidget);
          final container = tester.widget<Container>(paintedContainers);
          final decoration = container.decoration! as BoxDecoration;
          final gradient = decoration.gradient! as LinearGradient;
          expect(
            gradient.colors.last,
            teamColors[index],
            reason:
                '$tokenId preview index $index must preserve its team color.',
          );
        }
        final centers = List.generate(
          teamColors.length,
          (index) => tester.getCenter(
            find.byKey(ValueKey('shop-token-$tokenId-$index')),
          ),
        );
        expect(
          centers.map((center) => center.dx.toStringAsFixed(1)).toSet(),
          hasLength(2),
          reason: '$tokenId must use two deliberate preview columns.',
        );
        expect(
          centers.map((center) => center.dy.toStringAsFixed(1)).toSet(),
          hasLength(2),
          reason: '$tokenId must use two deliberate preview rows.',
        );
      }

      await _selectShopFilter(tester, 'Temas');
      final visibleThemeIds = shopCatalog
          .where((product) => product.category == CosmeticCategory.theme)
          .map((product) => product.id)
          .toSet();
      for (final entry in _matchingThemeTokens.entries.where(
        (entry) =>
            entry.key != 'theme_default' && visibleThemeIds.contains(entry.key),
      )) {
        expect(
          find.byKey(ValueKey('shop-theme-board-${entry.key}')),
          findsOneWidget,
        );
        expect(
          shopThemePreviewTokenStyleIdForPlayer(entry.key, PlayerColor.red),
          entry.value,
          reason: '${entry.key} must preview its bundled local pieces.',
        );
        for (final color in const [
          PlayerColor.blue,
          PlayerColor.yellow,
          PlayerColor.green,
        ]) {
          expect(
            shopThemePreviewTokenStyleIdForPlayer(entry.key, color),
            'tokens_default',
            reason: 'Other players keep their own/default pieces.',
          );
        }
      }
      expect(tester.takeException(), isNull);
    },
  );

  test('English purchase message also translates the product name', () {
    expect(
      translateForLanguage('¡Fichas Pulso Neón comprado y equipado!', 'en'),
      'Neon Pulse Pieces purchased and equipped!',
    );
  });

  test('all five pieces purchase, equip and persist independently', () async {
    const initialBalance = 10000;
    final wallet = await WalletController.create(
      initialBalance: initialBalance,
    );
    addTearDown(wallet.dispose);

    for (final tokenId in _premiumTokenProducts.keys) {
      expect(await wallet.purchase(tokenId), PurchaseResult.purchased);
      expect(await wallet.equip(tokenId), EquipResult.equipped);
      expect(wallet.isOwned(tokenId), isTrue);
      expect(wallet.equippedProductId(CosmeticCategory.tokens), tokenId);
    }

    final totalPrice = _premiumTokenProducts.values.fold<int>(
      0,
      (total, product) => total + product.price,
    );
    expect(wallet.balance, initialBalance - totalPrice);
    expect(wallet.ownedProductIds, containsAll(_premiumTokenProducts.keys));

    final reloaded = await WalletController.create();
    addTearDown(reloaded.dispose);
    expect(reloaded.balance, initialBalance - totalPrice);
    expect(reloaded.ownedProductIds, containsAll(_premiumTokenProducts.keys));
    expect(
      reloaded.equippedProductId(CosmeticCategory.tokens),
      _premiumTokenProducts.keys.last,
    );
  });

  testWidgets('each coordinated piece reaches the live GameScreen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(_iPhone14Landscape);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final wallet = await WalletController.create(initialBalance: 10000);
    addTearDown(wallet.dispose);

    for (final tokenId in _premiumTokenProducts.keys) {
      expect(await wallet.purchase(tokenId), PurchaseResult.purchased);
      expect(await wallet.equip(tokenId), EquipResult.equipped);

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
      expect(board.tokenStyleIds[PlayerColor.red], tokenId);
      expect(
        tokenVisualSpecFor(board.tokenStyleIds[PlayerColor.red]),
        same(tokenVisualSpecs[tokenId]),
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      engine.dispose();
    }
  });
}
