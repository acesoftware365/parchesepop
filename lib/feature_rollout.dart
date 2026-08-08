import 'package:flutter/foundation.dart';

/// Product switches used to release large systems independently.
///
/// Local Quick Pop and retention systems are safe defaults. Real-time online,
/// ranked play and live events remain off until their server-side validation
/// and telemetry gates pass.
@immutable
class AppFeatureRollout {
  const AppFeatureRollout({
    this.contextualTutorial = true,
    this.retentionRewards = true,
    this.quickPopLocal = true,
    this.quickPopOnline = false,
    this.rankedPlay = false,
    this.weeklyEvents = false,
  });

  final bool contextualTutorial;
  final bool retentionRewards;
  final bool quickPopLocal;
  final bool quickPopOnline;
  final bool rankedPlay;
  final bool weeklyEvents;

  static const safeDefaults = AppFeatureRollout();

  AppFeatureRollout copyWith({
    bool? contextualTutorial,
    bool? retentionRewards,
    bool? quickPopLocal,
    bool? quickPopOnline,
    bool? rankedPlay,
    bool? weeklyEvents,
  }) => AppFeatureRollout(
    contextualTutorial: contextualTutorial ?? this.contextualTutorial,
    retentionRewards: retentionRewards ?? this.retentionRewards,
    quickPopLocal: quickPopLocal ?? this.quickPopLocal,
    quickPopOnline: quickPopOnline ?? this.quickPopOnline,
    rankedPlay: rankedPlay ?? this.rankedPlay,
    weeklyEvents: weeklyEvents ?? this.weeklyEvents,
  );

  /// Advanced features depend on a server that owns dice, moves and rewards.
  /// This guard prevents a remote setting from exposing competitive systems
  /// when the installed build has no authoritative transport configured.
  AppFeatureRollout constrainedByServer({required bool serverConfigured}) {
    if (serverConfigured) return this;
    return copyWith(
      quickPopOnline: false,
      rankedPlay: false,
      weeklyEvents: false,
    );
  }
}
