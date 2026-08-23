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

  // Keep the Classic contract stable while versioning the changed Quick Pop
  // opening position independently. An old Quick Pop room must never mix
  // with the new base-start rules.
  static const int currentRulesVersion = 1;
  static const int quickPopRulesVersion = 2;

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
    rulesVersion: quickPopRulesVersion,
    tokenCount: 2,
    // Quick Pop keeps both pieces in base until the first roll. Any die may
    // release one; there is no required 5, and no visible starting stack.
    initialTokenProgress: -1,
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
