import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_engine.dart';

/// Shared audio service for every supported build of Parchís Pop.
/// Preferences are read before each cue so the Settings switches take effect
/// immediately without restarting a match.
class GameAudioController {
  final AudioPlayer _musicPlayer = AudioPlayer();
  final AudioPlayer _effectsPlayer = AudioPlayer();
  bool _musicStarted = false;
  bool _backgrounded = false;

  Future<void> initialize() async {
    await _musicPlayer.setReleaseMode(ReleaseMode.loop);
    await refreshMusic();
  }

  Future<bool> _enabled(String key) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(key) ?? true;
  }

  Future<void> refreshMusic() async {
    if (!await _enabled('settings_music')) {
      await _musicPlayer.stop();
      _musicStarted = false;
      return;
    }
    if (_musicStarted) return;
    await _musicPlayer.play(
      AssetSource('audio/music_background.wav'),
      volume: .12,
    );
    _musicStarted = true;
  }

  Future<void> setMusicEnabled(bool enabled) async {
    if (!enabled) {
      await _musicPlayer.stop();
      _musicStarted = false;
      return;
    }
    await refreshMusic();
  }

  /// Do not mix game music with the user's music while the app is hidden.
  Future<void> pauseForBackground() async {
    _backgrounded = true;
    if (_musicStarted) await _musicPlayer.pause();
    await _effectsPlayer.stop();
  }

  Future<void> resumeAfterForeground() async {
    _backgrounded = false;
    if (!await _enabled('settings_music')) return;
    if (_musicStarted) {
      await _musicPlayer.resume();
    } else {
      await refreshMusic();
    }
  }

  Future<void> playEvent(GameEventType type) async {
    if (_backgrounded) return;
    if (!await _enabled('settings_sound')) return;
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
    await _effectsPlayer.play(AssetSource(asset), volume: .72);
  }

  Future<void> dispose() async {
    await _musicPlayer.dispose();
    await _effectsPlayer.dispose();
  }
}

final gameAudio = GameAudioController();
