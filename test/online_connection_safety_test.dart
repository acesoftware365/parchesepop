import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/online_connection_safety.dart';

void main() {
  test('safe mode is enabled by default and has bounded budgets', () {
    expect(OnlineConnectionSafety.enabled, isTrue);
    expect(
      OnlineConnectionSafety.authTokenTimeout,
      lessThanOrEqualTo(const Duration(seconds: 3)),
    );
    expect(
      OnlineConnectionSafety.nativeOperationTimeout,
      lessThanOrEqualTo(const Duration(seconds: 3)),
    );
    expect(
      OnlineConnectionSafety.restOperationTimeout,
      lessThanOrEqualTo(const Duration(seconds: 5)),
    );
    expect(
      OnlineConnectionSafety.nativeTransactionTimeout,
      lessThanOrEqualTo(const Duration(seconds: 6)),
    );
    expect(
      OnlineConnectionSafety.restTransactionTimeout,
      lessThanOrEqualTo(const Duration(seconds: 12)),
    );
  });

  test('only the onlineV2 subtree receives online recovery', () {
    expect(
      OnlineConnectionSafety.protectsPath('onlineV2/quickQueues/q/u'),
      isTrue,
    );
    expect(OnlineConnectionSafety.protectsPath('/onlineV2/rooms/r'), isTrue);
    expect(
      OnlineConnectionSafety.protectsPath('profile/onlineV2-copy'),
      isFalse,
    );
    expect(OnlineConnectionSafety.protectsPath('settings'), isFalse);
    expect(OnlineConnectionSafety.protectsPath(''), isFalse);
  });

  test('bounded operation returns a value without changing it', () async {
    final value = await OnlineConnectionSafety.bounded(
      'read',
      'onlineV2/quickQueues/q',
      () async => 42,
      timeout: const Duration(seconds: 1),
    );
    expect(value, 42);
  });

  test('bounded operation fails closed instead of hanging', () async {
    await expectLater(
      OnlineConnectionSafety.bounded<void>(
        'write',
        'onlineV2/quickQueues/q/u',
        () => Completer<void>().future,
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(
        isA<OnlineConnectionTimeout>()
            .having((error) => error.operation, 'operation', 'write')
            .having((error) => error.path, 'path', 'onlineV2/quickQueues/q/u'),
      ),
    );
  });
}
