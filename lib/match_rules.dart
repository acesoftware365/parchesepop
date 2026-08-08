/// The board format is independent from the power-up mode.
///
/// A Classic match can therefore remain Traditional or Chaos without making
/// Quick Pop a third, unrelated power-up mode.
enum MatchFormat { classic, quickPop }

/// Immutable rules that define the structural differences between match
/// formats. Keep these values versioned because saved and online matches must
/// never silently change rules while they are in progress.
class MatchRules {
  const MatchRules._({
    required this.format,
    required this.rulesVersion,
    required this.tokenCount,
    required this.initialTokenProgress,
    required this.tokensRequiredToWin,
    required this.requiresFiveToExit,
    required this.initialStackFormsBarrier,
  });

  static const int currentRulesVersion = 1;

  static const MatchRules classic = MatchRules._(
    format: MatchFormat.classic,
    rulesVersion: currentRulesVersion,
    tokenCount: 4,
    initialTokenProgress: -1,
    tokensRequiredToWin: 4,
    requiresFiveToExit: true,
    initialStackFormsBarrier: true,
  );

  static const MatchRules quickPop = MatchRules._(
    format: MatchFormat.quickPop,
    rulesVersion: currentRulesVersion,
    tokenCount: 2,
    initialTokenProgress: 0,
    tokensRequiredToWin: 2,
    requiresFiveToExit: false,
    initialStackFormsBarrier: false,
  );

  factory MatchRules.forFormat(MatchFormat format) => switch (format) {
    MatchFormat.classic => classic,
    MatchFormat.quickPop => quickPop,
  };

  final MatchFormat format;
  final int rulesVersion;
  final int tokenCount;
  final int initialTokenProgress;
  final int tokensRequiredToWin;
  final bool requiresFiveToExit;
  final bool initialStackFormsBarrier;
}
