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
  });
}
