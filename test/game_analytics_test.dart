import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_analytics.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';
import 'package:parchesepop/online_match.dart';
import 'package:parchesepop/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingGameAnalytics implements GameAnalytics {
  final events = <MatchStartEvent>[];

  @override
  Future<void> logMatchStarted(MatchStartEvent event) async {
    events.add(event);
  }
}

class _RecordingTypedAnalytics implements TypedGameAnalytics {
  final events = <GameAnalyticsEvent>[];

  @override
  Future<void> logEvent(GameAnalyticsEvent event) async {
    events.add(event);
  }

  @override
  Future<void> logMatchStarted(MatchStartEvent event) => logEvent(event);
}

GameEngine _oneMoveFromVictory() {
  final engine = GameEngine();
  final player = engine.currentPlayer;
  for (var tokenId = 0; tokenId < 3; tokenId++) {
    player.tokens[tokenId].progress = GameEngine.finishProgress;
  }
  player.tokens.last.progress = GameEngine.finishProgress - 1;
  engine.hasRolled = true;
  engine.dice = [1, 6];
  engine.remainingDice.addAll([1, 6]);
  return engine;
}

class _RecordedSinkEvent {
  const _RecordedSinkEvent(this.name, this.parameters);

  final String name;
  final Map<String, Object> parameters;
}

class _RecordingSink implements GameAnalyticsSink {
  final events = <_RecordedSinkEvent>[];

  @override
  Future<void> log({
    required String eventName,
    required Map<String, Object> parameters,
  }) async {
    events.add(_RecordedSinkEvent(eventName, Map.of(parameters)));
  }
}

class _ThrowingSink implements GameAnalyticsSink {
  @override
  Future<void> log({
    required String eventName,
    required Map<String, Object> parameters,
  }) {
    throw StateError('Analytics destination is unavailable.');
  }
}

class _UnsafeAnalyticsEvent implements GameAnalyticsEvent {
  const _UnsafeAnalyticsEvent();

  @override
  String get eventName => 'unsafe_test_event';

  @override
  Map<String, Object> get parameters => <String, Object>{
    'email': 'player@example.com',
  };
}

const _correlation = AnalyticsCorrelation(
  anonymousMatchId: 'match_01HZZ5Y6T7',
  anonymousSessionId: 'session_01HZZ5Y6T7',
);

const _cpuMatch = MatchAnalyticsContext(
  playType: MatchPlayType.cpu,
  mode: GameMode.traditional,
  correlation: _correlation,
);

OnlineMatchSession _onlineSession() {
  OnlineParticipant participant(PlayerColor color, ParticipantKind kind) =>
      OnlineParticipant(
        id: '${color.name}-${kind.name}',
        displayName: 'Jugador ${color.name}',
        flag: '🎮',
        avatarId: 'avatar_default',
        level: 1,
        color: color,
        kind: kind,
        loadout: const CosmeticLoadout(),
      );

  return OnlineMatchSession(
    matchId: 'analytics-test',
    seed: 7,
    mode: GameMode.chaos,
    participants: [
      participant(PlayerColor.red, ParticipantKind.local),
      participant(PlayerColor.green, ParticipantKind.virtual),
      participant(PlayerColor.yellow, ParticipantKind.remoteHuman),
      participant(PlayerColor.blue, ParticipantKind.humanTakenOver),
    ],
  );
}

void main() {
  test('CPU match uses a dedicated event with non-identifying parameters', () {
    const event = MatchStartEvent(
      playType: MatchPlayType.cpu,
      mode: GameMode.chaos,
      cpuDifficulty: CpuDifficulty.expert,
    );

    expect(event.eventName, 'cpu_match_started');
    expect(event.parameters, {
      'play_type': 'cpu',
      'game_mode': 'chaos',
      'is_rematch': 0,
      'launch_source': 'home',
      'cpu_difficulty': 'expert',
    });
  });

  test('online match includes matchmaking counts without player identity', () {
    const event = MatchStartEvent(
      playType: MatchPlayType.online,
      mode: GameMode.traditional,
      launchSource: MatchLaunchSource.rematch,
      matchmakingWaitSeconds: 12,
      fallbackOpponentCount: 2,
      liveHumanOpponentCount: 1,
      takenOverOpponentCount: 0,
    );

    expect(event.eventName, 'online_match_started');
    expect(event.parameters, {
      'play_type': 'online',
      'game_mode': 'traditional',
      'is_rematch': 1,
      'launch_source': 'rematch',
      'matchmaking_wait_seconds': 12,
      'fallback_opponent_count': 2,
      'live_human_opponent_count': 1,
      'taken_over_opponent_count': 0,
    });
    expect(
      event.parameters.keys,
      isNot(
        contains(anyOf('name', 'email', 'phone', 'flag', 'avatar', 'user_id')),
      ),
    );
  });

  test(
    'typed logger sends first roll with anonymous correlation only',
    () async {
      final sink = _RecordingSink();
      final GameAnalytics analytics = SinkGameAnalytics(sink);

      await analytics.logEvent(
        const MatchFirstRollEvent(match: _cpuMatch, secondsFromMatchStart: 4),
      );

      expect(sink.events, hasLength(1));
      expect(sink.events.single.name, 'match_first_roll');
      expect(sink.events.single.parameters, <String, Object>{
        'play_type': 'cpu',
        'game_mode': 'traditional',
        'match_ref': 'match_01HZZ5Y6T7',
        'app_session_ref': 'session_01HZZ5Y6T7',
        'seconds_from_match_start': 4,
        'turn_number': 1,
        'dice_count': 2,
      });
    },
  );

  test('match lifecycle events use stable names and safe parameters', () async {
    final sink = _RecordingSink();
    final analytics = SinkGameAnalytics(sink);

    await analytics.logEvent(
      const MatchCompletedEvent(
        match: _cpuMatch,
        reason: MatchCompletionReason.reachedHome,
        placement: 1,
        durationSeconds: 420,
        turnsPlayed: 31,
      ),
    );
    await analytics.logEvent(
      const MatchAbandonedEvent(
        match: _cpuMatch,
        reason: MatchAbandonReason.backButton,
        secondsPlayed: 90,
        turnsPlayed: 6,
      ),
    );
    await analytics.logEvent(
      const MatchResumeEvent(
        match: _cpuMatch,
        stage: MatchResumeStage.attempted,
      ),
    );
    await analytics.logEvent(
      const MatchResumeEvent(
        match: _cpuMatch,
        stage: MatchResumeStage.succeeded,
        secondsAway: 15,
      ),
    );
    await analytics.logEvent(
      const RematchEvent(match: _cpuMatch, stage: RematchStage.offered),
    );
    await analytics.logEvent(
      const RematchEvent(match: _cpuMatch, stage: RematchStage.started),
    );

    expect(sink.events.map((event) => event.name), <String>[
      'match_completed',
      'match_abandoned',
      'match_resume_attempted',
      'match_resumed',
      'rematch_offered',
      'rematch_started',
    ]);
    for (final event in sink.events) {
      expect(event.parameters['match_ref'], 'match_01HZZ5Y6T7');
      expect(event.parameters['app_session_ref'], 'session_01HZZ5Y6T7');
      expect(
        event.parameters.keys,
        isNot(
          contains(
            anyOf('name', 'email', 'phone', 'flag', 'avatar', 'user_id'),
          ),
        ),
      );
    }
  });

  test('tutorial, rewarded ad, economy, and shop events are typed', () async {
    final sink = _RecordingSink();
    final analytics = SinkGameAnalytics(sink);

    await analytics.logEvent(
      const TutorialEvent(
        stage: TutorialStage.stepCompleted,
        step: TutorialStep.releaseToken,
        elapsedSeconds: 12,
        correlation: _correlation,
      ),
    );
    await analytics.logEvent(
      const RewardedAdEvent(
        stage: RewardedAdStage.completed,
        placement: RewardedAdPlacement.postMatchReward,
        rewardCoins: 70,
        match: _cpuMatch,
      ),
    );
    await analytics.logEvent(
      const CurrencyEvent(
        flow: CurrencyFlow.earned,
        source: CurrencySource.matchCompletion,
        amount: 70,
        balanceAfter: 320,
        anonymousTransactionId: 'transaction_001',
        match: _cpuMatch,
      ),
    );
    await analytics.logEvent(
      const ShopEvent(
        stage: ShopStage.previewed,
        productId: 'theme_cosmic_realms_red',
        productType: ShopProductType.theme,
        correlation: _correlation,
      ),
    );
    await analytics.logEvent(
      const ShopEvent(
        stage: ShopStage.purchased,
        productId: 'theme_cosmic_realms_red',
        productType: ShopProductType.theme,
        priceCoins: 1800,
        correlation: _correlation,
      ),
    );
    await analytics.logEvent(
      const ShopEvent(
        stage: ShopStage.equipped,
        productId: 'theme_cosmic_realms_red',
        productType: ShopProductType.theme,
        correlation: _correlation,
      ),
    );

    expect(sink.events.map((event) => event.name), <String>[
      'tutorial_step_completed',
      'rewarded_ad_completed',
      'currency_earned',
      'shop_previewed',
      'shop_purchased',
      'shop_equipped',
    ]);
    expect(sink.events[0].parameters['tutorial_step'], 'releaseToken');
    expect(sink.events[1].parameters['ad_placement'], 'postMatchReward');
    expect(sink.events[2].parameters['transaction_ref'], 'transaction_001');
    expect(sink.events[4].parameters['price_coins'], 1800);
  });

  test(
    'privacy allowlist rejects custom PII before it reaches the sink',
    () async {
      final sink = _RecordingSink();
      final analytics = SinkGameAnalytics(sink);

      await analytics.logEvent(const _UnsafeAnalyticsEvent());

      expect(sink.events, isEmpty);
    },
  );

  test('identifiers that could contain PII are rejected', () async {
    final sink = _RecordingSink();
    final analytics = SinkGameAnalytics(sink);

    await analytics.logEvent(
      const TutorialEvent(
        stage: TutorialStage.started,
        correlation: AnalyticsCorrelation(
          anonymousSessionId: 'player@example.com',
        ),
      ),
    );

    expect(sink.events, isEmpty);
  });

  test(
    'alphanumeric player names and phone numbers are not opaque IDs',
    () async {
      final sink = _RecordingSink();
      final analytics = SinkGameAnalytics(sink);

      for (final unsafeValue in const <String>['JuanPolanco', '8095551212']) {
        await analytics.logEvent(
          TutorialEvent(
            stage: TutorialStage.started,
            correlation: AnalyticsCorrelation(anonymousSessionId: unsafeValue),
          ),
        );
      }

      expect(sink.events, isEmpty);
    },
  );

  test(
    'rejected PII never appears in ArgumentError or diagnostic logs',
    () async {
      const rejectedValues = <String>[
        'player@example.com',
        'JuanPolanco',
        '8095551212',
      ];
      final originalDebugPrint = debugPrint;
      final diagnosticMessages = <String>[];
      debugPrint = (message, {wrapWidth}) {
        if (message != null) diagnosticMessages.add(message);
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      final analytics = SinkGameAnalytics(_RecordingSink());
      for (final rejectedValue in rejectedValues) {
        Object? thrown;
        try {
          AnalyticsCorrelation(anonymousSessionId: rejectedValue).parameters;
        } catch (error) {
          thrown = error;
        }
        expect(thrown, isA<ArgumentError>());
        expect(thrown.toString(), isNot(contains(rejectedValue)));

        await analytics.logEvent(
          TutorialEvent(
            stage: TutorialStage.started,
            correlation: AnalyticsCorrelation(
              anonymousSessionId: rejectedValue,
            ),
          ),
        );
      }

      final diagnostics = diagnosticMessages.join('\n');
      for (final rejectedValue in rejectedValues) {
        expect(diagnostics, isNot(contains(rejectedValue)));
      }
    },
  );

  test('app-generated opaque reference prefixes remain accepted', () async {
    const acceptedCorrelations = <AnalyticsCorrelation>[
      AnalyticsCorrelation(
        anonymousMatchId: 'match_01HZZ5Y6T7',
        anonymousSessionId: 'session_01HZZ5Y6T7',
      ),
      AnalyticsCorrelation(
        anonymousMatchId: 'cpu_match_lz4m9_84cc',
        anonymousSessionId: 'shop_session_lz4m9_84cc',
      ),
      AnalyticsCorrelation(anonymousMatchId: 'online_match_lz4m9_84cc'),
      AnalyticsCorrelation(anonymousMatchId: 'restored_match_lz4m9_84cc'),
      AnalyticsCorrelation(anonymousMatchId: 'resume_match_01'),
      AnalyticsCorrelation(anonymousMatchId: 'quick-123456'),
    ];

    for (final correlation in acceptedCorrelations) {
      expect(correlation.parameters, isNotEmpty);
    }

    for (final transactionReference in const <String>[
      'transaction_001',
      'reward_transaction_lz4m9_84cc',
      'shop_transaction_lz4m9_84cc',
    ]) {
      final event = CurrencyEvent(
        flow: CurrencyFlow.earned,
        source: CurrencySource.adjustment,
        amount: 1,
        anonymousTransactionId: transactionReference,
      );
      expect(event.parameters['transaction_ref'], transactionReference);
    }
  });

  test('analytics destination failures never interrupt gameplay', () async {
    final analytics = SinkGameAnalytics(_ThrowingSink());

    await expectLater(
      analytics.logEvent(
        const MatchFirstRollEvent(match: _cpuMatch, secondsFromMatchStart: 2),
      ),
      completes,
    );
  });

  test('legacy analytics doubles retain the original API', () async {
    final legacy = _RecordingGameAnalytics();
    final GameAnalytics analytics = legacy;

    await analytics.logEvent(
      const MatchStartEvent(
        playType: MatchPlayType.cpu,
        mode: GameMode.traditional,
      ),
    );
    await analytics.logEvent(
      const MatchFirstRollEvent(match: _cpuMatch, secondsFromMatchStart: 1),
    );

    expect(legacy.events, hasLength(1));
    expect(legacy.events.single.eventName, 'cpu_match_started');
  });

  testWidgets('GameScreen logs a CPU start exactly once from initState', (
    tester,
  ) async {
    final analytics = _RecordingGameAnalytics();

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'CPU • Fácil',
          mode: GameMode.traditional,
          analytics: analytics,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(analytics.events, hasLength(1));
    expect(analytics.events.single.eventName, 'cpu_match_started');
    expect(analytics.events.single.cpuDifficulty, CpuDifficulty.easy);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('online start logs counts and a rematch logs a new event', (
    tester,
  ) async {
    final analytics = _RecordingGameAnalytics();
    final session = _onlineSession();

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          key: const ValueKey('first-match'),
          opponent: 'Rival • Normal',
          onlineSession: session,
          matchmakingWaitSeconds: 12,
          analytics: analytics,
        ),
      ),
    );
    await tester.pump();

    expect(analytics.events, hasLength(1));
    expect(analytics.events.first.eventName, 'online_match_started');
    expect(analytics.events.first.matchmakingWaitSeconds, 12);
    expect(analytics.events.first.fallbackOpponentCount, 1);
    expect(analytics.events.first.liveHumanOpponentCount, 1);
    expect(analytics.events.first.takenOverOpponentCount, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          key: const ValueKey('rematch'),
          opponent: 'Rival • Normal',
          onlineSession: session,
          analytics: analytics,
          isRematch: true,
        ),
      ),
    );
    await tester.pump();

    expect(analytics.events, hasLength(2));
    expect(analytics.events.last.launchSource, MatchLaunchSource.rematch);
    expect(analytics.events.last.isRematch, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('GameScreen logs the first roll exactly once', (tester) async {
    final analytics = _RecordingTypedAnalytics();
    final engine = GameEngine();
    engine.currentPlayer.tokens.first.progress = 0;
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'CPU • Fácil',
          gameEngine: engine,
          analytics: analytics,
          analyticsMatchRef: 'match_first_roll_01',
        ),
      ),
    );
    await tester.pump();

    engine.roll();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(analytics.events.whereType<MatchFirstRollEvent>(), hasLength(1));

    await tester.pump(const Duration(milliseconds: 500));
    expect(analytics.events.whereType<MatchFirstRollEvent>(), hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('GameScreen logs match completion exactly once', (tester) async {
    final analytics = _RecordingTypedAnalytics();
    final engine = _oneMoveFromVictory();
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'CPU • Fácil',
          gameEngine: engine,
          analytics: analytics,
          analyticsMatchRef: 'match_lifecycle_01',
        ),
      ),
    );
    await tester.pump();

    expect(engine.moveToken(engine.currentPlayer.tokens.last, die: 1), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(analytics.events.whereType<MatchCompletedEvent>(), hasLength(1));

    await tester.pump(const Duration(seconds: 2));
    expect(analytics.events.whereType<MatchCompletedEvent>(), hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('resumed GameScreen keeps its match ref without a second start', (
    tester,
  ) async {
    final analytics = _RecordingTypedAnalytics();
    final engine = GameEngine();
    engine.currentPlayer.tokens.first.progress = 0;
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'CPU • Normal',
          gameEngine: engine,
          analytics: analytics,
          analyticsMatchRef: 'resume_match_01',
          analyticsFirstRollLogged: true,
          isResumedMatch: true,
          resumeSecondsAway: 15,
        ),
      ),
    );
    await tester.pump();

    expect(analytics.events.whereType<MatchStartEvent>(), isEmpty);
    final resumed = analytics.events.whereType<MatchResumeEvent>().single;
    expect(resumed.stage, MatchResumeStage.succeeded);
    expect(resumed.secondsAway, 15);
    expect(resumed.parameters['match_ref'], 'resume_match_01');

    engine.roll();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      analytics.events.whereType<MatchFirstRollEvent>(),
      isEmpty,
      reason: 'A resumed match must not report its first roll twice.',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shop preview purchase equip and coin spend are measured', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'parchesepop.wallet.balance.v1': 750,
    });
    final wallet = await WalletController.create();
    final analytics = _RecordingTypedAnalytics();
    addTearDown(wallet.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 844));

    await tester.pumpWidget(
      MaterialApp(
        home: ShopScreen(
          wallet: wallet,
          analytics: analytics,
          showTestCoinControls: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('shop-filters')),
      const Offset(-260, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('shop-filters')),
        matching: find.text('Dados'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('shop-preview-button-dice_galaxy')),
    );
    await tester.pumpAndSettle();
    expect(
      analytics.events.whereType<ShopEvent>().single.stage,
      ShopStage.previewed,
    );
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('shop-action-dice_galaxy')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shop-confirm-purchase')));
    await tester.pumpAndSettle();

    expect(
      analytics.events.whereType<ShopEvent>().map((event) => event.stage),
      <ShopStage>[ShopStage.previewed, ShopStage.purchased, ShopStage.equipped],
    );
    final spent = analytics.events.whereType<CurrencyEvent>().single;
    expect(spent.flow, CurrencyFlow.spent);
    expect(spent.amount, 350);
    expect(spent.balanceAfter, 400);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
