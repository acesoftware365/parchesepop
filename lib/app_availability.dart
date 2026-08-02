import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'firebase_options.dart';

/// Controls whether this installed version can enter the game.
///
/// Set these values in Firebase Remote Config when a replacement is live:
/// - minimum_supported_version: e.g. `1.1.0`
/// - update_message: e.g. `Download the new app to keep playing.`
/// - update_url: the App Store / Google Play URL for the replacement
/// - app_enabled: false only for an emergency global shutdown.
@immutable
class AppAvailability {
  const AppAvailability({
    required this.isAvailable,
    required this.message,
    required this.updateUrl,
    required this.installedVersion,
  });

  final bool isAvailable;
  final String message;
  final String updateUrl;
  final String installedVersion;

  static const available = AppAvailability(
    isAvailable: true,
    message: '',
    updateUrl: '',
    installedVersion: '1.0.0',
  );
}

class AppAvailabilityService {
  static const _defaultMessage = 'Download the new app to keep playing.';

  static Future<AppAvailability> load() async {
    final installedVersion = (await PackageInfo.fromPlatform()).version;
    var enabled = true;
    var minimumVersion = '0.0.0';
    var message = _defaultMessage;
    var updateUrl = '';

    final supportsFirebase =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    if (supportsFirebase) {
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        }
        final remote = FirebaseRemoteConfig.instance;
        await remote.setConfigSettings(
          RemoteConfigSettings(
            fetchTimeout: const Duration(seconds: 8),
            minimumFetchInterval: const Duration(hours: 1),
          ),
        );
        await remote.setDefaults(const {
          'app_enabled': true,
          'minimum_supported_version': '0.0.0',
          'update_message': _defaultMessage,
          'update_url': '',
        });
        await remote.fetchAndActivate();
        enabled = remote.getBool('app_enabled');
        minimumVersion = remote.getString('minimum_supported_version').trim();
        message = remote.getString('update_message').trim();
        updateUrl = remote.getString('update_url').trim();
      } catch (error) {
        debugPrint('Version availability check used safe defaults: $error');
      }
    }

    return AppAvailability(
      isAvailable: enabled && _isAtLeast(installedVersion, minimumVersion),
      message: message.isEmpty ? _defaultMessage : message,
      updateUrl: updateUrl,
      installedVersion: installedVersion,
    );
  }

  static bool _isAtLeast(String installed, String minimum) {
    List<int> values(String value) => value
        .split('+')
        .first
        .split('.')
        .map(
          (part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
        )
        .toList();
    final current = values(installed);
    final required = values(minimum);
    final length = current.length > required.length
        ? current.length
        : required.length;
    for (var index = 0; index < length; index++) {
      final a = index < current.length ? current[index] : 0;
      final b = index < required.length ? required[index] : 0;
      if (a != b) return a > b;
    }
    return true;
  }
}
