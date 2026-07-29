import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';

void _prepareCurrentPlayerToFinish(GameEngine game) {
  final player = game.currentPlayer;
  for (var tokenId = 0; tokenId < player.tokens.length - 1; tokenId++) {
    player.tokens[tokenId].progress = GameEngine.finishProgress;
  }
  player.tokens.last.progress = GameEngine.finishProgress - 1;
  game.hasRolled = true;
  game.dice = const [1, 2];
  game.remainingDice
    ..clear()
    ..addAll(const [1, 2]);
}

void main() {
  test('continuing after first place preserves the complete board state', () {
    final game = GameEngine(mode: GameMode.chaos, random: Random(17));
    final first = game.currentPlayer;
    final green = game.players[1];
    final yellow = game.players[2];
    final blue = game.players[3];

    green.tokens[0].progress = 8;
    green.tokens[1].progress = 23;
    green.inventory = PowerUp.shield;
    yellow.tokens[0].progress = 19;
    yellow.skippedTurns = 1;
    blue.tokens[0].progress = 41;
    blue.shielded = true;
    game.traps.add(
      const BoardTrap(
        owner: PlayerColor.blue,
        type: PowerUp.setbackTrap,
        loopIndex: 31,
      ),
    );

    _prepareCurrentPlayerToFinish(game);
    expect(game.moveToken(first.tokens.last, die: 1), isTrue);
    expect(game.gameOver, isTrue);

    final tokenProgressBefore = <PlayerColor, List<int>>{
      for (final player in game.players)
        player.color: player.tokens
            .map((token) => token.progress)
            .toList(growable: false),
    };
    final inventoriesBefore = <PlayerColor, PowerUp?>{
      for (final player in game.players) player.color: player.inventory,
    };
    final shieldsBefore = <PlayerColor, bool>{
      for (final player in game.players) player.color: player.shielded,
    };
    final skippedTurnsBefore = <PlayerColor, int>{
      for (final player in game.players) player.color: player.skippedTurns,
    };
    final trapsBefore = game.traps
        .map((trap) => (trap.owner, trap.type, trap.loopIndex))
        .toList(growable: false);
    final itemsBefore = game.itemLoopIndices.toSet();
    final firstWinner = game.winner;

    expect(game.continueAfterWinner(), isTrue);

    expect(<PlayerColor, List<int>>{
      for (final player in game.players)
        player.color: player.tokens
            .map((token) => token.progress)
            .toList(growable: false),
    }, tokenProgressBefore);
    expect(<PlayerColor, PowerUp?>{
      for (final player in game.players) player.color: player.inventory,
    }, inventoriesBefore);
    expect(<PlayerColor, bool>{
      for (final player in game.players) player.color: player.shielded,
    }, shieldsBefore);
    expect(<PlayerColor, int>{
      for (final player in game.players) player.color: player.skippedTurns,
    }, skippedTurnsBefore);
    expect(
      game.traps.map((trap) => (trap.owner, trap.type, trap.loopIndex)),
      trapsBefore,
    );
    expect(game.itemLoopIndices, itemsBefore);
    expect(game.winner, same(firstWinner));
    expect(game.finishOrder, const [PlayerColor.red]);
    expect(game.currentPlayer.color, PlayerColor.green);
    expect(game.gameOver, isFalse);
    game.dispose();
  });

  test('one uninterrupted match records all four places and their points', () {
    final game = GameEngine();
    final originalWinner = game.currentPlayer;

    for (var placement = 1; placement <= 3; placement++) {
      final expectedColor = PlayerColor.values[placement - 1];
      expect(game.currentPlayer.color, expectedColor);
      _prepareCurrentPlayerToFinish(game);

      expect(game.moveToken(game.currentPlayer.tokens.last, die: 1), isTrue);
      expect(game.placementFor(expectedColor), placement);

      if (placement == 1) {
        expect(game.gameOver, isTrue);
        expect(game.continueAfterWinner(), isTrue);
      } else if (placement < 3) {
        expect(game.gameOver, isFalse);
      }
    }

    expect(game.gameOver, isTrue);
    expect(game.standingsComplete, isTrue);
    expect(game.canContinueAfterWinner, isFalse);
    expect(game.winner, same(originalWinner));
    expect(game.finishOrder, PlayerColor.values);
    expect(
      game.players[PlayerColor.blue.index].tokens.every(
        (token) => token.finished,
      ),
      isFalse,
      reason: 'fourth place is certain without playing out the last pieces',
    );
    expect(
      game.message,
      'Finalizó la partida. Ya quedaron definidas las cuatro posiciones.',
    );
    expect(
      game.standings
          .map(
            (standing) =>
                (standing.competitor, standing.placement, standing.points),
          )
          .toList(growable: false),
      const [
        (PlayerColor.red, 1, 100),
        (PlayerColor.green, 2, 60),
        (PlayerColor.yellow, 3, 30),
        (PlayerColor.blue, 4, 10),
      ],
    );
    expect(game.placementPointsFor(PlayerColor.red), 100);
    expect(game.placementPointsFor(PlayerColor.green), 60);
    expect(game.placementPointsFor(PlayerColor.yellow), 30);
    expect(game.placementPointsFor(PlayerColor.blue), 10);
    game.dispose();
  });
}
