import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/feature_rollout.dart';

void main() {
  test('safe defaults expose validated local systems only', () {
    const flags = AppFeatureRollout.safeDefaults;

    expect(flags.contextualTutorial, isTrue);
    expect(flags.retentionRewards, isTrue);
    expect(flags.quickPopLocal, isTrue);
    expect(flags.quickPopOnline, isFalse);
    expect(flags.rankedPlay, isFalse);
    expect(flags.weeklyEvents, isFalse);
  });

  test('server constraint closes every authoritative feature', () {
    const requested = AppFeatureRollout(
      quickPopOnline: true,
      rankedPlay: true,
      weeklyEvents: true,
    );

    final constrained = requested.constrainedByServer(serverConfigured: false);

    expect(constrained.quickPopLocal, isTrue);
    expect(constrained.quickPopOnline, isFalse);
    expect(constrained.rankedPlay, isFalse);
    expect(constrained.weeklyEvents, isFalse);
  });

  test('configured server preserves remotely requested features', () {
    const requested = AppFeatureRollout(
      quickPopOnline: true,
      rankedPlay: true,
      weeklyEvents: true,
    );

    expect(
      identical(
        requested,
        requested.constrainedByServer(serverConfigured: true),
      ),
      isTrue,
    );
  });
}
