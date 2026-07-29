import 'package:flutter/foundation.dart';

import 'game_engine.dart';

/// Match telemetry remains isolated behind this interface so it can be sent to
/// Google Analytics once its iOS plugin is compatible with the target device.
enum MatchPlayType { online, cpu }

enum MatchLaunchSource { home, rematch }

enum CpuDifficulty { easy, normal, expert }

@immutable
class MatchStartEvent {
  const MatchStartEvent({
    required this.playType,
    required this.mode,
    this.launchSource = MatchLaunchSource.home,
    this.cpuDifficulty,
    this.matchmakingWaitSeconds,
    this.fallbackOpponentCount,
    this.liveHumanOpponentCount,
    this.takenOverOpponentCount,
  });

  final MatchPlayType playType;
  final GameMode mode;
  final MatchLaunchSource launchSource;
  final CpuDifficulty? cpuDifficulty;
  final int? matchmakingWaitSeconds;
  final int? fallbackOpponentCount;
  final int? liveHumanOpponentCount;
  final int? takenOverOpponentCount;

  bool get isRematch => launchSource == MatchLaunchSource.rematch;

  String get eventName => playType == MatchPlayType.online
      ? 'online_match_started'
      : 'cpu_match_started';

  Map<String, Object> get parameters {
    final values = <String, Object>{
      'play_type': playType.name,
      'game_mode': mode == GameMode.chaos ? 'chaos' : 'traditional',
      'is_rematch': isRematch ? 1 : 0,
      'launch_source': launchSource.name,
    };
    if (cpuDifficulty case final value?) values['cpu_difficulty'] = value.name;
    if (matchmakingWaitSeconds case final value?) {
      values['matchmaking_wait_seconds'] = value;
    }
    if (fallbackOpponentCount case final value?) {
      values['fallback_opponent_count'] = value;
    }
    if (liveHumanOpponentCount case final value?) {
      values['live_human_opponent_count'] = value;
    }
    if (takenOverOpponentCount case final value?) {
      values['taken_over_opponent_count'] = value;
    }
    return values;
  }
}

abstract interface class GameAnalytics {
  Future<void> logMatchStarted(MatchStartEvent event);
}

class NoopGameAnalytics implements GameAnalytics {
  const NoopGameAnalytics();

  @override
  Future<void> logMatchStarted(MatchStartEvent event) async {
    debugPrint('Telemetry ready: ${event.eventName}');
  }
}

/// Firebase Analytics is disabled for this build because its iOS registration
/// crashes on the current JP device. The game must always launch first.
Future<GameAnalytics> initializeGameAnalytics() async =>
    const NoopGameAnalytics();
