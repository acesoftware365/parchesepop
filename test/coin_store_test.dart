import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:parchesepop/coin_store.dart';

PurchaseDetails _purchase({
  String? purchaseId = 'transaction-1',
  String receipt = 'signed-store-receipt',
}) => PurchaseDetails(
  purchaseID: purchaseId,
  productID: coinPacks.first.productId,
  verificationData: PurchaseVerificationData(
    localVerificationData: receipt,
    serverVerificationData: receipt,
    source: 'test_store',
  ),
  transactionDate: '1785326400000',
  status: PurchaseStatus.purchased,
);

void main() {
  test('verified purchase key is stable and transaction-specific', () {
    final first = verifiedCoinPurchaseKey(_purchase());
    final repeated = verifiedCoinPurchaseKey(_purchase());
    final second = verifiedCoinPurchaseKey(
      _purchase(purchaseId: 'transaction-2'),
    );

    expect(first, isNotNull);
    expect(repeated, first);
    expect(second, isNot(first));
  });

  test('receipt digest is the fallback when a purchase ID is absent', () {
    final first = verifiedCoinPurchaseKey(
      _purchase(purchaseId: null, receipt: 'receipt-a'),
    );
    final second = verifiedCoinPurchaseKey(
      _purchase(purchaseId: null, receipt: 'receipt-b'),
    );

    expect(first, isNotNull);
    expect(second, isNot(first));
    expect(first, isNot(contains('receipt-a')));
  });

  test('purchase without store verification data is rejected', () {
    expect(verifiedCoinPurchaseKey(_purchase(receipt: '')), isNull);
  });
}
