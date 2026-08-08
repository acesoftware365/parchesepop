import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('deterministic credit is applied once across reloads', () async {
    final wallet = await WalletController.create();
    expect(
      await wallet.applyCredit(
        transactionId: 'match:m1:completion',
        amount: 30,
      ),
      ApplyCreditResult.applied,
    );
    expect(
      await wallet.applyCredit(
        transactionId: 'match:m1:completion',
        amount: 30,
      ),
      ApplyCreditResult.alreadyApplied,
    );
    expect(wallet.balance, 280);

    final restored = await WalletController.create();
    expect(restored.balance, 280);
    expect(
      await restored.applyCredit(
        transactionId: 'match:m1:completion',
        amount: 30,
      ),
      ApplyCreditResult.alreadyApplied,
    );
    expect(restored.balance, 280);
  });

  test('concurrent duplicate credits cannot mint twice', () async {
    final wallet = await WalletController.create();
    final results = await Future.wait([
      wallet.applyCredit(transactionId: 'daily:2026-08-08:first', amount: 50),
      wallet.applyCredit(transactionId: 'daily:2026-08-08:first', amount: 50),
    ]);

    expect(
      results,
      containsAll([
        ApplyCreditResult.applied,
        ApplyCreditResult.alreadyApplied,
      ]),
    );
    expect(wallet.balance, 300);
  });

  test('purchase preserves credit ledger and updated balance', () async {
    final wallet = await WalletController.create(initialBalance: 2000);
    await wallet.applyCredit(transactionId: 'mission:one', amount: 40);
    expect(
      await wallet.purchase('theme_cosmic_realms_red'),
      PurchaseResult.purchased,
    );
    expect(wallet.balance, 240);

    final restored = await WalletController.create(initialBalance: 2000);
    expect(restored.balance, 240);
    expect(
      await restored.applyCredit(transactionId: 'mission:one', amount: 40),
      ApplyCreditResult.alreadyApplied,
    );
  });

  test('concurrent purchases cannot spend the same balance twice', () async {
    final wallet = await WalletController.create(initialBalance: 2000);

    final results = await Future.wait([
      wallet.purchase('theme_cosmic_realms_red'),
      wallet.purchase('theme_cosmic_realms_yellow'),
    ]);

    expect(results, [
      PurchaseResult.purchased,
      PurchaseResult.insufficientFunds,
    ]);
    expect(wallet.balance, 200);
    expect(wallet.isOwned('theme_cosmic_realms_red'), isTrue);
    expect(wallet.isOwned('theme_cosmic_realms_yellow'), isFalse);
  });

  test('startup completes a purchase interrupted before the debit', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'parchesepop.wallet.balance.v1': 500,
      'parchesepop.wallet.purchase.v1.pending': jsonEncode(<String, Object>{
        'schemaVersion': 1,
        'productId': 'dice_galaxy',
        'price': 350,
        'balanceBefore': 500,
        'balanceAfter': 150,
      }),
    });

    final wallet = await WalletController.create();

    expect(wallet.balance, 150);
    expect(wallet.isOwned('dice_galaxy'), isTrue);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.containsKey('parchesepop.wallet.purchase.v1.pending'),
      isFalse,
    );
  });

  test('startup completes ownership after an interrupted debit', () async {
    final envelope = jsonEncode(<String, Object>{
      'schemaVersion': 2,
      'balance': 150,
      'appliedCreditIds': <String>[],
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      'parchesepop.wallet.balance.v1': 150,
      'parchesepop.wallet.credits.v2': envelope,
      'parchesepop.wallet.credits.v2.backup': envelope,
      'parchesepop.wallet.purchase.v1.pending': jsonEncode(<String, Object>{
        'schemaVersion': 1,
        'productId': 'dice_galaxy',
        'price': 350,
        'balanceBefore': 500,
        'balanceAfter': 150,
      }),
    });

    final wallet = await WalletController.create();

    expect(wallet.balance, 150);
    expect(wallet.isOwned('dice_galaxy'), isTrue);
  });

  test('invalid credits never change balance', () async {
    final wallet = await WalletController.create();
    expect(
      await wallet.applyCredit(transactionId: 'contains space', amount: 10),
      ApplyCreditResult.invalid,
    );
    expect(
      await wallet.applyCredit(transactionId: 'valid', amount: 0),
      ApplyCreditResult.invalid,
    );
    expect(wallet.balance, 250);
  });

  test('a corrupt primary ledger recovers from its verified backup', () async {
    final wallet = await WalletController.create();
    await wallet.applyCredit(
      transactionId: 'match:backup:completion',
      amount: 30,
    );
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('parchesepop.wallet.credits.v2', '{partial');

    final restored = await WalletController.create();
    expect(restored.balance, 280);
    expect(restored.creditLedgerNeedsReconciliation, isFalse);
    expect(
      await restored.applyCredit(
        transactionId: 'match:backup:completion',
        amount: 30,
      ),
      ApplyCreditResult.alreadyApplied,
    );
    expect(restored.balance, 280);
  });

  test('legacy fallback adopts known credits before replay', () async {
    SharedPreferences.setMockInitialValues({
      'parchesepop.wallet.balance.v1': 370,
      'parchesepop.wallet.credits.v2': '{partial',
      'parchesepop.wallet.credits.v2.backup': '{partial',
    });
    final wallet = await WalletController.create();
    expect(wallet.creditLedgerNeedsReconciliation, isTrue);

    await wallet.reconcileKnownCredits(const ['match:legacy:completion']);
    expect(wallet.creditLedgerNeedsReconciliation, isFalse);
    expect(
      await wallet.applyCredit(
        transactionId: 'match:legacy:completion',
        amount: 30,
      ),
      ApplyCreditResult.alreadyApplied,
    );
    expect(wallet.balance, 370);

    final restored = await WalletController.create();
    expect(restored.balance, 370);
    expect(restored.creditLedgerNeedsReconciliation, isFalse);
  });
}
