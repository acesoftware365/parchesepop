import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_analytics.dart';
import 'package:parchesepop/tutorial_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingAnalytics implements TypedGameAnalytics {
  final List<GameAnalyticsEvent> events = <GameAnalyticsEvent>[];

  List<TutorialEvent> get tutorialEvents =>
      events.whereType<TutorialEvent>().toList();

  @override
  Future<void> logEvent(GameAnalyticsEvent event) async {
    events.add(event);
  }

  @override
  Future<void> logMatchStarted(MatchStartEvent event) => logEvent(event);
}

class _ThrowingAnalytics implements TypedGameAnalytics {
  int attempts = 0;

  @override
  Future<void> logEvent(GameAnalyticsEvent event) async {
    attempts++;
    throw StateError('offline');
  }

  @override
  Future<void> logMatchStarted(MatchStartEvent event) => logEvent(event);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late SharedPreferences preferences;
  late _RecordingAnalytics analytics;

  Future<TutorialController> createController({GameAnalytics? logger}) =>
      TutorialController.create(
        analytics: logger ?? analytics,
        preferences: preferences,
        clock: () => now,
        correlation: const AnalyticsCorrelation(
          anonymousSessionId: 'tutorial_session_01HZZ5Y6T7',
        ),
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await SharedPreferences.getInstance();
    analytics = _RecordingAnalytics();
    now = DateTime.utc(2026, 8, 8, 12);
  });

  test('new progress offers the first of the six ordered steps', () async {
    final controller = await createController();
    addTearDown(controller.dispose);

    expect(controller.lifecycle, TutorialLifecycle.notStarted);
    expect(controller.currentStep, TutorialStep.firstRoll);
    expect(controller.completedSteps, isEmpty);
    expect(controller.shouldOffer, isTrue);
    expect(controller.isTerminal, isFalse);
    expect(controller.elapsed, Duration.zero);
    expect(TutorialController.orderedSteps, <TutorialStep>[
      TutorialStep.firstRoll,
      TutorialStep.releaseToken,
      TutorialStep.chooseMove,
      TutorialStep.safeSquare,
      TutorialStep.capture,
      TutorialStep.reachHome,
    ]);
    expect(analytics.events, isEmpty);
  });

  test('start is idempotent and logs exactly once', () async {
    final controller = await createController();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    expect(await controller.start(), TutorialCommandResult.started);
    expect(await controller.start(), TutorialCommandResult.alreadyStarted);

    expect(controller.lifecycle, TutorialLifecycle.inProgress);
    expect(notifications, 1);
    expect(analytics.tutorialEvents, hasLength(1));
    expect(analytics.tutorialEvents.single.stage, TutorialStage.started);
    expect(analytics.tutorialEvents.single.elapsedSeconds, 0);
  });

  test('all six real-action reports complete in strict order', () async {
    final controller = await createController();
    addTearDown(controller.dispose);
    await controller.start();

    for (
      var index = 0;
      index < TutorialController.orderedSteps.length;
      index++
    ) {
      now = now.add(const Duration(seconds: 7));
      final result = await controller.completeStep(
        TutorialController.orderedSteps[index],
      );
      expect(
        result,
        index == TutorialController.orderedSteps.length - 1
            ? TutorialCommandResult.completed
            : TutorialCommandResult.stepCompleted,
      );
    }

    expect(controller.lifecycle, TutorialLifecycle.completed);
    expect(controller.currentStep, isNull);
    expect(controller.completedSteps, TutorialController.orderedSteps);
    expect(controller.shouldOffer, isFalse);
    expect(controller.isTerminal, isTrue);

    final events = analytics.tutorialEvents;
    expect(events, hasLength(8));
    expect(events.first.stage, TutorialStage.started);
    expect(
      events.skip(1).take(6).map((event) => event.stage),
      everyElement(TutorialStage.stepCompleted),
    );
    expect(
      events.skip(1).take(6).map((event) => event.step),
      TutorialController.orderedSteps,
    );
    expect(events.last.stage, TutorialStage.completed);
    expect(
      events.map((event) => event.elapsedSeconds ?? 0).toList(),
      orderedEquals(<int>[0, 7, 14, 21, 28, 35, 42, 42]),
    );
  });

  test(
    'not-started, out-of-order, and duplicate reports are safe no-ops',
    () async {
      final controller = await createController();
      addTearDown(controller.dispose);

      expect(
        await controller.completeStep(TutorialStep.firstRoll),
        TutorialCommandResult.notStarted,
      );
      expect(await controller.skip(), TutorialCommandResult.notStarted);
      await controller.start();
      expect(
        await controller.completeStep(TutorialStep.chooseMove),
        TutorialCommandResult.outOfOrder,
      );
      expect(
        await controller.completeStep(TutorialStep.firstRoll),
        TutorialCommandResult.stepCompleted,
      );
      expect(
        await controller.completeStep(TutorialStep.firstRoll),
        TutorialCommandResult.alreadyCompletedStep,
      );

      expect(controller.completedSteps, const <TutorialStep>[
        TutorialStep.firstRoll,
      ]);
      expect(controller.currentStep, TutorialStep.releaseToken);
      expect(analytics.tutorialEvents, hasLength(2));
    },
  );

  test(
    'skip is terminal, persisted, and emitted only once after reopening',
    () async {
      final first = await createController();
      await first.start();
      now = now.add(const Duration(seconds: 9));
      await first.completeStep(TutorialStep.firstRoll);
      now = now.add(const Duration(seconds: 3));
      expect(await first.skip(), TutorialCommandResult.skipped);
      expect(await first.skip(), TutorialCommandResult.alreadyTerminal);
      first.dispose();

      final reopened = await createController();
      addTearDown(reopened.dispose);
      expect(reopened.lifecycle, TutorialLifecycle.skipped);
      expect(reopened.completedSteps, const <TutorialStep>[
        TutorialStep.firstRoll,
      ]);
      expect(reopened.currentStep, isNull);
      expect(await reopened.start(), TutorialCommandResult.alreadyTerminal);
      expect(
        await reopened.completeStep(TutorialStep.releaseToken),
        TutorialCommandResult.alreadyTerminal,
      );

      expect(
        analytics.tutorialEvents.map((event) => event.stage),
        <TutorialStage>[
          TutorialStage.started,
          TutorialStage.stepCompleted,
          TutorialStage.skipped,
        ],
      );
      expect(analytics.tutorialEvents.last.elapsedSeconds, 12);
    },
  );

  test('in-progress state resumes without replaying analytics', () async {
    final first = await createController();
    await first.start();
    await first.completeStep(TutorialStep.firstRoll);
    await first.completeStep(TutorialStep.releaseToken);
    first.dispose();

    final reopened = await createController();
    addTearDown(reopened.dispose);
    expect(reopened.lifecycle, TutorialLifecycle.inProgress);
    expect(reopened.currentStep, TutorialStep.chooseMove);
    expect(await reopened.start(), TutorialCommandResult.alreadyStarted);

    for (final step in TutorialController.orderedSteps.skip(2)) {
      await reopened.completeStep(step);
    }

    expect(reopened.lifecycle, TutorialLifecycle.completed);
    expect(analytics.tutorialEvents, hasLength(8));
    expect(
      analytics.tutorialEvents.where(
        (event) => event.stage == TutorialStage.started,
      ),
      hasLength(1),
    );
    expect(
      analytics.tutorialEvents.where(
        (event) => event.stage == TutorialStage.completed,
      ),
      hasLength(1),
    );
  });

  test('concurrent duplicate commands remain exactly once', () async {
    final controller = await createController();
    addTearDown(controller.dispose);

    final starts = await Future.wait(<Future<TutorialCommandResult>>[
      controller.start(),
      controller.start(),
      controller.start(),
    ]);
    expect(
      starts.where((result) => result == TutorialCommandResult.started),
      hasLength(1),
    );

    final steps = await Future.wait(<Future<TutorialCommandResult>>[
      controller.completeStep(TutorialStep.firstRoll),
      controller.completeStep(TutorialStep.firstRoll),
      controller.completeStep(TutorialStep.firstRoll),
    ]);
    expect(
      steps.where((result) => result == TutorialCommandResult.stepCompleted),
      hasLength(1),
    );
    expect(analytics.tutorialEvents, hasLength(2));
  });

  test(
    'account-data reset clears persisted and mounted tutorial state',
    () async {
      final controller = await createController();
      addTearDown(controller.dispose);
      await controller.start();
      await controller.completeStep(TutorialStep.firstRoll);

      await controller.resetLocalData();

      expect(controller.lifecycle, TutorialLifecycle.notStarted);
      expect(controller.currentStep, TutorialStep.firstRoll);
      expect(controller.completedSteps, isEmpty);
      expect(preferences.getString(TutorialController.storageKey), isNull);

      final reopened = await createController();
      addTearDown(reopened.dispose);
      expect(reopened.lifecycle, TutorialLifecycle.notStarted);
      expect(reopened.currentStep, TutorialStep.firstRoll);
    },
  );

  test('a backwards clock is clamped to zero elapsed time', () async {
    final controller = await createController();
    addTearDown(controller.dispose);
    await controller.start();
    now = now.subtract(const Duration(minutes: 5));

    await controller.completeStep(TutorialStep.firstRoll);

    expect(controller.elapsed, Duration.zero);
    expect(analytics.tutorialEvents.last.elapsedSeconds, 0);
  });

  test('corrupt or noncontiguous persisted progress fails safe', () async {
    await preferences.setString(TutorialController.storageKey, '{bad json');
    var controller = await createController();
    expect(controller.lifecycle, TutorialLifecycle.notStarted);
    expect(controller.completedSteps, isEmpty);
    controller.dispose();

    await preferences.setString(
      TutorialController.storageKey,
      jsonEncode(<String, Object>{
        'schemaVersion': 1,
        'lifecycle': TutorialLifecycle.inProgress.name,
        'completedSteps': <String>[
          TutorialStep.firstRoll.name,
          TutorialStep.chooseMove.name,
        ],
        'startedAtMilliseconds': now.millisecondsSinceEpoch,
        'recordedAnalytics': <String>['started'],
      }),
    );
    controller = await createController();
    addTearDown(controller.dispose);

    expect(controller.completedSteps, const <TutorialStep>[
      TutorialStep.firstRoll,
    ]);
    expect(controller.currentStep, TutorialStep.releaseToken);
  });

  test(
    'analytics failures never block progress or cause duplicate attempts',
    () async {
      final throwing = _ThrowingAnalytics();
      final controller = await createController(logger: throwing);
      addTearDown(controller.dispose);

      expect(await controller.start(), TutorialCommandResult.started);
      expect(await controller.start(), TutorialCommandResult.alreadyStarted);
      expect(
        await controller.completeStep(TutorialStep.firstRoll),
        TutorialCommandResult.stepCompleted,
      );
      expect(
        await controller.completeStep(TutorialStep.firstRoll),
        TutorialCommandResult.alreadyCompletedStep,
      );

      expect(controller.currentStep, TutorialStep.releaseToken);
      expect(throwing.attempts, 2);
    },
  );
}
