import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final canonicalIcon = File('assets/images/parchis_pop_icon.png');
  late final String canonicalIconHash;

  setUpAll(() {
    expect(canonicalIcon.existsSync(), isTrue);
    canonicalIconHash = sha256
        .convert(canonicalIcon.readAsBytesSync())
        .toString();
  });

  const legacySizes = <String, int>{
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };
  const foregroundSizes = <String, int>{
    'mdpi': 108,
    'hdpi': 162,
    'xhdpi': 216,
    'xxhdpi': 324,
    'xxxhdpi': 432,
  };
  const stockFlutterHashes = <String>{
    'c7c0c0189145e4e32a401c61c9bdc615754b0264e7afae24e834bb81049eaf81',
    '6a7c8f0d703e3682108f9662f813302236240d3f8f638bb391e32bfb96055fef',
    'e14aa40904929bf313fded22cf7e7ffcbf1d1aac4263b5ef1be8bfce650397aa',
    '4d470bf22d5c17d84edc5f82516d1ba8a1c09559cd761cefb792f86d9f52b540',
    '3c34e1f298d0c9ea3455d46db6b7759c8211a49e9ec6e44b635fc5c87dfb4180',
  };

  test(
    'Android launcher uses branded legacy, round, and foreground artwork',
    () {
      for (final entry in legacySizes.entries) {
        final directory = 'android/app/src/main/res/mipmap-${entry.key}';
        final launcher = File('$directory/ic_launcher.png');
        final round = File('$directory/ic_launcher_round.png');
        final foreground = File('$directory/ic_launcher_foreground.png');

        expect(launcher.existsSync(), isTrue, reason: launcher.path);
        expect(round.existsSync(), isTrue, reason: round.path);
        expect(foreground.existsSync(), isTrue, reason: foreground.path);
        expect(_pngSize(launcher), (entry.value, entry.value));
        expect(_pngSize(round), (entry.value, entry.value));
        expect(_pngSize(foreground), (
          foregroundSizes[entry.key]!,
          foregroundSizes[entry.key]!,
        ));
        expect(
          stockFlutterHashes,
          isNot(
            contains(sha256.convert(launcher.readAsBytesSync()).toString()),
          ),
          reason: '${launcher.path} must never revert to the Flutter logo.',
        );
      }
    },
  );

  test('Android 8 and Android 13 launcher resources are complete', () {
    for (final name in const ['ic_launcher.xml', 'ic_launcher_round.xml']) {
      final adaptive = File(
        'android/app/src/main/res/mipmap-anydpi-v26/$name',
      ).readAsStringSync();
      expect(adaptive, contains('<adaptive-icon'));
      expect(adaptive, contains('@color/ic_launcher_background'));
      expect(adaptive, contains('@mipmap/ic_launcher_foreground'));

      final themed = File(
        'android/app/src/main/res/mipmap-anydpi-v33/$name',
      ).readAsStringSync();
      expect(themed, contains('<adaptive-icon'));
      expect(themed, contains('@drawable/ic_launcher_monochrome'));
    }

    expect(
      File(
        'android/app/src/main/res/drawable/ic_launcher_monochrome.xml',
      ).existsSync(),
      isTrue,
    );
    // The rendered four-player board is the single canonical icon source.
    // Keeping the retired yellow die SVGs would make it too easy for a future
    // regeneration to silently restore the wrong launcher artwork.
    expect(File('assets/images/parchis_pop_icon.png').existsSync(), isTrue);
    expect(
      File('assets/branding/parchis_pop_app_icon.svg').existsSync(),
      isFalse,
    );
    expect(
      File('assets/branding/parchis_pop_app_icon_foreground.svg').existsSync(),
      isFalse,
    );
  });

  test('Android manifest declares branded standard and round icons', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifest, contains('android:roundIcon="@mipmap/ic_launcher_round"'));
  });

  test('iOS launcher keeps the canonical four-player board artwork', () {
    final iosMarketingIcon = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    expect(iosMarketingIcon.existsSync(), isTrue);
    expect(
      sha256.convert(iosMarketingIcon.readAsBytesSync()).toString(),
      canonicalIconHash,
    );
  });

  test('retired yellow die icon sources stay removed', () {
    expect(
      File('assets/branding/parchis_pop_app_icon.svg').existsSync(),
      isFalse,
    );
    expect(
      File('assets/branding/parchis_pop_app_icon_foreground.svg').existsSync(),
      isFalse,
    );
  });
}

(int, int) _pngSize(File file) {
  final bytes = file.readAsBytesSync();
  expect(bytes.length, greaterThanOrEqualTo(24), reason: file.path);
  expect(bytes.sublist(0, 8), const <int>[
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
  ], reason: file.path);
  final data = ByteData.sublistView(bytes);
  return (data.getUint32(16), data.getUint32(20));
}
