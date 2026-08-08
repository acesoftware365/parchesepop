import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/game_feedback.dart';

class _RecordingOutput implements GameFeedbackOutput {
  final sounds = <GameEventType>[];
  final haptics = <GameHapticCue>[];

  @override
  Future<void> playHaptic(GameHapticCue cue) async => haptics.add(cue);

  @override
  Future<void> playSound(GameEventType eventType) async =>
      sounds.add(eventType);
}

class _BlockingOutput extends _RecordingOutput {
  final soundStarted = Completer<void>();
  final releaseSound = Completer<void>();

  @override
  Future<void> playSound(GameEventType eventType) async {
    sounds.add(eventType);
    if (!soundStarted.isCompleted) soundStarted.complete();
    await releaseSound.future;
  }
}

GameEvent _event(int sequence, GameEventType type, {int? toProgress}) =>
    GameEvent(
      sequence: sequence,
      turn: 1,
      type: type,
      playerName: 'Tú',
      playerColor: PlayerColor.red,
      description: type.name,
      toProgress: toProgress,
    );

void main() {
  test('processes a burst completely, in order, and exactly once', () async {
    final output = _RecordingOutput();
    final controller = GameFeedbackController(output: output);
    final events = [
      _event(1, GameEventType.move),
      _event(2, GameEventType.capture),
      _event(3, GameEventType.goal),
      _event(4, GameEventType.victory),
    ];

    await controller.process(events.reversed);
    await controller.process(events);

    expect(output.sounds, [
      GameEventType.move,
      GameEventType.capture,
      GameEventType.goal,
      GameEventType.victory,
    ]);
    expect(output.haptics, [
      GameHapticCue.light,
      GameHapticCue.strong,
      GameHapticCue.success,
      GameHapticCue.celebration,
    ]);
    expect(controller.lastSequence, 4);
  });

  test('safe landing replaces movement tap with a calm cue', () async {
    final output = _RecordingOutput();
    final controller = GameFeedbackController(
      output: output,
      safeLandingResolver: (event) => event.toProgress == 7,
    );

    await controller.process([_event(1, GameEventType.move, toProgress: 7)]);

    expect(output.haptics, [GameHapticCue.calm]);
  });

  test('sound and haptics can be disabled independently', () async {
    final output = _RecordingOutput();
    final controller = GameFeedbackController(
      output: output,
      soundEnabled: false,
      hapticsEnabled: false,
    );

    await controller.process([
      _event(1, GameEventType.roll),
      _event(2, GameEventType.capture),
    ]);

    expect(output.sounds, isEmpty);
    expect(output.haptics, isEmpty);
    expect(controller.lastSequence, 2);
  });

  test('non-gameplay lifecycle events do not produce feedback', () async {
    final output = _RecordingOutput();
    final controller = GameFeedbackController(output: output);

    await controller.process([
      _event(1, GameEventType.matchStarted),
      _event(2, GameEventType.turnStarted),
      _event(3, GameEventType.noMove),
    ]);

    expect(output.sounds, isEmpty);
    expect(output.haptics, isEmpty);
  });

  test('serializes concurrent calls and consumes an event only once', () async {
    final output = _BlockingOutput();
    final controller = GameFeedbackController(output: output);
    final event = _event(1, GameEventType.move);

    final first = controller.process([event]);
    await output.soundStarted.future;
    final second = controller.process([event]);
    output.releaseSound.complete();

    await Future.wait([first, second]);
    expect(output.sounds, [GameEventType.move]);
    expect(output.haptics, [GameHapticCue.light]);
    expect(controller.lastSequence, 1);
  });
}
