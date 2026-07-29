import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wallet.dart';

/// Store identifiers are shared by App Store Connect and Google Play Console.
/// Keep these values unchanged once the products have been created in a store.
class CoinPack {
  const CoinPack({
    required this.productId,
    required this.coins,
    required this.fallbackPrice,
  });

  final String productId;
  final int coins;
  final String fallbackPrice;
}

const coinPacks = <CoinPack>[
  CoinPack(
    productId: 'com.liisgo.parchesepop.coins.500',
    coins: 500,
    fallbackPrice: r'$0.99',
  ),
  CoinPack(
    productId: 'com.liisgo.parchesepop.coins.1200',
    coins: 1200,
    fallbackPrice: r'$1.99',
  ),
  CoinPack(
    productId: 'com.liisgo.parchesepop.coins.3000',
    coins: 3000,
    fallbackPrice: r'$4.99',
  ),
  CoinPack(
    productId: 'com.liisgo.parchesepop.coins.7000',
    coins: 7000,
    fallbackPrice: r'$9.99',
  ),
  CoinPack(
    productId: 'com.liisgo.parchesepop.coins.16000',
    coins: 16000,
    fallbackPrice: r'$19.99',
  ),
];

@visibleForTesting
String? verifiedCoinPurchaseKey(PurchaseDetails purchase) {
  final source = purchase.verificationData.source.trim();
  final receipt = purchase.verificationData.serverVerificationData.trim();
  if (source.isEmpty || receipt.isEmpty) return null;
  final purchaseId = purchase.purchaseID?.trim();
  final uniqueValue = purchaseId == null || purchaseId.isEmpty
      ? sha256.convert(utf8.encode(receipt)).toString()
      : purchaseId;
  return '$source:${purchase.productID}:$uniqueValue';
}

class CoinStore extends ChangeNotifier {
  CoinStore(this._wallet);

  static const _fulfilledPurchaseKey = 'parchesepop.iap.fulfilled-purchases.v1';

  final WalletController _wallet;
  final InAppPurchase _iap = InAppPurchase.instance;
  final Map<String, ProductDetails> _products = {};
  final Set<String> _fulfilledPurchases = {};
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  SharedPreferences? _preferences;
  bool _available = false;
  bool _loading = true;
  String? _error;

  bool get available => _available;
  bool get loading => _loading;
  String? get error => _error;
  ProductDetails? productFor(CoinPack pack) => _products[pack.productId];

  Future<void> initialize() async {
    _preferences ??= await SharedPreferences.getInstance();
    _fulfilledPurchases
      ..clear()
      ..addAll(
        _preferences!.getStringList(_fulfilledPurchaseKey) ?? const <String>[],
      );
    _subscription ??= _iap.purchaseStream.listen(
      _handlePurchases,
      onError: (Object error) {
        _error = error.toString();
        notifyListeners();
      },
    );
    _available = await _iap.isAvailable();
    if (_available) {
      final response = await _iap.queryProductDetails(
        coinPacks.map((pack) => pack.productId).toSet(),
      );
      _products
        ..clear()
        ..addEntries(
          response.productDetails.map((item) => MapEntry(item.id, item)),
        );
      if (response.error != null) _error = response.error!.message;
    }
    _loading = false;
    notifyListeners();
  }

  Future<bool> buy(CoinPack pack) async {
    final product = productFor(pack);
    if (!_available || product == null) return false;
    return _iap.buyConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
      autoConsume: true,
    );
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      var shouldComplete = purchase.status != PurchaseStatus.purchased;
      final pack = coinPacks.where(
        (item) => item.productId == purchase.productID,
      );
      if (pack.isNotEmpty && purchase.status == PurchaseStatus.purchased) {
        final purchaseKey = verifiedCoinPurchaseKey(purchase);
        if (purchaseKey == null) {
          _error =
              'La tienda no entregó un comprobante válido. No se añadieron monedas.';
        } else if (!_fulfilledPurchases.contains(purchaseKey)) {
          await _wallet.addCoins(pack.first.coins);
          _fulfilledPurchases.add(purchaseKey);
          await _persistFulfilledPurchases();
        }
        shouldComplete = purchaseKey != null;
      }
      if (purchase.status == PurchaseStatus.error) {
        _error = purchase.error?.message ?? 'No se pudo completar la compra.';
      }
      if (purchase.pendingCompletePurchase && shouldComplete) {
        await _iap.completePurchase(purchase);
      }
    }
    notifyListeners();
  }

  Future<void> _persistFulfilledPurchases() async {
    _preferences ??= await SharedPreferences.getInstance();
    final keys = _fulfilledPurchases.toList(growable: false);
    final retained = keys.length <= 250
        ? keys
        : keys.sublist(keys.length - 250);
    await _preferences!.setStringList(_fulfilledPurchaseKey, retained);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
