import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/game_interaction_state.dart';

void _setRolledDice(GameEngine engine, List<int> values) {
  engine.hasRolled = true;
  engine.dice = List<int>.of(values);
  engine.remainingDice
    ..clear()
    ..addAll(values);
}

void main() {
  group('GameInteractionState', () {
    test('starts with one dominant roll action', () {
      final engine = GameEngine();
      addTearDown(engine.dispose);

      final state = GameInteractionState.derive(
        engine: engine,
        isLocallyControlledTurn: true,
      );

      expect(state.phase, GameInteractionPhase.waitingForRoll);
      expect(state.primaryAction, GamePrimaryAction.rollDice);
      expect(state.canRollDice, isTrue);
      expect(state.canChooseToken, isFalse);
      expect(state.canChooseDestination, isFalse);
      expect(state.boardInputEnabled, isFalse);
      expect(state.gameplayControlsLocked, isFalse);
      expect(state.selectedToken, isNull);
    });

    test('an uncontrolled turn exposes no local action', () {
      final engine = GameEngine();
      addTearDown(engine.dispose);

      final state = GameInteractionState.derive(
        engine: engine,
        isLocallyControlledTurn: false,
      );

      expect(state.phase, GameInteractionPhase.opponentTurn);
      expect(state.primaryAction, GamePrimaryAction.wait);
      expect(state.gameplayControlsLocked, isTrue);
      expect(state.boardInputEnabled, isFalse);
    });

    test('a rolled turn with a legal move asks for one token', () {
      final engine = GameEngine();
      addTearDown(engine.dispose);
      _setRolledDice(engine, const [5, 2]);

      final state = GameInteractionState.derive(
        engine: engine,
        isLocallyControlledTurn: true,
      );

      expect(engine.hasAnyMove(), isTrue);
      expect(state.phase, GameInteractionPhase.choosingToken);
      expect(state.primaryAction, GamePrimaryAction.chooseToken);
      expect(state.canChooseToken, isTrue);
      expect(state.boardInputEnabled, isTrue);
      expect(state.selectedToken, isNull);
    });

    test('a valid selected token asks for its destination', () {
      final engine = GameEngine();
      addTearDown(engine.dispose);
      _setRolledDice(engine, const [5, 2]);
      final token = engine.currentPlayer.tokens.first;

      final state = GameInteractionState.derive(
        engine: engine,
        isLocallyControlledTurn: true,
        selectedToken: token,
      );

      expect(engine.legalDiceFor(token), contains(5));
      expect(state.phase, GameInteractionPhase.choosingDestination);
      expect(state.primaryAction, GamePrimaryAction.chooseDestination);
      expect(state.canChooseDestination, isTrue);
      expect(state.boardInputEnabled, isTrue);
      expect(state.selectedToken, same(token));
    });

    test('a combined-dice-only selection is accepted', () {
      final engine = GameEngine();
      addTearDown(engine.dispose);
      final token = engine.currentPlayer.tokens.first..progress = 0;
      _setRolledDice(engine, const [1, 6]);

      final state = GameInteractionState.derive(
        engine: engine,
        isLocallyControlledTurn: true,
        selectedToken: token,
      );

      expect(engine.canMoveUsingAllDice(token), isTrue);
      expect(state.phase, GameInteractionPhase.choosingDestination);
      expect(state.selectedToken, same(token));
    });

    test('a stale opponent selection is discarded', () {
      final engine = GameEngine();
      addTearDown(engine.dispose);
      _setRolledDice(engine, const [5, 2]);
      final opponentToken = engine.players[1].tokens.first;

      final state = GameInteractionState.derive(
        engine: engine,
        isLocallyControlledTurn: true,
        selectedToken: opponentToken,
      );

      expect(state.phase, GameInteractionPhase.choosingToken);
      expect(state.selectedToken, isNull);
    });

    test('a finished or immobile selection is discarded', () {
      final engine = GameEngine();
      addTearDown(engine.dispose);
      _setRolledDice(engine, const [5, 2]);
      final token = engine.currentPlayer.tokens.first
        ..progress = GameEngine.finishProgress;

      final state = GameInteractionState.derive(
        engine: engine,
        isLocallyControlledTurn: true,
        selectedToken: token,
      );

      expect(state.phase, GameInteractionPhase.choosingToken);
      expect(state.selectedToken, isNull);
    });

    test('a rolled turn without a legal move waits for turn resolution', () {
      final engine = GameEngine();
      addTearDown(engine.dispose);
      _setRolledDice(engine, const [1, 2]);

      final state = GameInteractionState.derive(
        engine: engine,
        isLocallyControlledTurn: true,
      );

      expect(engine.hasAnyMove(), isFalse);
      expect(state.phase, GameInteractionPhase.resolvingMove);
      expect(state.primaryAction, GamePrimaryAction.wait);
      expect(state.gameplayControlsLocked, isTrue);
    });

    test('an effect resolution takes precedence over turn ownership', () {
      final engine = GameEngine()..effectResolving = true;
      addTearDown(engine.dispose);

      final state = GameInteractionState.derive(
        engine: engine,
        isLocallyControlledTurn: false,
      );

      expect(state.phase, GameInteractionPhase.resolvingMove);
      expect(state.primaryAction, GamePrimaryAction.wait);
      expect(state.gameplayControlsLocked, isTrue);
    });

    test('game over has final precedence and no dominant action', () {
      final engine = GameEngine()
        ..effectResolving = true
        ..gameOver = true;
      addTearDown(engine.dispose);

      final state = GameInteractionState.derive(
        engine: engine,
        isLocallyControlledTurn: false,
        selectedToken: engine.currentPlayer.tokens.first,
      );

      expect(state.phase, GameInteractionPhase.finished);
      expect(state.primaryAction, GamePrimaryAction.none);
      expect(state.gameplayControlsLocked, isTrue);
      expect(state.selectedToken, isNull);
    });

    test('a stale selection cannot survive before the dice are rolled', () {
      final engine = GameEngine();
      addTearDown(engine.dispose);

      final state = GameInteractionState.derive(
        engine: engine,
        isLocallyControlledTurn: true,
        selectedToken: engine.currentPlayer.tokens.first,
      );

      expect(state.phase, GameInteractionPhase.waitingForRoll);
      expect(state.selectedToken, isNull);
    });
  });
}
