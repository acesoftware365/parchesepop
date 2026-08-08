import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/player_progression.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MutableClock {
  _MutableClock(this.value);

  DateTime value;

  DateTime call() => value;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('fresh state starts at 250 with the documented reward policy', () async {
    final clock = _MutableClock(DateTime(2026, 8, 8, 10));
    final progression = await PlayerProgressionController.create(
      clock: clock.call,
    );
    addTearDown(progression.dispose);

    expect(progression.balance, 250);
    expect(progression.policy.matchCompletionCoins, 30);
    expect(progression.policy.placementCoins, <int, int>{
      1: 40,
      2: 25,
      3: 15,
      4: 5,
    });
    expect(progression.policy.firstMatchOfDayCoins, 50);
    expect(
      progression.policy.dailyMoveMissionCoins +
          progression.policy.dailyReleaseMissionCoins,
      75,
    );
    expect(progression.policy.weeklyMatchesCoins, 150);
    expect(progression.dailyMissions.dayKey, '2026-08-08');
    expect(progression.dailyMissions.matchCompleted, isFalse);
    expect(progression.dailyMissions.finishRewardClaimed, isFalse);
    expect(progression.weeklyMission.weekKey, '2026-08-03');
  });

  test(
    'first completed match awards completion, placement, and daily bonus',
    () async {
      final progression = await PlayerProgressionController.create(
        clock: () => DateTime(2026, 8, 8, 10),
      );
      addTearDown(progression.dispose);

      final update = await progression.recordMatchCompleted(
        matchId: 'match_one',
        placement: 1,
      );

      expect(update.coinsAwarded, 120);
      expect(progression.balance, 370);
      expect(
        update.transactions.map((transaction) => transaction.source),
        containsAll(<ProgressionTransactionSource>[
          ProgressionTransactionSource.matchCompletion,
          ProgressionTransactionSource.placement,
          ProgressionTransactionSource.firstMatchOfDay,
        ]),
      );
      expect(progression.matchPayout('match_one'), 70);
      expect(progression.weeklyMission.matchesCompleted, 1);
      expect(progression.dailyMissions.matchCompleted, isTrue);
      expect(progression.dailyMissions.finishRewardClaimed, isTrue);
    },
  );

  test('placement rewards use 40, 25, 15, and 5 coins', () async {
    final progression = await PlayerProgressionController.create(
      clock: () => DateTime(2026, 8, 8, 10),
    );
    addTearDown(progression.dispose);

    for (var placement = 1; placement <= 4; placement++) {
      await progression.recordMatchCompleted(
        matchId: 'placement_$placement',
        placement: placement,
      );
      expect(
        progression.matchPayout('placement_$placement'),
        30 + progression.policy.coinsForPlacement(placement),
      );
    }

    final placementTransactions = progression.transactions
        .where(
          (transaction) =>
              transaction.source == ProgressionTransactionSource.placement,
        )
        .toList();
    expect(
      placementTransactions.map((transaction) => transaction.amount),
      <int>[40, 25, 15, 5],
    );
  });

  test('completion is idempotent across duplicate calls and reloads', () async {
    final clock = _MutableClock(DateTime(2026, 8, 8, 10));
    final first = await PlayerProgressionController.create(clock: clock.call);

    final initial = await first.recordMatchCompleted(
      matchId: 'stable_match',
      placement: 2,
    );
    final duplicate = await first.recordMatchCompleted(
      matchId: 'stable_match',
      placement: 2,
    );
    expect(initial.coinsAwarded, 105);
    expect(duplicate, same(ProgressionUpdate.none));
    expect(first.balance, 355);
    first.dispose();

    final reloaded = await PlayerProgressionController.create(
      clock: clock.call,
    );
    addTearDown(reloaded.dispose);
    final afterReload = await reloaded.recordMatchCompleted(
      matchId: 'stable_match',
      placement: 2,
    );

    expect(afterReload.coinsAwarded, 0);
    expect(reloaded.balance, 355);
    expect(reloaded.weeklyMission.matchesCompleted, 1);
    expect(reloaded.transactions, hasLength(3));
  });

  test('concurrent duplicate completion requests settle only once', () async {
    final progression = await PlayerProgressionController.create(
      clock: () => DateTime(2026, 8, 8, 10),
    );
    addTearDown(progression.dispose);

    final updates = await Future.wait(<Future<ProgressionUpdate>>[
      for (var index = 0; index < 8; index++)
        progression.recordMatchCompleted(
          matchId: 'concurrent_match',
          placement: 1,
        ),
    ]);

    expect(
      updates.fold<int>(0, (sum, update) => sum + update.coinsAwarded),
      120,
    );
    expect(progression.balance, 370);
    expect(progression.weeklyMission.matchesCompleted, 1);
    expect(progression.transactions, hasLength(3));
  });

  test(
    'a late placement is supported but conflicting results are rejected',
    () async {
      final progression = await PlayerProgressionController.create(
        clock: () => DateTime(2026, 8, 8, 10),
      );
      addTearDown(progression.dispose);

      final completion = await progression.recordMatchCompleted(
        matchId: 'late_result',
      );
      expect(completion.coinsAwarded, 80);
      expect(progression.matchPayout('late_result'), 30);

      final placement = await progression.recordPlacement(
        matchId: 'late_result',
        placement: 3,
      );
      expect(placement.coinsAwarded, 15);
      expect(progression.matchPayout('late_result'), 45);
      expect(
        progression.recordPlacement(matchId: 'late_result', placement: 2),
        throwsStateError,
      );
    },
  );

  test('placement cannot create a reward for a nonexistent match', () async {
    final progression = await PlayerProgressionController.create(
      clock: () => DateTime(2026, 8, 8, 10),
    );
    addTearDown(progression.dispose);

    await expectLater(
      progression.recordPlacement(matchId: 'missing_match', placement: 1),
      throwsStateError,
    );
    expect(progression.balance, 250);
  });

  test('first-match reward is paid once per local calendar day', () async {
    final clock = _MutableClock(DateTime(2026, 8, 8, 9));
    final progression = await PlayerProgressionController.create(
      clock: clock.call,
    );
    addTearDown(progression.dispose);

    final first = await progression.recordMatchCompleted(matchId: 'day1_a');
    final second = await progression.recordMatchCompleted(matchId: 'day1_b');
    expect(first.coinsAwarded, 80);
    expect(second.coinsAwarded, 30);

    clock.value = DateTime(2026, 8, 9, 0, 1);
    final nextDay = await progression.recordMatchCompleted(matchId: 'day2_a');
    expect(nextDay.coinsAwarded, 80);
    expect(
      progression.transactions
          .where(
            (transaction) =>
                transaction.source ==
                ProgressionTransactionSource.firstMatchOfDay,
          )
          .length,
      2,
    );
  });

  test(
    'moving 20 cells completes once and duplicate events do not count',
    () async {
      final progression = await PlayerProgressionController.create(
        clock: () => DateTime(2026, 8, 8, 10),
      );
      addTearDown(progression.dispose);

      expect(
        (await progression.recordCellsMoved(
          eventId: 'move_1',
          cells: 12,
        )).coinsAwarded,
        0,
      );
      expect(progression.dailyMissions.cellsMoved, 12);
      expect(
        (await progression.recordCellsMoved(
          eventId: 'move_1',
          cells: 12,
        )).coinsAwarded,
        0,
      );
      expect(progression.dailyMissions.cellsMoved, 12);

      final completion = await progression.recordCellsMoved(
        eventId: 'move_2',
        cells: 8,
      );
      expect(completion.coinsAwarded, 40);
      expect(progression.dailyMissions.cellsMoved, 20);
      expect(progression.dailyMissions.moveMissionComplete, isTrue);
      expect(progression.dailyMissions.moveRewardClaimed, isTrue);

      final extra = await progression.recordCellsMoved(
        eventId: 'move_3',
        cells: 25,
      );
      expect(extra.coinsAwarded, 0);
      expect(progression.dailyMissions.cellsMoved, 20);
    },
  );

  test('releasing a token completes the second daily mission once', () async {
    final progression = await PlayerProgressionController.create(
      clock: () => DateTime(2026, 8, 8, 10),
    );
    addTearDown(progression.dispose);

    final first = await progression.recordTokenReleased(eventId: 'departure_1');
    final duplicate = await progression.recordTokenReleased(
      eventId: 'departure_1',
    );
    final anotherDeparture = await progression.recordTokenReleased(
      eventId: 'departure_2',
    );

    expect(first.coinsAwarded, 35);
    expect(duplicate.coinsAwarded, 0);
    expect(anotherDeparture.coinsAwarded, 0);
    expect(progression.dailyMissions.tokenReleased, isTrue);
    expect(progression.dailyMissions.releaseRewardClaimed, isTrue);
  });

  test('daily mission progress resets and can reward again next day', () async {
    final clock = _MutableClock(DateTime(2026, 8, 8, 23, 59));
    final progression = await PlayerProgressionController.create(
      clock: clock.call,
    );
    addTearDown(progression.dispose);

    await progression.recordCellsMoved(eventId: 'old_move', cells: 20);
    await progression.recordTokenReleased(eventId: 'old_departure');
    expect(progression.balance, 325);

    clock.value = DateTime(2026, 8, 9, 0, 1);
    await progression.recordCellsMoved(eventId: 'new_move', cells: 20);
    await progression.recordTokenReleased(eventId: 'new_departure');

    expect(progression.balance, 400);
    expect(progression.dailyMissions.dayKey, '2026-08-09');
    expect(progression.dailyMissions.cellsMoved, 20);
  });

  test(
    'weekly mission pays 150 on the seventh unique completed match',
    () async {
      final progression = await PlayerProgressionController.create(
        clock: () => DateTime(2026, 8, 5, 10),
      );
      addTearDown(progression.dispose);

      for (var match = 1; match <= 6; match++) {
        final update = await progression.recordMatchCompleted(
          matchId: 'weekly_$match',
        );
        expect(
          update.transactions.any(
            (transaction) =>
                transaction.source ==
                ProgressionTransactionSource.weeklyMatchesMission,
          ),
          isFalse,
        );
      }
      expect(progression.weeklyMission.matchesCompleted, 6);
      expect(progression.weeklyMission.rewardClaimed, isFalse);

      final seventh = await progression.recordMatchCompleted(
        matchId: 'weekly_7',
      );
      expect(
        seventh.transactions
            .singleWhere(
              (transaction) =>
                  transaction.source ==
                  ProgressionTransactionSource.weeklyMatchesMission,
            )
            .amount,
        150,
      );
      expect(progression.weeklyMission.matchesCompleted, 7);
      expect(progression.weeklyMission.rewardClaimed, isTrue);

      await progression.recordMatchCompleted(matchId: 'weekly_7');
      await progression.recordMatchCompleted(matchId: 'weekly_8');
      expect(
        progression.transactions
            .where(
              (transaction) =>
                  transaction.source ==
                  ProgressionTransactionSource.weeklyMatchesMission,
            )
            .length,
        1,
      );
    },
  );

  test('weekly progress resets on Monday including a year boundary', () async {
    final clock = _MutableClock(DateTime(2027, 1, 3, 20)); // Sunday.
    final progression = await PlayerProgressionController.create(
      clock: clock.call,
    );
    addTearDown(progression.dispose);

    await progression.recordMatchCompleted(matchId: 'old_week_1');
    await progression.recordMatchCompleted(matchId: 'old_week_2');
    expect(progression.weeklyMission.weekKey, '2026-12-28');
    expect(progression.weeklyMission.matchesCompleted, 2);

    clock.value = DateTime(2027, 1, 4, 0, 1); // Monday.
    await progression.recordMatchCompleted(matchId: 'new_week_1');
    expect(progression.weeklyMission.weekKey, '2027-01-04');
    expect(progression.weeklyMission.matchesCompleted, 1);
  });

  test('rewarded x2 duplicates only completion plus placement once', () async {
    final progression = await PlayerProgressionController.create(
      clock: () => DateTime(2026, 8, 8, 10),
    );
    addTearDown(progression.dispose);

    await progression.recordMatchCompleted(matchId: 'ad_match', placement: 2);
    await progression.recordCellsMoved(eventId: 'ad_move', cells: 20);
    await progression.recordTokenReleased(eventId: 'ad_departure');
    final balanceBeforeAd = progression.balance;

    final result = await progression.claimRewardedDouble(matchId: 'ad_match');
    expect(result.status, RewardedDoubleStatus.awarded);
    expect(result.coinsAwarded, 55);
    expect(progression.balance, balanceBeforeAd + 55);
    expect(
      result.transaction!.source,
      ProgressionTransactionSource.rewardedDouble,
    );

    final duplicate = await progression.claimRewardedDouble(
      matchId: 'ad_match',
    );
    expect(duplicate.status, RewardedDoubleStatus.alreadyClaimed);
    expect(duplicate.coinsAwarded, 0);
    expect(progression.balance, balanceBeforeAd + 55);
  });

  test('rewarded x2 waits for both completion and placement', () async {
    final progression = await PlayerProgressionController.create(
      clock: () => DateTime(2026, 8, 8, 10),
    );
    addTearDown(progression.dispose);

    expect(
      (await progression.claimRewardedDouble(matchId: 'not_started')).status,
      RewardedDoubleStatus.notEligible,
    );
    await progression.recordMatchCompleted(matchId: 'pending_placement');
    expect(
      (await progression.claimRewardedDouble(
        matchId: 'pending_placement',
      )).status,
      RewardedDoubleStatus.notEligible,
    );
    await progression.recordPlacement(
      matchId: 'pending_placement',
      placement: 4,
    );
    expect(
      (await progression.claimRewardedDouble(
        matchId: 'pending_placement',
      )).coinsAwarded,
      35,
    );
  });

  test(
    'legacy wallet balance migrates once into the progression envelope',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'parchesepop.wallet.balance.v1': 875,
      });
      final first = await PlayerProgressionController.create(
        clock: () => DateTime(2026, 8, 8, 10),
      );
      expect(first.balance, 875);
      await first.recordMatchCompleted(matchId: 'migrated_match');
      expect(first.balance, 955);
      first.dispose();

      final preferences = await SharedPreferences.getInstance();
      await preferences.setInt('parchesepop.wallet.balance.v1', 12);
      final reloaded = await PlayerProgressionController.create(
        clock: () => DateTime(2026, 8, 8, 11),
      );
      addTearDown(reloaded.dispose);
      expect(reloaded.balance, 955);
    },
  );

  test(
    'corrupt storage falls back safely and writes a valid envelope',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        playerProgressionStorageKey: '{not-json',
        'parchesepop.wallet.balance.v1': 500,
      });
      final progression = await PlayerProgressionController.create(
        clock: () => DateTime(2026, 8, 8, 10),
      );
      addTearDown(progression.dispose);

      // A corrupt V1 envelope is not allowed to overwrite itself with arbitrary
      // legacy data; the constructor's safe starting balance is used.
      expect(progression.balance, 250);
      final preferences = await SharedPreferences.getInstance();
      final decoded =
          jsonDecode(preferences.getString(playerProgressionStorageKey)!)
              as Map<String, dynamic>;
      expect(decoded['schemaVersion'], 1);
      expect(decoded['balance'], 250);
    },
  );

  test('valid JSON with malformed field types cannot break startup', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      playerProgressionStorageKey: jsonEncode(<String, Object>{
        'schemaVersion': 1,
        'balance': 410,
        'transactions': <Object>[
          <String, Object>{
            'id': 'bad_created_at',
            'source': 'matchCompletion',
            'amount': 30,
            'balanceBefore': 250,
            'balanceAfter': 280,
            'createdAt': 12345,
          },
        ],
        'daily': <String, Object>{
          'key': 20260808,
          'cellsMoved': 9,
          'tokenReleased': true,
          'processedEventIds': 'not-a-list',
        },
        'weekly': <String, Object>{'key': false, 'matchesCompleted': 3},
      }),
    });

    final progression = await PlayerProgressionController.create(
      clock: () => DateTime(2026, 8, 8, 10),
    );
    addTearDown(progression.dispose);

    expect(progression.balance, 410);
    expect(progression.transactions, isEmpty);
    expect(progression.dailyMissions.dayKey, '2026-08-08');
    expect(progression.dailyMissions.cellsMoved, 0);
    expect(progression.dailyMissions.tokenReleased, isFalse);
    expect(progression.weeklyMission.weekKey, '2026-08-03');
    expect(progression.weeklyMission.matchesCompleted, 0);
  });

  test(
    'transactions preserve a continuous before/after balance chain',
    () async {
      final progression = await PlayerProgressionController.create(
        clock: () => DateTime(2026, 8, 8, 10),
      );
      addTearDown(progression.dispose);

      await progression.recordMatchCompleted(
        matchId: 'chain_match',
        placement: 3,
      );
      await progression.recordCellsMoved(eventId: 'chain_move', cells: 20);

      var expectedBefore = 250;
      for (final transaction in progression.transactions) {
        expect(transaction.balanceBefore, expectedBefore);
        expect(
          transaction.balanceAfter,
          transaction.balanceBefore + transaction.amount,
        );
        expectedBefore = transaction.balanceAfter;
      }
      expect(progression.balance, expectedBefore);
    },
  );

  test(
    'normal play reaches a 1,800 theme within seven days without ads',
    () async {
      final clock = _MutableClock(DateTime(2026, 8, 3, 10));
      final progression = await PlayerProgressionController.create(
        clock: clock.call,
      );
      addTearDown(progression.dispose);

      final endOfDayBalances = <int>[];
      for (var day = 1; day <= 7; day++) {
        await progression.recordCellsMoved(
          eventId: 'day_${day}_move',
          cells: 20,
        );
        await progression.recordTokenReleased(eventId: 'day_${day}_departure');
        await progression.recordMatchCompleted(
          matchId: 'day_${day}_match_a',
          placement: 2,
        );
        await progression.recordMatchCompleted(
          matchId: 'day_${day}_match_b',
          placement: 3,
        );
        endOfDayBalances.add(progression.balance);
        clock.value = clock.value.add(const Duration(days: 1));
      }

      expect(endOfDayBalances[4], lessThan(1800));
      expect(endOfDayBalances[5], lessThan(1800));
      expect(endOfDayBalances[6], greaterThanOrEqualTo(1800));
      expect(
        progression.transactions.where(
          (transaction) =>
              transaction.source == ProgressionTransactionSource.rewardedDouble,
        ),
        isEmpty,
      );
    },
  );

  test(
    'account data reset removes rewards and prevents later replay',
    () async {
      final clock = _MutableClock(DateTime(2026, 8, 8, 10));
      final progression = await PlayerProgressionController.create(
        clock: clock.call,
      );
      await progression.recordMatchCompleted(
        matchId: 'before_account_delete',
        placement: 1,
      );
      await progression.recordCellsMoved(eventId: 'old_move', cells: 20);
      expect(progression.transactions, isNotEmpty);
      expect(progression.balance, greaterThan(250));

      await progression.resetLocalData();
      expect(progression.balance, 250);
      expect(progression.transactions, isEmpty);
      expect(progression.dailyMissions.cellsMoved, 0);
      expect(progression.weeklyMission.matchesCompleted, 0);
      progression.dispose();

      final restored = await PlayerProgressionController.create(
        clock: clock.call,
      );
      addTearDown(restored.dispose);
      expect(restored.balance, 250);
      expect(restored.transactions, isEmpty);
      expect(restored.dailyMissions.cellsMoved, 0);
      expect(restored.weeklyMission.matchesCompleted, 0);
    },
  );

  test('invalid identifiers, movement, and placement are rejected', () async {
    final progression = await PlayerProgressionController.create(
      clock: () => DateTime(2026, 8, 8, 10),
    );
    addTearDown(progression.dispose);

    expect(
      () => progression.recordMatchCompleted(matchId: 'player@example.com'),
      throwsArgumentError,
    );
    expect(
      () => progression.recordCellsMoved(eventId: 'move', cells: 0),
      throwsArgumentError,
    );
    expect(
      () => progression.recordMatchCompleted(
        matchId: 'bad_placement',
        placement: 5,
      ),
      throwsRangeError,
    );
    expect(progression.balance, 250);
  });
}
