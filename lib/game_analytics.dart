import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options.dart';
import 'game_engine.dart';

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
  }) : assert(
         playType == MatchPlayType.cpu || cpuDifficulty == null,
         'Online matches cannot include a CPU difficulty.',
       ),
       assert(
         playType == MatchPlayType.online ||
             (matchmakingWaitSeconds == null &&
                 fallbackOpponentCount == null &&
                 liveHumanOpponentCount == null &&
                 takenOverOpponentCount == null),
         'CPU matches cannot include online matchmaking metrics.',
       );

  final MatchPlayType playType;
  final GameMode mode;
  final MatchLaunchSource launchSource;
  final CpuDifficulty? cpuDifficulty;
  final int? matchmakingWaitSeconds;
  final int? fallbackOpponentCount;
  final int? liveHumanOpponentCount;
  final int? takenOverOpponentCount;

  bool get isRematch => launchSource == MatchLaunchSource.rematch;

  String get eventName => switch (playType) {
    MatchPlayType.online => 'online_match_started',
    MatchPlayType.cpu => 'cpu_match_started',
  };

  Map<String, Object> get parameters {
    final result = <String, Object>{
      'play_type': playType.name,
      'game_mode': switch (mode) {
        GameMode.traditional => 'traditional',
        GameMode.chaos => 'chaos',
      },
      'is_rematch': isRematch ? 1 : 0,
      'launch_source': launchSource.name,
    };
    if (cpuDifficulty case final value?) {
      result['cpu_difficulty'] = value.name;
    }
    if (matchmakingWaitSeconds case final value?) {
      result['matchmaking_wait_seconds'] = value;
    }
    if (fallbackOpponentCount case final value?) {
      result['fallback_opponent_count'] = value;
    }
    if (liveHumanOpponentCount case final value?) {
      result['live_human_opponent_count'] = value;
    }
    if (takenOverOpponentCount case final value?) {
      result['taken_over_opponent_count'] = value;
    }
    return result;
  }
}

abstract interface class GameAnalytics {
  Future<void> logMatchStarted(MatchStartEvent event);
}

class NoopGameAnalytics implements GameAnalytics {
  const NoopGameAnalytics();

  @override
  Future<void> logMatchStarted(MatchStartEvent event) async {}
}

class FirebaseGameAnalytics implements GameAnalytics {
  const FirebaseGameAnalytics(this._analytics);

  final FirebaseAnalytics _analytics;

  @override
  Future<void> logMatchStarted(MatchStartEvent event) async {
    try {
      await _analytics.logEvent(
        name: event.eventName,
        parameters: event.parameters,
      );
    } catch (error, stackTrace) {
      debugPrint('Google Analytics could not record the match: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}

Future<GameAnalytics> initializeGameAnalytics() async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS &&
          defaultTargetPlatform != TargetPlatform.macOS)) {
    return const NoopGameAnalytics();
  }

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    return FirebaseGameAnalytics(FirebaseAnalytics.instance);
  } catch (error, stackTrace) {
    debugPrint('Google Analytics initialization was skipped: $error');
    debugPrintStack(stackTrace: stackTrace);
    return const NoopGameAnalytics();
  }
}
