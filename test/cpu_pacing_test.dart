import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';

class _SequenceRandom implements math.Random {
  _SequenceRandom(this.values);

  final List<int> values;
  var index = 0;

  @override
  bool nextBool() => nextInt(2) == 0;

  @override
  double nextDouble() => nextInt(1000000) / 1000000;

  @override
  int nextInt(int max) {
    final value = values[index % values.length];
    index++;
    return value % max;
  }
}

void main() {
  testWidgets('CPU waits before rolling and again before moving', (
    tester,
  ) async {
    final engine = GameEngine(random: _SequenceRandom([4, 0]))
      ..currentPlayerIndex = PlayerColor.green.index;
    var delayCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'CPU • Normal',
          gameEngine: engine,
          cpuThinkDelayProvider: () {
            delayCalls++;
            return const Duration(seconds: 1);
          },
        ),
      ),
    );
    engine.notifyListeners();
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 999));
    expect(engine.rollSerial, 0);
    expect(engine.currentPlayer.tokens.every((token) => token.inNest), isTrue);

    await tester.pump(const Duration(milliseconds: 1));
    expect(engine.rollSerial, 1);
    expect(engine.dice, const [5, 1]);
    expect(engine.currentPlayer.tokens.every((token) => token.inNest), isTrue);

    await tester.pump(const Duration(milliseconds: 999));
    expect(engine.currentPlayer.tokens.every((token) => token.inNest), isTrue);

    await tester.pump(const Duration(milliseconds: 1));
    expect(engine.currentPlayer.tokens.any((token) => !token.inNest), isTrue);
    expect(delayCalls, 2);

    engine.gameOver = true;
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(const SizedBox.shrink());
    engine.dispose();
  });
}
