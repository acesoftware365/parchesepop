import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';

Map<String, dynamic> _checkpointFor(GameEngine game) => <String, dynamic>{
  ...game.checkpointRuleMetadata,
  'mode': game.mode.name,
  'cpuLevel': game.cpuLevel,
  'turn': game.turnNumber,
  'currentPlayer': game.currentPlayer.color.name,
  'dice': game.dice,
  'remainingDice': game.remainingDice,
  'hasRolled': game.hasRolled,
  'players': <Map<String, dynamic>>[
    for (final player in game.players)
      <String, dynamic>{
        'color': player.color.name,
        'name': player.name,
        'tokens': <int>[for (final token in player.tokens) token.progress],
        'inventory': player.inventory?.name,
        'shielded': player.shielded,
        'skippedTurns': player.skippedTurns,
      },
  ],
};

void main() {
  group('match format rules', () {
    testWidgets('restore advances consumed and no-move rolls without a tap', (
      tester,
    ) async {
      final consumedSource = GameEngine()
        ..turnNumber = 5
        ..hasRolled = true
        ..dice = const [2, 3];
      final consumed = GameEngine.fromCheckpoint(
        _checkpointFor(consumedSource),
      );
      await tester.pump(const Duration(milliseconds: 1));
      expect(consumed.currentPlayer.color, PlayerColor.green);
      expect(consumed.turnNumber, 6);
      expect(consumed.hasRolled, isFalse);

      final noMoveSource = GameEngine()
        ..turnNumber = 9
        ..hasRolled = true
        ..dice = const [1, 2];
      noMoveSource.remainingDice.addAll(const [1, 2]);
      final noMove = GameEngine.fromCheckpoint(_checkpointFor(noMoveSource));
      await tester.pump(const Duration(milliseconds: 1));
      expect(noMove.currentPlayer.color, PlayerColor.green);
      expect(noMove.turnNumber, 10);
      expect(noMove.hasRolled, isFalse);

      noMove.dispose();
      noMoveSource.dispose();
      consumed.dispose();
      consumedSource.dispose();
    });

    testWidgets('restored CPU turn starts automatically after mount', (
      tester,
    ) async {
      final source = GameEngine()..currentPlayerIndex = PlayerColor.green.index;
      final restored = GameEngine.fromCheckpoint(_checkpointFor(source));

      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            opponent: 'CPU • Fácil',
            gameEngine: restored,
            isResumedMatch: true,
            cpuThinkDelayProvider: () => const Duration(milliseconds: 10),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 11));

      expect(restored.rollSerial, greaterThan(0));

      // Stop before the second CPU pacing delay so this regression test only
      // verifies the automatic startup behavior.
      restored.gameOver = true;
      await tester.pump(const Duration(milliseconds: 11));

      await tester.pumpWidget(const SizedBox.shrink());
      restored.dispose();
      source.dispose();
    });

    test('checkpoint preserves doubles and per-turn trap protection', () {
      final game = GameEngine(mode: GameMode.chaos)
        ..turnNumber = 7
        ..consecutiveDoubles = 2;
      final checkpoint = _checkpointFor(game)
        ..['consecutiveDoubles'] = 2
        ..['lastTrapEffectTurn'] = <String, int>{'red': 7};

      final restored = GameEngine.fromCheckpoint(checkpoint);

      expect(restored.consecutiveDoubles, 2);
      expect(
        restored.checkpointRuleMetadata['lastTrapEffectTurn'],
        <String, int>{'red': 7},
      );

      restored.dispose();
      game.dispose();
    });

    test('Classic keeps the existing four-token contract', () {
      final game = GameEngine();

      expect(game.matchFormat, MatchFormat.classic);
      expect(game.rules.tokenCount, 4);
      expect(game.rules.tokensRequiredToWin, 4);
      expect(game.rules.requiresFiveToExit, isTrue);
      expect(game.rules.initialStackFormsBarrier, isTrue);
      for (final player in game.players) {
        expect(player.tokens, hasLength(4));
        expect(player.tokens.every((token) => token.inNest), isTrue);
      }

      game.dispose();
    });

    test('Quick Pop starts two tokens in base without a visible stack', () {
      final game = GameEngine(matchFormat: MatchFormat.quickPop);

      expect(game.rules.tokenCount, 2);
      expect(game.rules.tokensRequiredToWin, 2);
      expect(game.rules.requiresFiveToExit, isFalse);
      expect(game.rules.initialTokenProgress, -1);
      expect(game.rules.initialStackFormsBarrier, isFalse);
      for (final player in game.players) {
        expect(player.tokens, hasLength(2));
        expect(player.tokens.every((token) => token.inNest), isTrue);
        expect(
          player.tokens.every((token) => game.tokenCell(token) == null),
          isTrue,
        );
      }

      game.dispose();
    });

    test('any die can release a Quick Pop token from base', () {
      final game = GameEngine(matchFormat: MatchFormat.quickPop);
      final token = game.currentPlayer.tokens.first;
      game
        ..hasRolled = true
        ..dice = const <int>[1, 6];
      game.remainingDice.addAll(const <int>[1, 6]);

      expect(game.mustUseFiveToLeaveNest(PlayerColor.red), isFalse);
      expect(game.canMove(token, 1), isTrue);
      expect(game.moveToken(token, die: 1), isTrue);
      expect(token.inNest, isFalse);
      expect(token.progress, 0);
      expect(game.remainingDice, <int>[6]);

      game.dispose();
    });

    test('a five releases one Quick Pop token like any other die', () {
      final game = GameEngine(matchFormat: MatchFormat.quickPop);
      final token = game.currentPlayer.tokens.first;
      game
        ..hasRolled = true
        ..dice = const <int>[5, 2];
      game.remainingDice.addAll(const <int>[5, 2]);

      expect(game.mustUseFiveToLeaveNest(PlayerColor.red), isFalse);
      expect(game.moveToken(token, die: 5), isTrue);
      // Leaving base places the token on its own departure square; the die
      // value is the permission to leave, not five travelled spaces.
      expect(token.progress, 0);
      expect(game.remainingDice, <int>[2]);

      game.dispose();
    });

    test('the empty Quick Pop departure square can be crossed', () {
      final game = GameEngine(matchFormat: MatchFormat.quickPop);
      final red = game.players.first.tokens.first..progress = 16;

      // Green's pieces are still in base, so there is no initial stack on
      // global square 17 to block or capture.
      expect(game.canMove(red, 2), isTrue);
      expect(game.canMove(red, 1), isTrue);

      game.dispose();
    });

    test('two Quick Pop tokens can form a barrier after leaving base', () {
      final game = GameEngine(matchFormat: MatchFormat.quickPop);
      final green = game.players[1];
      green.tokens[0].progress = 0;
      green.tokens[1].progress = 0;
      green.initialStackIntact = false;

      game.currentPlayerIndex = 0;
      final red = game.currentPlayer.tokens.first..progress = 16;
      expect(game.canMove(red, 2), isFalse);

      game.dispose();
    });

    test('a captured Quick Pop token returns inside base', () {
      final game = GameEngine(matchFormat: MatchFormat.quickPop);
      final red = game.currentPlayer.tokens.first..progress = 1;
      final green = game.players[1].tokens.first
        ..progress =
            (4 - GameEngine.startOffset[PlayerColor.green]!) %
            GameEngine.loopLength;
      game
        ..hasRolled = true
        ..dice = const <int>[3, 6];
      game.remainingDice.addAll(const <int>[3, 6]);

      expect(game.moveToken(red, die: 3), isTrue);
      expect(green.progress, -1);
      expect(green.inNest, isTrue);

      game.dispose();
    });

    test('Quick Pop declares victory as soon as both tokens finish', () {
      final game = GameEngine(matchFormat: MatchFormat.quickPop);
      final player = game.currentPlayer;
      player.tokens.first.progress = GameEngine.finishProgress;
      player.tokens.last.progress = GameEngine.finishProgress - 1;
      game
        ..hasRolled = true
        ..dice = const <int>[1, 6];
      game.remainingDice.addAll(const <int>[1, 6]);

      expect(game.moveToken(player.tokens.last, die: 1), isTrue);
      expect(game.winner, same(player));
      expect(game.gameOver, isTrue);

      game.dispose();
    });
  });

  group('normalized legal move commands', () {
    test('equal dice are de-duplicated into one single-die command', () {
      final game = GameEngine(matchFormat: MatchFormat.quickPop);
      game.currentPlayer.tokens.first.progress = GameEngine.finishProgress;
      final finalToken = game.currentPlayer.tokens.last
        ..progress = GameEngine.finishProgress - 1;
      game
        ..hasRolled = true
        ..dice = const <int>[1, 1];
      game.remainingDice.addAll(const <int>[1, 1]);

      final commands = game.legalMoveCommands();
      expect(commands, hasLength(1));
      expect(commands.single.token, same(finalToken));
      expect(commands.single.die, 1);
      expect(commands.single.usesAllDice, isFalse);
      expect(game.uniqueLegalMoveCommand?.token, same(finalToken));
      expect(game.uniqueLegalMoveCommand?.die, 1);

      game.dispose();
    });

    test('single-die and combined-dice destinations remain real choices', () {
      final game = GameEngine(matchFormat: MatchFormat.quickPop);
      game.currentPlayer.tokens.first.progress = GameEngine.finishProgress;
      final finalToken = game.currentPlayer.tokens.last
        ..progress = GameEngine.finishProgress - 2;
      game
        ..hasRolled = true
        ..dice = const <int>[1, 1];
      game.remainingDice.addAll(const <int>[1, 1]);

      final commands = game.legalMoveCommands();
      expect(commands, hasLength(2));
      expect(commands.every((command) => command.token == finalToken), isTrue);
      expect(commands.map((command) => command.amount), <int>[1, 2]);
      expect(commands.map((command) => command.usesAllDice), <bool>[
        false,
        true,
      ]);
      expect(game.uniqueLegalMoveCommand, isNull);

      game.dispose();
    });

    test('the unique command helper executes only a still-legal command', () {
      final game = GameEngine(matchFormat: MatchFormat.quickPop);
      game.currentPlayer.tokens.first.progress = GameEngine.finishProgress;
      final finalToken = game.currentPlayer.tokens.last
        ..progress = GameEngine.finishProgress - 1;
      game
        ..hasRolled = true
        ..dice = const <int>[1, 1];
      game.remainingDice.addAll(const <int>[1, 1]);

      final command = game.uniqueLegalMoveCommand;
      expect(command, isNotNull);
      expect(game.executeMoveCommand(command!), isTrue);
      expect(finalToken.finished, isTrue);
      expect(game.executeMoveCommand(command), isFalse);

      game.dispose();
    });
  });

  group('checkpoint compatibility', () {
    test('Quick Pop metadata and initial-stack state round-trip', () {
      final game = GameEngine(matchFormat: MatchFormat.quickPop);
      game
        ..hasRolled = true
        ..dice = const <int>[4, 6];
      game.remainingDice.addAll(const <int>[4, 6]);
      expect(game.moveToken(game.currentPlayer.tokens.first, die: 4), isTrue);

      final checkpoint = _checkpointFor(game);
      expect(checkpoint['matchFormat'], MatchFormat.quickPop.name);
      expect(checkpoint['rulesVersion'], MatchRules.quickPopRulesVersion);

      final restored = GameEngine.fromCheckpoint(checkpoint);
      expect(restored.matchFormat, MatchFormat.quickPop);
      expect(restored.players.first.tokens, hasLength(2));
      expect(
        restored.players.first.tokens.map((token) => token.progress),
        <int>[0, -1],
      );
      expect(restored.players.first.initialStackIntact, isFalse);

      game.dispose();
      restored.dispose();
    });

    test('a legacy checkpoint without format metadata migrates to Classic', () {
      final restored = GameEngine.fromCheckpoint(<String, dynamic>{
        'mode': GameMode.traditional.name,
      });

      expect(restored.matchFormat, MatchFormat.classic);
      expect(restored.rules.rulesVersion, MatchRules.currentRulesVersion);
      for (final player in restored.players) {
        expect(player.tokens, hasLength(4));
        expect(player.tokens.every((token) => token.inNest), isTrue);
      }

      restored.dispose();
    });

    test('unknown formats and rules versions are rejected explicitly', () {
      expect(
        () => GameEngine.fromCheckpoint(<String, dynamic>{
          'matchFormat': 'turboUnknown',
        }),
        throwsFormatException,
      );
      expect(
        () => GameEngine.fromCheckpoint(<String, dynamic>{
          'matchFormat': MatchFormat.quickPop.name,
          'rulesVersion': MatchRules.quickPopRulesVersion + 1,
        }),
        throwsFormatException,
      );
    });
  });
}
