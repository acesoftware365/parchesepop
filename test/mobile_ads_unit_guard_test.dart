import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/mobile_ads.dart';

void main() {
  group('AdMob test-unit guard', () {
    test('debug builds always use Google test units', () {
      expect(shouldUseTestAdUnits(debugBuild: true, qaOverride: false), isTrue);
      expect(shouldUseTestAdUnits(debugBuild: true, qaOverride: true), isTrue);
    });

    test('release builds require the explicit QA override', () {
      expect(shouldUseTestAdUnits(debugBuild: false, qaOverride: true), isTrue);
      expect(
        shouldUseTestAdUnits(debugBuild: false, qaOverride: false),
        isFalse,
      );
    });
  });
}
