import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CosmeticCategory { theme, dice, tokens, avatar }

enum CosmeticRarity { basic, common, rare, epic, legendary }

class WalletProduct {
  const WalletProduct({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.category,
    this.featured = false,
    this.rarity = CosmeticRarity.common,
  });

  final String id;
  final String name;
  final String description;
  final int price;
  final CosmeticCategory category;
  final bool featured;
  final CosmeticRarity rarity;
}

const List<WalletProduct> walletCatalog = [
  WalletProduct(
    id: 'theme_default',
    name: 'Tablero Clásico',
    description: 'Colores originales',
    price: 0,
    category: CosmeticCategory.theme,
    rarity: CosmeticRarity.basic,
  ),
  WalletProduct(
    id: 'dice_default',
    name: 'Dados Clásicos',
    description: 'Diseño básico',
    price: 0,
    category: CosmeticCategory.dice,
    rarity: CosmeticRarity.basic,
  ),
  WalletProduct(
    id: 'tokens_default',
    name: 'Fichas Clásicas',
    description: 'Estrellas originales',
    price: 0,
    category: CosmeticCategory.tokens,
    rarity: CosmeticRarity.basic,
  ),
  WalletProduct(
    id: 'avatar_default',
    name: 'Jugador Pop',
    description: 'Emblema clásico',
    price: 0,
    category: CosmeticCategory.avatar,
    rarity: CosmeticRarity.basic,
  ),
  WalletProduct(
    id: 'theme_neon_rush',
    name: 'Ciudad Futurista',
    description: 'Rascacielos, neón y energía en movimiento',
    price: 900,
    category: CosmeticCategory.theme,
    featured: true,
    rarity: CosmeticRarity.rare,
  ),
  WalletProduct(
    id: 'theme_golden_night',
    name: 'Templo de las Pirámides',
    description: 'Dunas doradas y monumentos bajo el sol',
    price: 1200,
    category: CosmeticCategory.theme,
    rarity: CosmeticRarity.epic,
  ),
  WalletProduct(
    id: 'theme_tropical_splash',
    name: 'Selva Viva',
    description: 'Río, hojas y luciérnagas en movimiento',
    price: 1050,
    category: CosmeticCategory.theme,
    featured: true,
    rarity: CosmeticRarity.rare,
  ),
  WalletProduct(
    id: 'theme_celestial_carnival',
    name: 'Arcade Retro',
    description: 'Atardecer pixelado y pista de neón en movimiento',
    price: 1350,
    category: CosmeticCategory.theme,
    rarity: CosmeticRarity.epic,
  ),
  WalletProduct(
    id: 'theme_velvet_lounge',
    name: 'Aurora Ártica',
    description: 'Luces polares sobre montañas de hielo',
    price: 1500,
    category: CosmeticCategory.theme,
    featured: true,
    rarity: CosmeticRarity.legendary,
  ),
  WalletProduct(
    id: 'dice_galaxy',
    name: 'Dados Galaxia',
    description: 'Nebulosa brillante',
    price: 350,
    category: CosmeticCategory.dice,
    featured: true,
    rarity: CosmeticRarity.rare,
  ),
  WalletProduct(
    id: 'dice_candy_pop',
    name: 'Dados Caramelo',
    description: 'Rosa y naranja',
    price: 300,
    category: CosmeticCategory.dice,
    rarity: CosmeticRarity.common,
  ),
  WalletProduct(
    id: 'dice_volcano',
    name: 'Dados Volcán',
    description: 'Fuego y lava',
    price: 425,
    category: CosmeticCategory.dice,
    rarity: CosmeticRarity.rare,
  ),
  WalletProduct(
    id: 'dice_ice_crystal',
    name: 'Dados Hielo',
    description: 'Cristal congelado',
    price: 450,
    category: CosmeticCategory.dice,
    rarity: CosmeticRarity.rare,
  ),
  WalletProduct(
    id: 'dice_arcade_neon',
    name: 'Dados Arcade',
    description: 'Neón retro',
    price: 550,
    category: CosmeticCategory.dice,
    rarity: CosmeticRarity.epic,
  ),
  WalletProduct(
    id: 'dice_ocean_pearl',
    name: 'Dados Perla',
    description: 'Brillo del océano',
    price: 425,
    category: CosmeticCategory.dice,
    rarity: CosmeticRarity.rare,
  ),
  WalletProduct(
    id: 'dice_prism_party',
    name: 'Dados Prisma',
    description: 'Color en cada faceta',
    price: 525,
    category: CosmeticCategory.dice,
    featured: true,
    rarity: CosmeticRarity.epic,
  ),
  WalletProduct(
    id: 'dice_midnight_gold',
    name: 'Dados Medianoche',
    description: 'Constelaciones doradas',
    price: 625,
    category: CosmeticCategory.dice,
    rarity: CosmeticRarity.legendary,
  ),
  WalletProduct(
    id: 'tokens_robot',
    name: 'Fichas Robot',
    description: 'Diseño de fichas',
    price: 450,
    category: CosmeticCategory.tokens,
    rarity: CosmeticRarity.rare,
  ),
  WalletProduct(
    id: 'tokens_crystal',
    name: 'Fichas Cristal',
    description: 'Gemas con reflejo',
    price: 550,
    category: CosmeticCategory.tokens,
    featured: true,
    rarity: CosmeticRarity.rare,
  ),
  WalletProduct(
    id: 'tokens_rocket',
    name: 'Fichas Cohete',
    description: 'Despega por el tablero',
    price: 600,
    category: CosmeticCategory.tokens,
    rarity: CosmeticRarity.epic,
  ),
  WalletProduct(
    id: 'tokens_crown',
    name: 'Fichas Corona',
    description: 'Acabado digno del podio',
    price: 675,
    category: CosmeticCategory.tokens,
    rarity: CosmeticRarity.legendary,
  ),
  WalletProduct(
    id: 'tokens_neon_pulse',
    name: 'Fichas Pulso Neón',
    description: 'Combinan con Ciudad Futurista',
    price: 650,
    category: CosmeticCategory.tokens,
    rarity: CosmeticRarity.rare,
  ),
  WalletProduct(
    id: 'tokens_solar_scarab',
    name: 'Fichas Escarabajo Solar',
    description: 'Combinan con Templo de las Pirámides',
    price: 700,
    category: CosmeticCategory.tokens,
    rarity: CosmeticRarity.epic,
  ),
  WalletProduct(
    id: 'tokens_jungle_totem',
    name: 'Fichas Tótem Selvático',
    description: 'Combinan con Selva Viva',
    price: 650,
    category: CosmeticCategory.tokens,
    rarity: CosmeticRarity.rare,
  ),
  WalletProduct(
    id: 'tokens_pixel_blaster',
    name: 'Fichas Pixel Blaster',
    description: 'Combinan con Arcade Retro',
    price: 725,
    category: CosmeticCategory.tokens,
    rarity: CosmeticRarity.epic,
  ),
  WalletProduct(
    id: 'tokens_aurora_shard',
    name: 'Fichas Fragmento Aurora',
    description: 'Combinan con Aurora Ártica',
    price: 800,
    category: CosmeticCategory.tokens,
    rarity: CosmeticRarity.legendary,
  ),
  WalletProduct(
    id: 'avatar_astro',
    name: 'Astro Pop',
    description: 'Avatar espacial',
    price: 250,
    category: CosmeticCategory.avatar,
    rarity: CosmeticRarity.common,
  ),
  WalletProduct(
    id: 'avatar_ninja',
    name: 'Ninja Pixel',
    description: 'Avatar sigiloso',
    price: 300,
    category: CosmeticCategory.avatar,
    rarity: CosmeticRarity.common,
  ),
  WalletProduct(
    id: 'avatar_robot',
    name: 'Robot Turbo',
    description: 'Avatar mecánico',
    price: 350,
    category: CosmeticCategory.avatar,
    rarity: CosmeticRarity.rare,
  ),
  WalletProduct(
    id: 'avatar_explorer',
    name: 'Explorador Pop',
    description: 'Avatar aventurero',
    price: 400,
    category: CosmeticCategory.avatar,
    rarity: CosmeticRarity.rare,
  ),
  WalletProduct(
    id: 'avatar_comet',
    name: 'Cometa Pop',
    description: 'Sonrisa a toda velocidad',
    price: 275,
    category: CosmeticCategory.avatar,
    rarity: CosmeticRarity.common,
  ),
  WalletProduct(
    id: 'avatar_axolotl',
    name: 'Axolotl Splash',
    description: 'Mascota de agua y color',
    price: 350,
    category: CosmeticCategory.avatar,
    featured: true,
    rarity: CosmeticRarity.rare,
  ),
  WalletProduct(
    id: 'avatar_toucan',
    name: 'Tucán Turbo',
    description: 'Pico grande, juego grande',
    price: 425,
    category: CosmeticCategory.avatar,
    featured: true,
    rarity: CosmeticRarity.epic,
  ),
];

enum AddCoinsResult { added, invalidAmount }

enum PurchaseResult {
  purchased,
  alreadyOwned,
  insufficientFunds,
  productNotFound,
}

enum EquipResult { equipped, alreadyEquipped, notOwned, productNotFound }

class WalletController extends ChangeNotifier {
  WalletController({SharedPreferences? preferences, this.initialBalance = 250})
    : _preferences = preferences,
      _balance = initialBalance;

  static const _balanceKey = 'parchesepop.wallet.balance.v1';
  static const _ownedKey = 'parchesepop.wallet.owned.v1';
  static const _equippedPrefix = 'parchesepop.wallet.equipped.v1.';

  final int initialBalance;
  SharedPreferences? _preferences;
  int _balance;
  bool _initialized = false;
  final Set<String> _ownedProductIds = {};
  final Map<CosmeticCategory, String> _equippedProductIds = {};

  static Future<WalletController> create({
    SharedPreferences? preferences,
    int initialBalance = 250,
  }) async {
    final controller = WalletController(
      preferences: preferences,
      initialBalance: initialBalance,
    );
    await controller.initialize();
    return controller;
  }

  int get balance => _balance;
  bool get isInitialized => _initialized;
  Set<String> get ownedProductIds => Set.unmodifiable(_ownedProductIds);
  Map<CosmeticCategory, String> get equippedProductIds =>
      Map.unmodifiable(_equippedProductIds);

  Iterable<WalletProduct> get ownedProducts =>
      walletCatalog.where((product) => isOwned(product.id));

  Future<void> initialize() async {
    if (_initialized) return;

    final preferences = _preferences ??= await SharedPreferences.getInstance();
    final savedBalance = preferences.getInt(_balanceKey);
    _balance = savedBalance == null || savedBalance < 0
        ? initialBalance
        : savedBalance;

    final validIds = walletCatalog.map((product) => product.id).toSet();
    _ownedProductIds
      ..clear()
      ..addAll(
        walletCatalog
            .where((product) => product.price == 0)
            .map((product) => product.id),
      )
      ..addAll(
        (preferences.getStringList(_ownedKey) ?? const <String>[]).where(
          validIds.contains,
        ),
      );

    _equippedProductIds.clear();
    for (final category in CosmeticCategory.values) {
      final productId = preferences.getString(
        '$_equippedPrefix${category.name}',
      );
      final product = productById(productId);
      if (product != null &&
          product.category == category &&
          _ownedProductIds.contains(product.id)) {
        _equippedProductIds[category] = product.id;
      }
      if (!_equippedProductIds.containsKey(category)) {
        for (final basicProduct in walletCatalog) {
          if (basicProduct.category == category && basicProduct.price == 0) {
            _equippedProductIds[category] = basicProduct.id;
            break;
          }
        }
      }
    }

    _initialized = true;
    notifyListeners();
  }

  WalletProduct? productById(String? productId) {
    if (productId == null) return null;
    for (final product in walletCatalog) {
      if (product.id == productId) return product;
    }
    return null;
  }

  bool isOwned(String productId) => _ownedProductIds.contains(productId);

  String? equippedProductId(CosmeticCategory category) =>
      _equippedProductIds[category];

  WalletProduct? equippedProduct(CosmeticCategory category) =>
      productById(equippedProductId(category));

  bool isEquipped(String productId) =>
      _equippedProductIds.values.contains(productId);

  Future<AddCoinsResult> addCoins(int amount) async {
    await _ensureInitialized();
    if (amount <= 0) return AddCoinsResult.invalidAmount;

    _balance += amount;
    await _preferences!.setInt(_balanceKey, _balance);
    notifyListeners();
    return AddCoinsResult.added;
  }

  Future<PurchaseResult> purchase(String productId) async {
    await _ensureInitialized();
    final product = productById(productId);
    if (product == null) return PurchaseResult.productNotFound;
    if (isOwned(productId)) return PurchaseResult.alreadyOwned;
    if (_balance < product.price) return PurchaseResult.insufficientFunds;

    _balance -= product.price;
    _ownedProductIds.add(productId);
    await Future.wait([
      _preferences!.setInt(_balanceKey, _balance),
      _preferences!.setStringList(_ownedKey, _ownedProductIds.toList()..sort()),
    ]);
    notifyListeners();
    return PurchaseResult.purchased;
  }

  Future<EquipResult> equip(String productId) async {
    await _ensureInitialized();
    final product = productById(productId);
    if (product == null) return EquipResult.productNotFound;
    if (!isOwned(productId)) return EquipResult.notOwned;
    if (isEquipped(productId)) return EquipResult.alreadyEquipped;

    _equippedProductIds[product.category] = productId;
    await _preferences!.setString(
      '$_equippedPrefix${product.category.name}',
      productId,
    );
    notifyListeners();
    return EquipResult.equipped;
  }

  Future<void> resetLocalData() async {
    await _ensureInitialized();
    await Future.wait([
      _preferences!.remove(_balanceKey),
      _preferences!.remove(_ownedKey),
      for (final category in CosmeticCategory.values)
        _preferences!.remove('$_equippedPrefix${category.name}'),
    ]);

    _balance = initialBalance;
    _ownedProductIds
      ..clear()
      ..addAll(
        walletCatalog
            .where((product) => product.price == 0)
            .map((product) => product.id),
      );
    _equippedProductIds.clear();
    for (final category in CosmeticCategory.values) {
      for (final product in walletCatalog) {
        if (product.category == category && product.price == 0) {
          _equippedProductIds[category] = product.id;
          break;
        }
      }
    }
    notifyListeners();
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) await initialize();
  }
}
