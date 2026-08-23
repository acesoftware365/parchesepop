import 'dart:async';

/// Guardrails for the authenticated Realtime Database adapter.
///
/// The online protocol is intentionally isolated under `onlineV2/`.  These
/// guardrails keep bounded timeouts and recovery paths scoped to that subtree,
/// while leaving the normal Firebase SDK path untouched for local game data,
/// settings, and any future non-online records.
final class OnlineConnectionSafety {
  OnlineConnectionSafety._();

  /// Set `--dart-define=PARCHESE_POP_SAFE_ONLINE=false` only for a diagnostic
  /// rollback build. Production and QA builds keep the guard enabled.
  static const bool enabled = bool.fromEnvironment(
    'PARCHESE_POP_SAFE_ONLINE',
    defaultValue: true,
  );

  static const Duration authTokenTimeout = Duration(seconds: 3);
  static const Duration queueReadTimeout = Duration(seconds: 3);
  static const Duration nativeOperationTimeout = Duration(seconds: 3);
  static const Duration restOperationTimeout = Duration(seconds: 5);
  static const Duration nativeTransactionTimeout = Duration(seconds: 6);
  static const Duration restTransactionTimeout = Duration(seconds: 12);

  /// Returns true only for paths whose first non-empty segment is `onlineV2`.
  /// A substring check is deliberately avoided so a user-controlled path can
  /// never accidentally opt into the online recovery behavior.
  static bool protectsPath(String path) {
    final first = path
        .trim()
        .split('/')
        .firstWhere((segment) => segment.isNotEmpty, orElse: () => '');
    return first == 'onlineV2';
  }

  /// A bounded operation that preserves the original error when safe mode is
  /// disabled. The timeout is a circuit breaker, not a retry: callers decide
  /// whether an idempotent fallback is safe for the specific operation.
  static Future<T> bounded<T>(
    String operation,
    String path,
    Future<T> Function() action, {
    required Duration timeout,
  }) {
    if (!enabled) return action();
    return action().timeout(
      timeout,
      onTimeout: () => throw OnlineConnectionTimeout(
        operation: operation,
        path: path,
        timeout: timeout,
      ),
    );
  }
}

/// An operation exceeded the online circuit-breaker budget.
final class OnlineConnectionTimeout implements Exception {
  const OnlineConnectionTimeout({
    required this.operation,
    required this.path,
    required this.timeout,
  });

  final String operation;
  final String path;
  final Duration timeout;

  @override
  String toString() =>
      'Online $operation timed out after ${timeout.inSeconds}s at $path.';
}
