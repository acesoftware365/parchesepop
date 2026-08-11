import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_analytics.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingAnalytics implements TypedGameAnalytics {
  final events = <GameAnalyticsEvent>[];

  @override
  Future<void> logEvent(GameAnalyticsEvent event) async {
    events.add(event);
  }

  @override
  Future<void> logMatchStarted(MatchStartEvent event) => logEvent(event);
}

void main() {
  group('anonymous analytics consent', () {
    test('defaults to off and blocks typed and legacy events', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final delegate = _RecordingAnalytics();
      final analytics = ConsentManagedGameAnalytics(
        delegate: delegate,
        preferences: preferences,
        enabled: preferences.getBool(analyticsCollectionPreferenceKey) ?? false,
      );

      expect(analytics.analyticsCollectionEnabled, isFalse);
      expect(
        preferences.containsKey(analyticsCollectionPreferenceKey),
        isFalse,
      );

      await analytics.logEvent(
        const TutorialEvent(stage: TutorialStage.started),
      );
      await analytics.logMatchStarted(
        const MatchStartEvent(
          playType: MatchPlayType.cpu,
          mode: GameMode.traditional,
          cpuDifficulty: CpuDifficulty.normal,
        ),
      );

      expect(delegate.events, isEmpty);
    });

    test(
      'persists opt-in and opt-out while forwarding only when enabled',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final preferences = await SharedPreferences.getInstance();
        final delegate = _RecordingAnalytics();
        final platformCollectionChanges = <bool>[];
        final analytics = ConsentManagedGameAnalytics(
          delegate: delegate,
          preferences: preferences,
          enabled: false,
          applyPlatformCollection: (enabled) async {
            platformCollectionChanges.add(enabled);
          },
        );

        await analytics.setAnalyticsCollectionEnabled(true);

        expect(analytics.analyticsCollectionEnabled, isTrue);
        expect(preferences.getBool(analyticsCollectionPreferenceKey), isTrue);
        expect(platformCollectionChanges, <bool>[true]);

        await analytics.logEvent(
          const TutorialEvent(stage: TutorialStage.started),
        );
        expect(delegate.events, hasLength(1));

        final restoredAnalytics = ConsentManagedGameAnalytics(
          delegate: delegate,
          preferences: preferences,
          enabled:
              preferences.getBool(analyticsCollectionPreferenceKey) ?? false,
        );
        expect(restoredAnalytics.analyticsCollectionEnabled, isTrue);

        await analytics.setAnalyticsCollectionEnabled(false);

        expect(analytics.analyticsCollectionEnabled, isFalse);
        expect(preferences.getBool(analyticsCollectionPreferenceKey), isFalse);
        expect(platformCollectionChanges, <bool>[true, false]);

        await analytics.logEvent(
          const TutorialEvent(stage: TutorialStage.completed),
        );
        expect(delegate.events, hasLength(1));
      },
    );

    test(
      'session and retention events remain off until explicit opt-in',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final preferences = await SharedPreferences.getInstance();
        final delegate = _RecordingAnalytics();
        final analytics = ConsentManagedGameAnalytics(
          delegate: delegate,
          preferences: preferences,
          enabled: false,
        );
        final firstDay = DateTime.utc(2026, 8, 8, 9);

        await recordAppSessionAnalytics(
          analytics,
          anonymousSessionId: 'session_before_opt_in',
          preferences: preferences,
          now: firstDay,
        );

        expect(delegate.events, isEmpty);
        expect(
          preferences.getInt(analyticsFirstSeenAtPreferenceKey),
          firstDay.millisecondsSinceEpoch,
        );
        expect(
          preferences.containsKey(analyticsLastSessionAtPreferenceKey),
          isFalse,
        );

        await analytics.setAnalyticsCollectionEnabled(true);
        await recordAppSessionAnalytics(
          analytics,
          anonymousSessionId: 'session_after_opt_in',
          preferences: preferences,
          now: firstDay.add(const Duration(days: 1)),
        );

        final session = delegate.events.single as AppSessionStartedEvent;
        expect(session.daysSinceFirstSeen, 1);
        expect(session.milestone, RetentionMilestone.day1);
        expect(session.isFirstAnalyticsSession, isTrue);
        expect(session.parameters['app_session_ref'], 'session_after_opt_in');
      },
    );

    test(
      'a no-op destination cannot suppress the first recovered session',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          analyticsCollectionPreferenceKey: true,
        });
        final preferences = await SharedPreferences.getInstance();
        final firstLaunch = DateTime.utc(2026, 8, 9, 10);

        await recordAppSessionAnalytics(
          const NoopGameAnalytics(),
          anonymousSessionId: 'session_noop_destination',
          preferences: preferences,
          now: firstLaunch,
        );

        expect(
          preferences.getInt(analyticsFirstSeenAtPreferenceKey),
          firstLaunch.millisecondsSinceEpoch,
        );
        expect(
          preferences.containsKey(analyticsLastSessionAtPreferenceKey),
          isFalse,
        );

        final delegate = _RecordingAnalytics();
        final recovered = ConsentManagedGameAnalytics(
          delegate: delegate,
          preferences: preferences,
          enabled: true,
        );
        final recoveredAt = firstLaunch.add(const Duration(minutes: 5));
        await recordAppSessionAnalytics(
          recovered,
          anonymousSessionId: 'session_recovered_destination',
          preferences: preferences,
          now: recoveredAt,
        );

        final session = delegate.events.single as AppSessionStartedEvent;
        expect(session.isFirstAnalyticsSession, isTrue);
        expect(session.daysSinceFirstSeen, 0);
        expect(
          preferences.getInt(analyticsLastSessionAtPreferenceKey),
          recoveredAt.millisecondsSinceEpoch,
        );
      },
    );

    test('session events use a 30-minute boundary and mark D7', () async {
      final firstDay = DateTime.utc(2026, 8, 1, 12);
      SharedPreferences.setMockInitialValues(<String, Object>{
        analyticsCollectionPreferenceKey: true,
        analyticsFirstSeenAtPreferenceKey: firstDay.millisecondsSinceEpoch,
      });
      final preferences = await SharedPreferences.getInstance();
      final delegate = _RecordingAnalytics();
      final analytics = ConsentManagedGameAnalytics(
        delegate: delegate,
        preferences: preferences,
        enabled: true,
      );
      final daySeven = firstDay.add(const Duration(days: 7));

      await recordAppSessionAnalytics(
        analytics,
        anonymousSessionId: 'session_day_seven',
        preferences: preferences,
        now: daySeven,
      );
      await recordAppSessionAnalytics(
        analytics,
        anonymousSessionId: 'session_same_window',
        preferences: preferences,
        now: daySeven.add(const Duration(minutes: 29)),
      );
      await recordAppSessionAnalytics(
        analytics,
        anonymousSessionId: 'session_next_window',
        preferences: preferences,
        now: daySeven.add(const Duration(minutes: 30)),
      );

      expect(delegate.events, hasLength(2));
      final session = delegate.events.first as AppSessionStartedEvent;
      expect(session.daysSinceFirstSeen, 7);
      expect(session.milestone, RetentionMilestone.day7);
      expect(session.parameters.keys, isNot(contains('user_id')));
      expect(
        (delegate.events.last as AppSessionStartedEvent)
            .isFirstAnalyticsSession,
        isFalse,
      );
    });
  });
}
