import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';

const _baseOrigins = <PlayerColor, Offset>{
  PlayerColor.blue: Offset(0, 0),
  PlayerColor.yellow: Offset(13, 0),
  PlayerColor.red: Offset(0, 13),
  PlayerColor.green: Offset(13, 13),
};

void _finishAlternatingTokens(GameEngine engine) {
  for (final player in engine.players) {
    player.tokens[0].progress = GameEngine.finishProgress;
    player.tokens[2].progress = GameEngine.finishProgress;
  }
}

void main() {
  test('finished tokens form an ordered column inside each player base', () {
    final engine = GameEngine();
    addTearDown(engine.dispose);
    _finishAlternatingTokens(engine);

    final cells = displayTokenCellsForTesting(engine);

    for (final player in engine.players) {
      final origin = _baseOrigins[player.color]!;
      final firstFinished = cells[player.tokens[0]]!;
      final secondFinished = cells[player.tokens[2]]!;
      final jailed = <Offset>{
        cells[player.tokens[1]]!,
        cells[player.tokens[3]]!,
      };
      final columnStart = switch (player.color) {
        PlayerColor.blue || PlayerColor.yellow => 1.60,
        PlayerColor.red || PlayerColor.green => 1.05,
      };

      expect(firstFinished, origin + Offset(.72, columnStart));
      expect(secondFinished, origin + Offset(.72, columnStart + 1.05));
      expect(firstFinished.dx, secondFinished.dx);
      expect(firstFinished.dy, lessThan(secondFinished.dy));
      expect(
        Rect.fromLTWH(origin.dx, origin.dy, 7, 7).contains(firstFinished),
        isTrue,
      );
      expect(
        Rect.fromLTWH(origin.dx, origin.dy, 7, 7).contains(secondFinished),
        isTrue,
      );
      expect(jailed, isNot(contains(firstFinished)));
      expect(jailed, isNot(contains(secondFinished)));
    }
  });

  test('compact phone keeps jailed pieces in their own two by two slots', () {
    final engine = GameEngine();
    addTearDown(engine.dispose);
    final red = engine.players.firstWhere(
      (player) => player.color == PlayerColor.red,
    );
    red.tokens[1].progress = GameEngine.finishProgress;
    red.tokens[3].progress = GameEngine.finishProgress;

    final cells = displayTokenCellsForTesting(engine, compactPhone: true);
    const origin = Offset(0, 13);
    final finished = <Offset>{cells[red.tokens[1]]!, cells[red.tokens[3]]!};
    final jailed = <Offset>{cells[red.tokens[0]]!, cells[red.tokens[2]]!};

    expect(
      [cells[red.tokens[1]], cells[red.tokens[3]]],
      [origin + const Offset(.72, 1.05), origin + const Offset(.72, 2.10)],
      reason: 'Finished positions compact by token id, without empty gaps.',
    );
    expect(
      [cells[red.tokens[0]], cells[red.tokens[2]]],
      [origin + const Offset(2.5, 2.5), origin + const Offset(2.5, 4.5)],
      reason: 'Unstarted pieces retain the compact-phone jail slots.',
    );
    expect(finished.intersection(jailed), isEmpty);
  });

  test('all four completed pieces fit as one non-overlapping column', () {
    final engine = GameEngine();
    addTearDown(engine.dispose);
    for (final player in engine.players) {
      for (final token in player.tokens) {
        token.progress = GameEngine.finishProgress;
      }
    }

    final cells = displayTokenCellsForTesting(engine, compactPhone: true);
    for (final player in engine.players) {
      final positions = player.tokens.map((token) => cells[token]!).toList();
      expect(positions.map((position) => position.dx).toSet(), hasLength(1));
      expect(positions.map((position) => position.dy).toSet(), hasLength(4));
      for (var index = 1; index < positions.length; index++) {
        expect(
          positions[index].dy - positions[index - 1].dy,
          closeTo(1.05, .001),
        );
      }
      final origin = _baseOrigins[player.color]!;
      for (final position in positions) {
        expect(
          Rect.fromLTWH(origin.dx, origin.dy, 7, 7).contains(position),
          isTrue,
        );
      }
    }
  });
}
