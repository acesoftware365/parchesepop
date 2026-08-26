import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';

class _SequenceRandom implements Random {
  _SequenceRandom(this.values);

  final List<int> values;
  int _position = 0;

  int _next() => _position < values.length ? values[_position++] : 0;

  @override
  bool nextBool() => _next().isOdd;

  @override
  double nextDouble() => (_next() % 1000) / 1000;

  @override
  int nextInt(int max) => _next() % max;
}

GameEngine chaosGame({List<int> randomValues = const [0, 0, 0, 0]}) =>
    GameEngine(mode: GameMode.chaos, random: _SequenceRandom(randomValues));

GameToken placeOnGlobal(GameEngine game, int player, int token, int global) {
  final piece = game.players[player].tokens[token];
  piece.progress =
      (global - GameEngine.startOffset[piece.owner]!) % GameEngine.loopLength;
  return piece;
}

void main() {
  test('online identities replace only the default player labels', () {
    final game = GameEngine(
      humanName: 'JuanPop',
      cpuNames: const ['LunaRápida', 'PixelRey', 'BrisaDorada'],
    );

    expect(game.players.map((player) => player.name), [
      'JuanPop',
      'LunaRápida',
      'PixelRey',
      'BrisaDorada',
    ]);
    game.dispose();
  });

  test('Pass & Play can mix named human seats with CPU seats', () {
    final game = GameEngine(
      humanPlayerColors: const {PlayerColor.red, PlayerColor.green},
      playerNames: const {PlayerColor.red: 'Mari', PlayerColor.green: 'Juan'},
    );

    expect(game.players[PlayerColor.red.index].name, 'Mari');
    expect(game.players[PlayerColor.green.index].name, 'Juan');
    expect(game.players[PlayerColor.red.index].isHuman, isTrue);
    expect(game.players[PlayerColor.green.index].isHuman, isTrue);
    expect(game.players[PlayerColor.yellow.index].isHuman, isFalse);
    expect(game.players[PlayerColor.blue.index].isHuman, isFalse);
    game.dispose();
  });

  test('a CPU seat can be claimed without resetting its board state', () {
    final game = GameEngine(
      humanPlayerColors: const {PlayerColor.red},
      playerNames: const {PlayerColor.red: 'Mari'},
    );
    final cpu = game.players[PlayerColor.yellow.index];
    cpu.tokens.first.progress = 18;
    game.currentPlayerIndex = PlayerColor.yellow.index;

    expect(game.claimCpuSeat(PlayerColor.yellow, name: 'Juan'), isTrue);
    expect(cpu.isHuman, isTrue);
    expect(cpu.name, 'Juan');
    expect(cpu.tokens.first.progress, 18);
    expect(game.currentPlayer.color, PlayerColor.yellow);
    game.dispose();
  });

  test('a claimed CPU seat remains human after restoring a checkpoint', () {
    final game = GameEngine(
      humanPlayerColors: const {PlayerColor.red},
      playerNames: const {PlayerColor.red: 'Mari'},
    );
    game.claimCpuSeat(PlayerColor.green, name: 'Juan');
    game.players[PlayerColor.green.index].tokens.first.progress = 11;

    final restored = GameEngine.fromCheckpoint(game.createCheckpoint());
    final green = restored.players[PlayerColor.green.index];
    expect(green.isHuman, isTrue);
    expect(green.name, 'Juan');
    expect(green.tokens.first.progress, 11);
    game.dispose();
    restored.dispose();
  });

  test('each accepted roll receives a new animation serial', () {
    final game = GameEngine(random: _SequenceRandom([2, 3, 2, 3]));
    game.currentPlayer.tokens.first.progress = 0;

    expect(game.rollSerial, 0);
    game.roll();
    expect(game.dice, [3, 4]);
    expect(game.rollSerial, 1);

    game.roll();
    expect(game.rollSerial, 1, reason: 'a disabled roll must not animate');

    game.hasRolled = false;
    game.remainingDice.clear();
    game.roll();
    expect(game.dice, [3, 4]);
    expect(game.rollSerial, 2);
  });

  test('event history records a roll, movement, and capture in play order', () {
    final game = GameEngine(random: _SequenceRandom([2, 5]));
    final red = game.players[0].tokens.first..progress = 1;
    final green = placeOnGlobal(game, 1, 0, 4);

    game.roll();
    expect(game.dice, [3, 6]);
    expect(game.moveToken(red, die: 3), isTrue);
    expect(green.inNest, isTrue);

    final roll = game.eventHistory.lastWhere(
      (event) => event.type == GameEventType.roll,
    );
    final movement = game.eventHistory.lastWhere(
      (event) => event.type == GameEventType.move,
    );
    final capture = game.eventHistory.lastWhere(
      (event) => event.type == GameEventType.capture,
    );

    expect(roll.dice, (3, 6));
    expect(roll.playerName, 'Tú');
    expect(roll.playerColor, PlayerColor.red);
    expect(movement.tokenId, red.id);
    expect(movement.fromProgress, 1);
    expect(movement.toProgress, 4);
    expect(capture.playerName, 'Tú');
    expect(capture.playerColor, PlayerColor.red);
    expect(capture.targetName, 'CPU 1');
    expect(capture.targetColor, PlayerColor.green);
    expect(capture.tokenId, green.id);
    expect(roll.sequence, lessThan(movement.sequence));
    expect(movement.sequence, lessThan(capture.sequence));
    game.dispose();
  });

  test('three doubles logs why one token leaves a same-color barrier', () {
    final game = GameEngine(random: _SequenceRandom([3, 3]));
    game.currentPlayerIndex = 2;
    final yellow = game.currentPlayer;
    final penalized = yellow.tokens[0]..progress = 12;
    final protectedPartner = yellow.tokens[1]..progress = 12;
    game.consecutiveDoubles = 2;

    game.roll();

    expect(game.dice, [4, 0]);
    expect(penalized.inNest, isTrue);
    expect(protectedPartner.progress, 12);
    final rolls = game.eventHistory
        .where((event) => event.type == GameEventType.roll)
        .toList();
    final penalties = game.eventHistory
        .where((event) => event.type == GameEventType.threeDoublesPenalty)
        .toList();
    expect(rolls, hasLength(1));
    expect(rolls.single.dice, (4, 4));
    expect(penalties, hasLength(1));
    final penalty = penalties.single;
    expect(penalty.playerName, yellow.name);
    expect(penalty.playerColor, PlayerColor.yellow);
    expect(penalty.tokenId, penalized.id);
    expect(penalty.fromProgress, 12);
    expect(penalty.toProgress, -1);
    expect(penalty.description.toLowerCase(), contains('tres dobles'));
    expect(rolls.single.sequence, lessThan(penalty.sequence));
    game.dispose();
  });

  test('three doubles never penalizes a token inside its protected lane', () {
    final game = GameEngine(random: _SequenceRandom([3, 3]));
    final protectedLaneToken = game.currentPlayer.tokens[0]
      ..progress = GameEngine.commonPathLength + 2;
    final commonPathToken = game.currentPlayer.tokens[1]..progress = 31;
    game.consecutiveDoubles = 2;

    game.roll();

    expect(protectedLaneToken.progress, GameEngine.commonPathLength + 2);
    expect(commonPathToken.inNest, isTrue);
    expect(
      game.eventHistory
          .where((event) => event.type == GameEventType.threeDoublesPenalty)
          .single
          .tokenId,
      commonPathToken.id,
    );
    game.dispose();
  });

  test(
    'three doubles leaves all pieces alone when only protected pieces exist',
    () {
      final game = GameEngine(random: _SequenceRandom([3, 3]));
      final protectedLaneToken = game.currentPlayer.tokens[0]
        ..progress = GameEngine.commonPathLength + 2;
      final finishedToken = game.currentPlayer.tokens[1]
        ..progress = GameEngine.finishProgress;
      game.consecutiveDoubles = 2;

      game.roll();

      expect(protectedLaneToken.progress, GameEngine.commonPathLength + 2);
      expect(finishedToken.finished, isTrue);
      expect(game.message, contains('pasillo final están protegidas'));
      game.dispose();
    },
  );

  test('event history keeps only the latest 100 immutable entries', () {
    final game = GameEngine(
      random: _SequenceRandom([
        for (var roll = 0; roll < 110; roll++) ...[0, 1],
      ]),
    );

    for (var roll = 0; roll < 110; roll++) {
      game.hasRolled = false;
      game.remainingDice.clear();
      game.roll();
    }

    expect(game.eventHistory, hasLength(100));
    expect(
      game.eventHistory.map((event) => event.sequence).toList(),
      orderedEquals(
        game.eventHistory.map((event) => event.sequence).toList()..sort(),
      ),
    );
    expect(game.eventHistory.first.sequence, greaterThan(1));
    final latestRoll = game.eventHistory.lastWhere(
      (event) => event.type == GameEventType.roll,
    );
    expect(latestRoll.dice, (1, 2));
    expect(() => game.eventHistory.clear(), throwsUnsupportedError);
    expect(game.eventHistory, hasLength(100));
    game.dispose();
  });

  test('a token can leave the nest only with a five', () {
    final game = GameEngine();
    final token = game.currentPlayer.tokens.first;

    game.hasRolled = true;
    game.remainingDice.addAll([3, 5]);

    expect(game.canMove(token, 3), isFalse);
    expect(game.canMove(token, 5), isTrue);
    expect(game.moveToken(token, die: 5), isTrue);
    expect(token.progress, 0);
  });

  test('leaving the nest publishes a SALIDA board effect', () {
    final game = GameEngine();
    final token = game.currentPlayer.tokens.first;
    final previousSerial = game.effectSerial;
    game.hasRolled = true;
    game.remainingDice.addAll([5, 2]);

    expect(game.moveToken(token, die: 5), isTrue);
    expect(game.effectSerial, previousSerial + 1);
    expect(game.effectKind, PowerEffectKind.departure);
    expect(game.effectLoopIndex, GameEngine.startOffset[PlayerColor.red]);
    expect(
      game.effectBoardCell,
      GameEngine.loop[GameEngine.startOffset[PlayerColor.red]!],
    );
    expect(game.effectOwner, PlayerColor.red);
    expect(game.effectPowerUp, isNull);
    expect(game.effectResolving, isFalse);
    game.dispose();
  });

  test('a capture publishes an impact effect on the captured square', () {
    final game = GameEngine();
    final red = game.players[0].tokens.first..progress = 1;
    final green = placeOnGlobal(game, 1, 0, 4);
    final previousSerial = game.effectSerial;
    game.hasRolled = true;
    game.remainingDice.add(3);

    expect(game.moveToken(red, die: 3), isTrue);
    expect(green.inNest, isTrue);
    expect(game.remainingDice, contains(20));
    expect(game.effectSerial, previousSerial + 1);
    expect(game.effectKind, PowerEffectKind.capture);
    expect(game.effectLoopIndex, 4);
    expect(game.effectBoardCell, GameEngine.loop[4]);
    expect(game.effectToken, same(green));
    expect(game.effectOwner, PlayerColor.red);
    game.dispose();
  });

  test('leaving the nest onto a rival uses one combined effect', () {
    final game = GameEngine();
    final red = game.players[0].tokens.first;
    final green = placeOnGlobal(game, 1, 0, 0);
    final previousSerial = game.effectSerial;
    game.hasRolled = true;
    game.remainingDice.add(5);

    expect(game.moveToken(red, die: 5), isTrue);
    expect(red.progress, 0);
    expect(green.inNest, isTrue);
    expect(game.effectSerial, previousSerial + 1);
    expect(game.effectKind, PowerEffectKind.departureCapture);
    expect(game.effectLoopIndex, 0);
    expect(game.effectBoardCell, GameEngine.loop[0]);
    expect(game.effectToken, same(green));
    game.dispose();
  });

  test('arriving at the center publishes a goal effect for every color', () {
    for (
      var playerIndex = 0;
      playerIndex < PlayerColor.values.length;
      playerIndex++
    ) {
      final game = GameEngine();
      game.currentPlayerIndex = playerIndex;
      final player = game.currentPlayer;
      final token = player.tokens.first
        ..progress = GameEngine.finishProgress - 1;
      game.hasRolled = true;
      game.remainingDice.addAll([1, 6]);

      expect(game.moveToken(token, die: 1), isTrue);
      expect(token.finished, isTrue);
      expect(game.effectKind, PowerEffectKind.goal);
      expect(game.effectBoardCell, GameEngine.goalCells[player.color]);
      expect(game.effectLoopIndex, isNull);
      expect(game.effectOwner, player.color);
      expect(game.remainingDice, contains(10));
      game.dispose();
    }
  });

  for (final format in MatchFormat.values) {
    for (final mode in GameMode.values) {
      test('${format.name} ${mode.name} keeps the +10 goal bonus playable', () {
        final game = GameEngine(matchFormat: format, mode: mode);
        final player = game.currentPlayer;
        final finisher = player.tokens.first
          ..progress = GameEngine.finishProgress - 1;
        final bonusMover = player.tokens.last..progress = 4;
        game
          ..hasRolled = true
          ..dice = const <int>[1, 6];
        game.remainingDice.addAll(const <int>[1, 6]);

        expect(game.moveToken(finisher, die: 1), isTrue);
        expect(finisher.finished, isTrue);
        expect(game.gameOver, isFalse);
        expect(game.remainingDice, const <int>[6, 10]);
        expect(game.canMove(bonusMover, 10), isTrue);
        expect(game.moveToken(bonusMover, die: 10), isTrue);
        expect(bonusMover.progress, 14);
        expect(game.remainingDice, const <int>[6]);
        game.dispose();
      });
    }
  }

  test('a five must be used for salida while a token remains in the nest', () {
    final game = GameEngine();
    final outside = game.currentPlayer.tokens.first..progress = 4;
    final nested = game.currentPlayer.tokens[1];
    game.hasRolled = true;
    game.remainingDice.addAll([2, 5]);

    expect(game.mustUseFiveToLeaveNest(PlayerColor.red), isTrue);
    expect(game.canMove(nested, 5), isTrue);
    expect(game.canMove(outside, 5), isFalse);
    expect(game.canMove(outside, 2), isTrue);
  });

  test('a five becomes five steps after every token is outside', () {
    final game = GameEngine();
    for (var index = 0; index < game.currentPlayer.tokens.length; index++) {
      game.currentPlayer.tokens[index].progress = index * 3;
    }
    final token = game.currentPlayer.tokens.first;
    game.hasRolled = true;
    game.remainingDice.add(5);

    expect(game.mustUseFiveToLeaveNest(PlayerColor.red), isFalse);
    expect(game.canMove(token, 5), isTrue);
  });

  test('a blocked start converts five into five steps', () {
    final game = GameEngine();
    final first = game.currentPlayer.tokens[0]..progress = 0;
    game.currentPlayer.tokens[1].progress = 0;
    final nested = game.currentPlayer.tokens[2];
    game.hasRolled = true;
    game.remainingDice.add(5);

    expect(game.mustUseFiveToLeaveNest(PlayerColor.red), isFalse);
    expect(game.canMove(nested, 5), isFalse);
    expect(game.canMove(first, 5), isTrue);
    expect(game.moveToken(first, die: 5), isTrue);
    expect(first.progress, 5);
  });

  test('a reserved five never moves a board token or consumes the die', () {
    final game = GameEngine();
    final outside = game.currentPlayer.tokens.first..progress = 4;
    game.hasRolled = true;
    game.remainingDice.addAll([2, 5]);

    expect(game.moveToken(outside, die: 5), isFalse);
    expect(outside.progress, 4);
    expect(game.remainingDice, [2, 5]);
  });

  test('double five releases two tokens while the start remains available', () {
    final game = GameEngine();
    final first = game.currentPlayer.tokens[0];
    final second = game.currentPlayer.tokens[1];
    game.hasRolled = true;
    game.dice = [5, 5];
    game.remainingDice.addAll([5, 5]);

    expect(game.moveToken(first, die: 5), isTrue);
    expect(first.progress, 0);
    expect(game.remainingDice, [5]);
    expect(game.mustUseFiveToLeaveNest(PlayerColor.red), isTrue);

    expect(game.moveToken(second, die: 5), isTrue);
    expect(second.progress, 0);
    expect(game.remainingDice, isEmpty);
  });

  test('a token needs an exact roll to finish', () {
    final game = GameEngine();
    final token = game.currentPlayer.tokens.first
      ..progress = GameEngine.finishProgress - 2;

    expect(game.canMove(token, 2), isTrue);
    expect(game.canMove(token, 3), isFalse);
  });

  test('a winning move closes the match in a clean terminal state', () {
    final game = GameEngine();
    final player = game.currentPlayer;
    for (var tokenId = 0; tokenId < 3; tokenId++) {
      player.tokens[tokenId].progress = GameEngine.finishProgress;
    }
    final finalToken = player.tokens.last
      ..progress = GameEngine.finishProgress - 1;
    game.hasRolled = true;
    game.dice = [1, 6];
    game.remainingDice.addAll([1, 6]);
    game.pendingTrapPlacement = true;
    game.consecutiveDoubles = 2;

    expect(game.moveToken(finalToken, die: 1), isTrue);
    expect(finalToken.finished, isTrue);
    expect(game.gameOver, isTrue);
    expect(game.winner, same(player));
    expect(game.message, '¡Ganaste la partida!');
    expect(game.remainingDice, isEmpty);
    expect(game.hasRolled, isFalse);
    expect(game.pendingTrapPlacement, isFalse);
    expect(game.consecutiveDoubles, 0);

    final winningMessage = game.message;
    game.roll();
    game.endTurn();
    expect(game.moveToken(finalToken, die: 1), isFalse);
    expect(game.winner, same(player));
    expect(game.currentPlayer, same(player));
    expect(game.message, winningMessage);
  });

  test('a CPU winner is identified by name and stops the match', () {
    final game = GameEngine();
    game.currentPlayerIndex = 1;
    final player = game.currentPlayer;
    for (var tokenId = 0; tokenId < 3; tokenId++) {
      player.tokens[tokenId].progress = GameEngine.finishProgress;
    }
    final finalToken = player.tokens.last
      ..progress = GameEngine.finishProgress - 1;
    game.hasRolled = true;
    game.dice = [1, 3];
    game.remainingDice.addAll([1, 3]);

    expect(game.moveToken(finalToken, die: 1), isTrue);
    expect(game.winner, same(player));
    expect(game.gameOver, isTrue);
    expect(game.message, '¡CPU 1 ganó la partida!');
    expect(game.remainingDice, isEmpty);
    expect(game.hasRolled, isFalse);
  });

  test(
    'online spectator continuation preserves the winner and skips finishers',
    () {
      final game = GameEngine();
      final first = game.currentPlayer;
      for (var tokenId = 0; tokenId < 3; tokenId++) {
        first.tokens[tokenId].progress = GameEngine.finishProgress;
      }
      first.tokens.last.progress = GameEngine.finishProgress - 1;
      game.hasRolled = true;
      game.dice = const [1, 4];
      game.remainingDice.addAll(const [1, 4]);

      expect(game.moveToken(first.tokens.last, die: 1), isTrue);
      expect(game.winner, same(first));
      expect(game.finishOrder, [PlayerColor.red]);
      expect(game.canContinueAfterWinner, isTrue);

      expect(game.continueAfterWinner(), isTrue);
      expect(game.gameOver, isFalse);
      expect(game.spectatorContinuationActive, isTrue);
      expect(game.currentPlayer.color, PlayerColor.green);

      final second = game.currentPlayer;
      for (var tokenId = 0; tokenId < 3; tokenId++) {
        second.tokens[tokenId].progress = GameEngine.finishProgress;
      }
      second.tokens.last.progress = GameEngine.finishProgress - 1;
      game.hasRolled = true;
      game.dice = const [1, 2];
      game.remainingDice.addAll(const [1, 2]);

      expect(game.moveToken(second.tokens.last, die: 1), isTrue);
      expect(
        game.winner,
        same(first),
        reason: 'the original winner stays first',
      );
      expect(game.finishOrder, [PlayerColor.red, PlayerColor.green]);
      expect(game.gameOver, isFalse);
      expect(game.currentPlayer.color, PlayerColor.yellow);
      expect(game.hasPlayerFinished(PlayerColor.red), isTrue);
      expect(game.hasPlayerFinished(PlayerColor.green), isTrue);
      game.dispose();
    },
  );

  test('Turbo finishing the fourth token uses the same victory state', () {
    final game = GameEngine(mode: GameMode.chaos);
    final player = game.currentPlayer;
    for (var tokenId = 0; tokenId < 3; tokenId++) {
      player.tokens[tokenId].progress = GameEngine.finishProgress;
    }
    player.tokens.last.progress = GameEngine.finishProgress - 3;
    player.inventory = PowerUp.boost;
    game.hasRolled = true;
    game.remainingDice.add(4);

    expect(game.usePowerUp(), isTrue);
    expect(player.tokens.last.finished, isTrue);
    expect(game.winner, same(player));
    expect(game.gameOver, isTrue);
    expect(game.remainingDice, isEmpty);
    expect(game.hasRolled, isFalse);
    expect(game.message, '¡Ganaste la partida!');
    expect(game.effectKind, PowerEffectKind.goal);
    expect(game.effectBoardCell, GameEngine.goalCells[player.color]);
    final terminalEvents = game.eventHistory
        .where(
          (event) =>
              event.type == GameEventType.goal ||
              event.type == GameEventType.victory,
        )
        .map((event) => event.type)
        .toList();
    expect(terminalEvents, [GameEventType.goal, GameEventType.victory]);
  });

  test('Turbo awards capture +20 and preserves it through the next roll', () {
    final game = chaosGame(randomValues: [0, 0, 0, 0, 1, 2]);
    final mover = game.currentPlayer.tokens.first..progress = 1;
    final opponent = placeOnGlobal(game, 1, 0, 4);
    game.currentPlayer.inventory = PowerUp.boost;

    expect(game.usePowerUp(), isTrue);

    expect(mover.progress, 4);
    expect(opponent.inNest, isTrue);
    expect(game.remainingDice, [20]);
    expect(game.message, contains('Bono +20'));

    game.roll();

    expect(game.dice, [2, 3]);
    expect(game.remainingDice, [2, 3, 20]);
    game.dispose();
  });

  test('Turbo awards +10 when a non-final piece reaches the center', () {
    final game = chaosGame();
    final player = game.currentPlayer;
    final mover = player.tokens.first..progress = GameEngine.finishProgress - 3;
    player.inventory = PowerUp.boost;

    expect(game.usePowerUp(), isTrue);

    expect(mover.finished, isTrue);
    expect(game.gameOver, isFalse);
    expect(game.winner, isNull);
    expect(game.remainingDice, [10]);
    expect(game.message, contains('Bono +10'));
    expect(
      game.eventHistory
          .lastWhere((event) => event.type == GameEventType.goal)
          .tokenId,
      mover.id,
    );
    game.dispose();
  });

  test('landing on an opponent captures it outside a safe space', () {
    final game = GameEngine();
    final red = game.players[0].tokens.first..progress = 1;
    final green = game.players[1].tokens.first;
    final targetLoopIndex = game.loopIndex(PlayerColor.red, 4);
    green.progress =
        (targetLoopIndex - GameEngine.startOffset[PlayerColor.green]!) %
        GameEngine.loop.length;
    game.hasRolled = true;
    game.remainingDice.add(3);

    game.moveToken(red, die: 3);

    expect(green.inNest, isTrue);
  });

  test('a stored shield protects only from traps, never from a capture', () {
    final game = chaosGame();
    final mover = game.currentPlayer.tokens.first..progress = 1;
    final defender = placeOnGlobal(game, 1, 0, 4);
    game.players[1].inventory = PowerUp.shield;
    game.players[1].shielded = true;
    game.hasRolled = true;
    game.dice = [3, 6];
    game.remainingDice.addAll([3, 6]);

    expect(game.moveToken(mover, die: 3), isTrue);

    expect(defender.inNest, isTrue);
    expect(game.players[1].inventory, PowerUp.shield);
    expect(game.players[1].shielded, isTrue);
    expect(game.remainingDice, contains(20));
    game.dispose();
  });

  test('the complete route contains 68 numbered cells', () {
    expect(GameEngine.loop, hasLength(68));
    expect(GameEngine.commonPathLength, 64);
    expect(GameEngine.finishProgress, 71);
    expect(GameEngine.safeLoopIndices, hasLength(12));
    expect(GameEngine.startOffset[PlayerColor.red], 0);
    expect(GameEngine.startOffset[PlayerColor.green], 17);
    expect(GameEngine.startOffset[PlayerColor.yellow], 34);
    expect(GameEngine.startOffset[PlayerColor.blue], 51);
  });

  test('the complete board has four equal rotational 17-cell sectors', () {
    expect(GameEngine.loop.toSet(), hasLength(GameEngine.loopLength));

    const center = Offset(10, 10);
    for (var index = 0; index < 17; index++) {
      var expected = GameEngine.loop[index];
      for (var quarter = 1; quarter < 4; quarter++) {
        final delta = expected - center;
        expected = center + Offset(delta.dy, -delta.dx);
        final actual = GameEngine.loop[index + quarter * 17];
        expect(actual.dx, closeTo(expected.dx, .00001));
        expect(actual.dy, closeTo(expected.dy, .00001));
      }
    }

    for (final color in PlayerColor.values) {
      final start = GameEngine.startOffset[color]!;
      expect(
        GameEngine.homeEntryOffset[color],
        (start + GameEngine.commonPathLength - 1) % GameEngine.loopLength,
      );
    }
  });

  test('each SALIDA arrow points toward its next printed route cells', () {
    const expectedTargetSquares = {
      PlayerColor.red: 4,
      PlayerColor.blue: 55,
      PlayerColor.yellow: 38,
      PlayerColor.green: 21,
    };
    const expectedDirections = {
      PlayerColor.red: (1.0, 0.0),
      PlayerColor.blue: (0.0, 1.0),
      PlayerColor.yellow: (-1.0, 0.0),
      PlayerColor.green: (0.0, -1.0),
    };

    for (final color in PlayerColor.values) {
      final targetIndex = GameEngine.departureArrowTargetLoopIndex[color];
      final direction = GameEngine.departureArrowDirection[color];

      expect(
        targetIndex,
        isNotNull,
        reason: '$color needs a printed target cell for its SALIDA arrow',
      );
      expect(
        targetIndex! + 1,
        expectedTargetSquares[color],
        reason: '$color must point toward the requested printed square',
      );
      expect(
        (direction?.dx, direction?.dy),
        expectedDirections[color],
        reason: '$color must use the matching cardinal travel direction',
      );
    }
  });

  test('every piece enters its own home lane after the complete route', () {
    for (var playerIndex = 0; playerIndex < 4; playerIndex++) {
      for (var tokenId = 0; tokenId < 4; tokenId++) {
        final game = GameEngine();
        game.currentPlayerIndex = playerIndex;
        final token = game.currentPlayer.tokens[tokenId]
          ..progress = GameEngine.commonPathLength - 1;
        game.hasRolled = true;
        game.remainingDice.addAll([1, 6]);

        expect(
          game.loopIndex(token.owner, token.progress),
          GameEngine.homeEntryOffset[token.owner],
        );
        expect(game.movementCellsFor(token, 1), [
          GameEngine.homeLanes[token.owner]!.first,
        ]);
        expect(game.moveToken(token, die: 1), isTrue);
        expect(token.progress, GameEngine.commonPathLength);
        expect(game.tokenCell(token), GameEngine.homeLanes[token.owner]!.first);
        game.dispose();
      }
    }
  });

  test('a second piece enters through the same lane as the first', () {
    for (var playerIndex = 0; playerIndex < 4; playerIndex++) {
      final game = GameEngine();
      game.currentPlayerIndex = playerIndex;
      final first = game.currentPlayer.tokens[0]
        ..progress = GameEngine.commonPathLength + 1;
      final second = game.currentPlayer.tokens[1]
        ..progress = GameEngine.commonPathLength - 1;
      game.hasRolled = true;
      game.remainingDice.addAll([1, 6]);

      expect(game.moveToken(second, die: 1), isTrue);
      expect(game.tokenCell(first), GameEngine.homeLanes[first.owner]![1]);
      expect(game.tokenCell(second), GameEngine.homeLanes[second.owner]![0]);
      game.dispose();
    }
  });

  test('a multi-step move follows the turn into the matching home lane', () {
    for (var playerIndex = 0; playerIndex < 4; playerIndex++) {
      final game = GameEngine();
      game.currentPlayerIndex = playerIndex;
      final token = game.currentPlayer.tokens.first
        ..progress = GameEngine.commonPathLength - 2;
      game.hasRolled = true;
      game.remainingDice.addAll([3, 6]);
      final lastCommon = GameEngine
          .loop[game.loopIndex(token.owner, GameEngine.commonPathLength - 1)];

      expect(game.movementCellsFor(token, 3), [
        lastCommon,
        GameEngine.homeLanes[token.owner]![0],
        GameEngine.homeLanes[token.owner]![1],
      ]);
      expect(game.moveToken(token, die: 3), isTrue);
      expect(game.tokenCell(token), GameEngine.homeLanes[token.owner]![1]);
      game.dispose();
    }
  });

  test(
    'a physical five captures one rival blocking each home entry and keeps moving',
    () {
      for (var playerIndex = 0; playerIndex < 4; playerIndex++) {
        final game = GameEngine();
        game.currentPlayerIndex = playerIndex;
        final mover = game.currentPlayer.tokens.first
          ..progress = GameEngine.commonPathLength - 2;
        for (var tokenId = 1; tokenId < 4; tokenId++) {
          game.currentPlayer.tokens[tokenId].progress = tokenId * 10;
        }
        final gate = GameEngine.homeEntryOffset[mover.owner]!;
        final opponentIndex = (playerIndex + 1) % game.players.length;
        final blocker = placeOnGlobal(game, opponentIndex, 0, gate);
        game.hasRolled = true;
        game.dice = [5, 5];
        game.remainingDice.addAll([5, 5]);

        expect(
          game.loopIndex(mover.owner, mover.progress) + 1,
          game.loopIndex(mover.owner, GameEngine.commonPathLength - 2) + 1,
        );
        expect(gate, GameEngine.homeEntryOffset[mover.owner]);
        for (final blockedDie in [1, 2, 3, 4, 6]) {
          expect(
            game.canMove(mover, blockedDie),
            isFalse,
            reason:
                '${mover.owner.name}: the occupied entry blocks $blockedDie',
          );
        }
        expect(game.isHomeEntryCaptureMove(mover, 5), isTrue);
        expect(
          game.destinationProgressFor(mover, 5),
          GameEngine.commonPathLength + 3,
        );
        expect(game.movementCellsFor(mover, 5), [
          GameEngine.loop[gate],
          ...GameEngine.homeLanes[mover.owner]!.take(4),
        ]);

        expect(game.moveToken(mover, die: 5), isTrue);
        expect(mover.progress, GameEngine.commonPathLength + 3);
        expect(game.tokenCell(mover), GameEngine.homeLanes[mover.owner]![3]);
        expect(blocker.inNest, isTrue);
        expect(game.remainingDice, [5, 20]);
        expect(game.message, contains('entrada'));
        game.dispose();
      }
    },
  );

  test('a home entry without a rival uses five as a normal full move', () {
    final game = GameEngine();
    final mover = game.currentPlayer.tokens.first
      ..progress = GameEngine.commonPathLength - 2;
    for (var tokenId = 1; tokenId < 4; tokenId++) {
      game.currentPlayer.tokens[tokenId].progress = tokenId * 10;
    }
    game.hasRolled = true;
    game.dice = [5, 2];
    game.remainingDice.addAll([5, 2]);

    expect(game.isHomeEntryCaptureMove(mover, 5), isFalse);
    expect(game.canMove(mover, 5), isTrue);
    expect(game.moveToken(mover, die: 5), isTrue);
    expect(mover.progress, GameEngine.commonPathLength + 3);
    expect(game.remainingDice, [2]);
    expect(game.message, 'Avanzaste 5.');
  });

  test('two rival pieces at a home entry remain an unbreakable barrier', () {
    for (var playerIndex = 0; playerIndex < 4; playerIndex++) {
      final game = GameEngine();
      game.currentPlayerIndex = playerIndex;
      final mover = game.currentPlayer.tokens.first
        ..progress = GameEngine.commonPathLength - 2;
      for (var tokenId = 1; tokenId < 4; tokenId++) {
        game.currentPlayer.tokens[tokenId].progress = tokenId * 10;
      }
      final gate = GameEngine.homeEntryOffset[mover.owner]!;
      final opponentIndex = (playerIndex + 1) % game.players.length;
      placeOnGlobal(game, opponentIndex, 0, gate);
      placeOnGlobal(game, opponentIndex, 1, gate);
      game.hasRolled = true;
      game.dice = [5, 5];
      game.remainingDice.addAll([5, 5]);

      expect(game.isHomeEntryCaptureMove(mover, 5), isFalse);
      expect(game.canMove(mover, 5), isFalse);
      expect(game.moveToken(mover, die: 5), isFalse);
      expect(mover.progress, GameEngine.commonPathLength - 2);
      expect(game.remainingDice, [5, 5]);
      game.dispose();
    }
  });

  test(
    'the special five only works from the square immediately before entry',
    () {
      final game = GameEngine();
      final mover = game.currentPlayer.tokens.first
        ..progress = GameEngine.commonPathLength - 3;
      for (var tokenId = 1; tokenId < 4; tokenId++) {
        game.currentPlayer.tokens[tokenId].progress = tokenId * 10;
      }
      final gate = GameEngine.homeEntryOffset[mover.owner]!;
      placeOnGlobal(game, 1, 0, gate);
      game.hasRolled = true;
      game.dice = [5, 2];
      game.remainingDice.addAll([5, 2]);

      expect(game.isHomeEntryCaptureMove(mover, 5), isFalse);
      expect(game.canMove(mover, 5), isFalse);
      expect(game.remainingDice, [5, 2]);
    },
  );

  test('SALIDA keeps priority over a home-entry capture with five', () {
    final game = GameEngine();
    final mover = game.currentPlayer.tokens.first
      ..progress = GameEngine.commonPathLength - 2;
    game.currentPlayer.tokens[1].progress = 10;
    game.currentPlayer.tokens[2].progress = 20;
    final nested = game.currentPlayer.tokens[3];
    final gate = GameEngine.homeEntryOffset[mover.owner]!;
    placeOnGlobal(game, 1, 0, gate);
    game.hasRolled = true;
    game.dice = [5, 2];
    game.remainingDice.addAll([5, 2]);

    expect(game.mustUseFiveToLeaveNest(mover.owner), isTrue);
    expect(game.isHomeEntryCaptureMove(mover, 5), isFalse);
    expect(game.canMove(mover, 5), isFalse);
    expect(game.canMove(nested, 5), isTrue);
  });

  test('opponents cannot share any of the twelve safe places', () {
    for (final safe in GameEngine.safeLoopIndices) {
      final game = GameEngine();
      final movingPlayer = safe == GameEngine.startOffset[PlayerColor.red]
          ? 1
          : 0;
      final opponentPlayer = movingPlayer == 0 ? 1 : 0;
      game.currentPlayerIndex = movingPlayer;
      final mover = placeOnGlobal(
        game,
        movingPlayer,
        0,
        (safe - 1) % GameEngine.loopLength,
      );
      final opponent = placeOnGlobal(game, opponentPlayer, 0, safe);
      game.hasRolled = true;
      game.remainingDice.add(1);

      expect(
        game.canMove(mover, 1),
        isFalse,
        reason: 'safe square ${safe + 1} cannot be shared',
      );
      expect(game.moveToken(mover, die: 1), isFalse);
      expect(game.remainingDice, [1]);
      expect(
        game.loopIndex(mover.owner, mover.progress),
        (safe - 1) % GameEngine.loopLength,
      );
      expect(opponent.inNest, isFalse);
    }
  });

  test('a pawn may pass over one opponent standing on a safe place', () {
    final game = GameEngine();
    final red = placeOnGlobal(game, 0, 0, 6);
    final green = placeOnGlobal(game, 1, 0, 7);
    game.hasRolled = true;
    game.remainingDice.addAll([2, 6]);

    expect(game.canMove(red, 2), isTrue);
    expect(game.moveToken(red, die: 2), isTrue);
    expect(game.loopIndex(red.owner, red.progress), 8);
    expect(green.inNest, isFalse);
  });

  test('a five captures one opponent from the owner departure square', () {
    final game = GameEngine();
    final red = game.currentPlayer.tokens.first;
    final green = placeOnGlobal(
      game,
      1,
      0,
      GameEngine.startOffset[PlayerColor.red]!,
    );
    game.hasRolled = true;
    game.remainingDice.add(5);

    expect(game.canMove(red, 5), isTrue);
    expect(game.moveToken(red, die: 5), isTrue);
    expect(red.progress, 0);
    expect(green.inNest, isTrue);
    expect(game.remainingDice, [20]);
    expect(game.message, contains('Capturaste'));
  });

  test('two opponents blockade the owner departure square', () {
    final game = GameEngine();
    final red = game.currentPlayer.tokens.first;
    final departure = GameEngine.startOffset[PlayerColor.red]!;
    placeOnGlobal(game, 1, 0, departure);
    placeOnGlobal(game, 1, 1, departure);
    game.hasRolled = true;
    game.remainingDice.add(5);

    expect(game.canMove(red, 5), isFalse);
    expect(game.moveToken(red, die: 5), isFalse);
    expect(red.inNest, isTrue);
    expect(game.remainingDice, [5]);
  });

  test('one own pawn allows a second pawn to enter and form a blockade', () {
    final game = GameEngine();
    final first = game.currentPlayer.tokens[0]..progress = 0;
    final second = game.currentPlayer.tokens[1];
    game.hasRolled = true;
    game.remainingDice.addAll([5, 1]);

    expect(game.canMove(second, 5), isTrue);
    expect(game.moveToken(second, die: 5), isTrue);
    expect(first.progress, 0);
    expect(second.progress, 0);
    expect(game.remainingDice, [1]);
  });

  test('a two-token barrier cannot be crossed', () {
    final game = GameEngine();
    final red = placeOnGlobal(game, 0, 0, 4);
    placeOnGlobal(game, 1, 0, 6);
    placeOnGlobal(game, 1, 1, 6);
    game.hasRolled = true;
    game.remainingDice.add(3);

    expect(game.canMove(red, 3), isFalse);
  });

  test(
    'a rival barrier cannot be landed on, crossed, or captured on any route',
    () {
      for (var attackerIndex = 0; attackerIndex < 4; attackerIndex++) {
        final defenderIndex = (attackerIndex + 1) % 4;

        for (final die in [3, 4]) {
          final game = GameEngine();
          game.currentPlayerIndex = attackerIndex;
          final mover = game.currentPlayer.tokens.first..progress = 7;
          final barrierLoopIndex = game.loopIndex(mover.owner, 10);
          final firstBarrierToken = placeOnGlobal(
            game,
            defenderIndex,
            0,
            barrierLoopIndex,
          );
          final secondBarrierToken = placeOnGlobal(
            game,
            defenderIndex,
            1,
            barrierLoopIndex,
          );
          final firstBarrierProgress = firstBarrierToken.progress;
          final secondBarrierProgress = secondBarrierToken.progress;
          game.hasRolled = true;
          game.remainingDice.add(die);

          expect(
            game.canMove(mover, die),
            isFalse,
            reason:
                '${mover.owner.name} must not ${die == 3 ? 'land on' : 'cross'} '
                'the ${firstBarrierToken.owner.name} barrier',
          );
          expect(game.moveToken(mover, die: die), isFalse);
          expect(mover.progress, 7);
          expect(firstBarrierToken.progress, firstBarrierProgress);
          expect(secondBarrierToken.progress, secondBarrierProgress);
          expect(firstBarrierToken.inNest, isFalse);
          expect(secondBarrierToken.inNest, isFalse);
          expect(game.remainingDice, [die]);
          game.dispose();
        }
      }
    },
  );

  test('the capture bonus cannot cross or capture a two-token barrier', () {
    final game = GameEngine();
    final mover = game.currentPlayer.tokens.first..progress = 4;
    final barrierLoopIndex = game.loopIndex(mover.owner, 20);
    final firstBarrierToken = placeOnGlobal(game, 1, 0, barrierLoopIndex);
    final secondBarrierToken = placeOnGlobal(game, 1, 1, barrierLoopIndex);
    final firstBarrierProgress = firstBarrierToken.progress;
    final secondBarrierProgress = secondBarrierToken.progress;
    game.hasRolled = true;
    game.remainingDice.add(20);

    expect(game.canMove(mover, 20), isFalse);
    expect(game.moveToken(mover, die: 20), isFalse);
    expect(mover.progress, 4);
    expect(firstBarrierToken.progress, firstBarrierProgress);
    expect(secondBarrierToken.progress, secondBarrierProgress);
    expect(firstBarrierToken.inNest, isFalse);
    expect(secondBarrierToken.inNest, isFalse);
    expect(game.remainingDice, [20]);
    game.dispose();
  });

  test(
    'a five cannot leave the nest through a rival barrier for any color',
    () {
      for (var attackerIndex = 0; attackerIndex < 4; attackerIndex++) {
        final game = GameEngine();
        game.currentPlayerIndex = attackerIndex;
        final nested = game.currentPlayer.tokens.first;
        final defenderIndex = (attackerIndex + 1) % 4;
        final departure = GameEngine.startOffset[nested.owner]!;
        final firstBarrierToken = placeOnGlobal(
          game,
          defenderIndex,
          0,
          departure,
        );
        final secondBarrierToken = placeOnGlobal(
          game,
          defenderIndex,
          1,
          departure,
        );
        final firstBarrierProgress = firstBarrierToken.progress;
        final secondBarrierProgress = secondBarrierToken.progress;
        game.hasRolled = true;
        game.dice = const [5, 5];
        game.remainingDice.addAll([5, 5]);

        expect(game.canMove(nested, 5), isFalse);
        expect(game.moveToken(nested, die: 5), isFalse);
        expect(nested.inNest, isTrue);
        expect(firstBarrierToken.progress, firstBarrierProgress);
        expect(secondBarrierToken.progress, secondBarrierProgress);
        expect(firstBarrierToken.inNest, isFalse);
        expect(secondBarrierToken.inNest, isFalse);
        expect(game.remainingDice, [5, 5]);
        game.dispose();
      }
    },
  );

  test('Turbo stops before a barrier without capturing either token', () {
    final game = chaosGame();
    final mover = game.currentPlayer.tokens.first..progress = 5;
    final barrierLoopIndex = game.loopIndex(mover.owner, 7);
    final firstBarrierToken = placeOnGlobal(game, 1, 0, barrierLoopIndex);
    final secondBarrierToken = placeOnGlobal(game, 1, 1, barrierLoopIndex);
    final firstBarrierProgress = firstBarrierToken.progress;
    final secondBarrierProgress = secondBarrierToken.progress;
    game.currentPlayer.inventory = PowerUp.boost;

    expect(game.usePowerUp(), isTrue);
    expect(mover.progress, 6);
    expect(game.loopIndex(mover.owner, mover.progress), barrierLoopIndex - 1);
    expect(firstBarrierToken.progress, firstBarrierProgress);
    expect(secondBarrierToken.progress, secondBarrierProgress);
    expect(firstBarrierToken.inNest, isFalse);
    expect(secondBarrierToken.inNest, isFalse);
    expect(game.currentPlayer.inventory, isNull);
    game.dispose();
  });

  test('the CPU never selects a move that would hit a rival barrier', () {
    final game = GameEngine(cpuLevel: 'Experto');
    game.currentPlayerIndex = 1;
    final mover = game.currentPlayer.tokens.first..progress = 5;
    final barrierLoopIndex = game.loopIndex(mover.owner, 7);
    final firstBarrierToken = placeOnGlobal(game, 0, 0, barrierLoopIndex);
    final secondBarrierToken = placeOnGlobal(game, 0, 1, barrierLoopIndex);
    game.hasRolled = true;
    game.remainingDice.add(2);

    expect(game.canMove(mover, 2), isFalse);
    expect(game.chooseCpuMove(), isNull);
    expect(firstBarrierToken.inNest, isFalse);
    expect(secondBarrierToken.inNest, isFalse);
    expect(game.remainingDice, [2]);
    game.dispose();
  });

  test('a token can leave its own barrier', () {
    final game = GameEngine();
    final first = placeOnGlobal(game, 0, 0, 4);
    placeOnGlobal(game, 0, 1, 4);
    game.hasRolled = true;
    game.remainingDice.add(1);

    expect(game.canMove(first, 1), isTrue);
  });

  test('traditional mode never awards an item', () {
    final game = GameEngine(mode: GameMode.traditional);
    final red = placeOnGlobal(game, 0, 0, 4);
    game.hasRolled = true;
    game.remainingDice.addAll([1, 6]);

    game.moveToken(red, die: 1);

    expect(game.currentPlayer.inventory, isNull);
    expect(game.traps, isEmpty);
    expect(game.itemLoopIndices, isEmpty);
  });

  test('chaos mode keeps one pickup inside each side range', () {
    final game = chaosGame();

    expect(game.itemLoopIndices, hasLength(4));
    for (final entry in GameEngine.itemLoopRanges.entries) {
      final pickup = game.itemLoopIndexForSide(entry.key);
      expect(pickup, isNotNull, reason: '${entry.key.name} needs a pickup');
      expect(pickup, inInclusiveRange(entry.value.$1, entry.value.$2));
      expect(
        GameEngine.safeLoopIndices,
        isNot(contains(pickup)),
        reason: '${entry.key.name} pickup cannot cover a safe square',
      );
    }

    expect(game.itemLoopIndexForSide(PlayerColor.red), 1);
    expect(game.itemLoopIndexForSide(PlayerColor.green), 18);
    expect(game.itemLoopIndexForSide(PlayerColor.yellow), 35);
    expect(game.itemLoopIndexForSide(PlayerColor.blue), 52);
  });

  test('collecting a pickup respawns it elsewhere on the same side', () {
    final game = chaosGame();
    final originalPickups = Set<int>.of(game.itemLoopIndices);
    final redPickup = game.itemLoopIndexForSide(PlayerColor.red)!;
    final red = placeOnGlobal(game, 0, 0, redPickup - 1);
    game.hasRolled = true;
    game.remainingDice.addAll([1, 6]);
    final previousEffectSerial = game.effectSerial;

    expect(game.moveToken(red, die: 1), isTrue);

    final replacement = game.itemLoopIndexForSide(PlayerColor.red)!;
    expect(game.currentPlayer.inventory, PowerUp.shield);
    expect(game.effectSerial, previousEffectSerial + 1);
    expect(game.effectLoopIndex, redPickup);
    expect(game.effectPowerUp, PowerUp.shield);
    expect(game.effectKind, PowerEffectKind.pickup);
    expect(replacement, isNot(redPickup));
    expect(replacement, inInclusiveRange(1, 16));
    expect(game.itemLoopIndices, hasLength(4));
    expect(game.itemLoopIndexForSide(PlayerColor.green), 18);
    expect(game.itemLoopIndexForSide(PlayerColor.yellow), 35);
    expect(game.itemLoopIndexForSide(PlayerColor.blue), 52);
    expect(game.itemLoopIndices.difference(originalPickups), {replacement});
    expect(originalPickups.difference(game.itemLoopIndices), {redPickup});
  });

  for (final heldPower in const [PowerUp.shield, PowerUp.boost]) {
    test(
      'a stored ${heldPower.name} does not block an automatic trap pickup',
      () {
        final game = chaosGame(randomValues: [0, 0, 0, 0, 3, 0]);
        final redPickup = game.itemLoopIndexForSide(PlayerColor.red)!;
        final red = placeOnGlobal(game, 0, 0, redPickup - 1);
        game.currentPlayer.inventory = heldPower;
        game.hasRolled = true;
        game.remainingDice.addAll([1, 6]);

        expect(game.moveToken(red, die: 1), isTrue);

        final ownedTraps = game.traps
            .where((trap) => trap.owner == PlayerColor.red)
            .toList();
        expect(game.currentPlayer.inventory, heldPower);
        expect(ownedTraps, hasLength(1));
        expect(ownedTraps.single.type, PowerUp.bomb);
        expect(ownedTraps.single.loopIndex, redPickup);
        expect(game.itemLoopIndices, isNot(contains(redPickup)));
        expect(game.itemLoopIndexForSide(PlayerColor.red), isNot(redPickup));
        expect(game.itemLoopIndices, hasLength(4));
        game.dispose();
      },
    );
  }

  test('Turbo can collect and keep a new power-up on landing', () {
    final game = chaosGame(randomValues: [4, 0, 0, 0, 1, 0]);
    final pickup = game.itemLoopIndexForSide(PlayerColor.red)!;
    final red = placeOnGlobal(game, 0, 0, pickup - 3);
    game.currentPlayer.inventory = PowerUp.boost;

    expect(game.usePowerUp(), isTrue);

    expect(game.loopIndex(PlayerColor.red, red.progress), pickup);
    expect(game.currentPlayer.inventory, PowerUp.boost);
    expect(game.effectKind, PowerEffectKind.pickup);
    expect(game.itemLoopIndexForSide(PlayerColor.red), isNot(pickup));
  });

  for (final entry in const {PowerUp.bomb: 5, PowerUp.setbackTrap: 3}.entries) {
    test(
      'collecting ${entry.key.name} leaves it hidden on the pickup square',
      () {
        final game = chaosGame(randomValues: [0, 0, 0, 0, entry.value, 0]);
        final pickup = game.itemLoopIndexForSide(PlayerColor.red)!;
        final red = placeOnGlobal(game, 0, 0, pickup - 1);
        game.hasRolled = true;
        game.remainingDice.addAll([1, 6]);

        expect(game.moveToken(red, die: 1), isTrue);

        final trap = game.activeTrapFor(PlayerColor.red);
        expect(game.currentPlayer.inventory, isNull);
        expect(trap, isNotNull);
        expect(trap!.owner, PlayerColor.red);
        expect(trap.type, entry.key);
        expect(trap.loopIndex, pickup);
        expect(game.visibleTrapsFor(PlayerColor.red), [trap]);
        expect(game.visibleTrapsFor(PlayerColor.green), isEmpty);
        expect(game.itemLoopIndices, isNot(contains(pickup)));
        expect(game.itemLoopIndexForSide(PlayerColor.red), 2);
        expect(game.itemLoopIndices, hasLength(4));
      },
    );
  }

  test('a prison trap returns an opponent to the nest', () {
    final game = chaosGame();
    game.traps.add(
      const BoardTrap(
        owner: PlayerColor.red,
        type: PowerUp.prisonTrap,
        loopIndex: 6,
      ),
    );

    game.currentPlayerIndex = 1;
    final green = placeOnGlobal(game, 1, 0, 5);
    game.hasRolled = true;
    game.remainingDice.addAll([1, 6]);

    game.moveToken(green, die: 1);

    expect(green.inNest, isTrue);
    expect(game.traps, isEmpty);
    expect(game.message, contains('TRAMPA CÁRCEL'));
  });

  test('traditional mode rejects power-up use', () {
    final game = GameEngine(mode: GameMode.traditional);
    game.currentPlayer.inventory = PowerUp.shield;

    expect(game.usePowerUp(), isFalse);
    expect(game.currentPlayer.shielded, isFalse);
  });

  test(
    'a stored shield stays ready instead of requiring manual activation',
    () {
      final game = chaosGame();
      game.currentPlayer.inventory = PowerUp.shield;

      expect(game.usePowerUp(), isTrue);

      expect(game.currentPlayer.inventory, PowerUp.shield);
      expect(game.currentPlayer.shielded, isFalse);
      expect(game.message, contains('automáticamente'));
      game.dispose();
    },
  );

  for (final trapType in const [
    PowerUp.glueTrap,
    PowerUp.setbackTrap,
    PowerUp.prisonTrap,
    PowerUp.bomb,
  ]) {
    final tokenId = trapType.index - PowerUp.glueTrap.index;
    test('a stored shield automatically protects token ${tokenId + 1} '
        'from ${trapType.name}', () {
      final game = chaosGame();
      game.traps.add(
        BoardTrap(owner: PlayerColor.red, type: trapType, loopIndex: 20),
      );
      game.currentPlayerIndex = 1;
      final green = placeOnGlobal(game, 1, tokenId, 19);
      final landingProgress = green.progress + 1;
      game.currentPlayer.inventory = PowerUp.shield;
      game.hasRolled = true;
      game.dice = [1, 5];
      game.remainingDice.addAll([1, 5]);

      expect(game.moveToken(green, die: 1), isTrue);

      expect(green.progress, landingProgress);
      expect(green.inNest, isFalse);
      expect(game.currentPlayer.skippedTurns, 0);
      expect(game.currentPlayer.inventory, isNull);
      expect(game.currentPlayer.shielded, isFalse);
      expect(game.traps, isEmpty);
      expect(game.effectPowerUp, PowerUp.shield);
      expect(game.effectKind, PowerEffectKind.blocked);
      expect(game.effectToken, same(green));
      expect(game.effectLoopIndex, 20);
      expect(game.effectResolving, isTrue);
      expect(game.message, contains('¡PROTEGIDO!'));
      expect(game.remainingDice, [5]);
      game.dispose();
    });
  }

  for (final blockedTrap in const [PowerUp.glueTrap, PowerUp.bomb]) {
    test(
      'landing on ${blockedTrap.name} never leaves its owner sharing the square',
      () {
        final game = chaosGame();
        final trapOwner = placeOnGlobal(game, 0, 0, 20);
        game.traps.add(
          BoardTrap(owner: PlayerColor.red, type: blockedTrap, loopIndex: 20),
        );
        game.currentPlayerIndex = 1;
        final mover = placeOnGlobal(game, 1, 0, 19);
        if (blockedTrap == PowerUp.bomb) {
          game.currentPlayer.inventory = PowerUp.shield;
        }
        game.hasRolled = true;
        game.dice = [1, 5];
        game.remainingDice.addAll([1, 5]);

        expect(game.moveToken(mover, die: 1), isTrue);

        expect(trapOwner.inNest, isTrue);
        expect(mover.inNest, isFalse);
        expect(game.loopIndex(mover.owner, mover.progress), 20);
        expect(game.remainingDice, contains(20));
        expect(
          game.players
              .expand((player) => player.tokens)
              .where(
                (token) =>
                    !token.inNest &&
                    !token.finished &&
                    token.progress < GameEngine.commonPathLength &&
                    game.loopIndex(token.owner, token.progress) == 20,
              )
              .map((token) => token.owner)
              .toSet(),
          {PlayerColor.green},
        );
        game.dispose();
      },
    );
  }

  test(
    'a player can leave multiple automatic traps on successive crystals',
    () {
      final game = chaosGame(randomValues: [0, 0, 0, 0, 5, 0, 3, 0]);
      final red = game.currentPlayer.tokens.first;
      final firstPickup = game.itemLoopIndexForSide(PlayerColor.red)!;
      placeOnGlobal(game, 0, red.id, firstPickup - 1);
      game.hasRolled = true;
      game.remainingDice.addAll([1, 6]);

      expect(game.moveToken(red, die: 1), isTrue);
      final secondPickup = game.itemLoopIndexForSide(PlayerColor.red)!;

      placeOnGlobal(game, 0, red.id, secondPickup - 1);
      game.hasRolled = true;
      game.remainingDice
        ..clear()
        ..addAll([1, 6]);
      expect(game.moveToken(red, die: 1), isTrue);

      final ownedTraps = game.traps
          .where((trap) => trap.owner == PlayerColor.red)
          .toList();
      expect(ownedTraps, hasLength(2));
      expect(ownedTraps.map((trap) => (trap.type, trap.loopIndex)).toList(), [
        (PowerUp.bomb, firstPickup),
        (PowerUp.setbackTrap, secondPickup),
      ]);
      expect(game.currentPlayer.inventory, isNull);
      expect(game.itemLoopIndices, isNot(contains(firstPickup)));
      expect(game.itemLoopIndices, isNot(contains(secondPickup)));
      expect(game.itemLoopIndexForSide(PlayerColor.red), isNot(secondPickup));
      expect(game.itemLoopIndices, hasLength(4));
      game.dispose();
    },
  );

  test('only a trap owner can see its hidden square', () {
    final game = chaosGame();
    game.traps.addAll(const [
      BoardTrap(owner: PlayerColor.red, type: PowerUp.bomb, loopIndex: 6),
      BoardTrap(owner: PlayerColor.red, type: PowerUp.glueTrap, loopIndex: 9),
      BoardTrap(
        owner: PlayerColor.green,
        type: PowerUp.setbackTrap,
        loopIndex: 20,
      ),
    ]);

    expect(game.localViewerColor, PlayerColor.red);
    expect(
      game.visibleTrapsFor(PlayerColor.red).map((trap) => trap.loopIndex),
      [6, 9],
    );
    expect(
      game.visibleTrapsFor(PlayerColor.green).map((trap) => trap.loopIndex),
      [20],
    );
    expect(game.visibleTrapsFor(PlayerColor.yellow), isEmpty);
    expect(game.visibleTrapsFor(PlayerColor.blue), isEmpty);
  });

  test('an armed bomb returns an opponent to the nest', () {
    final game = chaosGame();
    final green = placeOnGlobal(game, 1, 0, 19);
    game.traps.add(
      const BoardTrap(
        owner: PlayerColor.red,
        type: PowerUp.bomb,
        loopIndex: 20,
      ),
    );
    expect(game.traps.single.owner, PlayerColor.red);
    expect(game.traps.single.type, PowerUp.bomb);
    expect(game.traps.single.loopIndex, 20);

    game.currentPlayerIndex = 1;
    game.hasRolled = true;
    game.dice = [1, 5];
    game.remainingDice.addAll([1, 5]);
    final previousEffectSerial = game.effectSerial;

    expect(game.moveToken(green, die: 1), isTrue);

    expect(green.inNest, isTrue);
    expect(game.traps, isEmpty);
    expect(game.remainingDice, [5]);
    expect(game.effectSerial, previousEffectSerial + 1);
    expect(game.effectLoopIndex, 20);
    expect(game.effectPowerUp, PowerUp.bomb);
    expect(game.effectKind, PowerEffectKind.triggered);
    expect(game.effectToken, same(green));
    expect(game.effectResolving, isTrue);
    expect(game.message, '¡BOMBA! CPU 1 volvió a la cárcel.');
  });

  test('a setback trap lands first and moves the victim back six steps', () {
    final game = chaosGame();
    game.traps.add(
      const BoardTrap(
        owner: PlayerColor.red,
        type: PowerUp.setbackTrap,
        loopIndex: 26,
      ),
    );

    game.currentPlayerIndex = 1;
    final green = placeOnGlobal(game, 1, 0, 25);
    expect(green.progress, 8);
    game.hasRolled = true;
    game.dice = [1, 5];
    game.remainingDice.addAll([1, 5]);
    final previousEffectSerial = game.effectSerial;

    expect(game.moveToken(green, die: 1), isTrue);

    expect(green.progress, 3);
    expect(game.loopIndex(PlayerColor.green, green.progress), 20);
    expect(game.traps, isEmpty);
    expect(game.remainingDice, [5]);
    expect(game.effectSerial, previousEffectSerial + 1);
    expect(game.effectLoopIndex, 26);
    expect(game.effectPowerUp, PowerUp.setbackTrap);
    expect(game.effectKind, PowerEffectKind.triggered);
    expect(game.effectToken, same(green));
    expect(game.effectResolving, isTrue);
    expect(game.message, '¡RETROCESO! CPU 1 retrocedió 6 pasos.');
  });

  test('setback stops before a barrier instead of crossing it', () {
    final game = chaosGame();
    game.traps.add(
      const BoardTrap(
        owner: PlayerColor.red,
        type: PowerUp.setbackTrap,
        loopIndex: 26,
      ),
    );
    placeOnGlobal(game, 0, 0, 23);
    placeOnGlobal(game, 0, 1, 23);
    game.currentPlayerIndex = 1;
    final mover = placeOnGlobal(game, 1, 0, 25);
    game.hasRolled = true;
    game.dice = [1, 5];
    game.remainingDice.addAll([1, 5]);

    expect(game.moveToken(mover, die: 1), isTrue);

    expect(game.loopIndex(mover.owner, mover.progress), 24);
    expect(game.message, contains('retrocedió 2 pasos'));
    game.dispose();
  });

  test('setback uses the nearest legal square before an occupied safe', () {
    final game = chaosGame();
    game.traps.add(
      const BoardTrap(
        owner: PlayerColor.red,
        type: PowerUp.setbackTrap,
        loopIndex: 30,
      ),
    );
    final safeOccupant = placeOnGlobal(game, 0, 0, 24);
    game.currentPlayerIndex = 1;
    final mover = placeOnGlobal(game, 1, 0, 29);
    game.hasRolled = true;
    game.dice = [1, 5];
    game.remainingDice.addAll([1, 5]);

    expect(GameEngine.safeLoopIndices, contains(24));
    expect(game.moveToken(mover, die: 1), isTrue);

    expect(game.loopIndex(mover.owner, mover.progress), 25);
    expect(safeOccupant.inNest, isFalse);
    expect(game.loopIndex(safeOccupant.owner, safeOccupant.progress), 24);
    game.dispose();
  });

  test(
    'setback leaves the piece in place when a barrier is immediately behind',
    () {
      final game = chaosGame();
      game.traps.add(
        const BoardTrap(
          owner: PlayerColor.red,
          type: PowerUp.setbackTrap,
          loopIndex: 20,
        ),
      );
      placeOnGlobal(game, 0, 0, 19);
      placeOnGlobal(game, 0, 1, 19);
      game.currentPlayerIndex = 1;
      final mover = placeOnGlobal(game, 1, 0, 19);
      game.hasRolled = true;
      game.dice = [1, 5];
      game.remainingDice.addAll([1, 5]);

      expect(game.moveToken(mover, die: 1), isTrue);

      expect(game.loopIndex(mover.owner, mover.progress), 20);
      expect(game.message, contains('retrocedió 0 pasos'));
      game.dispose();
    },
  );

  test('only one trap can affect the same player during one turn', () {
    final game = chaosGame();
    game.traps.addAll(const [
      BoardTrap(owner: PlayerColor.red, type: PowerUp.glueTrap, loopIndex: 20),
      BoardTrap(owner: PlayerColor.red, type: PowerUp.bomb, loopIndex: 24),
    ]);
    game.currentPlayerIndex = 1;
    final first = placeOnGlobal(game, 1, 0, 19);
    final second = placeOnGlobal(game, 1, 1, 23);
    game.hasRolled = true;
    game.dice = [1, 1];
    game.remainingDice.addAll([1, 1]);

    expect(game.moveToken(first, die: 1), isTrue);
    expect(game.currentPlayer.skippedTurns, 1);
    game.effectResolving = false;
    expect(game.moveToken(second, die: 1), isTrue);

    expect(second.inNest, isFalse);
    expect(game.loopIndex(second.owner, second.progress), 24);
    expect(game.traps, hasLength(1));
    expect(game.traps.single.type, PowerUp.bomb);
    expect(game.traps.single.loopIndex, 24);
    game.dispose();
  });

  test('glue clearly skips a doubled extra turn', () {
    final game = chaosGame();
    game.currentPlayerIndex = 1;
    game.currentPlayer.skippedTurns = 1;
    game.dice = [3, 3];

    game.endTurn();

    expect(game.currentPlayer.name, 'CPU 2');
    expect(game.players[1].skippedTurns, 0);
    expect(game.message, contains('CPU 1 perdió su turno por el pegamento'));
    expect(game.message, contains('Turno de CPU 2'));
    expect(game.message, isNot(contains('CPU 2 sacó dobles')));
  });

  test('glue resets the doubles chain when it cancels the repeat roll', () {
    final game = chaosGame(randomValues: [0, 0, 0, 0, 2, 2]);
    game.currentPlayerIndex = 1;
    game.currentPlayer.skippedTurns = 1;
    game.consecutiveDoubles = 1;
    game.dice = [3, 3];

    game.endTurn();

    expect(game.currentPlayer.color, PlayerColor.yellow);
    expect(game.consecutiveDoubles, 0);

    game.roll();

    expect(game.dice, [3, 3]);
    expect(game.consecutiveDoubles, 1);
    expect(
      game.eventHistory.where(
        (event) => event.type == GameEventType.threeDoublesPenalty,
      ),
      isEmpty,
    );
    game.dispose();
  });

  test('chosen dice can be split between two different tokens', () {
    final game = GameEngine();
    final first = game.currentPlayer.tokens[0]..progress = 0;
    final second = game.currentPlayer.tokens[1]..progress = 10;
    game.hasRolled = true;
    game.dice = [2, 3];
    game.remainingDice.addAll([2, 3]);

    expect(game.legalDieValuesFor(first), [2, 3]);
    expect(game.moveToken(first, die: 2), isTrue);
    expect(first.progress, 2);
    expect(game.remainingDice, [3]);

    expect(game.legalDieValuesFor(second), [3]);
    expect(game.moveToken(second, die: 3), isTrue);
    expect(second.progress, 13);
    expect(game.remainingDice, isEmpty);
  });

  test('an explicit illegal die never consumes another die', () {
    final game = GameEngine();
    final token = game.currentPlayer.tokens.first..progress = 4;
    game.hasRolled = true;
    game.dice = [2, 3];
    game.remainingDice.addAll([2, 3]);

    expect(game.moveToken(token, die: 6), isFalse);
    expect(token.progress, 4);
    expect(game.remainingDice, [2, 3]);
  });

  test('different legal dice require an explicit choice', () {
    final game = GameEngine();
    final token = game.currentPlayer.tokens.first..progress = 4;
    game.hasRolled = true;
    game.dice = [2, 3];
    game.remainingDice.addAll([2, 3]);

    expect(game.moveToken(token), isFalse);
    expect(token.progress, 4);
    expect(game.remainingDice, [2, 3]);
  });

  test('double dice show one value but consume one copy at a time', () {
    final game = GameEngine();
    final token = game.currentPlayer.tokens.first..progress = 4;
    game.hasRolled = true;
    game.dice = [3, 3];
    game.remainingDice.addAll([3, 3]);

    expect(game.legalDieValuesFor(token), [3]);
    expect(game.moveToken(token), isTrue);
    expect(token.progress, 7);
    expect(game.remainingDice, [3]);
  });

  group('using both physical dice on one token', () {
    test('moves by the total and consumes both dice atomically', () {
      final game = GameEngine();
      final token = game.currentPlayer.tokens.first..progress = 4;
      game.hasRolled = true;
      game.dice = [2, 3];
      game.remainingDice.addAll([2, 3]);

      expect(game.allDiceTotalFor(token), 5);
      expect(game.canMoveUsingAllDice(token), isTrue);
      expect(game.destinationProgressUsingAllDice(token), 9);

      expect(game.moveTokenUsingAllDice(token), isTrue);
      expect(token.progress, 9);
      expect(game.remainingDice, isEmpty);
      expect(
        game.message.toLowerCase(),
        anyOf(contains('todos'), contains('ambos dados')),
      );
      final movement = game.eventHistory.lastWhere(
        (event) => event.type == GameEventType.move,
      );
      expect(movement.fromProgress, 4);
      expect(movement.toProgress, 9);
      expect(
        movement.description.toLowerCase(),
        anyOf(contains('todos'), contains('ambos dados')),
      );
      game.dispose();
    });

    test('is available only while both original physical dice remain', () {
      final game = GameEngine();
      final token = game.currentPlayer.tokens.first..progress = 4;
      game.hasRolled = true;
      game.dice = [2, 3];
      game.remainingDice.addAll([2, 3]);

      expect(game.moveToken(token, die: 2), isTrue);
      expect(game.remainingDice, [3]);
      expect(game.allDiceTotalFor(token), isNull);
      expect(game.canMoveUsingAllDice(token), isFalse);
      expect(game.destinationProgressUsingAllDice(token), isNull);
      expect(game.moveTokenUsingAllDice(token), isFalse);
      expect(token.progress, 6);
      expect(game.remainingDice, [3]);
      game.dispose();

      final bonusGame = GameEngine();
      final bonusToken = bonusGame.currentPlayer.tokens.first..progress = 4;
      bonusGame.hasRolled = true;
      bonusGame.dice = [2, 3];
      bonusGame.remainingDice.addAll([2, 3, 20]);

      expect(bonusGame.allDiceTotalFor(bonusToken), isNull);
      expect(bonusGame.canMoveUsingAllDice(bonusToken), isFalse);
      expect(bonusGame.moveTokenUsingAllDice(bonusToken), isFalse);
      expect(bonusToken.progress, 4);
      expect(bonusGame.remainingDice, [2, 3, 20]);
      bonusGame.dispose();
    });

    test('cannot cross or land on a two-token rival barrier', () {
      for (final barrierProgress in [6, 7]) {
        final game = GameEngine();
        final mover = game.currentPlayer.tokens.first..progress = 4;
        final barrierLoopIndex = game.loopIndex(mover.owner, barrierProgress);
        final firstBarrierToken = placeOnGlobal(game, 1, 0, barrierLoopIndex);
        final secondBarrierToken = placeOnGlobal(game, 1, 1, barrierLoopIndex);
        game.hasRolled = true;
        game.dice = [1, 2];
        game.remainingDice.addAll([1, 2]);

        expect(
          game.canMoveUsingAllDice(mover),
          isFalse,
          reason: barrierProgress == 6
              ? 'the combined route must not cross a barrier'
              : 'the combined route must not land on a barrier',
        );
        expect(game.destinationProgressUsingAllDice(mover), isNull);
        expect(game.moveTokenUsingAllDice(mover), isFalse);
        expect(mover.progress, 4);
        expect(firstBarrierToken.inNest, isFalse);
        expect(secondBarrierToken.inNest, isFalse);
        expect(game.remainingDice, [1, 2]);
        game.dispose();
      }
    });

    test('does not bypass a five reserved for mandatory SALIDA', () {
      final game = GameEngine();
      final outside = game.currentPlayer.tokens.first..progress = 4;
      final nested = game.currentPlayer.tokens[1];
      game.hasRolled = true;
      game.dice = [5, 2];
      game.remainingDice.addAll([5, 2]);

      expect(game.mustUseFiveToLeaveNest(PlayerColor.red), isTrue);
      expect(game.canMove(outside, 2), isTrue);
      expect(game.canMove(nested, 5), isTrue);
      expect(game.allDiceTotalFor(outside), isNull);
      expect(game.allDiceTotalFor(nested), isNull);
      expect(game.canMoveUsingAllDice(outside), isFalse);
      expect(game.canMoveUsingAllDice(nested), isFalse);
      expect(game.moveTokenUsingAllDice(outside), isFalse);
      expect(outside.progress, 4);
      expect(nested.inNest, isTrue);
      expect(game.remainingDice, [5, 2]);
      game.dispose();
    });

    test('a 2 + 3 total is not a physical five at an occupied entry', () {
      final game = GameEngine();
      final mover = game.currentPlayer.tokens.first
        ..progress = GameEngine.commonPathLength - 2;
      for (var tokenId = 1; tokenId < 4; tokenId++) {
        game.currentPlayer.tokens[tokenId].progress = tokenId * 10;
      }
      final gate = GameEngine.homeEntryOffset[mover.owner]!;
      final blocker = placeOnGlobal(game, 1, 0, gate);
      game.hasRolled = true;
      game.dice = [2, 3];
      game.remainingDice.addAll([2, 3]);

      expect(game.isHomeEntryCaptureMove(mover, 5), isTrue);
      expect(game.allDiceTotalFor(mover), isNull);
      expect(game.canMoveUsingAllDice(mover), isFalse);
      expect(game.moveTokenUsingAllDice(mover), isFalse);
      expect(mover.progress, GameEngine.commonPathLength - 2);
      expect(blocker.inNest, isFalse);
      expect(game.remainingDice, [2, 3]);
      game.dispose();
    });

    test('requires an exact combined total to reach the goal', () {
      final exactGame = GameEngine();
      final exactToken = exactGame.currentPlayer.tokens.first
        ..progress = GameEngine.finishProgress - 5;
      exactGame.hasRolled = true;
      exactGame.dice = [2, 3];
      exactGame.remainingDice.addAll([2, 3]);

      expect(exactGame.allDiceTotalFor(exactToken), 5);
      expect(
        exactGame.destinationProgressUsingAllDice(exactToken),
        GameEngine.finishProgress,
      );
      expect(exactGame.moveTokenUsingAllDice(exactToken), isTrue);
      expect(exactToken.finished, isTrue);
      expect(exactGame.remainingDice, [10]);
      exactGame.dispose();

      final overshootGame = GameEngine();
      final overshootToken = overshootGame.currentPlayer.tokens.first
        ..progress = GameEngine.finishProgress - 4;
      overshootGame.hasRolled = true;
      overshootGame.dice = [2, 3];
      overshootGame.remainingDice.addAll([2, 3]);

      expect(overshootGame.legalDieValuesFor(overshootToken), [2, 3]);
      expect(overshootGame.allDiceTotalFor(overshootToken), isNull);
      expect(
        overshootGame.destinationProgressUsingAllDice(overshootToken),
        isNull,
      );
      expect(overshootGame.moveTokenUsingAllDice(overshootToken), isFalse);
      expect(overshootToken.progress, GameEngine.finishProgress - 4);
      expect(overshootGame.remainingDice, [2, 3]);
      overshootGame.dispose();
    });

    test('doubles keep the individual choice and also offer their sum', () {
      final game = GameEngine();
      final token = game.currentPlayer.tokens.first..progress = 4;
      game.hasRolled = true;
      game.dice = [3, 3];
      game.remainingDice.addAll([3, 3]);

      expect(game.legalDieValuesFor(token), [3]);
      expect(game.allDiceTotalFor(token), 6);
      expect(game.canMoveUsingAllDice(token), isTrue);
      expect(game.moveTokenUsingAllDice(token), isTrue);
      expect(token.progress, 10);
      expect(game.remainingDice, isEmpty);
      game.dispose();
    });

    test('CPU still finds a token when only the combined total is legal', () {
      final game = GameEngine(cpuLevel: 'Experto');
      game.currentPlayerIndex = 1;
      final mover = game.currentPlayer.tokens.first..progress = 6;
      final firstSafeBlocker = placeOnGlobal(game, 0, 0, 24);
      final secondSafeBlocker = placeOnGlobal(game, 0, 1, 29);
      game.hasRolled = true;
      game.dice = [1, 6];
      game.remainingDice.addAll([1, 6]);

      expect(GameEngine.safeLoopIndices, containsAll([24, 29]));
      expect(game.loopIndex(mover.owner, mover.progress), 23);
      expect(game.legalDiceFor(mover), isEmpty);
      expect(game.allDiceTotalFor(mover), 7);
      expect(game.canMoveUsingAllDice(mover), isTrue);
      expect(game.hasAnyMove(), isTrue);
      expect(game.chooseCpuMove(), same(mover));
      expect(firstSafeBlocker.inNest, isFalse);
      expect(secondSafeBlocker.inNest, isFalse);
      game.dispose();
    });

    test('captures only an opponent on the final combined destination', () {
      final game = GameEngine();
      final mover = game.currentPlayer.tokens.first..progress = 0;
      final intermediateOpponent = placeOnGlobal(game, 1, 0, 2);
      final finalOpponent = placeOnGlobal(game, 2, 0, 5);
      final intermediateProgress = intermediateOpponent.progress;
      game.hasRolled = true;
      game.dice = [2, 3];
      game.remainingDice.addAll([2, 3]);

      expect(game.moveTokenUsingAllDice(mover), isTrue);
      expect(mover.progress, 5);
      expect(intermediateOpponent.progress, intermediateProgress);
      expect(intermediateOpponent.inNest, isFalse);
      expect(finalOpponent.inNest, isTrue);
      expect(game.remainingDice, [20]);
      final captures = game.eventHistory
          .where((event) => event.type == GameEventType.capture)
          .toList();
      expect(captures, hasLength(1));
      expect(captures.single.targetColor, PlayerColor.yellow);
      game.dispose();
    });

    test('triggers only a trap on the final combined destination', () {
      final game = chaosGame();
      final mover = game.currentPlayer.tokens.first..progress = 0;
      game.traps.addAll(const [
        BoardTrap(
          owner: PlayerColor.green,
          type: PowerUp.glueTrap,
          loopIndex: 2,
        ),
        BoardTrap(owner: PlayerColor.green, type: PowerUp.bomb, loopIndex: 5),
      ]);
      game.hasRolled = true;
      game.dice = [2, 3];
      game.remainingDice.addAll([2, 3]);

      expect(game.moveTokenUsingAllDice(mover), isTrue);
      expect(mover.inNest, isTrue);
      expect(game.traps.map((trap) => trap.loopIndex), [2]);
      expect(game.effectLoopIndex, 5);
      expect(game.effectPowerUp, PowerUp.bomb);
      expect(game.effectKind, PowerEffectKind.triggered);
      expect(game.message, '¡BOMBA! Tú volvió a la cárcel.');
      game.dispose();
    });
  });

  group('authoritative viewer and checkpoint support', () {
    const names = <PlayerColor, String>{
      PlayerColor.red: 'Roja',
      PlayerColor.green: 'Verde',
      PlayerColor.yellow: 'Amarilla',
      PlayerColor.blue: 'Azul',
    };

    test('an arbitrary local color and opening-roll winner are respected', () {
      final game = GameEngine(
        localViewerColor: PlayerColor.green,
        initialPlayerColor: PlayerColor.yellow,
        playerNames: names,
      );

      expect(game.localViewerColor, PlayerColor.green);
      expect(
        game.players.where((player) => player.isHuman).single.color,
        PlayerColor.green,
      );
      expect(<PlayerColor, String>{
        for (final player in game.players) player.color: player.name,
      }, names);
      expect(game.initialPlayerColor, PlayerColor.yellow);
      expect(game.currentPlayer.color, PlayerColor.yellow);
      expect(game.message, 'Turno de Amarilla.');

      game.dice = const <int>[2, 3];
      game.endTurn();
      expect(game.currentPlayer.color, PlayerColor.blue);
      game.dispose();
    });

    test('legacy constructor defaults remain red and keep CPU name order', () {
      final game = GameEngine(
        humanName: 'Local',
        cpuNames: const <String>['Uno', 'Dos', 'Tres'],
      );

      expect(game.localViewerColor, PlayerColor.red);
      expect(game.initialPlayerColor, PlayerColor.red);
      expect(game.currentPlayer.color, PlayerColor.red);
      expect(game.players.map((player) => player.name), <String>[
        'Local',
        'Uno',
        'Dos',
        'Tres',
      ]);
      game.dispose();
    });

    test('checkpoint restore accepts a requested local viewer color', () {
      final source = GameEngine(
        initialPlayerColor: PlayerColor.blue,
        playerNames: names,
      );
      final restored = GameEngine.fromCheckpoint(
        Map<String, dynamic>.from(source.createCheckpoint()),
        localViewerColor: PlayerColor.green,
      );

      expect(restored.localViewerColor, PlayerColor.green);
      expect(
        restored.players.where((player) => player.isHuman).single.color,
        PlayerColor.green,
      );
      expect(restored.initialPlayerColor, PlayerColor.blue);
      expect(restored.currentPlayer.color, PlayerColor.blue);
      expect(restored.players.map((player) => player.name), names.values);

      restored.dispose();
      source.dispose();
    });

    test('a complete checkpoint applies atomically to a remote replica', () {
      final source = GameEngine(
        mode: GameMode.chaos,
        matchFormat: MatchFormat.quickPop,
        localViewerColor: PlayerColor.yellow,
        initialPlayerColor: PlayerColor.blue,
        playerNames: names,
        random: _SequenceRandom(<int>[1, 2, 3, 4]),
      );
      source
        ..turnNumber = 9
        ..dice = const <int>[4, 6]
        ..rollSerial = 5
        ..hasRolled = true
        ..message = 'Estado confirmado por el servidor.';
      source.remainingDice.addAll(const <int>[4, 6]);
      source.players[PlayerColor.blue.index]
        ..inventory = PowerUp.boost
        ..shielded = true
        ..skippedTurns = 1;
      source.players[PlayerColor.blue.index].tokens.first.progress = 12;
      source.traps.add(
        const BoardTrap(
          owner: PlayerColor.yellow,
          type: PowerUp.glueTrap,
          loopIndex: 31,
        ),
      );

      final checkpoint = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(source.createCheckpoint()))
            as Map<String, dynamic>,
      );
      final replica = GameEngine(
        mode: GameMode.chaos,
        matchFormat: MatchFormat.quickPop,
        localViewerColor: PlayerColor.green,
        playerNames: const <PlayerColor, String>{
          PlayerColor.red: 'Anterior 1',
          PlayerColor.green: 'Anterior 2',
          PlayerColor.yellow: 'Anterior 3',
          PlayerColor.blue: 'Anterior 4',
        },
      );
      var notifications = 0;
      replica.addListener(() => notifications++);

      replica.applyRemoteCheckpoint(checkpoint);

      expect(notifications, 1);
      expect(replica.localViewerColor, PlayerColor.green);
      expect(replica.initialPlayerColor, PlayerColor.blue);
      expect(replica.currentPlayer.color, PlayerColor.blue);
      expect(replica.turnNumber, 9);
      expect(replica.dice, <int>[4, 6]);
      expect(replica.remainingDice, <int>[4, 6]);
      expect(replica.rollSerial, 5);
      expect(replica.hasRolled, isTrue);
      expect(replica.message, 'Estado confirmado por el servidor.');
      expect(replica.players.map((player) => player.name), names.values);
      expect(replica.players[PlayerColor.blue.index].tokens.first.progress, 12);
      expect(replica.players[PlayerColor.blue.index].inventory, PowerUp.boost);
      expect(replica.players[PlayerColor.blue.index].shielded, isTrue);
      expect(replica.players[PlayerColor.blue.index].skippedTurns, 1);
      expect(replica.itemLoopIndices, source.itemLoopIndices);
      expect(
        replica.traps.map((trap) => (trap.owner, trap.type, trap.loopIndex)),
        source.traps.map((trap) => (trap.owner, trap.type, trap.loopIndex)),
      );
      expect(
        replica.eventHistory.map((event) => event.sequence),
        source.eventHistory.map((event) => event.sequence),
      );

      replica.dispose();
      source.dispose();
    });

    testWidgets('a remote replica never advances a server transition locally', (
      tester,
    ) async {
      final authority = GameEngine()
        ..turnNumber = 4
        ..hasRolled = true
        ..dice = const <int>[1, 2];
      final replica = GameEngine();

      replica.applyRemoteCheckpoint(
        Map<String, dynamic>.from(authority.createCheckpoint()),
      );
      await tester.pump(const Duration(milliseconds: 1));

      expect(replica.currentPlayer.color, PlayerColor.red);
      expect(replica.turnNumber, 4);
      expect(replica.hasRolled, isTrue);

      replica.dispose();
      authority.dispose();
    });

    test('an incompatible remote checkpoint leaves the replica unchanged', () {
      final replica = GameEngine();
      final previousMessage = replica.message;
      final incompatible = GameEngine(
        matchFormat: MatchFormat.quickPop,
      ).createCheckpoint();

      expect(
        () => replica.applyRemoteCheckpoint(
          Map<String, dynamic>.from(incompatible),
        ),
        throwsFormatException,
      );
      expect(replica.matchFormat, MatchFormat.classic);
      expect(replica.message, previousMessage);

      replica.dispose();
    });

    test('a malformed non-list remainingDice is still rejected', () {
      final replica = GameEngine();
      final malformed = Map<String, dynamic>.from(replica.createCheckpoint())
        ..['remainingDice'] = 'not-a-list';

      expect(
        () => replica.applyRemoteCheckpoint(malformed),
        throwsFormatException,
      );

      replica.dispose();
    });
  });
}
