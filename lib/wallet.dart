import 'dart:convert';

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
    this.availableInShop = true,
  });

  final String id;
  final String name;
  final String description;
  final int price;
  final CosmeticCategory category;
  final bool featured;
  final CosmeticRarity rarity;
  final bool availableInShop;
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
    availableInShop: false,
  ),
  WalletProduct(
    id: 'theme_golden_night',
    name: 'Templo de las Pirámides',
    description: 'Dunas doradas y monumentos bajo el sol',
    price: 1200,
    category: CosmeticCategory.theme,
    rarity: CosmeticRarity.epic,
    availableInShop: false,
  ),
  WalletProduct(
    id: 'theme_tropical_splash',
    name: 'Selva Viva',
    description: 'Río, hojas y luciérnagas en movimiento',
    price: 1050,
    category: CosmeticCategory.theme,
    featured: true,
    rarity: CosmeticRarity.rare,
    availableInShop: false,
  ),
  WalletProduct(
    id: 'theme_celestial_carnival',
    name: 'Arcade Retro',
    description: 'Atardecer pixelado y pista de neón en movimiento',
    price: 1350,
    category: CosmeticCategory.theme,
    rarity: CosmeticRarity.epic,
    availableInShop: false,
  ),
  WalletProduct(
    id: 'theme_velvet_lounge',
    name: 'Aurora Ártica',
    description: 'Luces polares sobre montañas de hielo',
    price: 1500,
    category: CosmeticCategory.theme,
    featured: true,
    rarity: CosmeticRarity.legendary,
    availableInShop: false,
  ),
  WalletProduct(
    id: 'theme_cosmic_realms_red',
    name: 'Cosmic Realms Red',
    description: 'Pack con fichas, ruta, entradas y estrellas cósmicas',
    price: 1800,
    category: CosmeticCategory.theme,
    featured: true,
    rarity: CosmeticRarity.legendary,
  ),
  WalletProduct(
    id: 'theme_cosmic_realms_yellow',
    name: 'Cosmic Realms Yellow',
    description:
        'Pack con fichas, ruta, entradas y estrellas cósmicas amarillas',
    price: 1800,
    category: CosmeticCategory.theme,
    featured: true,
    rarity: CosmeticRarity.legendary,
  ),
  WalletProduct(
    id: 'theme_cosmic_realms_blue',
    name: 'Cosmic Realms Blue',
    description: 'Pack con fichas, ruta, entradas y estrellas cósmicas azules',
    price: 1800,
    category: CosmeticCategory.theme,
    featured: true,
    rarity: CosmeticRarity.legendary,
  ),
  WalletProduct(
    id: 'theme_cosmic_realms_green',
    name: 'Cosmic Realms Green',
    description: 'Pack con fichas, ruta, entradas y estrellas cósmicas verdes',
    price: 1800,
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

/// Products currently presented for sale.
///
/// Archived products stay in [walletCatalog] so existing ownership and
/// equipped selections remain valid after the visible shop assortment changes.
Iterable<WalletProduct> get shopCatalog =>
    walletCatalog.where((product) => product.availableInShop);

enum AddCoinsResult { added, invalidAmount }

enum ApplyCreditResult { applied, alreadyApplied, invalid }

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
  static const _creditEnvelopeKey = 'parchesepop.wallet.credits.v2';
  static const _creditEnvelopeBackupKey =
      'parchesepop.wallet.credits.v2.backup';
  static const _purchaseJournalKey = 'parchesepop.wallet.purchase.v1.pending';
  static const _ownedKey = 'parchesepop.wallet.owned.v1';
  static const _equippedPrefix = 'parchesepop.wallet.equipped.v1.';

  final int initialBalance;
  SharedPreferences? _preferences;
  int _balance;
  bool _initialized = false;
  final Set<String> _ownedProductIds = {};
  final Map<CosmeticCategory, String> _equippedProductIds = {};
  final Set<String> _appliedCreditIds = {};
  Future<void> _mutationTail = Future<void>.value();
  bool _creditLedgerNeedsReconciliation = false;

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
  bool get creditLedgerNeedsReconciliation => _creditLedgerNeedsReconciliation;
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
    final creditEnvelope = preferences.getString(_creditEnvelopeKey);
    final backupEnvelope = preferences.getString(_creditEnvelopeBackupKey);
    final primaryLedger = _tryDecodeCreditEnvelope(creditEnvelope);
    final backupLedger = _tryDecodeCreditEnvelope(backupEnvelope);
    final ledger = primaryLedger ?? backupLedger;
    if (ledger != null) {
      _balance = ledger.$1;
      _appliedCreditIds
        ..clear()
        ..addAll(ledger.$2);
    } else {
      // With only the legacy balance there is no safe way to tell which
      // historical deterministic credits it already contains. The app adopts
      // known progression IDs before replaying them, preventing inflation.
      _creditLedgerNeedsReconciliation = savedBalance != null;
    }

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

    await _recoverPendingPurchase();

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
    if (primaryLedger == null && backupLedger != null) {
      // Repair a corrupt/partial primary from the last verified backup.
      await _persistCreditEnvelope();
    }
    notifyListeners();
  }

  /// Adopts historical transaction IDs without changing the legacy balance.
  ///
  /// This is used only when neither the primary nor backup v2 ledger can be
  /// recovered. New credits are applied normally after reconciliation.
  Future<void> reconcileKnownCredits(Iterable<String> transactionIds) =>
      _enqueueMutation<void>(() async {
        await _ensureInitialized();
        if (!_creditLedgerNeedsReconciliation) return;
        _appliedCreditIds.addAll(transactionIds.where(_isSafeCreditId));
        _creditLedgerNeedsReconciliation = false;
        await _persistCreditEnvelope();
        notifyListeners();
      });

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

  Future<AddCoinsResult> addCoins(int amount) =>
      _enqueueMutation<AddCoinsResult>(() async {
        await _ensureInitialized();
        if (amount <= 0) return AddCoinsResult.invalidAmount;

        _balance += amount;
        await _persistCreditEnvelope();
        notifyListeners();
        return AddCoinsResult.added;
      });

  /// Applies a reward exactly once across rebuilds, resumes and app restarts.
  ///
  /// Gameplay rewards should use this API with a deterministic transaction ID.
  /// [addCoins] remains for legacy/admin adjustments that are intentionally not
  /// deduplicated.
  Future<ApplyCreditResult> applyCredit({
    required String transactionId,
    required int amount,
  }) => _enqueueMutation<ApplyCreditResult>(() async {
        await _ensureInitialized();
        if (amount <= 0 || !_isSafeCreditId(transactionId)) {
          return ApplyCreditResult.invalid;
        }
        if (!_appliedCreditIds.add(transactionId)) {
          return ApplyCreditResult.alreadyApplied;
        }
        _balance += amount;
        await _persistCreditEnvelope();
        notifyListeners();
        return ApplyCreditResult.applied;
      });

  Future<PurchaseResult> purchase(String productId) =>
      _enqueueMutation<PurchaseResult>(() async {
        await _ensureInitialized();
        final product = productById(productId);
        if (product == null) return PurchaseResult.productNotFound;
        if (isOwned(productId)) return PurchaseResult.alreadyOwned;
        if (_balance < product.price) return PurchaseResult.insufficientFunds;

        final balanceBefore = _balance;
        final balanceAfter = balanceBefore - product.price;
        final journalSaved = await _preferences!.setString(
          _purchaseJournalKey,
          jsonEncode(<String, Object>{
            'schemaVersion': 1,
            'productId': product.id,
            'price': product.price,
            'balanceBefore': balanceBefore,
            'balanceAfter': balanceAfter,
          }),
        );
        if (!journalSaved) {
          throw StateError('Wallet purchase journal was not persisted.');
        }

        _balance = balanceAfter;
        _ownedProductIds.add(productId);
        await _persistCreditEnvelope();
        final ownedSaved = await _preferences!.setStringList(
          _ownedKey,
          _ownedProductIds.toList()..sort(),
        );
        if (!ownedSaved) {
          throw StateError('Wallet purchase ownership was not persisted.');
        }
        // If this final cleanup fails, startup recovery sees that both sides
        // already match and safely removes the journal on the next run.
        await _preferences!.remove(_purchaseJournalKey);
        notifyListeners();
        return PurchaseResult.purchased;
      });

  Future<EquipResult> equip(String productId) =>
      _enqueueMutation<EquipResult>(() async {
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
      });

  Future<void> resetLocalData() => _enqueueMutation<void>(() async {
    await _ensureInitialized();
    await Future.wait([
      _preferences!.remove(_balanceKey),
      _preferences!.remove(_creditEnvelopeKey),
      _preferences!.remove(_creditEnvelopeBackupKey),
      _preferences!.remove(_purchaseJournalKey),
      _preferences!.remove(_ownedKey),
      for (final category in CosmeticCategory.values)
        _preferences!.remove('$_equippedPrefix${category.name}'),
    ]);

    _balance = initialBalance;
    _creditLedgerNeedsReconciliation = false;
    _appliedCreditIds.clear();
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
  });

  Future<void> _ensureInitialized() async {
    if (!_initialized) await initialize();
  }

  Future<T> _enqueueMutation<T>(Future<T> Function() operation) {
    final result = _mutationTail.then((_) => operation());
    _mutationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _recoverPendingPurchase() async {
    final raw = _preferences!.getString(_purchaseJournalKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['schemaVersion'] != 1) {
        await _preferences!.remove(_purchaseJournalKey);
        return;
      }
      final productId = decoded['productId'];
      final price = decoded['price'];
      final balanceBefore = decoded['balanceBefore'];
      final balanceAfter = decoded['balanceAfter'];
      final product = productId is String ? productById(productId) : null;
      if (product == null ||
          price is! int ||
          price != product.price ||
          balanceBefore is! int ||
          balanceBefore < price ||
          balanceAfter is! int ||
          balanceAfter != balanceBefore - price) {
        await _preferences!.remove(_purchaseJournalKey);
        return;
      }

      // A crash can happen after the journal, after the debit, or after the
      // ownership write. Complete whichever half is missing, then persist both.
      if (_balance == balanceBefore) {
        _balance = balanceAfter;
      } else if (_balance != balanceAfter) {
        // The journal does not match the durable balance anymore. Do not guess
        // or alter money; discard malformed/stale recovery data safely.
        await _preferences!.remove(_purchaseJournalKey);
        return;
      }
      _ownedProductIds.add(product.id);
      await _persistCreditEnvelope();
      final ownedSaved = await _preferences!.setStringList(
        _ownedKey,
        _ownedProductIds.toList()..sort(),
      );
      if (!ownedSaved) {
        throw StateError('Recovered wallet ownership was not persisted.');
      }
      await _preferences!.remove(_purchaseJournalKey);
    } on FormatException {
      await _preferences!.remove(_purchaseJournalKey);
    }
  }

  Future<void> _persistCreditEnvelope() async {
    final encoded = jsonEncode(<String, Object>{
      'schemaVersion': 2,
      'balance': _balance,
      'appliedCreditIds': _appliedCreditIds.toList()..sort(),
    });
    final saved = await _preferences!.setString(_creditEnvelopeKey, encoded);
    if (!saved) throw StateError('Wallet credit envelope was not persisted.');
    final backupSaved = await _preferences!.setString(
      _creditEnvelopeBackupKey,
      encoded,
    );
    if (!backupSaved) {
      throw StateError('Wallet credit backup envelope was not persisted.');
    }
    // Keep the original key current for older builds and migration tools.
    await _preferences!.setInt(_balanceKey, _balance);
  }

  static bool _isSafeCreditId(String value) =>
      value.isNotEmpty &&
      value.length <= 160 &&
      RegExp(r'^[A-Za-z0-9:_\-.]+$').hasMatch(value);

  static (int, Set<String>)? _tryDecodeCreditEnvelope(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['schemaVersion'] != 2) return null;
      final balance = decoded['balance'];
      final rawIds = decoded['appliedCreditIds'];
      if (balance is! int || balance < 0 || rawIds is! List) return null;
      final ids = rawIds.whereType<String>().where(_isSafeCreditId).toSet();
      return (balance, ids);
    } on FormatException {
      return null;
    }
  }
}
