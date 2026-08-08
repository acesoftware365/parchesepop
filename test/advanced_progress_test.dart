import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/advanced_progress.dart';

void main() {
  test('rank accepts only verified results and is idempotent', () {
    final progress = CompetitiveProgress();

    expect(
      progress.applyVerifiedResult(
        resultId: 'result-1',
        outcome: VerifiedMatchOutcome.first,
        verifiedByAuthority: false,
      ),
      isFalse,
    );
    expect(
      progress.applyVerifiedResult(
        resultId: 'result-1',
        outcome: VerifiedMatchOutcome.first,
        verifiedByAuthority: true,
      ),
      isTrue,
    );
    expect(
      progress.applyVerifiedResult(
        resultId: 'result-1',
        outcome: VerifiedMatchOutcome.first,
        verifiedByAuthority: true,
      ),
      isFalse,
    );
    expect(progress.rating, 1024);
    expect(progress.verifiedMatches, 1);
    expect(progress.tier, CompetitiveTier.bronze);
  });

  test('rank survives a serialization round trip', () {
    final original = CompetitiveProgress();
    original.applyVerifiedResult(
      resultId: 'verified-a',
      outcome: VerifiedMatchOutcome.fourth,
      verifiedByAuthority: true,
    );

    final restored = CompetitiveProgress.fromJson(original.toJson());

    expect(restored.rating, original.rating);
    expect(restored.verifiedMatches, 1);
    expect(restored.appliedResultIds, contains('verified-a'));
  });

  test(
    'weekly event counts verified in-window matches once and claims once',
    () {
      final start = DateTime.utc(2026, 8, 3);
      final event = WeeklyEventProgress(
        definition: WeeklyEventDefinition(
          id: 'week-2026-32',
          startsAt: start,
          endsAt: start.add(const Duration(days: 7)),
          matchesGoal: 2,
          rewardCoins: 150,
        ),
      );

      expect(
        event.recordVerifiedMatch(
          matchId: 'm1',
          completedAt: start.add(const Duration(days: 1)),
          verifiedByAuthority: true,
        ),
        isTrue,
      );
      expect(
        event.recordVerifiedMatch(
          matchId: 'm1',
          completedAt: start.add(const Duration(days: 1)),
          verifiedByAuthority: true,
        ),
        isFalse,
      );
      expect(
        event.recordVerifiedMatch(
          matchId: 'm2',
          completedAt: start.add(const Duration(days: 2)),
          verifiedByAuthority: true,
        ),
        isTrue,
      );
      expect(event.complete, isTrue);
      expect(
        event.claimTransactionId(now: start.add(const Duration(days: 3))),
        'event:week-2026-32:claim',
      );
      expect(
        event.claimTransactionId(now: start.add(const Duration(days: 3))),
        isNull,
      );
    },
  );

  test('fair-play guard rejects monetized gameplay advantages', () {
    expect(
      FairPlayGuardrails.allows(
        changesLegalMoves: false,
        requiresEntryFee: false,
        containsPaidRandomReward: false,
        forcesAdvertisement: false,
      ),
      isTrue,
    );
    expect(
      FairPlayGuardrails.allows(
        changesLegalMoves: true,
        requiresEntryFee: false,
        containsPaidRandomReward: false,
        forcesAdvertisement: false,
      ),
      isFalse,
    );
    expect(
      FairPlayGuardrails.allows(
        changesLegalMoves: false,
        requiresEntryFee: true,
        containsPaidRandomReward: false,
        forcesAdvertisement: false,
      ),
      isFalse,
    );
  });
}
