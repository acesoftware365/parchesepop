import 'dart:math';

import 'game_engine.dart';
import 'game_analytics.dart';

/// A short, deterministic practice table for the six onboarding actions.
///
/// Every action still goes through [GameEngine]. The scenario only prepares
/// legal board positions between lessons so a new player never has to wait for
/// a lucky roll, a random capture opportunity, or an entire classic match.
class TutorialGameScenario {
  TutorialGameScenario._(this.engine);

  factory TutorialGameScenario.create({
    required TutorialStep step,
    String humanName = 'Tú',
  }) {
    final scenario = TutorialGameScenario._(
      GameEngine(
        cpuLevel: 'Fácil',
        mode: GameMode.traditional,
        random: _TutorialSequenceRandom(const <int>[4, 1]),
        humanName: humanName,
      ),
    );
    scenario.prepareFor(step);
    return scenario;
  }

  final GameEngine engine;
  TutorialStep? _preparedStep;

  TutorialStep? get preparedStep => _preparedStep;

  int? expectedTokenId(TutorialStep? step) => switch (step) {
    TutorialStep.releaseToken ||
    TutorialStep.chooseMove ||
    TutorialStep.safeSquare ||
    TutorialStep.capture ||
    TutorialStep.reachHome => 0,
    TutorialStep.firstRoll || null => null,
  };

  int? expectedDie(TutorialStep? step) => switch (step) {
    TutorialStep.releaseToken => 5,
    TutorialStep.chooseMove || TutorialStep.safeSquare => 2,
    TutorialStep.capture => 3,
    TutorialStep.reachHome => 1,
    TutorialStep.firstRoll || null => null,
  };

  GameToken? expectedToken(TutorialStep? step) {
    final tokenId = expectedTokenId(step);
    if (tokenId == null) return null;
    return engine.players
        .firstWhere((player) => player.color == PlayerColor.red)
        .tokens[tokenId];
  }

  bool allowsRoll(TutorialStep? step) =>
      step == TutorialStep.firstRoll && !engine.hasRolled;

  bool allowsToken(TutorialStep? step, GameToken token) =>
      token.owner == PlayerColor.red && token.id == expectedTokenId(step);

  bool allowsMove(
    TutorialStep? step,
    GameToken token,
    int die, {
    bool usesAllDice = false,
  }) => !usesAllDice && allowsToken(step, token) && die == expectedDie(step);

  /// Rebuilds the compact example for [step]. Calling this repeatedly for the
  /// same step is a no-op so duplicate engine notifications cannot rewind play.
  void prepareFor(TutorialStep? step) {
    if (step == null || _preparedStep == step) return;
    _preparedStep = step;
    _resetBoard();

    switch (step) {
      case TutorialStep.firstRoll:
        engine.message = 'Práctica guiada: toca los dados para empezar.';
      case TutorialStep.releaseToken:
        _setRoll(const <int>[5, 2], const <int>[5, 2]);
        engine.message = 'Tienes un 5. Toca la ficha 1 para sacarla.';
      case TutorialStep.chooseMove:
        _redToken(0).progress = 0;
        _setRoll(const <int>[2, 6], const <int>[2, 6]);
        engine.message = 'Ahora elige la ficha 1 y avanza 2 pasos.';
      case TutorialStep.safeSquare:
        _redToken(0).progress = 5;
        _setRoll(const <int>[2, 6], const <int>[2, 6]);
        engine.message = 'Usa el 2 para caer en la estrella segura.';
      case TutorialStep.capture:
        _redToken(0).progress = 7;
        _placeTokenAtLoopIndex(PlayerColor.green, tokenId: 0, loopIndex: 10);
        _setRoll(const <int>[3, 6], const <int>[3, 6]);
        engine.message = 'Usa el 3 para capturar la ficha rival.';
      case TutorialStep.reachHome:
        _redToken(0).progress = GameEngine.finishProgress - 1;
        _redToken(1).progress = 0;
        _setRoll(const <int>[1, 6], const <int>[1, 6]);
        engine.message = 'Usa el 1 exacto para entrar a la meta.';
    }
  }

  void _resetBoard() {
    engine
      ..currentPlayerIndex = 0
      ..turnNumber = 1
      ..dice = const <int>[1, 1]
      ..hasRolled = false
      ..gameOver = false
      ..spectatorContinuationActive = false
      ..consecutiveDoubles = 0
      ..winner = null
      ..pendingTrapPlacement = false
      ..effectResolving = false;
    engine.remainingDice.clear();

    for (final player in engine.players) {
      player
        ..initialStackIntact = false
        ..inventory = null
        ..shielded = false
        ..skippedTurns = 0;
      for (final token in player.tokens) {
        token.progress = engine.rules.initialTokenProgress;
      }
    }

    _redToken(0).progress = engine.rules.initialTokenProgress;
  }

  void _setRoll(List<int> dice, List<int> remaining) {
    engine
      ..dice = List<int>.unmodifiable(dice)
      ..hasRolled = true;
    engine.remainingDice
      ..clear()
      ..addAll(remaining);
  }

  GameToken _redToken(int id) => engine.players
      .firstWhere((player) => player.color == PlayerColor.red)
      .tokens[id];

  void _placeTokenAtLoopIndex(
    PlayerColor owner, {
    required int tokenId,
    required int loopIndex,
  }) {
    final progress =
        (loopIndex - GameEngine.startOffset[owner]! + GameEngine.loopLength) %
        GameEngine.loopLength;
    engine.players
            .firstWhere((player) => player.color == owner)
            .tokens[tokenId]
            .progress =
        progress;
  }
}

class _TutorialSequenceRandom implements Random {
  _TutorialSequenceRandom(this._values);

  final List<int> _values;
  int _position = 0;

  int _next() => _position < _values.length ? _values[_position++] : 0;

  @override
  bool nextBool() => _next().isOdd;

  @override
  double nextDouble() => (_next() % 1000) / 1000;

  @override
  int nextInt(int max) => _next() % max;
}
