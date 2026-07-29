import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_analytics.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';
import 'package:parchesepop/online_match.dart';

class _RecordingGameAnalytics implements GameAnalytics {
  final events = <MatchStartEvent>[];

  @override
  Future<void> logMatchStarted(MatchStartEvent event) async {
    events.add(event);
  }
}

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
      isNot(containsAll(<String>['name', 'email', 'flag', 'avatar'])),
    );
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
}
