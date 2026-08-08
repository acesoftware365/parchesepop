import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';

void main() {
  test('compact phone nudges only exterior safe stars toward the board', () {
    expect(
      safeStarPaintNudgeForTesting(12, compactPhone: true),
      const Offset(0, -.16),
    );
    expect(
      safeStarPaintNudgeForTesting(29, compactPhone: true),
      const Offset(-.12, 0),
    );
    expect(
      safeStarPaintNudgeForTesting(46, compactPhone: true),
      const Offset(0, .12),
    );
    expect(
      safeStarPaintNudgeForTesting(63, compactPhone: true),
      const Offset(.12, 0),
    );

    for (final index in const [7, 24, 41, 58]) {
      expect(
        safeStarPaintNudgeForTesting(index, compactPhone: true),
        Offset.zero,
      );
    }
  });

  test('larger displays retain the original safe-star placement', () {
    for (final index in const [7, 12, 24, 29, 41, 46, 58, 63]) {
      expect(
        safeStarPaintNudgeForTesting(index, compactPhone: false),
        Offset.zero,
      );
    }
  });

  test('safe-star visual adjustment does not mutate logical route cells', () {
    final before = List<Offset>.of(GameEngine.loop);

    for (var index = 0; index < GameEngine.loop.length; index++) {
      safeStarPaintNudgeForTesting(index, compactPhone: true);
    }

    expect(GameEngine.loop, orderedEquals(before));
  });
}
