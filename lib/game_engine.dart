import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/material.dart';

import 'online_spectator.dart';

enum PlayerColor { red, green, yellow, blue }

enum GameMode { traditional, chaos }

enum PowerUp { shield, boost, glueTrap, setbackTrap, prisonTrap, bomb }

enum PowerEffectKind {
  pickup,
  armed,
  triggered,
  blocked,
  activated,
  departure,
  capture,
  departureCapture,
  goal,
}

enum GameEventType {
  matchStarted,
  turnStarted,
  roll,
  move,
  departure,
  barrierFormed,
  barrierOpened,
  capture,
  threeDoublesPenalty,
  noMove,
  goal,
  powerUp,
  trap,
  victory,
}

class GameEvent {
  const GameEvent({
    required this.sequence,
    required this.turn,
    required this.type,
    required this.playerName,
    required this.playerColor,
    required this.description,
    this.dice,
    this.tokenId,
    this.fromProgress,
    this.toProgress,
    this.targetName,
    this.targetColor,
  });

  final int sequence;
  final int turn;
  final GameEventType type;
  final String playerName;
  final PlayerColor playerColor;
  final String description;
  final (int, int)? dice;
  final int? tokenId;
  final int? fromProgress;
  final int? toProgress;
  final String? targetName;
  final PlayerColor? targetColor;
}

class BoardTrap {
  const BoardTrap({
    required this.owner,
    required this.type,
    required this.loopIndex,
  });

  final PlayerColor owner;
  final PowerUp type;
  final int loopIndex;
}

class GameToken {
  GameToken(this.owner, this.id);

  final PlayerColor owner;
  final int id;
  int progress = -1;

  bool get inNest => progress < 0;
  bool get finished => progress >= GameEngine.finishProgress;
}

class PlayerState {
  PlayerState(this.color, this.name, {this.isHuman = false})
    : tokens = List.generate(4, (index) => GameToken(color, index));

  final PlayerColor color;
  final String name;
  final bool isHuman;
  final List<GameToken> tokens;
  PowerUp? inventory;
  bool shielded = false;
  int skippedTurns = 0;
}

String _resolvedCpuName(List<String>? names, int index, String fallback) =>
    names != null && index < names.length && names[index].trim().isNotEmpty
    ? names[index].trim()
    : fallback;

class GameEngine extends ChangeNotifier {
  GameEngine({
    this.cpuLevel = 'Normal',
    this.mode = GameMode.traditional,
    Random? random,
    String humanName = 'Tú',
    List<String>? cpuNames,
  }) : _random = random ?? Random(),
       players = [
         PlayerState(PlayerColor.red, humanName, isHuman: true),
         PlayerState(PlayerColor.green, _resolvedCpuName(cpuNames, 0, 'CPU 1')),
         PlayerState(
           PlayerColor.yellow,
           _resolvedCpuName(cpuNames, 1, 'CPU 2'),
         ),
         PlayerState(PlayerColor.blue, _resolvedCpuName(cpuNames, 2, 'CPU 3')),
       ] {
    if (isChaos) {
      for (final side in PlayerColor.values) {
        _spawnItemForSide(side);
      }
    }
    _recordEvent(
      type: GameEventType.matchStarted,
      description:
          'Comenzó la partida en modo ${isChaos ? 'Caos' : 'Tradicional'}.',
    );
    _recordEvent(
      type: GameEventType.turnStarted,
      description: 'Comenzó el turno de ${currentPlayer.name}.',
    );
  }

  /// Restores an interrupted local match from the lifecycle checkpoint.
  /// Effects are intentionally not resumed half-way through an animation; the
  /// board resumes in the exact stable state immediately before backgrounding.
  factory GameEngine.fromCheckpoint(Map<String, dynamic> checkpoint) {
    final rawPlayers = (checkpoint['players'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .toList(growable: false);
    final red = rawPlayers.cast<Map?>().firstWhere(
      (player) => player?['color'] == PlayerColor.red.name,
      orElse: () => null,
    );
    String playerName(PlayerColor color, String fallback) {
      final entry = rawPlayers.cast<Map?>().firstWhere(
        (player) => player?['color'] == color.name,
        orElse: () => null,
      );
      return entry?['name'] as String? ?? fallback;
    }

    final modeName = checkpoint['mode'] as String?;
    final engine = GameEngine(
      cpuLevel: checkpoint['cpuLevel'] as String? ?? 'Normal',
      mode: modeName == GameMode.chaos.name
          ? GameMode.chaos
          : GameMode.traditional,
      humanName: red?['name'] as String? ?? 'Tú',
      cpuNames: [
        playerName(PlayerColor.green, 'CPU 1'),
        playerName(PlayerColor.yellow, 'CPU 2'),
        playerName(PlayerColor.blue, 'CPU 3'),
      ],
    );
    for (final player in engine.players) {
      final saved = rawPlayers.cast<Map?>().firstWhere(
        (entry) => entry?['color'] == player.color.name,
        orElse: () => null,
      );
      if (saved == null) continue;
      final tokens = saved['tokens'] as List<dynamic>? ?? const [];
      for (
        var index = 0;
        index < player.tokens.length && index < tokens.length;
        index++
      ) {
        player.tokens[index].progress = tokens[index] as int? ?? -1;
      }
      final powerName = saved['inventory'] as String?;
      player.inventory = powerName == null
          ? null
          : PowerUp.values
                .where((power) => power.name == powerName)
                .firstOrNull;
      player.shielded = saved['shielded'] as bool? ?? false;
      player.skippedTurns = saved['skippedTurns'] as int? ?? 0;
    }
    engine.traps
      ..clear()
      ..addAll(
        (checkpoint['traps'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((trap) {
              final owner = PlayerColor.values.firstWhere(
                (color) => color.name == trap['owner'],
                orElse: () => PlayerColor.red,
              );
              final type = PowerUp.values.firstWhere(
                (power) => power.name == trap['type'],
                orElse: () => PowerUp.glueTrap,
              );
              return BoardTrap(
                owner: owner,
                type: type,
                loopIndex: trap['loopIndex'] as int? ?? 0,
              );
            }),
      );
    engine._itemLoopIndices
      ..clear()
      ..addAll(
        (checkpoint['items'] as List<dynamic>? ?? const []).whereType<int>(),
      );
    // Chaos now keeps one surprise item per area for the entire match. Older
    // checkpoints may contain the former timed-escalation items, so retain at
    // most one valid item from each colour side when they are restored.
    engine._chaosItemsPerSide = 1;
    if (engine.isChaos) {
      final oneItemPerSide = <int>{};
      for (final side in PlayerColor.values) {
        final items =
            engine._itemLoopIndices
                .where((index) => engine.itemSideForLoopIndex(index) == side)
                .toList()
              ..sort();
        if (items.isNotEmpty) oneItemPerSide.add(items.first);
      }
      engine._itemLoopIndices
        ..clear()
        ..addAll(oneItemPerSide);
    }
    final currentColor = checkpoint['currentPlayer'] as String?;
    engine.currentPlayerIndex = PlayerColor.values.indexWhere(
      (color) => color.name == currentColor,
    );
    if (engine.currentPlayerIndex < 0) engine.currentPlayerIndex = 0;
    engine.turnNumber = checkpoint['turn'] as int? ?? 1;
    engine.dice = List<int>.from(
      checkpoint['dice'] as List<dynamic>? ?? const [1, 1],
    );
    engine.remainingDice
      ..clear()
      ..addAll(
        (checkpoint['remainingDice'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<int>(),
      );
    engine.hasRolled = checkpoint['hasRolled'] as bool? ?? false;
    engine.message = 'Partida reanudada.';
    engine.effectResolving = false;
    engine.pendingTrapPlacement = false;
    engine._eventHistory.clear();
    engine._nextEventSequence = 1;
    engine._recordEvent(
      type: GameEventType.matchStarted,
      description: 'La partida se reanudó desde el último punto guardado.',
    );
    return engine;
  }

  final String cpuLevel;
  final GameMode mode;
  final List<PlayerState> players;
  final Random _random;
  final List<BoardTrap> traps = [];
  final Set<int> _itemLoopIndices = <int>{};
  int _chaosItemsPerSide = 1;
  final List<GameEvent> _eventHistory = <GameEvent>[];
  final OnlineStandingsTracker<PlayerColor> _standings =
      OnlineStandingsTracker<PlayerColor>(competitors: PlayerColor.values);
  final Map<PlayerColor, int> _lastTrapEffectTurn = <PlayerColor, int>{};
  late final Set<int> itemLoopIndices = UnmodifiableSetView(_itemLoopIndices);
  int get chaosItemsPerSide => _chaosItemsPerSide;
  UnmodifiableListView<GameEvent> get eventHistory =>
      UnmodifiableListView(_eventHistory);
  UnmodifiableListView<PlayerColor> get finishOrder => _standings.finishOrder;
  UnmodifiableListView<MatchStanding<PlayerColor>> get standings =>
      _standings.standings;

  int currentPlayerIndex = 0;
  int turnNumber = 1;
  List<int> dice = const [1, 1];
  int rollSerial = 0;
  final List<int> remainingDice = [];
  bool hasRolled = false;
  bool gameOver = false;
  bool spectatorContinuationActive = false;
  int consecutiveDoubles = 0;
  String message = '¡Tu turno! Lanza los dados.';
  PlayerState? winner;
  bool pendingTrapPlacement = false;
  int effectSerial = 0;
  int? effectLoopIndex;
  Offset? effectBoardCell;
  PowerUp? effectPowerUp;
  PowerEffectKind? effectKind;
  GameToken? effectToken;
  PlayerColor? effectOwner;
  bool effectResolving = false;
  Timer? _effectResolutionTimer;
  Timer? _turnTimer;
  GameToken? _lastCapturedToken;
  int _nextEventSequence = 1;

  static const int maxEventHistory = 100;

  PlayerState get currentPlayer => players[currentPlayerIndex];
  bool get isChaos => mode == GameMode.chaos;
  PlayerColor get localViewerColor =>
      players.firstWhere((player) => player.isHuman).color;

  bool get canContinueAfterWinner =>
      gameOver && winner != null && _standings.hasRemainingPlayers;

  bool hasPlayerFinished(PlayerColor color) => _standings.hasFinished(color);

  int? placementFor(PlayerColor color) => _standings.placementFor(color);

  int? placementPointsFor(PlayerColor color) => _standings.pointsFor(color);

  bool get standingsComplete => _standings.isComplete;

  BoardTrap? activeTrapFor(PlayerColor owner) {
    for (final trap in traps) {
      if (trap.owner == owner) return trap;
    }
    return null;
  }

  Iterable<BoardTrap> activeTrapsFor(PlayerColor owner) =>
      traps.where((trap) => trap.owner == owner);

  int activeTrapCountFor(PlayerColor owner) => activeTrapsFor(owner).length;

  // Defensive/utility powers use one held slot. Armed traps live on the board,
  // so they never prevent their owner from collecting another crystal.
  bool powerSlotFilled(PlayerState player) => player.inventory != null;

  Iterable<BoardTrap> visibleTrapsFor(PlayerColor viewer) =>
      traps.where((trap) => trap.owner == viewer);

  void _recordEvent({
    required GameEventType type,
    required String description,
    PlayerState? player,
    (int, int)? dice,
    int? tokenId,
    int? fromProgress,
    int? toProgress,
    PlayerState? target,
  }) {
    final actor = player ?? currentPlayer;
    _eventHistory.add(
      GameEvent(
        sequence: _nextEventSequence++,
        turn: turnNumber,
        type: type,
        playerName: actor.name,
        playerColor: actor.color,
        description: description,
        dice: dice,
        tokenId: tokenId,
        fromProgress: fromProgress,
        toProgress: toProgress,
        targetName: target?.name,
        targetColor: target?.color,
      ),
    );
    if (_eventHistory.length > maxEventHistory) {
      _eventHistory.removeRange(0, _eventHistory.length - maxEventHistory);
    }
  }

  /// The complete board has 68 visible spaces. A piece travels the original
  /// 64-space common route from its departure square through its colored
  /// entry, then turns into the seven-space home lane.
  static const int loopLength = 68;
  static const int commonPathLength = 64;
  static const int homeLaneLength = 7;
  static const int finishProgress = commonPathLength + homeLaneLength;

  /// Centers of the 68 numbered cells on the complete 20×20 board.
  /// Index 0 is square 1 and index 67 is square 68.
  static const List<Offset> loop = [
    Offset(4.5, 12),
    Offset(5.5, 12),
    Offset(6.5, 12),
    Offset(7.444444, 11.777778),
    Offset(8.222222, 12.555556),
    Offset(8, 13.5),
    Offset(8, 14.5),
    Offset(8, 15.5),
    Offset(8, 16.5),
    Offset(8, 17.5),
    Offset(8, 18.5),
    Offset(8, 19.5),
    Offset(10, 19.5),
    Offset(12, 19.5),
    Offset(12, 18.5),
    Offset(12, 17.5),
    Offset(12, 16.5),
    Offset(12, 15.5),
    Offset(12, 14.5),
    Offset(12, 13.5),
    Offset(11.777778, 12.555556),
    Offset(12.555556, 11.777778),
    Offset(13.5, 12),
    Offset(14.5, 12),
    Offset(15.5, 12),
    Offset(16.5, 12),
    Offset(17.5, 12),
    Offset(18.5, 12),
    Offset(19.5, 12),
    Offset(19.5, 10),
    Offset(19.5, 8),
    Offset(18.5, 8),
    Offset(17.5, 8),
    Offset(16.5, 8),
    Offset(15.5, 8),
    Offset(14.5, 8),
    Offset(13.5, 8),
    Offset(12.555556, 8.222222),
    Offset(11.777778, 7.444444),
    Offset(12, 6.5),
    Offset(12, 5.5),
    Offset(12, 4.5),
    Offset(12, 3.5),
    Offset(12, 2.5),
    Offset(12, 1.5),
    Offset(12, .5),
    Offset(10, .5),
    Offset(8, .5),
    Offset(8, 1.5),
    Offset(8, 2.5),
    Offset(8, 3.5),
    Offset(8, 4.5),
    Offset(8, 5.5),
    Offset(8, 6.5),
    Offset(8.222222, 7.444444),
    Offset(7.444444, 8.222222),
    Offset(6.5, 8),
    Offset(5.5, 8),
    Offset(4.5, 8),
    Offset(3.5, 8),
    Offset(2.5, 8),
    Offset(1.5, 8),
    Offset(.5, 8),
    Offset(.5, 10),
    Offset(.5, 12),
    Offset(1.5, 12),
    Offset(2.5, 12),
    Offset(3.5, 12),
  ];

  static const Map<PlayerColor, int> startOffset = {
    PlayerColor.red: 0,
    PlayerColor.green: 17,
    PlayerColor.yellow: 34,
    PlayerColor.blue: 51,
  };
  static const Map<PlayerColor, int> departureArrowTargetLoopIndex = {
    PlayerColor.red: 3,
    PlayerColor.green: 20,
    PlayerColor.yellow: 37,
    PlayerColor.blue: 54,
  };
  static const Map<PlayerColor, Offset> departureArrowDirection = {
    PlayerColor.red: Offset(1, 0),
    PlayerColor.green: Offset(0, -1),
    PlayerColor.yellow: Offset(-1, 0),
    PlayerColor.blue: Offset(0, 1),
  };
  static const Map<PlayerColor, int> homeEntryOffset = {
    PlayerColor.red: 63,
    PlayerColor.green: 12,
    PlayerColor.yellow: 29,
    PlayerColor.blue: 46,
  };

  static const Map<PlayerColor, List<Offset>> homeLanes = {
    PlayerColor.red: [
      Offset(1.5, 10),
      Offset(2.5, 10),
      Offset(3.5, 10),
      Offset(4.5, 10),
      Offset(5.5, 10),
      Offset(6.5, 10),
      Offset(7.5, 10),
    ],
    PlayerColor.green: [
      Offset(10, 18.5),
      Offset(10, 17.5),
      Offset(10, 16.5),
      Offset(10, 15.5),
      Offset(10, 14.5),
      Offset(10, 13.5),
      Offset(10, 12.5),
    ],
    PlayerColor.yellow: [
      Offset(18.5, 10),
      Offset(17.5, 10),
      Offset(16.5, 10),
      Offset(15.5, 10),
      Offset(14.5, 10),
      Offset(13.5, 10),
      Offset(12.5, 10),
    ],
    PlayerColor.blue: [
      Offset(10, 1.5),
      Offset(10, 2.5),
      Offset(10, 3.5),
      Offset(10, 4.5),
      Offset(10, 5.5),
      Offset(10, 6.5),
      Offset(10, 7.5),
    ],
  };
  static const Map<PlayerColor, Offset> goalCells = {
    PlayerColor.red: Offset(9, 10),
    PlayerColor.green: Offset(10, 11),
    PlayerColor.yellow: Offset(11, 10),
    PlayerColor.blue: Offset(10, 9),
  };

  /// Eight gray stars plus the four colored departure squares.
  static const Set<int> safeLoopIndices = {
    0,
    7,
    12,
    17,
    24,
    29,
    34,
    41,
    46,
    51,
    58,
    63,
  };
  static const Map<PlayerColor, (int, int)> itemLoopRanges = {
    PlayerColor.red: (1, 16),
    PlayerColor.green: (18, 33),
    PlayerColor.yellow: (35, 50),
    PlayerColor.blue: (52, 67),
  };

  PlayerColor? itemSideForLoopIndex(int loopIndex) {
    for (final entry in itemLoopRanges.entries) {
      if (loopIndex >= entry.value.$1 && loopIndex <= entry.value.$2) {
        return entry.key;
      }
    }
    return null;
  }

  int? itemLoopIndexForSide(PlayerColor side) {
    final range = itemLoopRanges[side]!;
    for (final index in _itemLoopIndices) {
      if (index >= range.$1 && index <= range.$2) return index;
    }
    return null;
  }

  int itemCountForSide(PlayerColor side) {
    final range = itemLoopRanges[side]!;
    return _itemLoopIndices
        .where((index) => index >= range.$1 && index <= range.$2)
        .length;
  }

  void _spawnItemForSide(PlayerColor side, {int? previousIndex}) {
    final range = itemLoopRanges[side]!;
    final candidates = <int>[
      for (var index = range.$1; index <= range.$2; index++)
        if (index != previousIndex &&
            !safeLoopIndices.contains(index) &&
            !_itemLoopIndices.contains(index) &&
            !traps.any((trap) => trap.loopIndex == index))
          index,
    ];
    final emptyCandidates = candidates
        .where((index) => _commonOccupancy(index) == 0)
        .toList();
    final pool = emptyCandidates.isNotEmpty ? emptyCandidates : candidates;
    if (pool.isNotEmpty) {
      _itemLoopIndices.add(pool[_random.nextInt(pool.length)]);
    }
  }

  bool _collectItemAt(GameToken token, {bool showEffect = true}) {
    if (!isChaos) return false;
    final index = loopIndex(token.owner, token.progress);
    if (!_itemLoopIndices.contains(index)) return false;
    final side = itemSideForLoopIndex(index);
    if (side == null) return false;

    // A player may keep one defensive/utility power, while offensive traps
    // bypass that slot and arm immediately. If the held slot is occupied, the
    // crystal therefore draws only from the offensive pool.
    final availableItems = powerSlotFilled(currentPlayer)
        ? PowerUp.values.where(isTrapPowerUp).toList(growable: false)
        : PowerUp.values;
    final item = availableItems[_random.nextInt(availableItems.length)];
    _itemLoopIndices.remove(index);
    if (showEffect) {
      _showEffect(
        index,
        currentPlayer.isHuman ? item : null,
        kind: PowerEffectKind.pickup,
      );
    }
    if (isTrapPowerUp(item)) {
      traps.add(
        BoardTrap(owner: currentPlayer.color, type: item, loopIndex: index),
      );
      message = currentPlayer.isHuman
          ? 'Encontraste ${powerUpName(item)}. Se armó automáticamente y quedó oculta en la casilla ${index + 1}.'
          : '${currentPlayer.name} encontró un objeto sorpresa y dejó una trampa oculta.';
      _recordEvent(
        type: GameEventType.trap,
        description: message,
        tokenId: token.id,
        fromProgress: token.progress,
        toProgress: token.progress,
      );
    } else {
      currentPlayer.inventory = item;
      message = currentPlayer.isHuman
          ? 'Encontraste ${powerUpName(item)}. Quedó guardado.'
          : '${currentPlayer.name} encontró un objeto sorpresa.';
      _recordEvent(
        type: GameEventType.powerUp,
        description: message,
        tokenId: token.id,
        fromProgress: token.progress,
        toProgress: token.progress,
      );
    }
    while (itemCountForSide(side) < _chaosItemsPerSide) {
      final countBefore = _itemLoopIndices.length;
      _spawnItemForSide(side, previousIndex: index);
      if (_itemLoopIndices.length == countBefore) break;
    }
    return true;
  }

  void roll() {
    if (hasRolled || gameOver || effectResolving) return;
    final queuedBonuses = remainingDice
        .where((value) => value == 10 || value == 20)
        .toList(growable: false);
    rollSerial++;
    dice = [_random.nextInt(6) + 1, _random.nextInt(6) + 1];
    _recordEvent(
      type: GameEventType.roll,
      description: currentPlayer.isHuman
          ? 'Sacaste ${dice[0]} y ${dice[1]}.'
          : '${currentPlayer.name} sacó ${dice[0]} y ${dice[1]}.',
      dice: (dice[0], dice[1]),
    );
    if (dice[0] == dice[1]) {
      consecutiveDoubles++;
    } else {
      consecutiveDoubles = 0;
    }
    if (consecutiveDoubles >= 3) {
      final advanced =
          currentPlayer.tokens
              .where(
                (token) =>
                    !token.inNest &&
                    !token.finished &&
                    token.progress < commonPathLength,
              )
              .toList()
            ..sort((a, b) => b.progress.compareTo(a.progress));
      final penalized = advanced.isEmpty ? null : advanced.first;
      final hasProtectedLaneToken = currentPlayer.tokens.any(
        (token) =>
            token.progress >= commonPathLength &&
            token.progress < finishProgress,
      );
      final previousProgress = penalized?.progress;
      final openedBarrier =
          penalized != null && _barrierTokensFor(penalized).length >= 2;
      if (penalized != null) penalized.progress = -1;
      consecutiveDoubles = 0;
      dice = [dice[0], 0];
      hasRolled = true;
      message = penalized == null
          ? hasProtectedLaneToken
                ? 'Tres dobles: las fichas del pasillo final están protegidas.'
                : 'Tres dobles: no había una ficha en juego para penalizar.'
          : 'Tres dobles: la ficha ${penalized.id + 1} de '
                '${currentPlayer.name} volvió a la cárcel.'
                '${openedBarrier ? ' La barrera se abrió.' : ''}';
      _recordEvent(
        type: GameEventType.threeDoublesPenalty,
        description: message,
        tokenId: penalized?.id,
        fromProgress: previousProgress,
        toProgress: penalized?.progress,
      );
      notifyListeners();
      _scheduleEndTurn(const Duration(milliseconds: 900));
      return;
    }
    remainingDice
      ..clear()
      ..addAll(dice)
      ..addAll(queuedBonuses);
    hasRolled = true;
    message = currentPlayer.isHuman
        ? 'Sacaste ${dice[0]} y ${dice[1]}.'
        : '${currentPlayer.name} sacó ${dice[0]} y ${dice[1]}.';
    if (!hasAnyMove()) {
      message = currentPlayer.isHuman
          ? 'No tienes movimientos.'
          : '${currentPlayer.name} no tiene movimientos.';
      _recordEvent(type: GameEventType.noMove, description: message);
      _scheduleEndTurn(const Duration(milliseconds: 650));
    }
    notifyListeners();
  }

  bool canMove(GameToken token, int die) => _canMoveAmount(token, die);

  bool _canMoveAmount(
    GameToken token,
    int amount, {
    bool allowNestExit = true,
    bool enforceFiveReservation = true,
    bool allowHomeEntryCapture = true,
  }) {
    if (amount <= 0 || token.owner != currentPlayer.color || token.finished) {
      return false;
    }
    if (token.inNest) {
      return allowNestExit && amount == 5 && !_startBlocked(token.owner);
    }
    if (enforceFiveReservation &&
        amount == 5 &&
        mustUseFiveToLeaveNest(token.owner)) {
      return false;
    }
    final capturesAtHomeEntry =
        allowHomeEntryCapture && _isHomeEntryCapture(token, amount);
    final destination = token.progress + amount;
    if (destination > finishProgress) return false;
    for (var step = token.progress + 1; step <= destination; step++) {
      if (step < commonPathLength) {
        final global = loopIndex(token.owner, step);
        if (_isLoopBarrier(global)) return false;
        if (global == homeEntryOffset[token.owner] &&
            _opponentsAt(token.owner, global).isNotEmpty &&
            !capturesAtHomeEntry) {
          return false;
        }
        if (step == destination) {
          if (_commonOccupancy(global) >= 2) return false;
          if (_safeOccupiedByOpponent(token.owner, global)) return false;
        }
      } else if (step < finishProgress) {
        if (_laneOccupancy(token.owner, step) >= 2) return false;
      }
    }
    return true;
  }

  bool mustUseFiveToLeaveNest(PlayerColor owner) {
    final player = players.firstWhere((player) => player.color == owner);
    return player.tokens.any((token) => token.inNest) && !_startBlocked(owner);
  }

  List<int> legalDiceFor(GameToken token) =>
      remainingDice.where((die) => canMove(token, die)).toList();

  List<int> legalDieValuesFor(GameToken token) {
    final values = legalDiceFor(token).toSet().toList()..sort();
    return values;
  }

  List<int>? _rolledDiceAvailableForCombinedMove() {
    if (!hasRolled ||
        dice.length != 2 ||
        dice.any((value) => value <= 0) ||
        remainingDice.length != 2) {
      return null;
    }
    final unmatched = List<int>.of(remainingDice);
    for (final value in dice) {
      if (!unmatched.remove(value)) return null;
    }
    return unmatched.isEmpty ? List<int>.of(dice) : null;
  }

  int? allDiceTotalFor(GameToken token) {
    final values = _rolledDiceAvailableForCombinedMove();
    if (values == null || token.inNest) return null;
    if (values.contains(5) && mustUseFiveToLeaveNest(token.owner)) return null;
    final total = values.fold<int>(0, (sum, value) => sum + value);
    return _canMoveAmount(
          token,
          total,
          allowNestExit: false,
          enforceFiveReservation: false,
          allowHomeEntryCapture: false,
        )
        ? total
        : null;
  }

  bool canMoveUsingAllDice(GameToken token) => allDiceTotalFor(token) != null;

  int? destinationProgressUsingAllDice(GameToken token) {
    final total = allDiceTotalFor(token);
    return total == null ? null : token.progress + total;
  }

  Offset? destinationCellUsingAllDice(GameToken token) {
    final destination = destinationProgressUsingAllDice(token);
    return destination == null
        ? null
        : cellForProgress(token.owner, destination);
  }

  bool isHomeEntryCaptureMove(GameToken token, int die) {
    if (die <= 0 ||
        token.owner != currentPlayer.color ||
        token.finished ||
        token.inNest) {
      return false;
    }
    if (die == 5 && mustUseFiveToLeaveNest(token.owner)) return false;
    return _isHomeEntryCapture(token, die);
  }

  int? destinationProgressFor(GameToken token, int die) {
    if (!canMove(token, die)) return null;
    return token.inNest ? 0 : token.progress + die;
  }

  Offset? cellForProgress(PlayerColor owner, int progress) {
    if (progress < 0) return null;
    if (progress < commonPathLength) {
      return loop[loopIndex(owner, progress)];
    }
    if (progress < finishProgress) {
      return homeLanes[owner]![progress - commonPathLength];
    }
    return goalCells[owner];
  }

  List<Offset> movementCellsFor(GameToken token, int die) {
    final destination = destinationProgressFor(token, die);
    if (destination == null) return const <Offset>[];
    if (token.inNest) return <Offset>[cellForProgress(token.owner, 0)!];
    return <Offset>[
      for (
        var progress = token.progress + 1;
        progress <= destination;
        progress++
      )
        cellForProgress(token.owner, progress)!,
    ];
  }

  Offset? destinationCellFor(GameToken token, int die) {
    final route = movementCellsFor(token, die);
    return route.isEmpty ? null : route.last;
  }

  bool hasAnyMove() => currentPlayer.tokens.any(
    (token) =>
        remainingDice.any((die) => canMove(token, die)) ||
        canMoveUsingAllDice(token),
  );

  bool moveToken(GameToken token, {int? die}) {
    if (!hasRolled || gameOver || effectResolving) return false;
    final legal = legalDiceFor(token);
    if (legal.isEmpty) return false;
    if (die != null && !legal.contains(die)) return false;
    if (die == null && legal.toSet().length > 1) return false;
    final used = die ?? legal.first;
    return _moveTokenByAmount(token, used: used, consumedDice: <int>[used]);
  }

  bool moveTokenUsingAllDice(GameToken token) {
    if (!hasRolled || gameOver || effectResolving) return false;
    final consumedDice = _rolledDiceAvailableForCombinedMove();
    final total = allDiceTotalFor(token);
    if (consumedDice == null || total == null) return false;
    return _moveTokenByAmount(
      token,
      used: total,
      consumedDice: consumedDice,
      usingAllDice: true,
    );
  }

  bool _moveTokenByAmount(
    GameToken token, {
    required int used,
    required List<int> consumedDice,
    bool usingAllDice = false,
  }) {
    final effectSerialBeforeMove = effectSerial;
    _lastCapturedToken = null;
    final capturesAtHomeEntry =
        !usingAllDice && _isHomeEntryCapture(token, used);
    final previousProgress = token.progress;
    final previousBarrier = _barrierTokensFor(token);
    for (final value in consumedDice) {
      remainingDice.remove(value);
    }
    final enteredFromNest = token.inNest;

    if (enteredFromNest) {
      token.progress = 0;
      message = currentPlayer.isHuman
          ? 'Sacaste una ficha.'
          : '${currentPlayer.name} sacó una ficha.';
    } else {
      token.progress += used;
      message = usingAllDice
          ? currentPlayer.isHuman
                ? 'Avanzaste $used usando ambos dados.'
                : '${currentPlayer.name} avanzó $used usando ambos dados.'
          : currentPlayer.isHuman
          ? 'Avanzaste $used.'
          : '${currentPlayer.name} avanzó $used.';
    }
    _recordEvent(
      type: enteredFromNest ? GameEventType.departure : GameEventType.move,
      description: enteredFromNest
          ? '${currentPlayer.name} sacó la ficha ${token.id + 1} de la cárcel.'
          : usingAllDice
          ? '${currentPlayer.name} usó todos los dados '
                '(${consumedDice.join(' + ')}) con la ficha '
                '${token.id + 1} y avanzó $used pasos.'
          : '${currentPlayer.name} movió la ficha ${token.id + 1} '
                '$used pasos.',
      dice: usingAllDice && consumedDice.length == 2
          ? (consumedDice[0], consumedDice[1])
          : null,
      tokenId: token.id,
      fromProgress: previousProgress,
      toProgress: token.progress,
    );
    if (previousBarrier.length >= 2) {
      _recordEvent(
        type: GameEventType.barrierOpened,
        description:
            '${currentPlayer.name} abrió su barrera al mover la ficha '
            '${token.id + 1}.',
        tokenId: token.id,
        fromProgress: previousProgress,
        toProgress: token.progress,
      );
    }

    var captured = capturesAtHomeEntry && _captureAtHomeEntry(token.owner);
    final landingProgress = token.progress;
    final trapTriggered =
        token.progress < commonPathLength && _triggerTrapAt(token);
    if (token.progress == landingProgress &&
        token.progress < commonPathLength &&
        _captureAt(token, enteredFromNest: enteredFromNest)) {
      captured = true;
    }
    if (captured) remainingDice.add(20);
    if (!trapTriggered && token.progress < commonPathLength) {
      _collectItemAt(token, showEffect: !captured);
    }
    if (captured) {
      message = currentPlayer.isHuman
          ? '$message Bono +20: cada color muestra dónde puede caer tu ficha.'
          : '$message ${currentPlayer.name} ganó un bono de 20 pasos.';
    }
    if (token.progress >= finishProgress) {
      token.progress = finishProgress;
      remainingDice.add(10);
      _showBoardEvent(
        GameEngine.goalCells[token.owner]!,
        kind: PowerEffectKind.goal,
        owner: token.owner,
      );
      message = currentPlayer.isHuman
          ? '¡Llevaste una ficha a casa!'
          : '¡${currentPlayer.name} llevó una ficha a casa!';
      _recordEvent(
        type: GameEventType.goal,
        description:
            '${currentPlayer.name} llevó la ficha ${token.id + 1} a la meta.',
        tokenId: token.id,
        fromProgress: previousProgress,
        toProgress: token.progress,
      );
    } else if (captured && !trapTriggered) {
      final captureIndex = capturesAtHomeEntry
          ? homeEntryOffset[token.owner]!
          : loopIndex(token.owner, token.progress);
      _showBoardEvent(
        GameEngine.loop[captureIndex],
        kind: enteredFromNest
            ? PowerEffectKind.departureCapture
            : PowerEffectKind.capture,
        owner: token.owner,
        loopPosition: captureIndex,
        affectedToken: _lastCapturedToken,
      );
    } else if (enteredFromNest && effectSerial == effectSerialBeforeMove) {
      final departureIndex = startOffset[token.owner]!;
      _showBoardEvent(
        GameEngine.loop[departureIndex],
        kind: PowerEffectKind.departure,
        owner: token.owner,
        loopPosition: departureIndex,
      );
    }
    final resultingBarrier = _barrierTokensFor(token);
    if (resultingBarrier.length >= 2) {
      final pieceNumbers =
          resultingBarrier.map((piece) => piece.id + 1).toList()..sort();
      _recordEvent(
        type: GameEventType.barrierFormed,
        description:
            '${currentPlayer.name} formó una barrera con las fichas '
            '${pieceNumbers.join(' y ')}.',
        tokenId: token.id,
        fromProgress: previousProgress,
        toProgress: token.progress,
      );
    }
    if (currentPlayer.tokens.every((item) => item.finished)) {
      _finishGame();
      notifyListeners();
      return true;
    }

    if (remainingDice.isEmpty || !hasAnyMove()) {
      _scheduleEndTurn(Duration(milliseconds: trapTriggered ? 2300 : 450));
    }
    notifyListeners();
    return true;
  }

  bool _captureAt(GameToken moved, {bool enteredFromNest = false}) {
    final index = loopIndex(moved.owner, moved.progress);
    final capturesFromOwnStart =
        enteredFromNest && index == startOffset[moved.owner];
    return _captureAtLoopIndex(
      moved.owner,
      index,
      forcedSafeCapture: capturesFromOwnStart,
    );
  }

  bool _captureAtHomeEntry(PlayerColor owner) => _captureAtLoopIndex(
    owner,
    homeEntryOffset[owner]!,
    forcedSafeCapture: true,
    homeEntryCapture: true,
  );

  bool _captureAtLoopIndex(
    PlayerColor owner,
    int index, {
    bool forcedSafeCapture = false,
    bool homeEntryCapture = false,
  }) {
    if (safeLoopIndices.contains(index) && !forcedSafeCapture) return false;
    final targets = _opponentsAt(owner, index);

    // Capturing is strictly a one-versus-one action. A square containing two
    // rival tokens is a barrier and remains protected even if a special move
    // or a future caller reaches this central capture routine.
    if (targets.length != 1) return false;

    final token = targets.single;
    final player = players.firstWhere(
      (candidate) => candidate.color == token.owner,
    );

    final capturedProgress = token.progress;
    token.progress = -1;
    _lastCapturedToken = token;
    _recordEvent(
      type: GameEventType.capture,
      description:
          '${currentPlayer.name} capturó la ficha ${token.id + 1} de '
          '${player.name}.',
      tokenId: token.id,
      fromProgress: capturedProgress,
      toProgress: token.progress,
      target: player,
    );
    message = homeEntryCapture
        ? currentPlayer.isHuman
              ? '¡Despejaste tu entrada y capturaste una ficha!'
              : '¡${currentPlayer.name} despejó su entrada!'
        : currentPlayer.isHuman
        ? '¡Capturaste una ficha!'
        : '¡${currentPlayer.name} capturó una ficha!';
    return true;
  }

  bool _isHomeEntryCapture(GameToken token, int die) {
    if (die != 5 || token.progress != commonPathLength - 2) return false;
    final entry = homeEntryOffset[token.owner]!;
    return !_isLoopBarrier(entry) &&
        _opponentsAt(token.owner, entry).length == 1;
  }

  List<GameToken> _opponentsAt(PlayerColor owner, int loopPosition) => players
      .where((player) => player.color != owner)
      .expand((player) => player.tokens)
      .where(
        (token) =>
            !token.inNest &&
            !token.finished &&
            token.progress < commonPathLength &&
            loopIndex(token.owner, token.progress) == loopPosition,
      )
      .toList();

  bool _safeOccupiedByOpponent(PlayerColor owner, int loopPosition) {
    if (!safeLoopIndices.contains(loopPosition)) return false;
    return players.any(
      (player) =>
          player.color != owner &&
          player.tokens.any(
            (token) =>
                !token.inNest &&
                !token.finished &&
                token.progress < commonPathLength &&
                loopIndex(token.owner, token.progress) == loopPosition,
          ),
    );
  }

  bool _startBlocked(PlayerColor owner) {
    final start = startOffset[owner]!;
    return _isLoopBarrier(start) || _commonOccupancy(start) >= 2;
  }

  bool _isLoopBarrier(int loopPosition) {
    for (final player in players) {
      final count = player.tokens.where((token) {
        return token.progress >= 0 &&
            token.progress < commonPathLength &&
            loopIndex(token.owner, token.progress) == loopPosition;
      }).length;
      if (count >= 2) return true;
    }
    return false;
  }

  List<GameToken> _barrierTokensFor(GameToken token) {
    if (token.inNest || token.finished) return const <GameToken>[];
    final owner = players.firstWhere((player) => player.color == token.owner);
    if (token.progress < commonPathLength) {
      final index = loopIndex(token.owner, token.progress);
      return owner.tokens
          .where(
            (other) =>
                !other.inNest &&
                !other.finished &&
                other.progress < commonPathLength &&
                loopIndex(other.owner, other.progress) == index,
          )
          .toList();
    }
    return owner.tokens
        .where((other) => other.progress == token.progress)
        .toList();
  }

  int _commonOccupancy(int loopPosition) => players
      .expand((player) => player.tokens)
      .where(
        (token) =>
            token.progress >= 0 &&
            token.progress < commonPathLength &&
            loopIndex(token.owner, token.progress) == loopPosition,
      )
      .length;

  int _laneOccupancy(PlayerColor owner, int progress) => players
      .firstWhere((player) => player.color == owner)
      .tokens
      .where((token) => token.progress == progress)
      .length;

  int loopIndex(PlayerColor color, int progress) =>
      (startOffset[color]! + progress) % loop.length;

  Offset? tokenCell(GameToken token) {
    if (token.inNest || token.finished) return null;
    return cellForProgress(token.owner, token.progress);
  }

  void endTurn() {
    if (gameOver) return;
    _turnTimer?.cancel();
    _turnTimer = null;
    _effectResolutionTimer?.cancel();
    effectResolving = false;
    final rolledPlayer = currentPlayer;
    final rolledDouble = dice[0] == dice[1];
    final skippedPlayers = <String>[];
    remainingDice.clear();
    hasRolled = false;
    pendingTrapPlacement = false;
    if (!rolledDouble) {
      currentPlayerIndex = (currentPlayerIndex + 1) % players.length;
    }
    var inspectedPlayers = 0;
    while (inspectedPlayers < players.length &&
        (players[currentPlayerIndex].tokens.every((token) => token.finished) ||
            players[currentPlayerIndex].skippedTurns > 0)) {
      if (players[currentPlayerIndex].skippedTurns > 0) {
        skippedPlayers.add(players[currentPlayerIndex].name);
        players[currentPlayerIndex].skippedTurns--;
      }
      currentPlayerIndex = (currentPlayerIndex + 1) % players.length;
      inspectedPlayers++;
    }
    final keepsDoubleTurn = rolledDouble && skippedPlayers.isEmpty;
    if (rolledDouble && skippedPlayers.isNotEmpty) {
      consecutiveDoubles = 0;
    }
    turnNumber++;
    final nextTurnMessage = keepsDoubleTurn
        ? rolledPlayer.isHuman
              ? 'Sacaste dobles. ¡Tira otra vez!'
              : '${rolledPlayer.name} sacó dobles. ¡Tira otra vez!'
        : currentPlayer.isHuman
        ? '¡Tu turno!'
        : 'Turno de ${currentPlayer.name}.';
    message = skippedPlayers.isEmpty
        ? nextTurnMessage
        : '${skippedPlayers.join(' y ')} '
              '${skippedPlayers.length == 1 ? 'perdió' : 'perdieron'} '
              'su turno por el pegamento. '
              '$nextTurnMessage';
    _recordEvent(type: GameEventType.turnStarted, description: message);
    notifyListeners();
  }

  void _scheduleEndTurn(Duration delay) {
    _turnTimer?.cancel();
    _turnTimer = Timer(delay, () {
      _turnTimer = null;
      endTurn();
    });
  }

  GameToken? chooseCpuMove() {
    final legalTokens = currentPlayer.tokens
        .where(
          (token) =>
              legalDiceFor(token).isNotEmpty || canMoveUsingAllDice(token),
        )
        .toList();
    if (legalTokens.isEmpty) return null;
    if (cpuLevel == 'Fácil') {
      return legalTokens[_random.nextInt(legalTokens.length)];
    }
    legalTokens.sort((a, b) => _scoreToken(b).compareTo(_scoreToken(a)));
    return legalTokens.first;
  }

  int? chooseCpuDie(GameToken token) {
    final legal = legalDieValuesFor(token);
    if (legal.isEmpty) return null;
    if (cpuLevel == 'Fácil') return legal[_random.nextInt(legal.length)];
    return legal.last;
  }

  bool usePowerUp() {
    final item = currentPlayer.inventory;
    if (!isChaos || item == null || gameOver || effectResolving) return false;
    switch (item) {
      case PowerUp.shield:
        message = currentPlayer.isHuman
            ? 'Escudo listo: se activará automáticamente al caer en una trampa rival.'
            : '${currentPlayer.name} tiene un escudo automático preparado.';
        notifyListeners();
        return true;
      case PowerUp.boost:
        final movable =
            currentPlayer.tokens
                .where((token) => !token.inNest && !token.finished)
                .toList()
              ..sort((a, b) => b.progress.compareTo(a.progress));
        if (movable.isEmpty) return false;
        final token = movable.first;
        var amount = 3;
        while (amount > 0 && !canMove(token, amount)) {
          amount--;
        }
        if (amount == 0) return false;
        currentPlayer.inventory = null;
        _lastCapturedToken = null;
        final previousProgress = token.progress;
        token.progress += amount;
        _recordEvent(
          type: GameEventType.powerUp,
          description:
              '${currentPlayer.name} usó Turbo con la ficha '
              '${token.id + 1} y avanzó $amount pasos.',
          tokenId: token.id,
          fromProgress: previousProgress,
          toProgress: token.progress,
        );
        var resolvedLanding = false;
        if (token.progress < commonPathLength) {
          final landingProgress = token.progress;
          final trapTriggered = _triggerTrapAt(token);
          final captured =
              token.progress == landingProgress && _captureAt(token);
          if (captured) {
            remainingDice.add(20);
          }
          if (trapTriggered) {
            resolvedLanding = true;
          } else if (captured) {
            final captureIndex = loopIndex(token.owner, token.progress);
            _showBoardEvent(
              GameEngine.loop[captureIndex],
              kind: PowerEffectKind.capture,
              owner: token.owner,
              loopPosition: captureIndex,
              affectedToken: _lastCapturedToken,
            );
            resolvedLanding = true;
          }
          if (!trapTriggered && _collectItemAt(token, showEffect: !captured)) {
            resolvedLanding = true;
          }
          if (captured) {
            message = currentPlayer.isHuman
                ? '$message Bono +20: elige una ficha para mover.'
                : '$message ${currentPlayer.name} ganó un bono de 20 pasos.';
          }
        } else if (token.progress >= finishProgress) {
          token.progress = finishProgress;
          remainingDice.add(10);
          _showBoardEvent(
            GameEngine.goalCells[token.owner]!,
            kind: PowerEffectKind.goal,
            owner: token.owner,
          );
          resolvedLanding = true;
          message = currentPlayer.isHuman
              ? '¡Turbo llevó una ficha a casa! Bono +10.'
              : '¡${currentPlayer.name} llevó una ficha a casa con Turbo y ganó un bono de 10 pasos!';
          _recordEvent(
            type: GameEventType.goal,
            description:
                '${currentPlayer.name} llevó la ficha ${token.id + 1} '
                'a la meta con Turbo.',
            tokenId: token.id,
            fromProgress: previousProgress,
            toProgress: token.progress,
          );
          _checkWinner();
        }
        if (!resolvedLanding) {
          if (token.progress < commonPathLength) {
            _showEffect(
              loopIndex(token.owner, token.progress),
              item,
              kind: PowerEffectKind.activated,
            );
          }
          message = currentPlayer.isHuman
              ? 'Avanzaste $amount con Turbo.'
              : '${currentPlayer.name} avanzó $amount con Turbo.';
        }
        notifyListeners();
        return true;
      case PowerUp.glueTrap ||
          PowerUp.setbackTrap ||
          PowerUp.prisonTrap ||
          PowerUp.bomb:
        message =
            'Las trampas se arman automáticamente en la casilla del cristal.';
        notifyListeners();
        return false;
    }
  }

  String powerUpName(PowerUp item) => switch (item) {
    PowerUp.shield => 'Escudo',
    PowerUp.boost => 'Turbo',
    PowerUp.glueTrap => 'Trampa pegajosa',
    PowerUp.setbackTrap => 'Trampa de retroceso',
    PowerUp.prisonTrap => 'Trampa cárcel',
    PowerUp.bomb => 'Bomba',
  };

  String powerUpDescription(PowerUp item) => switch (item) {
    PowerUp.shield =>
      'Se activa automáticamente al caer en una trampa rival y se consume al bloquearla.',
    PowerUp.boost => 'Mueve tu ficha más adelantada hasta 3 pasos.',
    PowerUp.glueTrap => 'El rival que caiga aquí pierde su próximo turno.',
    PowerUp.setbackTrap => 'El rival que caiga aquí retrocede hasta 6 pasos.',
    PowerUp.prisonTrap => 'El rival que caiga aquí vuelve a la cárcel.',
    PowerUp.bomb => 'Explota y manda a la cárcel a la ficha rival.',
  };

  bool isTrapPowerUp(PowerUp item) =>
      item == PowerUp.glueTrap ||
      item == PowerUp.setbackTrap ||
      item == PowerUp.prisonTrap ||
      item == PowerUp.bomb;

  bool placePendingTrap(int loopPosition) {
    final item = currentPlayer.inventory;
    if (!pendingTrapPlacement || item == null || !isTrapPowerUp(item)) {
      return false;
    }
    return _placeTrap(loopPosition, item);
  }

  void cancelTrapPlacement() {
    if (!pendingTrapPlacement) return;
    pendingTrapPlacement = false;
    message = 'Colocación de trampa cancelada.';
    notifyListeners();
  }

  int? suggestedTrapIndex() {
    final opponents =
        players
            .where((player) => player.color != currentPlayer.color)
            .expand((player) => player.tokens)
            .where(
              (token) =>
                  !token.inNest &&
                  !token.finished &&
                  token.progress < commonPathLength,
            )
            .toList()
          ..sort((a, b) => b.progress.compareTo(a.progress));
    final seed = opponents.isEmpty
        ? (startOffset[currentPlayer.color]! + 8) % loopLength
        : loopIndex(opponents.first.owner, opponents.first.progress);
    for (var distance = 2; distance <= loopLength; distance++) {
      final candidate = (seed + distance) % loopLength;
      if (_canPlaceTrap(candidate)) return candidate;
    }
    return null;
  }

  bool _placeTrap(int loopPosition, PowerUp type) {
    if (!isChaos || !isTrapPowerUp(type) || !_canPlaceTrap(loopPosition)) {
      return false;
    }
    traps.add(
      BoardTrap(
        owner: currentPlayer.color,
        type: type,
        loopIndex: loopPosition,
      ),
    );
    pendingTrapPlacement = false;
    currentPlayer.inventory = null;
    if (currentPlayer.isHuman) {
      _showEffect(loopPosition, type, kind: PowerEffectKind.armed);
    }
    message = currentPlayer.isHuman
        ? 'Colocaste ${powerUpName(type).toLowerCase()} oculta en la casilla ${loopPosition + 1}.'
        : '${currentPlayer.name} colocó una trampa oculta.';
    _recordEvent(type: GameEventType.trap, description: message);
    notifyListeners();
    return true;
  }

  bool _canPlaceTrap(int loopPosition) =>
      loopPosition >= 0 &&
      loopPosition < loopLength &&
      !safeLoopIndices.contains(loopPosition) &&
      !_itemLoopIndices.contains(loopPosition) &&
      !traps.any((trap) => trap.loopIndex == loopPosition);

  bool _triggerTrapAt(GameToken token) {
    if (!isChaos) return false;
    if (_lastTrapEffectTurn[token.owner] == turnNumber) return false;
    final index = loopIndex(token.owner, token.progress);
    final trapPosition = traps.indexWhere(
      (trap) => trap.loopIndex == index && trap.owner != token.owner,
    );
    if (trapPosition < 0) return false;
    _lastTrapEffectTurn[token.owner] = turnNumber;
    final trap = traps.removeAt(trapPosition);
    final player = players.firstWhere((item) => item.color == token.owner);
    final trapOwner = players.firstWhere((item) => item.color == trap.owner);
    final landingProgress = token.progress;
    if (_consumeAutomaticShield(
      player: player,
      token: token,
      loopIndex: index,
      blockedTrap: trap.type,
    )) {
      _recordEvent(
        type: GameEventType.trap,
        description:
            'La trampa ${powerUpName(trap.type)} de ${trapOwner.name} '
            'fue bloqueada por el escudo de ${player.name}.',
        player: trapOwner,
        tokenId: token.id,
        fromProgress: landingProgress,
        toProgress: token.progress,
        target: player,
      );
      return true;
    }
    _showEffect(
      index,
      trap.type,
      kind: PowerEffectKind.triggered,
      affectedToken: token,
    );
    _beginEffectResolution();
    switch (trap.type) {
      case PowerUp.glueTrap:
        player.skippedTurns++;
        message = '¡PEGAMENTO! ${player.name} perderá su próximo turno.';
      case PowerUp.setbackTrap:
        final previousProgress = token.progress;
        token.progress = _setbackDestination(token, maximumSteps: 6);
        final setback = previousProgress - token.progress;
        message = '¡RETROCESO! ${player.name} retrocedió $setback pasos.';
      case PowerUp.prisonTrap:
        token.progress = -1;
        message = '¡TRAMPA CÁRCEL! ${player.name} volvió a la cárcel.';
      case PowerUp.bomb:
        token.progress = -1;
        message = '¡BOMBA! ${player.name} volvió a la cárcel.';
      case PowerUp.shield || PowerUp.boost:
        return false;
    }
    _recordEvent(
      type: GameEventType.trap,
      description: message,
      player: trapOwner,
      tokenId: token.id,
      fromProgress: landingProgress,
      toProgress: token.progress,
      target: player,
    );
    return true;
  }

  int _setbackDestination(GameToken token, {required int maximumSteps}) {
    final origin = token.progress;
    var destination = origin;
    final availableSteps = mathMin(maximumSteps, origin);
    for (var distance = 1; distance <= availableSteps; distance++) {
      final candidateProgress = origin - distance;
      final candidateLoopIndex = loopIndex(token.owner, candidateProgress);
      if (_isLoopBarrier(candidateLoopIndex) ||
          _commonOccupancy(candidateLoopIndex) >= 2) {
        break;
      }
      if (_opponentsAt(token.owner, candidateLoopIndex).isNotEmpty ||
          _safeOccupiedByOpponent(token.owner, candidateLoopIndex)) {
        continue;
      }
      destination = candidateProgress;
    }
    return destination;
  }

  bool _consumeAutomaticShield({
    required PlayerState player,
    required GameToken token,
    required int loopIndex,
    required PowerUp blockedTrap,
  }) {
    final hasStoredShield = player.inventory == PowerUp.shield;
    if (!hasStoredShield && !player.shielded) return false;

    if (hasStoredShield) player.inventory = null;
    player.shielded = false;
    _showEffect(
      loopIndex,
      PowerUp.shield,
      kind: PowerEffectKind.blocked,
      affectedToken: token,
    );
    _beginEffectResolution();
    final trapName = powerUpName(blockedTrap).toLowerCase();
    message = player.isHuman
        ? '¡PROTEGIDO! Tu escudo automático bloqueó $trapName.'
        : '¡PROTEGIDO! El escudo de ${player.name} bloqueó $trapName.';
    return true;
  }

  void _showEffect(
    int loopPosition,
    PowerUp? item, {
    required PowerEffectKind kind,
    GameToken? affectedToken,
  }) {
    effectLoopIndex = loopPosition;
    effectBoardCell = GameEngine.loop[loopPosition];
    effectPowerUp = item;
    effectKind = kind;
    effectToken = affectedToken;
    effectOwner = null;
    effectSerial++;
  }

  void _showBoardEvent(
    Offset boardCell, {
    required PowerEffectKind kind,
    required PlayerColor owner,
    int? loopPosition,
    GameToken? affectedToken,
  }) {
    effectLoopIndex = loopPosition;
    effectBoardCell = boardCell;
    effectPowerUp = null;
    effectKind = kind;
    effectToken = affectedToken;
    effectOwner = owner;
    effectSerial++;
  }

  void _beginEffectResolution() {
    effectResolving = true;
    _effectResolutionTimer?.cancel();
    _effectResolutionTimer = Timer(const Duration(milliseconds: 2200), () {
      effectResolving = false;
      notifyListeners();
    });
  }

  void _checkWinner() {
    if (!currentPlayer.tokens.every((item) => item.finished)) return;
    _finishGame();
  }

  bool continueAfterWinner() {
    if (!canContinueAfterWinner) return false;
    spectatorContinuationActive = true;
    gameOver = false;
    remainingDice.clear();
    hasRolled = false;
    pendingTrapPlacement = false;
    consecutiveDoubles = 0;
    _advanceToNextUnfinishedPlayer();
    turnNumber++;
    message = currentPlayer.isHuman
        ? 'La partida continúa. ¡Te toca!'
        : 'La partida continúa. Turno de ${currentPlayer.name}.';
    _recordEvent(type: GameEventType.turnStarted, description: message);
    notifyListeners();
    return true;
  }

  void _advanceToNextUnfinishedPlayer() {
    for (var offset = 1; offset <= players.length; offset++) {
      final candidate = (currentPlayerIndex + offset) % players.length;
      if (!_standings.hasFinished(players[candidate].color)) {
        currentPlayerIndex = candidate;
        return;
      }
    }
  }

  void _finishGame() {
    _standings.recordFinish(currentPlayer.color);
    _standings.assignLastPlaceIfDecided();
    winner ??= currentPlayer;
    remainingDice.clear();
    hasRolled = false;
    pendingTrapPlacement = false;
    consecutiveDoubles = 0;
    _effectResolutionTimer?.cancel();
    effectResolving = false;
    final placement = _standings.placementFor(currentPlayer.color)!;
    if (!spectatorContinuationActive) {
      gameOver = true;
      message = currentPlayer.isHuman
          ? '¡Ganaste la partida!'
          : '¡${currentPlayer.name} ganó la partida!';
    } else if (_standings.isComplete) {
      gameOver = true;
      message =
          'Finalizó la partida. Ya quedaron definidas las cuatro posiciones.';
    } else {
      gameOver = false;
      message = '${currentPlayer.name} llegó en la posición $placement.';
    }
    _recordEvent(type: GameEventType.victory, description: message);
    if (!gameOver) {
      _advanceToNextUnfinishedPlayer();
      turnNumber++;
      message = currentPlayer.isHuman
          ? 'La partida continúa. ¡Te toca!'
          : 'La partida continúa. Turno de ${currentPlayer.name}.';
      _recordEvent(type: GameEventType.turnStarted, description: message);
    }
  }

  int mathMin(int a, int b) => a < b ? a : b;
  int mathMax(int a, int b) => a > b ? a : b;

  int _scoreToken(GameToken token) {
    if (token.inNest) return 35;
    var score = token.progress;
    for (final die in legalDiceFor(token)) {
      final destination = destinationProgressFor(token, die)!;
      if (_isHomeEntryCapture(token, die)) score += 70;
      if (destination >= finishProgress) score += 100;
      if (destination < commonPathLength) {
        final index = loopIndex(token.owner, destination);
        if (safeLoopIndices.contains(index)) score += 18;
        for (final player in players) {
          if (player.color == token.owner) continue;
          if (player.tokens.any(
            (other) =>
                other.progress >= 0 &&
                other.progress < commonPathLength &&
                loopIndex(other.owner, other.progress) == index,
          )) {
            score += 45;
          }
        }
      }
    }
    return score;
  }

  @override
  void dispose() {
    _turnTimer?.cancel();
    _effectResolutionTimer?.cancel();
    super.dispose();
  }
}
