import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('catalog has valid unique IDs and preserves legacy contracts', () {
    final ids = walletCatalog.map((product) => product.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    expect(ids, hasLength(33));
    for (final product in walletCatalog) {
      expect(product.id, isNotEmpty);
      expect(product.name, isNotEmpty);
      expect(product.description, isNotEmpty);
      expect(product.price, greaterThanOrEqualTo(0));
      expect(
        product.rarity == CosmeticRarity.basic,
        product.price == 0,
        reason: '${product.id}: only free built-in cosmetics are basic',
      );
    }

    final productsById = {
      for (final product in walletCatalog) product.id: product,
    };
    const legacyContracts = {
      'theme_neon_rush': ('Ciudad Futurista', 900, CosmeticCategory.theme),
      'theme_golden_night': (
        'Templo de las Pirámides',
        1200,
        CosmeticCategory.theme,
      ),
      'dice_galaxy': ('Dados Galaxia', 350, CosmeticCategory.dice),
      'tokens_robot': ('Fichas Robot', 450, CosmeticCategory.tokens),
      'avatar_astro': ('Astro Pop', 250, CosmeticCategory.avatar),
      'avatar_ninja': ('Ninja Pixel', 300, CosmeticCategory.avatar),
      'avatar_robot': ('Robot Turbo', 350, CosmeticCategory.avatar),
      'avatar_explorer': ('Explorador Pop', 400, CosmeticCategory.avatar),
    };
    for (final contract in legacyContracts.entries) {
      final product = productsById[contract.key];
      expect(product, isNotNull, reason: '${contract.key} must remain valid');
      expect(
        (product!.name, product.price, product.category),
        contract.value,
        reason: '${contract.key} must preserve its persisted contract',
      );
    }

    const newDiceContracts = {
      'dice_candy_pop': ('Dados Caramelo', 300),
      'dice_volcano': ('Dados Volcán', 425),
      'dice_ice_crystal': ('Dados Hielo', 450),
      'dice_arcade_neon': ('Dados Arcade', 550),
    };
    for (final contract in newDiceContracts.entries) {
      final product = productsById[contract.key];
      expect(product, isNotNull);
      expect(product!.category, CosmeticCategory.dice);
      expect((product.name, product.price), contract.value);
    }

    const expandedContracts = {
      'theme_default': (
        'Tablero Clásico',
        0,
        CosmeticCategory.theme,
        CosmeticRarity.basic,
      ),
      'tokens_default': (
        'Fichas Clásicas',
        0,
        CosmeticCategory.tokens,
        CosmeticRarity.basic,
      ),
      'avatar_default': (
        'Jugador Pop',
        0,
        CosmeticCategory.avatar,
        CosmeticRarity.basic,
      ),
      'theme_tropical_splash': (
        'Selva Viva',
        1050,
        CosmeticCategory.theme,
        CosmeticRarity.rare,
      ),
      'theme_celestial_carnival': (
        'Arcade Retro',
        1350,
        CosmeticCategory.theme,
        CosmeticRarity.epic,
      ),
      'theme_velvet_lounge': (
        'Aurora Ártica',
        1500,
        CosmeticCategory.theme,
        CosmeticRarity.legendary,
      ),
      'dice_ocean_pearl': (
        'Dados Perla',
        425,
        CosmeticCategory.dice,
        CosmeticRarity.rare,
      ),
      'dice_prism_party': (
        'Dados Prisma',
        525,
        CosmeticCategory.dice,
        CosmeticRarity.epic,
      ),
      'dice_midnight_gold': (
        'Dados Medianoche',
        625,
        CosmeticCategory.dice,
        CosmeticRarity.legendary,
      ),
      'tokens_crystal': (
        'Fichas Cristal',
        550,
        CosmeticCategory.tokens,
        CosmeticRarity.rare,
      ),
      'tokens_rocket': (
        'Fichas Cohete',
        600,
        CosmeticCategory.tokens,
        CosmeticRarity.epic,
      ),
      'tokens_crown': (
        'Fichas Corona',
        675,
        CosmeticCategory.tokens,
        CosmeticRarity.legendary,
      ),
      'tokens_neon_pulse': (
        'Fichas Pulso Neón',
        650,
        CosmeticCategory.tokens,
        CosmeticRarity.rare,
      ),
      'tokens_solar_scarab': (
        'Fichas Escarabajo Solar',
        700,
        CosmeticCategory.tokens,
        CosmeticRarity.epic,
      ),
      'tokens_jungle_totem': (
        'Fichas Tótem Selvático',
        650,
        CosmeticCategory.tokens,
        CosmeticRarity.rare,
      ),
      'tokens_pixel_blaster': (
        'Fichas Pixel Blaster',
        725,
        CosmeticCategory.tokens,
        CosmeticRarity.epic,
      ),
      'tokens_aurora_shard': (
        'Fichas Fragmento Aurora',
        800,
        CosmeticCategory.tokens,
        CosmeticRarity.legendary,
      ),
      'avatar_comet': (
        'Cometa Pop',
        275,
        CosmeticCategory.avatar,
        CosmeticRarity.common,
      ),
      'avatar_axolotl': (
        'Axolotl Splash',
        350,
        CosmeticCategory.avatar,
        CosmeticRarity.rare,
      ),
      'avatar_toucan': (
        'Tucán Turbo',
        425,
        CosmeticCategory.avatar,
        CosmeticRarity.epic,
      ),
    };
    for (final contract in expandedContracts.entries) {
      final product = productsById[contract.key];
      expect(product, isNotNull, reason: '${contract.key} must be available');
      expect((
        product!.name,
        product.price,
        product.category,
        product.rarity,
      ), contract.value);
    }
  });

  test('theme catalog names describe visibly different destinations', () {
    const expectedThemeNames = {
      'theme_default': 'Tablero Clásico',
      'theme_neon_rush': 'Ciudad Futurista',
      'theme_golden_night': 'Templo de las Pirámides',
      'theme_tropical_splash': 'Selva Viva',
      'theme_celestial_carnival': 'Arcade Retro',
      'theme_velvet_lounge': 'Aurora Ártica',
    };
    final themes = walletCatalog
        .where((product) => product.category == CosmeticCategory.theme)
        .toList(growable: false);

    expect(themes, hasLength(expectedThemeNames.length));
    for (final theme in themes) {
      expect(theme.name, expectedThemeNames[theme.id]);
      expect(theme.description.length, greaterThan(15));
    }
    expect(themes.map((theme) => theme.name).toSet(), hasLength(themes.length));
    expect(
      themes.map((theme) => theme.description).toSet(),
      hasLength(themes.length),
    );
  });

  test('each category has one free basic item and it leads that category', () {
    final freeProducts = walletCatalog
        .where((product) => product.price == 0)
        .toList(growable: false);

    expect(freeProducts.map((product) => product.id).toSet(), {
      'theme_default',
      'dice_default',
      'tokens_default',
      'avatar_default',
    });

    const expectedDefaults = {
      CosmeticCategory.theme: 'theme_default',
      CosmeticCategory.dice: 'dice_default',
      CosmeticCategory.tokens: 'tokens_default',
      CosmeticCategory.avatar: 'avatar_default',
    };
    for (final category in CosmeticCategory.values) {
      final products = walletCatalog
          .where((product) => product.category == category)
          .toList(growable: false);
      expect(products.first.id, expectedDefaults[category]);
      expect(products.first.price, 0);
      expect(products.first.rarity, CosmeticRarity.basic);
      expect(products.where((product) => product.price == 0), hasLength(1));
    }

    final dice = walletCatalog
        .where((product) => product.category == CosmeticCategory.dice)
        .toList(growable: false);
    expect(dice.first.id, 'dice_default');
    expect(dice.first.price, 0);
    expect(
      dice.skip(1).map((product) => product.id),
      orderedEquals(const [
        'dice_galaxy',
        'dice_candy_pop',
        'dice_volcano',
        'dice_ice_crystal',
        'dice_arcade_neon',
        'dice_ocean_pearl',
        'dice_prism_party',
        'dice_midnight_gold',
      ]),
    );
  });

  test('featured collection is curated and never contains a basic item', () {
    final featured = walletCatalog
        .where((product) => product.featured)
        .toList(growable: false);

    expect(featured, hasLength(8));
    expect(featured.map((product) => product.id).toSet(), {
      'theme_neon_rush',
      'theme_tropical_splash',
      'theme_velvet_lounge',
      'dice_galaxy',
      'dice_prism_party',
      'tokens_crystal',
      'avatar_axolotl',
      'avatar_toucan',
    });
    expect(
      featured.every((product) => product.rarity != CosmeticRarity.basic),
      isTrue,
    );
  });

  test('new model fields keep source-compatible defaults', () {
    const product = WalletProduct(
      id: 'compatibility_sample',
      name: 'Compatibility',
      description: 'Uses constructor defaults',
      price: 1,
      category: CosmeticCategory.avatar,
    );

    expect(product.featured, isFalse);
    expect(product.rarity, CosmeticRarity.common);
  });

  test('fresh wallets own and equip every basic cosmetic', () async {
    final wallet = await WalletController.create();

    const expectedDefaults = {
      CosmeticCategory.theme: 'theme_default',
      CosmeticCategory.dice: 'dice_default',
      CosmeticCategory.tokens: 'tokens_default',
      CosmeticCategory.avatar: 'avatar_default',
    };
    for (final entry in expectedDefaults.entries) {
      expect(wallet.isOwned(entry.value), isTrue);
      expect(wallet.equippedProductId(entry.key), entry.value);
      expect(wallet.isEquipped(entry.value), isTrue);
    }
  });

  test(
    'new basics are added without replacing a saved legacy selection',
    () async {
      SharedPreferences.setMockInitialValues({
        'parchesepop.wallet.owned.v1': ['theme_neon_rush'],
        'parchesepop.wallet.equipped.v1.theme': 'theme_neon_rush',
      });

      final wallet = await WalletController.create();

      expect(
        wallet.ownedProductIds,
        containsAll({
          'theme_default',
          'dice_default',
          'tokens_default',
          'avatar_default',
        }),
      );
      expect(
        wallet.equippedProductId(CosmeticCategory.theme),
        'theme_neon_rush',
      );
      expect(wallet.equippedProductId(CosmeticCategory.dice), 'dice_default');
      expect(
        wallet.equippedProductId(CosmeticCategory.tokens),
        'tokens_default',
      );
      expect(
        wallet.equippedProductId(CosmeticCategory.avatar),
        'avatar_default',
      );
    },
  );

  test('adding coins, purchasing and equipping persist after reload', () async {
    final wallet = await WalletController.create();

    expect(wallet.balance, 250);
    expect(await wallet.addCoins(1000), AddCoinsResult.added);
    expect(await wallet.purchase('theme_neon_rush'), PurchaseResult.purchased);
    expect(wallet.balance, 350);
    expect(wallet.isOwned('theme_neon_rush'), isTrue);
    expect(await wallet.equip('theme_neon_rush'), EquipResult.equipped);

    final reloaded = await WalletController.create();
    expect(reloaded.balance, 350);
    expect(reloaded.isOwned('theme_neon_rush'), isTrue);
    expect(
      reloaded.equippedProductId(CosmeticCategory.theme),
      'theme_neon_rush',
    );
  });

  test('a failed purchase never changes the balance', () async {
    final wallet = await WalletController.create();

    expect(
      await wallet.purchase('theme_golden_night'),
      PurchaseResult.insufficientFunds,
    );
    expect(wallet.balance, 250);
    expect(wallet.isOwned('theme_golden_night'), isFalse);
  });

  test('purchase and equip return explicit non-success states', () async {
    final wallet = await WalletController.create(initialBalance: 2000);

    expect(await wallet.purchase('missing'), PurchaseResult.productNotFound);
    expect(await wallet.equip('dice_galaxy'), EquipResult.notOwned);
    expect(await wallet.purchase('dice_galaxy'), PurchaseResult.purchased);
    expect(await wallet.purchase('dice_galaxy'), PurchaseResult.alreadyOwned);
    expect(await wallet.equip('dice_galaxy'), EquipResult.equipped);
    expect(await wallet.equip('dice_galaxy'), EquipResult.alreadyEquipped);
    expect(await wallet.addCoins(0), AddCoinsResult.invalidAmount);
    expect(await wallet.addCoins(-50), AddCoinsResult.invalidAmount);
  });

  test('equipping another item replaces only its own category', () async {
    final wallet = await WalletController.create(initialBalance: 3000);
    await wallet.purchase('theme_neon_rush');
    await wallet.purchase('theme_golden_night');
    await wallet.purchase('dice_galaxy');

    await wallet.equip('theme_neon_rush');
    await wallet.equip('dice_galaxy');
    await wallet.equip('theme_golden_night');

    expect(
      wallet.equippedProductId(CosmeticCategory.theme),
      'theme_golden_night',
    );
    expect(wallet.equippedProductId(CosmeticCategory.dice), 'dice_galaxy');
  });

  test('a purchased avatar can be equipped and restored', () async {
    final wallet = await WalletController.create(initialBalance: 1000);

    expect(await wallet.purchase('avatar_ninja'), PurchaseResult.purchased);
    expect(await wallet.equip('avatar_ninja'), EquipResult.equipped);

    final reloaded = await WalletController.create();
    expect(reloaded.equippedProductId(CosmeticCategory.avatar), 'avatar_ninja');
  });

  test('a new dice design can be purchased, equipped and restored', () async {
    final wallet = await WalletController.create(initialBalance: 1000);

    expect(await wallet.purchase('dice_ice_crystal'), PurchaseResult.purchased);
    expect(wallet.balance, 550);
    expect(wallet.isOwned('dice_ice_crystal'), isTrue);
    expect(await wallet.equip('dice_ice_crystal'), EquipResult.equipped);

    final reloaded = await WalletController.create();
    expect(reloaded.balance, 550);
    expect(reloaded.isOwned('dice_ice_crystal'), isTrue);
    expect(
      reloaded.equippedProductId(CosmeticCategory.dice),
      'dice_ice_crystal',
    );
  });
}
