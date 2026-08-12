import 'dart:async';

import 'game_engine.dart';

/// Strength of the physical response associated with a game event.
///
/// The controller deliberately describes intent instead of importing a
/// platform haptics API. The UI layer can map these levels to iOS/Android
/// feedback while tests remain deterministic.
enum GameHapticCue { light, calm, strong, success, celebration, rollStart }

abstract interface class GameFeedbackOutput {
  Future<void> playSound(GameEventType eventType);

  Future<void> playHaptic(GameHapticCue cue);
}

typedef SafeLandingResolver = bool Function(GameEvent event);

/// Consumes every game event once and in sequence.
///
/// A single user action may append several events (for example move, capture
/// and goal). Keeping the cursor here prevents the UI from accidentally
/// playing feedback for only the final event in that burst.
class GameFeedbackController {
  GameFeedbackController({
    required this.output,
    this.soundEnabled = true,
    this.hapticsEnabled = true,
    this.safeLandingResolver,
    int initialSequence = 0,
  }) : _lastSequence = initialSequence;

  final GameFeedbackOutput output;
  final SafeLandingResolver? safeLandingResolver;
  bool soundEnabled;
  bool hapticsEnabled;
  int _lastSequence;
  Future<void> _operationTail = Future<void>.value();

  int get lastSequence => _lastSequence;

  /// Gives immediate feedback for a direct player input, before the engine
  /// publishes the resulting roll event. This keeps the dice/"Shake it"
  /// interaction responsive while still allowing the event pipeline to play
  /// the result feedback afterwards.
  void playInputHaptic(GameHapticCue cue) {
    if (!hapticsEnabled) return;
    final operation = output.playHaptic(cue);
    unawaited(
      operation.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {},
      ),
    );
  }

  Future<void> process(Iterable<GameEvent> events) {
    final snapshot = List<GameEvent>.unmodifiable(events);
    final operation = _operationTail.then((_) => _process(snapshot));
    _operationTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _process(Iterable<GameEvent> events) async {
    final pending =
        events
            .where((event) => event.sequence > _lastSequence)
            .toList(growable: false)
          ..sort((a, b) => a.sequence.compareTo(b.sequence));
    for (final event in pending) {
      if (soundEnabled && _hasSound(event.type)) {
        await output.playSound(event.type);
      }
      if (hapticsEnabled) {
        final cue = _cueFor(event);
        if (cue != null) await output.playHaptic(cue);
      }
      _lastSequence = event.sequence;
    }
  }

  bool _hasSound(GameEventType type) => switch (type) {
    GameEventType.matchStarted ||
    GameEventType.turnStarted ||
    GameEventType.noMove => false,
    _ => true,
  };

  GameHapticCue? _cueFor(GameEvent event) {
    if (event.type == GameEventType.move &&
        (safeLandingResolver?.call(event) ?? false)) {
      return GameHapticCue.calm;
    }
    return switch (event.type) {
      GameEventType.roll ||
      GameEventType.move ||
      GameEventType.barrierOpened ||
      GameEventType.barrierFormed => GameHapticCue.light,
      GameEventType.departure || GameEventType.powerUp => GameHapticCue.calm,
      GameEventType.capture ||
      GameEventType.trap ||
      GameEventType.threeDoublesPenalty => GameHapticCue.strong,
      GameEventType.goal => GameHapticCue.success,
      GameEventType.victory => GameHapticCue.celebration,
      GameEventType.matchStarted ||
      GameEventType.turnStarted ||
      GameEventType.noMove => null,
    };
  }
}
