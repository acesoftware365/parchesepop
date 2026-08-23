import 'package:flutter/foundation.dart';

/// Diagnostic controls are intentionally absent from normal release builds.
///
/// A debug build shows them by default.  A release QA build can opt in with
/// `--dart-define=PARCHESE_POP_SHOW_DEBUG=true`; production APKs omit the
/// define, so the copy button and diagnostic panels are not shipped in the
/// player-facing UI.
const bool onlineDiagnosticsUiEnabled =
    !kReleaseMode ||
    bool.fromEnvironment('PARCHESE_POP_SHOW_DEBUG', defaultValue: false);

/// The state of one visible step in the Quick Pop matchmaking trace.
enum QuickPopDiagnosticState { pending, waiting, success, info, error }

extension QuickPopDiagnosticStateLabels on QuickPopDiagnosticState {
  String get label => switch (this) {
    QuickPopDiagnosticState.pending => 'PENDING',
    QuickPopDiagnosticState.waiting => 'WAITING',
    QuickPopDiagnosticState.success => 'OK',
    QuickPopDiagnosticState.info => 'INFO',
    QuickPopDiagnosticState.error => 'ERROR',
  };

  String get symbol => switch (this) {
    QuickPopDiagnosticState.pending => '…',
    QuickPopDiagnosticState.waiting => '…',
    QuickPopDiagnosticState.success => '✓',
    QuickPopDiagnosticState.info => '•',
    QuickPopDiagnosticState.error => '✕',
  };
}

/// One append-only event in the Quick Pop search trace.
@immutable
class QuickPopDiagnosticEntry {
  const QuickPopDiagnosticEntry({
    required this.number,
    required this.elapsedMilliseconds,
    required this.step,
    required this.state,
    required this.detail,
    this.code,
    this.path,
  });

  final int number;
  final int elapsedMilliseconds;
  final String step;
  final QuickPopDiagnosticState state;
  final String detail;
  final String? code;
  final String? path;

  String get elapsedLabel {
    final seconds = elapsedMilliseconds ~/ 1000;
    final milliseconds = elapsedMilliseconds % 1000;
    return '${seconds.toString().padLeft(2, '0')}.'
        '${(milliseconds ~/ 10).toString().padLeft(2, '0')}s';
  }

  String toConsoleLine() {
    final buffer = StringBuffer()
      ..write('[${number.toString().padLeft(2, '0')}] ')
      ..write(elapsedLabel.padRight(8))
      ..write(state.label.padRight(8))
      ..write(step);
    if (detail.trim().isNotEmpty) buffer.write(' | $detail');
    if (code != null && code!.trim().isNotEmpty) {
      buffer.write(' | code=${code!.trim()}');
    }
    if (path != null && path!.trim().isNotEmpty) {
      buffer.write(' | path=${path!.trim()}');
    }
    return buffer.toString();
  }
}

/// Collects a copyable, chronological Quick Pop diagnostic trace.
///
/// This class deliberately contains no Firebase calls. The online screen adds
/// events at each protocol boundary, which makes the trace useful with the
/// real Firebase adapter and with deterministic transport tests alike.
final class QuickPopDiagnosticLog {
  QuickPopDiagnosticLog({DateTime? startedAt})
    : startedAt = startedAt ?? DateTime.now();

  final DateTime startedAt;
  final List<QuickPopDiagnosticEntry> _entries = <QuickPopDiagnosticEntry>[];

  List<QuickPopDiagnosticEntry> get entries =>
      List<QuickPopDiagnosticEntry>.unmodifiable(_entries);

  QuickPopDiagnosticEntry add({
    required int elapsedMilliseconds,
    required String step,
    required QuickPopDiagnosticState state,
    String detail = '',
    String? code,
    String? path,
  }) {
    final entry = QuickPopDiagnosticEntry(
      number: _entries.length + 1,
      elapsedMilliseconds: elapsedMilliseconds,
      step: step,
      state: state,
      detail: detail,
      code: code,
      path: path,
    );
    _entries.add(entry);
    return entry;
  }

  String toConsole({
    required String device,
    required String appVersion,
    String protocol = 'Quick Pop',
    String searchWindow = '30s',
    String firebaseProject = 'parchese-pop',
    String title = 'PARCHIS POP ONLINE DEBUG',
  }) {
    final buffer = StringBuffer()
      ..writeln(title)
      ..writeln('Started: ${startedAt.toUtc().toIso8601String()}')
      ..writeln('Version: $appVersion')
      ..writeln('Device: $device')
      ..writeln('Protocol: $protocol')
      ..writeln('Firebase project: $firebaseProject')
      ..writeln('Search deadline: $searchWindow')
      ..writeln();
    if (_entries.isEmpty) {
      buffer.writeln('[00] No diagnostic steps recorded.');
    } else {
      for (final entry in _entries) {
        buffer.writeln(entry.toConsoleLine());
      }
    }
    return buffer.toString().trimRight();
  }
}
