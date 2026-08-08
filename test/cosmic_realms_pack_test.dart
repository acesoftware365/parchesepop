import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/cosmetic_visuals.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';
import 'package:parchesepop/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'all four Cosmic Realms variants are purchasable complete packs',
    () async {
      const packs = {
        'theme_cosmic_realms_red': 'tokens_cosmic_realms_red',
        'theme_cosmic_realms_yellow': 'tokens_cosmic_realms_yellow',
        'theme_cosmic_realms_blue': 'tokens_cosmic_realms_blue',
        'theme_cosmic_realms_green': 'tokens_cosmic_realms_green',
      };

      final wallet = await WalletController.create(initialBalance: 10000);
      addTearDown(wallet.dispose);
      for (final entry in packs.entries) {
        final products = walletCatalog.where(
          (product) => product.id == entry.key,
        );
        expect(products, hasLength(1));
        expect(products.single.price, 1800);
        expect(products.single.rarity, CosmeticRarity.legendary);
        expect(products.single.availableInShop, isTrue);
        expect(
          walletCatalog.any((product) => product.id == entry.value),
          isFalse,
          reason: 'Bundled pieces must never require a second purchase.',
        );
        expect(bundledTokenStyleIdForTheme(entry.key), entry.value);
        expect(
          resolvedTokenStyleIdForTheme(
            themeId: entry.key,
            selectedTokenStyleId: 'tokens_robot',
          ),
          entry.value,
        );
        expect(await wallet.purchase(entry.key), PurchaseResult.purchased);
        expect(await wallet.equip(entry.key), EquipResult.equipped);
      }
      expect(wallet.balance, 2800);
    },
  );

  test('exterior route sectors retain four equal seventeen-space owners', () {
    for (final index in [
      ...List.generate(12, (index) => index),
      ...[63, 64, 65, 66, 67],
    ]) {
      expect(visualSectorOwnerForLoopIndex(index), PlayerColor.red);
    }
    for (var index = 12; index <= 28; index++) {
      expect(visualSectorOwnerForLoopIndex(index), PlayerColor.green);
    }
    for (var index = 29; index <= 45; index++) {
      expect(visualSectorOwnerForLoopIndex(index), PlayerColor.yellow);
    }
    for (var index = 46; index <= 62; index++) {
      expect(visualSectorOwnerForLoopIndex(index), PlayerColor.blue);
    }

    for (var visibleNumber = 53; visibleNumber <= 63; visibleNumber++) {
      expect(
        visualSectorOwnerForLoopIndex(visibleNumber - 1),
        PlayerColor.blue,
      );
    }
    for (var visibleNumber = 1; visibleNumber <= 12; visibleNumber++) {
      expect(visualSectorOwnerForLoopIndex(visibleNumber - 1), PlayerColor.red);
    }
  });

  testWidgets('equipping the pack changes only local theme and its pieces', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(844, 390);
    addTearDown(() {
      tester.view
        ..resetDevicePixelRatio()
        ..resetPhysicalSize();
    });
    SharedPreferences.setMockInitialValues({
      'parchesepop.wallet.owned.v1': ['theme_cosmic_realms_red'],
      'parchesepop.wallet.equipped.v1.theme': 'theme_cosmic_realms_red',
      'parchesepop.wallet.equipped.v1.tokens': 'tokens_robot',
    });
    final wallet = await WalletController.create();
    final engine = GameEngine(mode: GameMode.chaos);
    addTearDown(wallet.dispose);
    addTearDown(engine.dispose);

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
    await tester.pump(const Duration(milliseconds: 100));

    final board = tester.widget<GameBoardMockup>(find.byType(GameBoardMockup));
    expect(board.resolvedPlayerThemeIds, {
      PlayerColor.red: 'theme_cosmic_realms_red',
    });
    expect(board.tokenStyleIds[PlayerColor.red], 'tokens_cosmic_realms_red');
    for (final color in const [
      PlayerColor.blue,
      PlayerColor.yellow,
      PlayerColor.green,
    ]) {
      expect(board.resolvedPlayerThemeIds[color], isNull);
      expect(board.tokenStyleIds[color], isNull);
    }
    expect(tester.takeException(), isNull);
  });
}
