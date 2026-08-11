import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public privacy page and in-app link use the Firebase Hosting URL', () {
    final page = File('hosting/privacy.html').readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(page, contains('<title>Privacidad | Parchís Pop</title>'));
    expect(page, contains('Firebase Authentication'));
    expect(page, contains('Firebase Realtime Database'));
    expect(page, contains('sales@liisgo.com'));
    expect(page, contains('Rewarded ads are always voluntary.'));
    expect(page, contains('<strong>Tienda</strong>'));
    expect(page, contains('deletes the anonymous Firebase'));
    expect(
      page,
      contains('Resolved matchmaking tickets and claims, resolved matches'),
    );
    expect(page, contains('After that window, a player cannot list the queue'));
    expect(
      mainSource,
      contains("Uri.parse('https://parchese-pop.web.app/privacy.html')"),
    );
    expect(
      mainSource,
      isNot(contains('https://liisgo.com/#/apps/ParchesePop/privacy')),
    );
  });

  test('privacy copy documents banners and both voluntary rewarded offers', () {
    final policy = File('PRIVACY_POLICY.md').readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(
      policy,
      contains('including during gameplay, the game guide, and matchmaking'),
    );
    expect(policy, contains('in the **Shop** for the coin'));
    expect(policy, contains('after the whole table finishes'));
    expect(policy, contains('Rewarded advertisements are always voluntary.'));
    expect(policy, contains('deletes the anonymous Firebase Authentication'));
    expect(mainSource, contains('siempre voluntarios'));
    expect(mainSource, contains('pueden ofrecerse en la tienda'));
    expect(mainSource, contains('identidad anónima de Firebase'));
    expect(mainSource, contains('datos online removibles'));
    expect(mainSource, isNot(contains('banners únicamente fuera')));
  });

  test('Android explicitly disables application backup', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:allowBackup="false"'));
  });

  test('native analytics collection defaults off on macOS', () {
    final infoPlist = File('macos/Runner/Info.plist').readAsStringSync();

    expect(infoPlist, contains('FIREBASE_ANALYTICS_COLLECTION_ENABLED'));
    expect(
      infoPlist,
      contains('<key>FIREBASE_ANALYTICS_COLLECTION_ENABLED</key>\n\t<false/>'),
    );
  });

  test('analytics consent copy covers retention and both online funnels', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final languageSource = File('lib/app_language.dart').readAsStringSync();
    final policy = File('PRIVACY_POLICY.md').readAsStringSync();
    final hostedPolicy = File('hosting/privacy.html').readAsStringSync();

    expect(mainSource, contains('Mide sesiones, retención y pasos online'));
    expect(mainSource, contains('Quick Pop y Quick Table'));
    expect(mainSource, contains('códigos de sala'));
    expect(languageSource, contains('sessions, retention'));
    expect(languageSource, contains('room codes'));

    expect(policy, contains('anonymous app-session starts'));
    expect(policy, contains('since first use for aggregate retention'));
    expect(policy, contains('Quick Pop and Quick'));
    expect(policy, contains('Table; elapsed time'));
    expect(policy, contains('room codes, Firebase UID'));
    expect(policy, contains('raw error'));
    expect(policy, contains('inicios de sesión anónimos'));
    expect(policy, contains('UID de Firebase'));

    expect(hostedPolicy, contains('sesiones anónimas y días'));
    expect(hostedPolicy, contains('Quick Pop y Quick'));
    expect(hostedPolicy, contains('anonymous sessions and days since first'));
    expect(hostedPolicy, contains('room codes, Firebase identifiers'));
  });
}
