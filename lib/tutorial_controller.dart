import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_analytics.dart';

typedef TutorialClock = DateTime Function();

enum TutorialLifecycle { notStarted, inProgress, skipped, completed }

enum TutorialCommandResult {
  started,
  stepCompleted,
  completed,
  skipped,
  alreadyStarted,
  alreadyCompletedStep,
  alreadyTerminal,
  notStarted,
  outOfOrder,
}

/// Persistent, UI-independent orchestration for the six-step playable tutorial.
///
/// The controller never simulates a move. A UI or scenario adapter performs an
/// action through the real [GameEngine], then reports the matching completed
/// step here. This keeps tutorial progress separate from game rules.
class TutorialController extends ChangeNotifier {
  TutorialController._({
    required SharedPreferences preferences,
    required GameAnalytics analytics,
    required TutorialClock clock,
    required this.correlation,
  }) : _preferences = preferences,
       _analytics = analytics,
       _clock = clock;

  static const storageKey = 'parchesepop.tutorial.progress.v1';
  static const _schemaVersion = 1;

  static const orderedSteps = <TutorialStep>[
    TutorialStep.firstRoll,
    TutorialStep.releaseToken,
    TutorialStep.chooseMove,
    TutorialStep.safeSquare,
    TutorialStep.capture,
    TutorialStep.reachHome,
  ];

  final SharedPreferences _preferences;
  final GameAnalytics _analytics;
  final TutorialClock _clock;
  final AnalyticsCorrelation correlation;

  TutorialLifecycle _lifecycle = TutorialLifecycle.notStarted;
  final List<TutorialStep> _completedSteps = <TutorialStep>[];
  final Set<String> _recordedAnalytics = <String>{};
  DateTime? _startedAt;
  Future<void> _operationTail = Future<void>.value();

  TutorialLifecycle get lifecycle => _lifecycle;

  List<TutorialStep> get completedSteps =>
      List<TutorialStep>.unmodifiable(_completedSteps);

  TutorialStep? get currentStep {
    if (_lifecycle == TutorialLifecycle.skipped ||
        _lifecycle == TutorialLifecycle.completed ||
        _completedSteps.length >= orderedSteps.length) {
      return null;
    }
    return orderedSteps[_completedSteps.length];
  }

  bool get shouldOffer =>
      _lifecycle == TutorialLifecycle.notStarted ||
      _lifecycle == TutorialLifecycle.inProgress;

  bool get isTerminal =>
      _lifecycle == TutorialLifecycle.skipped ||
      _lifecycle == TutorialLifecycle.completed;

  Duration get elapsed {
    final startedAt = _startedAt;
    if (startedAt == null) return Duration.zero;
    final value = _clock().difference(startedAt);
    return value.isNegative ? Duration.zero : value;
  }

  static Future<TutorialController> create({
    required GameAnalytics analytics,
    SharedPreferences? preferences,
    TutorialClock? clock,
    AnalyticsCorrelation correlation = const AnalyticsCorrelation(),
  }) async {
    final store = preferences ?? await SharedPreferences.getInstance();
    final controller = TutorialController._(
      preferences: store,
      analytics: analytics,
      clock: clock ?? DateTime.now,
      correlation: correlation,
    );
    controller._restore(store.getString(storageKey));
    await controller._reconcilePersistedAnalytics();
    return controller;
  }

  Future<TutorialCommandResult> start() => _enqueue(() async {
    if (_lifecycle == TutorialLifecycle.inProgress) {
      return TutorialCommandResult.alreadyStarted;
    }
    if (isTerminal) return TutorialCommandResult.alreadyTerminal;

    _lifecycle = TutorialLifecycle.inProgress;
    _startedAt = _clock();
    notifyListeners();
    await _persist();
    await _recordOnce(
      'started',
      TutorialEvent(
        stage: TutorialStage.started,
        elapsedSeconds: 0,
        correlation: correlation,
      ),
    );
    return TutorialCommandResult.started;
  });

  /// Records a step only when it is the next expected step.
  ///
  /// Repeated and out-of-order calls are safe no-ops, making adapters resilient
  /// to rebuilds and duplicate engine notifications.
  Future<TutorialCommandResult> completeStep(TutorialStep step) =>
      _enqueue(() async {
        if (_lifecycle == TutorialLifecycle.notStarted) {
          return TutorialCommandResult.notStarted;
        }
        if (isTerminal) return TutorialCommandResult.alreadyTerminal;
        if (_completedSteps.contains(step)) {
          return TutorialCommandResult.alreadyCompletedStep;
        }
        if (currentStep != step) return TutorialCommandResult.outOfOrder;

        _completedSteps.add(step);
        final completesTutorial = _completedSteps.length == orderedSteps.length;
        if (completesTutorial) {
          _lifecycle = TutorialLifecycle.completed;
        }
        notifyListeners();
        await _persist();

        await _recordOnce(
          'step:${step.name}',
          TutorialEvent(
            stage: TutorialStage.stepCompleted,
            step: step,
            elapsedSeconds: elapsed.inSeconds,
            correlation: correlation,
          ),
        );
        if (completesTutorial) {
          await _recordOnce(
            'completed',
            TutorialEvent(
              stage: TutorialStage.completed,
              elapsedSeconds: elapsed.inSeconds,
              correlation: correlation,
            ),
          );
          return TutorialCommandResult.completed;
        }
        return TutorialCommandResult.stepCompleted;
      });

  Future<TutorialCommandResult> skip() => _enqueue(() async {
    if (_lifecycle == TutorialLifecycle.notStarted) {
      return TutorialCommandResult.notStarted;
    }
    if (isTerminal) return TutorialCommandResult.alreadyTerminal;

    _lifecycle = TutorialLifecycle.skipped;
    notifyListeners();
    await _persist();
    await _recordOnce(
      'skipped',
      TutorialEvent(
        stage: TutorialStage.skipped,
        elapsedSeconds: elapsed.inSeconds,
        correlation: correlation,
      ),
    );
    return TutorialCommandResult.skipped;
  });

  /// Removes every persisted tutorial marker and restores the first-run state.
  ///
  /// Account deletion calls this before clearing the shared preference store so
  /// the already-mounted controller cannot retain the previous player's state.
  Future<void> resetLocalData() => _enqueue(() async {
    _lifecycle = TutorialLifecycle.notStarted;
    _completedSteps.clear();
    _recordedAnalytics.clear();
    _startedAt = null;
    await _preferences.remove(storageKey);
    notifyListeners();
  });

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  int get _elapsedSeconds => elapsed.inSeconds;

  Future<void> _recordOnce(String key, TutorialEvent event) async {
    if (!_recordedAnalytics.add(key)) return;

    // Store the idempotency marker before handing the event to analytics. A
    // duplicate lifecycle callback can never submit the same event twice.
    await _persist();
    try {
      await _analytics.logEvent(event);
    } catch (_) {
      // Analytics must never block tutorial progression. Do not include the
      // exception text because a third-party implementation could expose data.
      debugPrint('Tutorial analytics event was not recorded.');
    }
  }

  Future<void> _reconcilePersistedAnalytics() async {
    if (_lifecycle == TutorialLifecycle.notStarted) return;

    await _recordOnce(
      'started',
      TutorialEvent(
        stage: TutorialStage.started,
        elapsedSeconds: 0,
        correlation: correlation,
      ),
    );
    for (final step in _completedSteps) {
      await _recordOnce(
        'step:${step.name}',
        TutorialEvent(
          stage: TutorialStage.stepCompleted,
          step: step,
          elapsedSeconds: _elapsedSeconds,
          correlation: correlation,
        ),
      );
    }
    if (_lifecycle == TutorialLifecycle.skipped) {
      await _recordOnce(
        'skipped',
        TutorialEvent(
          stage: TutorialStage.skipped,
          elapsedSeconds: _elapsedSeconds,
          correlation: correlation,
        ),
      );
    } else if (_lifecycle == TutorialLifecycle.completed) {
      await _recordOnce(
        'completed',
        TutorialEvent(
          stage: TutorialStage.completed,
          elapsedSeconds: _elapsedSeconds,
          correlation: correlation,
        ),
      );
    }
  }

  void _restore(String? raw) {
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded['schemaVersion'] != _schemaVersion) {
        return;
      }

      final lifecycleName = decoded['lifecycle'];
      _lifecycle = TutorialLifecycle.values.firstWhere(
        (value) => value.name == lifecycleName,
        orElse: () => TutorialLifecycle.notStarted,
      );

      final rawCompleted = decoded['completedSteps'];
      final completedNames = rawCompleted is List
          ? rawCompleted.whereType<String>().toSet()
          : const <String>{};
      // Only restore a contiguous prefix. This preserves the tutorial order if
      // a future or corrupt snapshot contains arbitrary step names.
      for (final step in orderedSteps) {
        if (!completedNames.contains(step.name)) break;
        _completedSteps.add(step);
      }

      final startedAtMilliseconds = decoded['startedAtMilliseconds'];
      if (startedAtMilliseconds is int) {
        _startedAt = DateTime.fromMillisecondsSinceEpoch(
          startedAtMilliseconds,
          isUtc: true,
        );
      }

      final rawRecorded = decoded['recordedAnalytics'];
      if (rawRecorded is List) {
        _recordedAnalytics.addAll(rawRecorded.whereType<String>());
      }

      if (_lifecycle == TutorialLifecycle.notStarted) {
        _completedSteps.clear();
        _recordedAnalytics.clear();
        _startedAt = null;
      } else {
        _startedAt ??= _clock();
        if (_completedSteps.length == orderedSteps.length) {
          _lifecycle = TutorialLifecycle.completed;
        } else if (_lifecycle == TutorialLifecycle.completed) {
          _lifecycle = TutorialLifecycle.inProgress;
        }
      }
    } catch (_) {
      _lifecycle = TutorialLifecycle.notStarted;
      _completedSteps.clear();
      _recordedAnalytics.clear();
      _startedAt = null;
    }
  }

  Future<void> _persist() async {
    await _preferences.setString(
      storageKey,
      jsonEncode(<String, Object?>{
        'schemaVersion': _schemaVersion,
        'lifecycle': _lifecycle.name,
        'completedSteps': [for (final step in _completedSteps) step.name],
        'startedAtMilliseconds': _startedAt?.millisecondsSinceEpoch,
        'recordedAnalytics': _recordedAnalytics.toList()..sort(),
      }),
    );
  }
}
