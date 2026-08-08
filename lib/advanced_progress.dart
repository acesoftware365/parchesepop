import 'dart:collection';

/// Competitive progression intentionally never accepts an entry fee and never
/// changes board rules. It is recognition only, so cosmetics and coins cannot
/// buy a gameplay advantage.
enum CompetitiveTier { rookie, bronze, silver, gold, master }

enum VerifiedMatchOutcome { first, second, third, fourth, abandoned }

class CompetitiveProgress {
  CompetitiveProgress({
    int rating = 1000,
    int verifiedMatches = 0,
    Iterable<String> appliedResultIds = const [],
  }) : _rating = rating.clamp(0, 3000),
       _verifiedMatches = verifiedMatches < 0 ? 0 : verifiedMatches,
       _appliedResultIds = Set<String>.of(appliedResultIds);

  int _rating;
  int _verifiedMatches;
  final Set<String> _appliedResultIds;

  int get rating => _rating;
  int get verifiedMatches => _verifiedMatches;
  Set<String> get appliedResultIds => UnmodifiableSetView(_appliedResultIds);

  CompetitiveTier get tier => switch (_rating) {
    < 900 => CompetitiveTier.rookie,
    < 1200 => CompetitiveTier.bronze,
    < 1500 => CompetitiveTier.silver,
    < 1800 => CompetitiveTier.gold,
    _ => CompetitiveTier.master,
  };

  /// Applies a server-verified result exactly once.
  ///
  /// Unverified local results are rejected so a modified client cannot mint
  /// rank. No wallet is accepted here by design: ranked play has no wager,
  /// rake, paid retry or currency payout.
  bool applyVerifiedResult({
    required String resultId,
    required VerifiedMatchOutcome outcome,
    required bool verifiedByAuthority,
  }) {
    if (!verifiedByAuthority || resultId.trim().isEmpty) return false;
    if (!_appliedResultIds.add(resultId)) return false;

    final delta = switch (outcome) {
      VerifiedMatchOutcome.first => 24,
      VerifiedMatchOutcome.second => 8,
      VerifiedMatchOutcome.third => -8,
      VerifiedMatchOutcome.fourth => -16,
      VerifiedMatchOutcome.abandoned => -20,
    };
    _rating = (_rating + delta).clamp(0, 3000);
    _verifiedMatches++;
    return true;
  }

  Map<String, Object> toJson() => {
    'rating': _rating,
    'verifiedMatches': _verifiedMatches,
    'appliedResultIds': _appliedResultIds.toList()..sort(),
  };

  factory CompetitiveProgress.fromJson(Map<String, dynamic> json) =>
      CompetitiveProgress(
        rating: json['rating'] as int? ?? 1000,
        verifiedMatches: json['verifiedMatches'] as int? ?? 0,
        appliedResultIds:
            (json['appliedResultIds'] as List<dynamic>? ?? const [])
                .whereType<String>(),
      );
}

class WeeklyEventDefinition {
  WeeklyEventDefinition({
    required this.id,
    required this.startsAt,
    required this.endsAt,
    required this.matchesGoal,
    required this.rewardCoins,
  }) : assert(matchesGoal > 0),
       assert(rewardCoins > 0),
       assert(endsAt.isAfter(startsAt));

  final String id;
  final DateTime startsAt;
  final DateTime endsAt;
  final int matchesGoal;
  final int rewardCoins;

  bool isActiveAt(DateTime now) =>
      !now.isBefore(startsAt) && now.isBefore(endsAt);
}

class WeeklyEventProgress {
  WeeklyEventProgress({
    required this.definition,
    int completedMatches = 0,
    bool claimed = false,
    Iterable<String> appliedMatchIds = const [],
  }) : _completedMatches = completedMatches.clamp(0, definition.matchesGoal),
       _claimed = claimed,
       _appliedMatchIds = Set<String>.of(appliedMatchIds);

  final WeeklyEventDefinition definition;
  int _completedMatches;
  bool _claimed;
  final Set<String> _appliedMatchIds;

  int get completedMatches => _completedMatches;
  bool get claimed => _claimed;
  bool get complete => _completedMatches >= definition.matchesGoal;
  double get progress => _completedMatches / definition.matchesGoal;

  bool recordVerifiedMatch({
    required String matchId,
    required DateTime completedAt,
    required bool verifiedByAuthority,
  }) {
    if (!verifiedByAuthority ||
        matchId.trim().isEmpty ||
        !definition.isActiveAt(completedAt) ||
        !_appliedMatchIds.add(matchId)) {
      return false;
    }
    if (_completedMatches < definition.matchesGoal) _completedMatches++;
    return true;
  }

  /// Returns the idempotent wallet transaction that may be credited by the
  /// authoritative economy service, or null when the event is not claimable.
  String? claimTransactionId({required DateTime now}) {
    if (_claimed || !complete || !definition.isActiveAt(now)) return null;
    _claimed = true;
    return 'event:${definition.id}:claim';
  }
}

/// Guardrails checked by future catalog/event configuration before exposure.
class FairPlayGuardrails {
  const FairPlayGuardrails._();

  static bool allows({
    required bool changesLegalMoves,
    required bool requiresEntryFee,
    required bool containsPaidRandomReward,
    required bool forcesAdvertisement,
  }) =>
      !changesLegalMoves &&
      !requiresEntryFee &&
      !containsPaidRandomReward &&
      !forcesAdvertisement;
}
