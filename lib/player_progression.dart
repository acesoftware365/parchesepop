import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef ProgressionClock = DateTime Function();

const String playerProgressionStorageKey = 'parchesepop.player_progression.v1';

@immutable
class ProgressionRewardPolicy {
  const ProgressionRewardPolicy({
    this.matchCompletionCoins = 30,
    this.placementCoins = const <int, int>{1: 40, 2: 25, 3: 15, 4: 5},
    this.firstMatchOfDayCoins = 50,
    this.dailyMoveMissionTarget = 20,
    this.dailyMoveMissionCoins = 40,
    this.dailyReleaseMissionCoins = 35,
    this.weeklyMatchesTarget = 7,
    this.weeklyMatchesCoins = 150,
  }) : assert(matchCompletionCoins > 0),
       assert(firstMatchOfDayCoins > 0),
       assert(dailyMoveMissionTarget > 0),
       assert(dailyMoveMissionCoins > 0),
       assert(dailyReleaseMissionCoins > 0),
       assert(weeklyMatchesTarget > 0),
       assert(weeklyMatchesCoins > 0);

  final int matchCompletionCoins;
  final Map<int, int> placementCoins;
  final int firstMatchOfDayCoins;
  final int dailyMoveMissionTarget;
  final int dailyMoveMissionCoins;
  final int dailyReleaseMissionCoins;
  final int weeklyMatchesTarget;
  final int weeklyMatchesCoins;

  int coinsForPlacement(int placement) {
    final coins = placementCoins[placement];
    if (coins == null) {
      throw RangeError.range(placement, 1, 4, 'placement');
    }
    return coins;
  }
}

enum ProgressionTransactionSource {
  matchCompletion,
  placement,
  firstMatchOfDay,
  dailyMoveMission,
  dailyReleaseMission,
  weeklyMatchesMission,
  rewardedDouble,
}

@immutable
class ProgressionTransaction {
  const ProgressionTransaction({
    required this.id,
    required this.source,
    required this.amount,
    required this.balanceBefore,
    required this.balanceAfter,
    required this.createdAt,
    this.matchId,
    this.placement,
  });

  final String id;
  final ProgressionTransactionSource source;
  final int amount;
  final int balanceBefore;
  final int balanceAfter;
  final DateTime createdAt;
  final String? matchId;
  final int? placement;

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'source': source.name,
    'amount': amount,
    'balanceBefore': balanceBefore,
    'balanceAfter': balanceAfter,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'matchId': ?matchId,
    'placement': ?placement,
  };

  static ProgressionTransaction? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final sourceName = raw['source'];
    final amount = raw['amount'];
    final balanceBefore = raw['balanceBefore'];
    final balanceAfter = raw['balanceAfter'];
    final rawCreatedAt = raw['createdAt'];
    final createdAt = rawCreatedAt is String
        ? DateTime.tryParse(rawCreatedAt)
        : null;
    final source = ProgressionTransactionSource.values
        .where((candidate) => candidate.name == sourceName)
        .firstOrNull;
    if (id is! String ||
        id.isEmpty ||
        source == null ||
        amount is! int ||
        amount <= 0 ||
        balanceBefore is! int ||
        balanceBefore < 0 ||
        balanceAfter is! int ||
        balanceAfter != balanceBefore + amount ||
        createdAt == null) {
      return null;
    }
    final matchId = raw['matchId'];
    final placement = raw['placement'];
    if (matchId != null && matchId is! String) return null;
    if (placement != null &&
        (placement is! int || placement < 1 || placement > 4)) {
      return null;
    }
    return ProgressionTransaction(
      id: id,
      source: source,
      amount: amount,
      balanceBefore: balanceBefore,
      balanceAfter: balanceAfter,
      createdAt: createdAt,
      matchId: matchId as String?,
      placement: placement as int?,
    );
  }
}

@immutable
class ProgressionUpdate {
  const ProgressionUpdate(this.transactions);

  static const none = ProgressionUpdate(<ProgressionTransaction>[]);

  final List<ProgressionTransaction> transactions;

  int get coinsAwarded => transactions.fold<int>(
    0,
    (total, transaction) => total + transaction.amount,
  );

  bool get awardedCoins => transactions.isNotEmpty;
}

enum RewardedDoubleStatus { awarded, alreadyClaimed, notEligible }

@immutable
class RewardedDoubleResult {
  const RewardedDoubleResult({required this.status, this.transaction});

  final RewardedDoubleStatus status;
  final ProgressionTransaction? transaction;

  int get coinsAwarded => transaction?.amount ?? 0;
}

@immutable
class DailyMissionSnapshot {
  const DailyMissionSnapshot({
    required this.dayKey,
    required this.cellsMoved,
    required this.moveTarget,
    required this.moveRewardClaimed,
    required this.tokenReleased,
    required this.releaseRewardClaimed,
    required this.matchCompleted,
    required this.finishRewardClaimed,
  });

  final String dayKey;
  final int cellsMoved;
  final int moveTarget;
  final bool moveRewardClaimed;
  final bool tokenReleased;
  final bool releaseRewardClaimed;
  final bool matchCompleted;
  final bool finishRewardClaimed;

  bool get moveMissionComplete => cellsMoved >= moveTarget;
  bool get releaseMissionComplete => tokenReleased;
}

@immutable
class WeeklyMissionSnapshot {
  const WeeklyMissionSnapshot({
    required this.weekKey,
    required this.matchesCompleted,
    required this.target,
    required this.rewardClaimed,
  });

  final String weekKey;
  final int matchesCompleted;
  final int target;
  final bool rewardClaimed;

  bool get complete => matchesCompleted >= target;
}

class PlayerProgressionController extends ChangeNotifier {
  PlayerProgressionController({
    SharedPreferences? preferences,
    ProgressionClock? clock,
    this.initialBalance = 250,
    this.policy = const ProgressionRewardPolicy(),
  }) : assert(initialBalance >= 0),
       _preferences = preferences,
       _clock = clock ?? DateTime.now,
       _balance = initialBalance;

  static const _schemaVersion = 1;
  static const _legacyWalletBalanceKey = 'parchesepop.wallet.balance.v1';

  final int initialBalance;
  final ProgressionRewardPolicy policy;
  final ProgressionClock _clock;
  SharedPreferences? _preferences;

  Future<void> _mutationTail = Future<void>.value();
  bool _initialized = false;
  int _balance;
  final List<ProgressionTransaction> _transactions = <ProgressionTransaction>[];
  final Set<String> _transactionIds = <String>{};
  final Map<String, int> _matchPlacements = <String, int>{};

  String _dailyKey = '';
  int _dailyCellsMoved = 0;
  bool _dailyTokenReleased = false;
  final Set<String> _dailyProcessedEventIds = <String>{};

  String _weeklyKey = '';
  int _weeklyMatchesCompleted = 0;

  static Future<PlayerProgressionController> create({
    SharedPreferences? preferences,
    ProgressionClock? clock,
    int initialBalance = 250,
    ProgressionRewardPolicy policy = const ProgressionRewardPolicy(),
  }) async {
    final controller = PlayerProgressionController(
      preferences: preferences,
      clock: clock,
      initialBalance: initialBalance,
      policy: policy,
    );
    await controller.initialize();
    return controller;
  }

  bool get isInitialized => _initialized;
  int get balance => _balance;
  UnmodifiableListView<ProgressionTransaction> get transactions =>
      UnmodifiableListView<ProgressionTransaction>(_transactions);

  DailyMissionSnapshot get dailyMissions => DailyMissionSnapshot(
    dayKey: _dailyKey,
    cellsMoved: _dailyCellsMoved,
    moveTarget: policy.dailyMoveMissionTarget,
    moveRewardClaimed: _hasTransaction(_dailyMoveTransactionId(_dailyKey)),
    tokenReleased: _dailyTokenReleased,
    releaseRewardClaimed: _hasTransaction(
      _dailyReleaseTransactionId(_dailyKey),
    ),
    matchCompleted: _hasTransaction(_firstDailyTransactionId(_dailyKey)),
    finishRewardClaimed: _hasTransaction(_firstDailyTransactionId(_dailyKey)),
  );

  WeeklyMissionSnapshot get weeklyMission => WeeklyMissionSnapshot(
    weekKey: _weeklyKey,
    matchesCompleted: _weeklyMatchesCompleted,
    target: policy.weeklyMatchesTarget,
    rewardClaimed: _hasTransaction(_weeklyTransactionId(_weeklyKey)),
  );

  Future<void> initialize() => _enqueue<void>(() async {
    if (_initialized) return;
    _preferences ??= await SharedPreferences.getInstance();
    _loadState();
    final periodsChanged = _rollPeriods(_clock());
    _initialized = true;
    if (periodsChanged ||
        !_preferences!.containsKey(playerProgressionStorageKey)) {
      await _persist();
    }
    notifyListeners();
  });

  /// Records one newly completed match and automatically grants all rewards
  /// that become eligible at that moment.
  ///
  /// A placement may be omitted until the result is authoritative, then added
  /// later with [recordPlacement]. Duplicate calls with the same [matchId] are
  /// safe across rebuilds, resumes, and app restarts.
  Future<ProgressionUpdate> recordMatchCompleted({
    required String matchId,
    int? placement,
  }) {
    _validateExternalId(matchId, 'matchId');
    if (placement != null) _validatePlacement(placement);
    return _enqueue<ProgressionUpdate>(() async {
      await _initializeUnlocked();
      final now = _clock();
      var changed = _rollPeriods(now);
      final awarded = <ProgressionTransaction>[];

      final knownPlacement = _matchPlacements[matchId];
      if (knownPlacement != null &&
          placement != null &&
          knownPlacement != placement) {
        throw StateError(
          'Match $matchId already has placement $knownPlacement.',
        );
      }

      final completion = _applyTransaction(
        id: _matchCompletionTransactionId(matchId),
        source: ProgressionTransactionSource.matchCompletion,
        amount: policy.matchCompletionCoins,
        now: now,
        matchId: matchId,
      );
      if (completion != null) {
        changed = true;
        awarded.add(completion);

        final firstDaily = _applyTransaction(
          id: _firstDailyTransactionId(_dailyKey),
          source: ProgressionTransactionSource.firstMatchOfDay,
          amount: policy.firstMatchOfDayCoins,
          now: now,
          matchId: matchId,
        );
        if (firstDaily != null) awarded.add(firstDaily);

        _weeklyMatchesCompleted = math.min(
          policy.weeklyMatchesTarget,
          _weeklyMatchesCompleted + 1,
        );
        final weekly = _maybeCompleteWeeklyMission(now);
        if (weekly != null) awarded.add(weekly);
      }

      if (placement != null) {
        final placementTransaction = _recordPlacementUnlocked(
          matchId: matchId,
          placement: placement,
          now: now,
        );
        if (placementTransaction != null) {
          changed = true;
          awarded.add(placementTransaction);
        }
        final rewardedPlacementTransaction = _recordRewardedPlacementUnlocked(
          matchId: matchId,
          placement: placement,
          now: now,
        );
        if (rewardedPlacementTransaction != null) {
          changed = true;
          awarded.add(rewardedPlacementTransaction);
        }
      }

      if (changed) await _commit();
      return awarded.isEmpty
          ? ProgressionUpdate.none
          : ProgressionUpdate(List.unmodifiable(awarded));
    });
  }

  Future<ProgressionUpdate> recordPlacement({
    required String matchId,
    required int placement,
  }) {
    _validateExternalId(matchId, 'matchId');
    _validatePlacement(placement);
    return _enqueue<ProgressionUpdate>(() async {
      await _initializeUnlocked();
      final now = _clock();
      var changed = _rollPeriods(now);
      if (!_hasTransaction(_matchCompletionTransactionId(matchId))) {
        throw StateError('A placement cannot be recorded before completion.');
      }
      final knownPlacement = _matchPlacements[matchId];
      if (knownPlacement != null && knownPlacement != placement) {
        throw StateError(
          'Match $matchId already has placement $knownPlacement.',
        );
      }
      final awarded = <ProgressionTransaction>[];
      final placementTransaction = _recordPlacementUnlocked(
        matchId: matchId,
        placement: placement,
        now: now,
      );
      if (placementTransaction != null) {
        changed = true;
        awarded.add(placementTransaction);
      }
      final rewardedPlacementTransaction = _recordRewardedPlacementUnlocked(
        matchId: matchId,
        placement: placement,
        now: now,
      );
      if (rewardedPlacementTransaction != null) {
        changed = true;
        awarded.add(rewardedPlacementTransaction);
      }
      if (changed) await _commit();
      return awarded.isEmpty
          ? ProgressionUpdate.none
          : ProgressionUpdate(List.unmodifiable(awarded));
    });
  }

  /// Adds movement to the daily 20-cell mission.
  ///
  /// [eventId] should be stable for the originating game-engine event so a
  /// restored checkpoint cannot count the same movement twice.
  Future<ProgressionUpdate> recordCellsMoved({
    required String eventId,
    required int cells,
  }) {
    _validateExternalId(eventId, 'eventId');
    if (cells <= 0) throw ArgumentError.value(cells, 'cells', 'Must be > 0.');
    return _enqueue<ProgressionUpdate>(() async {
      await _initializeUnlocked();
      final now = _clock();
      var changed = _rollPeriods(now);
      if (!_dailyProcessedEventIds.add(eventId)) {
        if (changed) await _commit();
        return ProgressionUpdate.none;
      }
      changed = true;
      _dailyCellsMoved = math.min(
        policy.dailyMoveMissionTarget,
        _dailyCellsMoved + cells,
      );
      final transaction = _dailyCellsMoved >= policy.dailyMoveMissionTarget
          ? _applyTransaction(
              id: _dailyMoveTransactionId(_dailyKey),
              source: ProgressionTransactionSource.dailyMoveMission,
              amount: policy.dailyMoveMissionCoins,
              now: now,
            )
          : null;
      await _commit();
      return transaction == null
          ? ProgressionUpdate.none
          : ProgressionUpdate(<ProgressionTransaction>[transaction]);
    });
  }

  /// Completes the daily "release one token" mission.
  Future<ProgressionUpdate> recordTokenReleased({required String eventId}) {
    _validateExternalId(eventId, 'eventId');
    return _enqueue<ProgressionUpdate>(() async {
      await _initializeUnlocked();
      final now = _clock();
      var changed = _rollPeriods(now);
      if (!_dailyProcessedEventIds.add(eventId)) {
        if (changed) await _commit();
        return ProgressionUpdate.none;
      }
      changed = true;
      _dailyTokenReleased = true;
      final transaction = _applyTransaction(
        id: _dailyReleaseTransactionId(_dailyKey),
        source: ProgressionTransactionSource.dailyReleaseMission,
        amount: policy.dailyReleaseMissionCoins,
        now: now,
      );
      await _commit();
      return transaction == null
          ? ProgressionUpdate.none
          : ProgressionUpdate(<ProgressionTransaction>[transaction]);
    });
  }

  /// Grants the voluntary rewarded-ad x2 bonus after the ad SDK reports that
  /// the reward was earned.
  ///
  /// Only the completion and placement transactions are duplicated. Daily and
  /// weekly rewards are deliberately excluded. If placement is still pending,
  /// completion is doubled immediately and the placement reward is doubled
  /// automatically when the authoritative result arrives.
  Future<RewardedDoubleResult> claimRewardedDouble({required String matchId}) {
    _validateExternalId(matchId, 'matchId');
    return _enqueue<RewardedDoubleResult>(() async {
      await _initializeUnlocked();
      final now = _clock();
      final periodsChanged = _rollPeriods(now);
      final transactionId = _rewardedDoubleTransactionId(matchId);
      if (_hasTransaction(transactionId)) {
        if (periodsChanged) await _commit();
        return const RewardedDoubleResult(
          status: RewardedDoubleStatus.alreadyClaimed,
        );
      }
      if (!_hasTransaction(_matchCompletionTransactionId(matchId))) {
        if (periodsChanged) await _commit();
        return const RewardedDoubleResult(
          status: RewardedDoubleStatus.notEligible,
        );
      }
      final payout = matchPayout(matchId);
      if (payout <= 0) {
        if (periodsChanged) await _commit();
        return const RewardedDoubleResult(
          status: RewardedDoubleStatus.notEligible,
        );
      }
      final transaction = _applyTransaction(
        id: transactionId,
        source: ProgressionTransactionSource.rewardedDouble,
        amount: payout,
        now: now,
        matchId: matchId,
        placement: _matchPlacements[matchId],
      )!;
      await _commit();
      return RewardedDoubleResult(
        status: RewardedDoubleStatus.awarded,
        transaction: transaction,
      );
    });
  }

  /// Removes every locally earned reward and mission marker.
  ///
  /// This is separate from period rollover because account/data deletion must
  /// not restore old wallet credits during startup recovery.
  Future<void> resetLocalData() => _enqueue<void>(() async {
    await _initializeUnlocked();
    await _preferences!.remove(playerProgressionStorageKey);
    _balance = initialBalance;
    _transactions.clear();
    _transactionIds.clear();
    _matchPlacements.clear();
    _dailyKey = '';
    _dailyCellsMoved = 0;
    _dailyTokenReleased = false;
    _dailyProcessedEventIds.clear();
    _weeklyKey = '';
    _weeklyMatchesCompleted = 0;
    _rollPeriods(_clock());
    await _persist();
    notifyListeners();
  });

  int matchPayout(String matchId) {
    _validateExternalId(matchId, 'matchId');
    return _transactions
        .where(
          (transaction) =>
              transaction.matchId == matchId &&
              (transaction.source ==
                      ProgressionTransactionSource.matchCompletion ||
                  transaction.source == ProgressionTransactionSource.placement),
        )
        .fold<int>(0, (total, transaction) => total + transaction.amount);
  }

  /// Coins already credited for playing [matchId], excluding the optional
  /// rewarded-ad bonus. Used to reconstruct a restored result screen.
  int matchCoinsAwarded(String matchId) {
    _validateExternalId(matchId, 'matchId');
    return _transactions
        .where(
          (transaction) =>
              transaction.matchId == matchId &&
              transaction.source != ProgressionTransactionSource.rewardedDouble,
        )
        .fold<int>(0, (total, transaction) => total + transaction.amount);
  }

  /// Whether the optional rewarded-ad bonus for [matchId] was already paid.
  ///
  /// This lets restored result screens preserve the claimed state instead of
  /// offering an advertisement that can no longer grant another reward.
  bool rewardedDoubleClaimed(String matchId) {
    _validateExternalId(matchId, 'matchId');
    return _hasTransaction(_rewardedDoubleTransactionId(matchId));
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _mutationTail.then<T>((_) => operation());
    _mutationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _initializeUnlocked() async {
    if (_initialized) return;
    _preferences ??= await SharedPreferences.getInstance();
    _loadState();
    final periodsChanged = _rollPeriods(_clock());
    _initialized = true;
    if (periodsChanged ||
        !_preferences!.containsKey(playerProgressionStorageKey)) {
      await _persist();
    }
    notifyListeners();
  }

  void _loadState() {
    final raw = _preferences!.getString(playerProgressionStorageKey);
    if (raw == null) {
      final legacyBalance = _preferences!.getInt(_legacyWalletBalanceKey);
      _balance = legacyBalance != null && legacyBalance >= 0
          ? legacyBalance
          : initialBalance;
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['schemaVersion'] != _schemaVersion) {
        return;
      }
      final balance = decoded['balance'];
      if (balance is int && balance >= 0) _balance = balance;

      _transactions.clear();
      _transactionIds.clear();
      final rawTransactions = decoded['transactions'];
      if (rawTransactions is List) {
        for (final rawTransaction in rawTransactions) {
          final transaction = ProgressionTransaction.tryParse(rawTransaction);
          if (transaction == null || !_transactionIds.add(transaction.id)) {
            continue;
          }
          _transactions.add(transaction);
        }
      }

      _matchPlacements.clear();
      final rawPlacements = decoded['matchPlacements'];
      if (rawPlacements is Map) {
        for (final entry in rawPlacements.entries) {
          final matchId = entry.key;
          final placement = entry.value;
          if (matchId is String &&
              _isSafeExternalId(matchId) &&
              placement is int &&
              placement >= 1 &&
              placement <= 4) {
            _matchPlacements[matchId] = placement;
          }
        }
      }

      final daily = decoded['daily'];
      if (daily is Map) {
        final dailyKey = daily['key'];
        _dailyKey = dailyKey is String ? dailyKey : '';
        final cellsMoved = daily['cellsMoved'];
        _dailyCellsMoved = cellsMoved is int && cellsMoved >= 0
            ? math.min(cellsMoved, policy.dailyMoveMissionTarget)
            : 0;
        _dailyTokenReleased = daily['tokenReleased'] == true;
        _dailyProcessedEventIds.clear();
        final processedEventIds = daily['processedEventIds'];
        if (processedEventIds is List) {
          _dailyProcessedEventIds.addAll(
            processedEventIds.whereType<String>().where(_isSafeExternalId),
          );
        }
      }

      final weekly = decoded['weekly'];
      if (weekly is Map) {
        final weeklyKey = weekly['key'];
        _weeklyKey = weeklyKey is String ? weeklyKey : '';
        final matches = weekly['matchesCompleted'];
        _weeklyMatchesCompleted = matches is int && matches >= 0
            ? math.min(matches, policy.weeklyMatchesTarget)
            : 0;
      }
    } on FormatException {
      // Corrupt or partially written state falls back safely. A fresh envelope
      // is persisted by initialization without touching legacy wallet keys.
    }
  }

  bool _rollPeriods(DateTime now) {
    var changed = false;
    final nextDailyKey = _dayKey(now);
    if (_dailyKey != nextDailyKey) {
      _dailyKey = nextDailyKey;
      _dailyCellsMoved = 0;
      _dailyTokenReleased = false;
      _dailyProcessedEventIds.clear();
      changed = true;
    }
    final nextWeeklyKey = _weekKey(now);
    if (_weeklyKey != nextWeeklyKey) {
      _weeklyKey = nextWeeklyKey;
      _weeklyMatchesCompleted = 0;
      changed = true;
    }
    return changed;
  }

  ProgressionTransaction? _recordPlacementUnlocked({
    required String matchId,
    required int placement,
    required DateTime now,
  }) {
    if (!_hasTransaction(_matchCompletionTransactionId(matchId))) {
      throw StateError('A placement cannot be recorded before completion.');
    }
    final existingPlacement = _matchPlacements[matchId];
    if (existingPlacement != null && existingPlacement != placement) {
      throw StateError(
        'Match $matchId already has placement $existingPlacement.',
      );
    }
    final transaction = _applyTransaction(
      id: _matchPlacementTransactionId(matchId),
      source: ProgressionTransactionSource.placement,
      amount: policy.coinsForPlacement(placement),
      now: now,
      matchId: matchId,
      placement: placement,
    );
    _matchPlacements[matchId] = placement;
    return transaction;
  }

  ProgressionTransaction? _recordRewardedPlacementUnlocked({
    required String matchId,
    required int placement,
    required DateTime now,
  }) {
    final originalReward = _transactionById(
      _rewardedDoubleTransactionId(matchId),
    );
    if (originalReward == null || originalReward.placement != null) {
      return null;
    }
    return _applyTransaction(
      id: _rewardedDoublePlacementTransactionId(matchId),
      source: ProgressionTransactionSource.rewardedDouble,
      amount: policy.coinsForPlacement(placement),
      now: now,
      matchId: matchId,
      placement: placement,
    );
  }

  ProgressionTransaction? _maybeCompleteWeeklyMission(DateTime now) {
    if (_weeklyMatchesCompleted < policy.weeklyMatchesTarget) return null;
    return _applyTransaction(
      id: _weeklyTransactionId(_weeklyKey),
      source: ProgressionTransactionSource.weeklyMatchesMission,
      amount: policy.weeklyMatchesCoins,
      now: now,
    );
  }

  ProgressionTransaction? _applyTransaction({
    required String id,
    required ProgressionTransactionSource source,
    required int amount,
    required DateTime now,
    String? matchId,
    int? placement,
  }) {
    if (_transactionIds.contains(id)) return null;
    final transaction = ProgressionTransaction(
      id: id,
      source: source,
      amount: amount,
      balanceBefore: _balance,
      balanceAfter: _balance + amount,
      createdAt: now,
      matchId: matchId,
      placement: placement,
    );
    _balance = transaction.balanceAfter;
    _transactionIds.add(id);
    _transactions.add(transaction);
    return transaction;
  }

  bool _hasTransaction(String id) => _transactionIds.contains(id);

  ProgressionTransaction? _transactionById(String id) {
    for (final transaction in _transactions) {
      if (transaction.id == id) return transaction;
    }
    return null;
  }

  Future<void> _commit() async {
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final encoded = jsonEncode(<String, Object>{
      'schemaVersion': _schemaVersion,
      'balance': _balance,
      'transactions': <Map<String, Object>>[
        for (final transaction in _transactions) transaction.toJson(),
      ],
      'matchPlacements': <String, int>{..._matchPlacements},
      'daily': <String, Object>{
        'key': _dailyKey,
        'cellsMoved': _dailyCellsMoved,
        'tokenReleased': _dailyTokenReleased,
        'processedEventIds': _dailyProcessedEventIds.toList()..sort(),
      },
      'weekly': <String, Object>{
        'key': _weeklyKey,
        'matchesCompleted': _weeklyMatchesCompleted,
      },
    });
    final saved = await _preferences!.setString(
      playerProgressionStorageKey,
      encoded,
    );
    if (!saved) throw StateError('Player progression could not be persisted.');
  }

  static String _dayKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _weekKey(DateTime value) {
    final calendarDay = DateTime.utc(value.year, value.month, value.day);
    final monday = calendarDay.subtract(
      Duration(days: calendarDay.weekday - DateTime.monday),
    );
    return _dayKey(monday);
  }

  static String _matchCompletionTransactionId(String matchId) =>
      'match:$matchId:completion';
  static String _matchPlacementTransactionId(String matchId) =>
      'match:$matchId:placement';
  static String _firstDailyTransactionId(String dayKey) =>
      'daily:$dayKey:first_match';
  static String _dailyMoveTransactionId(String dayKey) =>
      'daily:$dayKey:mission_move_20';
  static String _dailyReleaseTransactionId(String dayKey) =>
      'daily:$dayKey:mission_release_token';
  static String _weeklyTransactionId(String weekKey) =>
      'weekly:$weekKey:finish_7';
  static String _rewardedDoubleTransactionId(String matchId) =>
      'ad:$matchId:double_match_payout';
  static String _rewardedDoublePlacementTransactionId(String matchId) =>
      'ad:$matchId:double_placement_payout';

  static void _validatePlacement(int placement) {
    if (placement < 1 || placement > 4) {
      throw RangeError.range(placement, 1, 4, 'placement');
    }
  }

  static void _validateExternalId(String value, String argumentName) {
    if (!_isSafeExternalId(value)) {
      throw ArgumentError.value(
        value,
        argumentName,
        'Use a 1-80 character opaque identifier containing only letters, '
        'numbers, underscores, or hyphens.',
      );
    }
  }

  static bool _isSafeExternalId(String value) {
    if (value.isEmpty || value.length > 80) return false;
    for (final codeUnit in value.codeUnits) {
      final digit = codeUnit >= 48 && codeUnit <= 57;
      final uppercase = codeUnit >= 65 && codeUnit <= 90;
      final lowercase = codeUnit >= 97 && codeUnit <= 122;
      final separator = codeUnit == 45 || codeUnit == 95;
      if (!digit && !uppercase && !lowercase && !separator) return false;
    }
    return true;
  }
}
