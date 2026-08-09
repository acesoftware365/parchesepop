import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_audio.dart';
import 'package:parchesepop/game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Android effects mix with music instead of stealing its focus',
    () async {
      final music = _FakeAudioPlayer();
      final effects = _FakeAudioPlayer();
      final controller = _controller(music: music, effects: effects);
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(music.context?.android.contentType, AndroidContentType.music);
      expect(music.context?.android.usageType, AndroidUsageType.game);
      expect(music.context?.android.audioFocus, AndroidAudioFocus.gain);
      expect(
        effects.context?.android.contentType,
        AndroidContentType.sonification,
      );
      expect(effects.context?.android.usageType, AndroidUsageType.game);
      expect(effects.context?.android.audioFocus, AndroidAudioFocus.none);

      music.calls.clear();
      effects.calls.clear();
      await controller.playEvent(GameEventType.roll);

      expect(effects.calls, ['play:audio/dice.wav:0.72']);
      expect(music.calls, isEmpty);
    },
  );

  test('background and foreground transitions are idempotent', () async {
    final music = _FakeAudioPlayer();
    final effects = _FakeAudioPlayer();
    final controller = _controller(music: music, effects: effects);
    addTearDown(controller.dispose);
    await controller.initialize();
    music.calls.clear();
    effects.calls.clear();

    await controller.pauseForBackground();
    await controller.pauseForBackground();
    expect(music.calls, ['stop']);
    expect(effects.calls, ['stop']);

    await controller.resumeAfterForeground();
    await controller.resumeAfterForeground();
    expect(music.calls, ['stop', 'play:audio/music_background.wav:0.12']);
    expect(effects.calls, ['stop']);
  });

  test(
    'the latest lifecycle state wins while stopping is still pending',
    () async {
      final music = _FakeAudioPlayer();
      final effects = _FakeAudioPlayer();
      final controller = _controller(music: music, effects: effects);
      addTearDown(controller.dispose);
      await controller.initialize();
      music.calls.clear();
      effects.calls.clear();

      final stopGate = Completer<void>();
      music.stopGate = stopGate;
      final background = controller.pauseForBackground();
      await _waitFor(() => music.calls.contains('stop'));
      final foreground = controller.resumeAfterForeground();
      stopGate.complete();

      await Future.wait<void>([background, foreground]);
      expect(music.calls, ['stop', 'play:audio/music_background.wav:0.12']);
    },
  );

  test(
    'enabling music trusts the switch instead of a stale preference',
    () async {
      final music = _FakeAudioPlayer();
      final effects = _FakeAudioPlayer();
      final controller = GameAudioController(
        musicPlayer: music,
        effectsPlayer: effects,
        preferenceReader: (key) async => key == 'settings_sound',
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      expect(music.calls.where((call) => call.startsWith('play:')), isEmpty);

      await controller.setMusicEnabled(true);
      expect(music.calls.where((call) => call.startsWith('play:')), [
        'play:audio/music_background.wav:0.12',
      ]);
    },
  );

  test('disabled music stays silent after background and foreground', () async {
    final music = _FakeAudioPlayer();
    final effects = _FakeAudioPlayer();
    final controller = _controller(music: music, effects: effects);
    addTearDown(controller.dispose);
    await controller.initialize();

    await controller.setMusicEnabled(false);
    music.calls.clear();
    await controller.handleAppLifecycleState(AppLifecycleState.paused);
    await controller.handleAppLifecycleState(AppLifecycleState.resumed);

    expect(music.calls.where((call) => call == 'resume'), isEmpty);
    expect(music.calls.where((call) => call.startsWith('play:')), isEmpty);
  });

  test('an effect waiting on preferences cannot start in background', () async {
    final music = _FakeAudioPlayer();
    final effects = _FakeAudioPlayer();
    final soundPreference = Completer<bool>();
    final controller = GameAudioController(
      musicPlayer: music,
      effectsPlayer: effects,
      preferenceReader: (key) => key == 'settings_music'
          ? Future<bool>.value(true)
          : soundPreference.future,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    effects.calls.clear();

    final cue = controller.playEvent(GameEventType.capture);
    await Future<void>.delayed(Duration.zero);
    final background = controller.pauseForBackground();
    soundPreference.complete(true);
    await Future.wait<void>([cue, background]);

    expect(effects.calls, ['stop']);
  });

  test('a newer switch value wins over a pending preference read', () async {
    final music = _FakeAudioPlayer();
    final effects = _FakeAudioPlayer();
    final storedMusic = Completer<bool>();
    final controller = GameAudioController(
      musicPlayer: music,
      effectsPlayer: effects,
      preferenceReader: (key) => key == 'settings_music'
          ? storedMusic.future
          : Future<bool>.value(true),
    );
    addTearDown(controller.dispose);

    final initialization = controller.initialize();
    await _waitFor(() => music.calls.contains('release:loop'));
    final disable = controller.setMusicEnabled(false);
    storedMusic.complete(true);
    await Future.wait<void>([initialization, disable]);

    expect(music.calls.where((call) => call.startsWith('play:')), isEmpty);
  });

  test('foreground retries a temporary initialization failure', () async {
    final music = _FakeAudioPlayer()..contextFailures = 1;
    final effects = _FakeAudioPlayer();
    final controller = _controller(music: music, effects: effects);
    addTearDown(controller.dispose);

    await controller.initialize();
    expect(music.calls.where((call) => call.startsWith('play:')), isEmpty);

    await controller.handleAppLifecycleState(AppLifecycleState.resumed);
    expect(music.calls.where((call) => call.startsWith('play:')), [
      'play:audio/music_background.wav:0.12',
    ]);
  });

  for (final lifecycleState in const <AppLifecycleState>[
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ]) {
    test('$lifecycleState independently stops all audio', () async {
      final music = _FakeAudioPlayer();
      final effects = _FakeAudioPlayer();
      final controller = _controller(music: music, effects: effects);
      addTearDown(controller.dispose);
      await controller.initialize();
      music.calls.clear();
      effects.calls.clear();

      await controller.handleAppLifecycleState(lifecycleState);

      expect(music.calls, ['stop']);
      expect(effects.calls, ['stop']);
    });
  }

  test(
    'the global lifecycle stops music even when no match is open',
    () async {
      final music = _FakeAudioPlayer();
      final effects = _FakeAudioPlayer();
      final controller = _controller(music: music, effects: effects);
      await controller.initialize();
      addTearDown(controller.dispose);
      music.calls.clear();
      effects.calls.clear();

      await controller.handleAppLifecycleState(AppLifecycleState.inactive);
      await controller.handleAppLifecycleState(AppLifecycleState.hidden);
      await controller.handleAppLifecycleState(AppLifecycleState.paused);

      expect(music.calls.where((call) => call == 'stop').length, 1);
      expect(effects.calls.where((call) => call == 'stop').length, 1);

      await controller.handleAppLifecycleState(AppLifecycleState.resumed);
      expect(
        music.calls
            .where((call) => call == 'play:audio/music_background.wav:0.12')
            .length,
        1,
      );
    },
  );
}

GameAudioController _controller({
  required _FakeAudioPlayer music,
  required _FakeAudioPlayer effects,
}) => GameAudioController(
  musicPlayer: music,
  effectsPlayer: effects,
  preferenceReader: (_) async => true,
);

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition was not reached.');
}

class _FakeAudioPlayer implements GameAudioPlayerPort {
  final List<String> calls = <String>[];
  AudioContext? context;
  Completer<void>? stopGate;
  int contextFailures = 0;

  @override
  Future<void> setAudioContext(AudioContext value) async {
    if (contextFailures > 0) {
      contextFailures--;
      throw StateError('temporary context failure');
    }
    context = value;
    calls.add('context');
  }

  @override
  Future<void> setReleaseMode(ReleaseMode releaseMode) async {
    calls.add('release:${releaseMode.name}');
  }

  @override
  Future<void> playAsset(String asset, {required double volume}) async {
    calls.add('play:$asset:$volume');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    await stopGate?.future;
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
  }
}
