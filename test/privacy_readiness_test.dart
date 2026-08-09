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
    expect(page, contains('Resolved matches, immutable chat'));
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
}
