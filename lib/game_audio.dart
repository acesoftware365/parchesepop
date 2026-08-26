import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_engine.dart';

typedef GameAudioPreferenceReader = Future<bool> Function(String key);

/// Small player boundary that keeps lifecycle and audio-focus behavior
/// deterministic in tests while the production adapter uses audioplayers.
abstract interface class GameAudioPlayerPort {
  Future<void> setAudioContext(AudioContext context);

  Future<void> setReleaseMode(ReleaseMode releaseMode);

  Future<void> playAsset(String asset, {required double volume});

  Future<void> stop();

  Future<void> dispose();
}

class _AudioplayersGameAudioPlayer implements GameAudioPlayerPort {
  _AudioplayersGameAudioPlayer() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> setAudioContext(AudioContext context) =>
      _player.setAudioContext(context);

  @override
  Future<void> setReleaseMode(ReleaseMode releaseMode) =>
      _player.setReleaseMode(releaseMode);

  @override
  Future<void> playAsset(String asset, {required double volume}) =>
      _player.play(AssetSource(asset), volume: volume);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// Shared audio service for every supported build of Parchís Pop.
///
/// Music transitions are serialized so rapid Android lifecycle changes cannot
/// leave an old pause or resume command as the final player state. Short game
/// effects request a short ducking focus on Android. Some Android devices
/// silence a sonification player that requests no focus while the music player
/// owns game focus; transient ducking keeps the soundtrack playing and makes
/// each dice/move cue audible.
class GameAudioController {
  GameAudioController({
    GameAudioPlayerPort? musicPlayer,
    GameAudioPlayerPort? effectsPlayer,
    GameAudioPreferenceReader? preferenceReader,
  }) : _musicPlayer = musicPlayer ?? _AudioplayersGameAudioPlayer(),
       _effectsPlayer = effectsPlayer ?? _AudioplayersGameAudioPlayer(),
       _preferenceReader = preferenceReader ?? _readStoredPreference;

  static Future<bool> _readStoredPreference(String key) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(key) ?? true;
  }

  final GameAudioPlayerPort _musicPlayer;
  final GameAudioPlayerPort _effectsPlayer;
  final GameAudioPreferenceReader _preferenceReader;

  Future<void> _musicOperations = Future<void>.value();
  Future<void> _effectsOperations = Future<void>.value();
  bool _initialized = false;
  bool _disposed = false;
  bool _musicEnabled = true;
  bool _musicStarted = false;
  bool _backgrounded = false;
  int _lifecycleRevision = 0;
  int _musicPreferenceRevision = 0;

  Future<void> initialize() => _queueMusic(() async {
    if (_initialized || _disposed) return;
    await _musicPlayer.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.game,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ),
    );
    await _effectsPlayer.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.game,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
      ),
    );
    await _musicPlayer.setReleaseMode(ReleaseMode.loop);
    // Keep the short-effect player allocated between turns. Recreating the
    // native player after every dice/move sound can make the first cue late or
    // silent on slower Android devices.
    await _effectsPlayer.setReleaseMode(ReleaseMode.stop);
    final preferenceRevision = _musicPreferenceRevision;
    final storedMusicEnabled = await _preferenceReader('settings_music');
    if (preferenceRevision == _musicPreferenceRevision) {
      _musicEnabled = storedMusicEnabled;
    }
    _initialized = true;
    await _applyDesiredMusicState();
  });

  Future<void> refreshMusic() {
    final preferenceRevision = _musicPreferenceRevision;
    return _queueMusic(() async {
      final storedMusicEnabled = await _preferenceReader('settings_music');
      if (preferenceRevision == _musicPreferenceRevision) {
        _musicEnabled = storedMusicEnabled;
      }
      await _applyDesiredMusicState();
    });
  }

  Future<void> setMusicEnabled(bool enabled) {
    // Trust the switch value immediately. Reading SharedPreferences here used
    // to race the asynchronous write and could leave an enabled switch silent.
    _musicPreferenceRevision++;
    _musicEnabled = enabled;
    return _queueMusic(_applyDesiredMusicState);
  }

  Future<void> handleAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      return resumeAfterForeground();
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      return pauseForBackground();
    }
    return Future<void>.value();
  }

  /// Stops every cue when the application is no longer visible.
  Future<void> pauseForBackground() {
    if (_disposed || _backgrounded) {
      return Future.wait<void>([_musicOperations, _effectsOperations]);
    }
    _backgrounded = true;
    _lifecycleRevision++;
    final music = _queueMusic(_applyDesiredMusicState);
    final effects = _queueEffects(_effectsPlayer.stop);
    return Future.wait<void>([music, effects]);
  }

  /// Restores music only when the app is visible and the setting is enabled.
  Future<void> resumeAfterForeground() {
    if (_disposed) return _musicOperations;
    _backgrounded = false;
    _lifecycleRevision++;
    if (!_initialized) return initialize();
    return _queueMusic(_applyDesiredMusicState);
  }

  Future<void> _applyDesiredMusicState() async {
    if (!_initialized || _disposed) return;
    if (!_musicEnabled) {
      if (_musicStarted) {
        try {
          await _musicPlayer.stop();
        } finally {
          _musicStarted = false;
        }
      }
      return;
    }
    if (_backgrounded) {
      // Stopping instead of merely pausing makes audioplayers abandon Android
      // audio focus. A paused game must never keep another app's audio muted,
      // and reloading the short looping track is more reliable after Android
      // has reclaimed the native player.
      if (_musicStarted) {
        try {
          await _musicPlayer.stop();
        } finally {
          _musicStarted = false;
        }
      }
      return;
    }
    if (_musicStarted) return;
    await _musicPlayer.playAsset('audio/music_background.wav', volume: .12);
    _musicStarted = true;
  }

  Future<void> playEvent(GameEventType type) async {
    if (_backgrounded || _disposed) return;
    final lifecycleRevision = _lifecycleRevision;
    if (!await _preferenceReader('settings_sound')) return;
    if (_backgrounded || _disposed || lifecycleRevision != _lifecycleRevision) {
      return;
    }
    final asset = switch (type) {
      GameEventType.roll => 'audio/dice.wav',
      GameEventType.move ||
      GameEventType.departure ||
      GameEventType.goal => 'audio/move.wav',
      GameEventType.barrierFormed ||
      GameEventType.barrierOpened ||
      GameEventType.capture ||
      GameEventType.threeDoublesPenalty ||
      GameEventType.noMove ||
      GameEventType.trap => 'audio/block.wav',
      GameEventType.powerUp || GameEventType.victory => 'audio/dice.wav',
      _ => null,
    };
    if (asset == null) return;
    await _queueEffects(() async {
      if (_backgrounded ||
          _disposed ||
          lifecycleRevision != _lifecycleRevision) {
        return;
      }
      await _effectsPlayer.playAsset(asset, volume: .72);
      if (_backgrounded ||
          _disposed ||
          lifecycleRevision != _lifecycleRevision) {
        await _effectsPlayer.stop();
      }
    });
  }

  Future<void> _queueMusic(Future<void> Function() operation) {
    _musicOperations = _musicOperations.then((_) => operation()).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _musicStarted = false;
      if (kDebugMode) {
        debugPrint('Parchís Pop music error: $error');
      }
    });
    return _musicOperations;
  }

  Future<void> _queueEffects(Future<void> Function() operation) {
    _effectsOperations = _effectsOperations.then((_) => operation()).catchError(
      (Object error, StackTrace stackTrace) {
        if (kDebugMode) {
          debugPrint('Parchís Pop sound effect error: $error');
        }
      },
    );
    return _effectsOperations;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _backgrounded = true;
    _lifecycleRevision++;
    await Future.wait<void>([_musicOperations, _effectsOperations]);
    await _musicPlayer.dispose();
    await _effectsPlayer.dispose();
  }
}

final gameAudio = GameAudioController();
