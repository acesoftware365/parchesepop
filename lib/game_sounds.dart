import 'dart:async';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_engine.dart';

/// Sound cues backed by the small native audio bridge.
///
/// Keeping the player native avoids the iOS 26 crash caused by the third-party
/// audio plugin during application registration.
class GameSoundController {
  static const _effectsPreference = 'settings_sound';
  static const _musicPreference = 'settings_music';
  static const _channel = MethodChannel('com.liisgo.parchesepop/sounds');

  bool _effectsEnabled = true;
  bool _musicEnabled = true;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final store = await SharedPreferences.getInstance();
      _effectsEnabled = store.getBool(_effectsPreference) ?? true;
      _musicEnabled = store.getBool(_musicPreference) ?? true;
      await _channel.invokeMethod<void>('setMusicEnabled', {
        'enabled': _musicEnabled,
      });
    } catch (_) {
      // Sound is optional. A device without the bridge remains fully playable.
    }
  }

  Future<void> setEffectsEnabled(bool enabled) async {
    _effectsEnabled = enabled;
    final store = await SharedPreferences.getInstance();
    await store.setBool(_effectsPreference, enabled);
  }

  Future<void> setMusicEnabled(bool enabled) async {
    _musicEnabled = enabled;
    final store = await SharedPreferences.getInstance();
    await store.setBool(_musicPreference, enabled);
    try {
      await _channel.invokeMethod<void>('setMusicEnabled', {
        'enabled': enabled,
      });
    } catch (_) {
      // Do not interrupt settings or gameplay if audio is unavailable.
    }
  }

  Future<void> playForEvent(GameEvent event) async {
    if (!_effectsEnabled) return;
    final asset = switch (event.type) {
      GameEventType.roll => 'dice_roll.wav',
      GameEventType.barrierFormed ||
      GameEventType.barrierOpened => 'barrier_block.wav',
      GameEventType.move ||
      GameEventType.departure ||
      GameEventType.capture ||
      GameEventType.goal ||
      GameEventType.powerUp ||
      GameEventType.trap ||
      GameEventType.victory => 'token_move.wav',
      _ => null,
    };
    if (asset == null) return;
    try {
      await _channel.invokeMethod<void>('playEffect', {'asset': asset});
    } catch (_) {
      // Individual sound failures are non-critical.
    }
  }

  /// Plays the dice sound from Settings so a player can verify audio without
  /// starting a match.
  Future<void> playPreview() async {
    if (!_effectsEnabled) return;
    try {
      await _channel.invokeMethod<void>('playEffect', {
        'asset': 'dice_roll.wav',
      });
    } catch (_) {
      // Preview audio is optional and must never block Settings.
    }
  }
}

final gameSounds = GameSoundController();
