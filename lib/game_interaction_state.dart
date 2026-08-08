import 'package:flutter/foundation.dart';

import 'game_engine.dart';

/// The single player-facing phase of an active match.
///
/// This model deliberately contains no widgets, timers, or translated copy. It
/// can therefore be shared by the HUD, tutorial, accessibility layer, and
/// analytics without each consumer reimplementing the game-state conditions.
enum GameInteractionPhase {
  waitingForRoll,
  choosingToken,
  choosingDestination,
  resolvingMove,
  opponentTurn,
  finished,
}

/// The one dominant gameplay action presented by the current phase.
enum GamePrimaryAction { rollDice, chooseToken, chooseDestination, wait, none }

@immutable
class GameInteractionState {
  const GameInteractionState._({
    required this.phase,
    required this.primaryAction,
    this.selectedToken,
  });

  final GameInteractionPhase phase;
  final GamePrimaryAction primaryAction;

  /// The selected token only survives when it still belongs to the current
  /// player and has at least one legal destination.
  final GameToken? selectedToken;

  bool get canRollDice => phase == GameInteractionPhase.waitingForRoll;

  bool get canChooseToken => phase == GameInteractionPhase.choosingToken;

  bool get canChooseDestination =>
      phase == GameInteractionPhase.choosingDestination;

  bool get boardInputEnabled => canChooseToken || canChooseDestination;

  bool get gameplayControlsLocked => switch (phase) {
    GameInteractionPhase.resolvingMove ||
    GameInteractionPhase.opponentTurn ||
    GameInteractionPhase.finished => true,
    _ => false,
  };

  /// Derives the interaction state from authoritative match data.
  ///
  /// [isLocallyControlledTurn] is intentionally supplied by the caller. It can
  /// represent a normal human turn, an online disconnect takeover, or spectator
  /// mode without coupling this pure resolver to any one transport/UI policy.
  static GameInteractionState derive({
    required GameEngine engine,
    required bool isLocallyControlledTurn,
    GameToken? selectedToken,
  }) {
    if (engine.gameOver) {
      return const GameInteractionState._(
        phase: GameInteractionPhase.finished,
        primaryAction: GamePrimaryAction.none,
      );
    }

    if (engine.effectResolving) {
      return const GameInteractionState._(
        phase: GameInteractionPhase.resolvingMove,
        primaryAction: GamePrimaryAction.wait,
      );
    }

    if (!isLocallyControlledTurn) {
      return const GameInteractionState._(
        phase: GameInteractionPhase.opponentTurn,
        primaryAction: GamePrimaryAction.wait,
      );
    }

    if (!engine.hasRolled) {
      return const GameInteractionState._(
        phase: GameInteractionPhase.waitingForRoll,
        primaryAction: GamePrimaryAction.rollDice,
      );
    }

    // A rolled turn with no remaining legal action is already transitioning to
    // the next turn. Presenting "choose a piece" here would create a false tap.
    if (!engine.hasAnyMove()) {
      return const GameInteractionState._(
        phase: GameInteractionPhase.resolvingMove,
        primaryAction: GamePrimaryAction.wait,
      );
    }

    final validSelection =
        selectedToken != null &&
        selectedToken.owner == engine.currentPlayer.color &&
        !selectedToken.finished &&
        (engine.legalDiceFor(selectedToken).isNotEmpty ||
            engine.canMoveUsingAllDice(selectedToken));
    if (validSelection) {
      return GameInteractionState._(
        phase: GameInteractionPhase.choosingDestination,
        primaryAction: GamePrimaryAction.chooseDestination,
        selectedToken: selectedToken,
      );
    }

    return const GameInteractionState._(
      phase: GameInteractionPhase.choosingToken,
      primaryAction: GamePrimaryAction.chooseToken,
    );
  }

  @override
  String toString() =>
      'GameInteractionState(${phase.name}, action: ${primaryAction.name})';
}
