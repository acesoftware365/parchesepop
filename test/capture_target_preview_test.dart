import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';

GameToken _placeOnGlobal(
  GameEngine game,
  int playerIndex,
  int tokenIndex,
  int globalIndex,
) {
  final token = game.players[playerIndex].tokens[tokenIndex];
  token.progress =
      (globalIndex - GameEngine.startOffset[token.owner]!) %
      GameEngine.loopLength;
  return token;
}

void _makeRollAvailable(GameEngine game, List<int> dice) {
  game.hasRolled = true;
  game.dice = List<int>.of(dice);
  game.remainingDice
    ..clear()
    ..addAll(dice);
}

void main() {
  group('capture target previews', () {
    test('single die returns the exact rival and its color', () {
      final game = GameEngine();
      addTearDown(game.dispose);
      final mover = game.players[0].tokens.first..progress = 1;
      final greenTarget = _placeOnGlobal(game, 1, 0, 4);
      _makeRollAvailable(game, const [3, 6]);

      final target = game.captureTargetFor(mover, 3);

      expect(target, same(greenTarget));
      expect(target?.owner, PlayerColor.green);
      expect(mover.progress, 1, reason: 'a preview must not move the attacker');
      expect(
        greenTarget.inNest,
        isFalse,
        reason: 'a preview must not capture the rival early',
      );
    });

    test('safe destination never reports a capture', () {
      final game = GameEngine();
      addTearDown(game.dispose);
      final mover = _placeOnGlobal(game, 0, 0, 6);
      final protectedTarget = _placeOnGlobal(game, 1, 0, 7);
      _makeRollAvailable(game, const [1, 6]);

      expect(GameEngine.safeLoopIndices, contains(7));
      expect(game.canMove(mover, 1), isFalse);
      expect(game.captureTargetFor(mover, 1), isNull);
      expect(protectedTarget.inNest, isFalse);
    });

    test('safe landing helper identifies a four-step star destination', () {
      final game = GameEngine();
      addTearDown(game.dispose);
      final mover = game.currentPlayer.tokens.first..progress = 3;
      _makeRollAvailable(game, const [4, 2]);

      // Red progress 3 + 4 reaches global loop index 7, one of the
      // protected star squares. The preview must not rely on the token's
      // eventual movement side effects to identify it.
      expect(game.isSafeLandingFor(mover, 4), isTrue);
      expect(game.isSafeLandingFor(mover, 2), isFalse);
    });

    test('rival barrier is illegal and never reports either token', () {
      final game = GameEngine();
      addTearDown(game.dispose);
      final mover = game.players[0].tokens.first..progress = 1;
      final firstBarrierToken = _placeOnGlobal(game, 1, 0, 4);
      final secondBarrierToken = _placeOnGlobal(game, 1, 1, 4);
      _makeRollAvailable(game, const [3, 6]);

      expect(game.canMove(mover, 3), isFalse);
      expect(game.captureTargetFor(mover, 3), isNull);
      expect(firstBarrierToken.inNest, isFalse);
      expect(secondBarrierToken.inNest, isFalse);
    });

    test('reserved five previews only the forced departure capture', () {
      final game = GameEngine();
      addTearDown(game.dispose);
      final nested = game.players[0].tokens.first;
      final outside = game.players[0].tokens[1]..progress = 1;
      final departureTarget = _placeOnGlobal(
        game,
        1,
        0,
        GameEngine.startOffset[PlayerColor.red]!,
      );
      _placeOnGlobal(game, 1, 1, 6);
      _makeRollAvailable(game, const [5, 2]);

      expect(game.mustUseFiveToLeaveNest(PlayerColor.red), isTrue);
      expect(game.captureTargetFor(nested, 5), same(departureTarget));
      expect(game.captureTargetFor(nested, 5)?.owner, PlayerColor.green);
      expect(game.canMove(outside, 5), isFalse);
      expect(
        game.captureTargetFor(outside, 5),
        isNull,
        reason: 'the reserved five cannot preview an ordinary board move',
      );
    });

    test('special five reports the rival blocking the home entry', () {
      final game = GameEngine();
      addTearDown(game.dispose);
      final mover = game.players[0].tokens.first
        ..progress = GameEngine.commonPathLength - 2;
      for (var tokenIndex = 1; tokenIndex < 4; tokenIndex++) {
        game.players[0].tokens[tokenIndex].progress = tokenIndex * 10;
      }
      final entryTarget = _placeOnGlobal(
        game,
        1,
        0,
        GameEngine.homeEntryOffset[PlayerColor.red]!,
      );
      _makeRollAvailable(game, const [5, 2]);

      expect(game.isHomeEntryCaptureMove(mover, 5), isTrue);
      expect(game.captureTargetFor(mover, 5), same(entryTarget));
      expect(game.captureTargetFor(mover, 5)?.owner, PlayerColor.green);
      expect(entryTarget.inNest, isFalse);
    });

    test('all dice reports only a rival on the final destination', () {
      final game = GameEngine();
      addTearDown(game.dispose);
      final mover = game.players[0].tokens.first..progress = 1;
      final intermediateTarget = _placeOnGlobal(game, 1, 0, 3);
      final finalTarget = _placeOnGlobal(game, 2, 0, 6);
      _makeRollAvailable(game, const [2, 3]);

      expect(game.allDiceTotalFor(mover), 5);
      expect(game.captureTargetUsingAllDice(mover), same(finalTarget));
      expect(game.captureTargetUsingAllDice(mover)?.owner, PlayerColor.yellow);
      expect(intermediateTarget.inNest, isFalse);
      expect(finalTarget.inNest, isFalse);

      finalTarget.progress = -1;

      expect(
        game.captureTargetUsingAllDice(mover),
        isNull,
        reason: 'a rival passed along the route is not the capture target',
      );
      expect(intermediateTarget.inNest, isFalse);
    });

    test('an unavailable die never reports a stale capture target', () {
      final game = GameEngine();
      addTearDown(game.dispose);
      final mover = game.players[0].tokens.first..progress = 1;
      _placeOnGlobal(game, 1, 0, 4);
      _makeRollAvailable(game, const [6, 6]);

      expect(game.canMove(mover, 3), isTrue);
      expect(game.captureTargetFor(mover, 3), isNull);

      game.gameOver = true;
      game.remainingDice
        ..clear()
        ..add(3);
      expect(game.captureTargetFor(mover, 3), isNull);
      expect(game.captureTargetUsingAllDice(mover), isNull);
    });
  });
}
