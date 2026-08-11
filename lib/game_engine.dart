import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/material.dart';

import 'match_rules.dart';
import 'online_spectator.dart';

export 'match_rules.dart';

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
  GameToken(this.owner, this.id, {this.progress = -1});

  final PlayerColor owner;
  final int id;
  int progress;

  bool get inNest => progress < 0;
  bool get finished => progress >= GameEngine.finishProgress;
}

/// A normalized move choice suitable for CPU, UI, and future server clients.
/// Duplicate dice values produce one command, while a combined-dice move is a
/// distinct command because it consumes a different set of resources.
class LegalMoveCommand {
  LegalMoveCommand._({
    required this.token,
    required this.die,
    required this.amount,
    required this.usesAllDice,
    required Iterable<int> consumedDice,
    required this.destinationProgress,
  }) : consumedDice = UnmodifiableListView<int>(List<int>.of(consumedDice));

  factory LegalMoveCommand.singleDie({
    required GameToken token,
    required int die,
    required int destinationProgress,
  }) => LegalMoveCommand._(
    token: token,
    die: die,
    amount: die,
    usesAllDice: false,
    consumedDice: <int>[die],
    destinationProgress: destinationProgress,
  );

  factory LegalMoveCommand.allDice({
    required GameToken token,
    required int amount,
    required Iterable<int> dice,
    required int destinationProgress,
  }) => LegalMoveCommand._(
    token: token,
    die: null,
    amount: amount,
    usesAllDice: true,
    consumedDice: dice,
    destinationProgress: destinationProgress,
  );

  final GameToken token;
  final int? die;
  final int amount;
  final bool usesAllDice;
  final UnmodifiableListView<int> consumedDice;
  final int destinationProgress;

  bool representsSameChoice(LegalMoveCommand other) {
    if (!identical(token, other.token) ||
        die != other.die ||
        amount != other.amount ||
        usesAllDice != other.usesAllDice ||
        destinationProgress != other.destinationProgress ||
        consumedDice.length != other.consumedDice.length) {
      return false;
    }
    for (var index = 0; index < consumedDice.length; index++) {
      if (consumedDice[index] != other.consumedDice[index]) return false;
    }
    return true;
  }
}

class PlayerState {
  PlayerState(
    this.color,
    this.name, {
    this.isHuman = false,
    int tokenCount = 4,
    int initialTokenProgress = -1,
    this.initialStackIntact = false,
  }) : tokens = List.generate(
         tokenCount,
         (index) => GameToken(color, index, progress: initialTokenProgress),
       );

  final PlayerColor color;
  String name;
  final bool isHuman;
  final List<GameToken> tokens;
  bool initialStackIntact;
  PowerUp? inventory;
  bool shielded = false;
  int skippedTurns = 0;
}

String _resolvedCpuName(List<String>? names, int index, String fallback) =>
    names != null && index < names.length && names[index].trim().isNotEmpty
    ? names[index].trim()
    : fallback;

String _resolvedPlayerName({
  required PlayerColor color,
  required PlayerColor localViewerColor,
  required String humanName,
  required List<String>? cpuNames,
  required Map<PlayerColor, String>? playerNames,
}) {
  final explicitName = playerNames?[color]?.trim();
  if (explicitName != null && explicitName.isNotEmpty) return explicitName;
  if (color == localViewerColor) return humanName;

  final opponentColors = PlayerColor.values
      .where((candidate) => candidate != localViewerColor)
      .toList(growable: false);
  final opponentIndex = opponentColors.indexOf(color);
  return _resolvedCpuName(cpuNames, opponentIndex, 'CPU ${opponentIndex + 1}');
}

class GameEngine extends ChangeNotifier {
  GameEngine({
    this.cpuLevel = 'Normal',
    this.mode = GameMode.traditional,
    this.matchFormat = MatchFormat.classic,
    this.localViewerColor = PlayerColor.red,
    this.initialPlayerColor = PlayerColor.red,
    bool allPlayersHuman = false,
    Random? random,
    String humanName = 'Tú',
    List<String>? cpuNames,
    Map<PlayerColor, String>? playerNames,
  }) : _random = random ?? Random(),
       rules = MatchRules.forFormat(matchFormat),
       players = [
         PlayerState(
           PlayerColor.red,
           _resolvedPlayerName(
             color: PlayerColor.red,
             localViewerColor: localViewerColor,
             humanName: humanName,
             cpuNames: cpuNames,
             playerNames: playerNames,
           ),
           isHuman: allPlayersHuman || localViewerColor == PlayerColor.red,
           tokenCount: MatchRules.forFormat(matchFormat).tokenCount,
           initialTokenProgress: MatchRules.forFormat(
             matchFormat,
           ).initialTokenProgress,
           initialStackIntact: !MatchRules.forFormat(
             matchFormat,
           ).initialStackFormsBarrier,
         ),
         PlayerState(
           PlayerColor.green,
           _resolvedPlayerName(
             color: PlayerColor.green,
             localViewerColor: localViewerColor,
             humanName: humanName,
             cpuNames: cpuNames,
             playerNames: playerNames,
           ),
           isHuman: allPlayersHuman || localViewerColor == PlayerColor.green,
           tokenCount: MatchRules.forFormat(matchFormat).tokenCount,
           initialTokenProgress: MatchRules.forFormat(
             matchFormat,
           ).initialTokenProgress,
           initialStackIntact: !MatchRules.forFormat(
             matchFormat,
           ).initialStackFormsBarrier,
         ),
         PlayerState(
           PlayerColor.yellow,
           _resolvedPlayerName(
             color: PlayerColor.yellow,
             localViewerColor: localViewerColor,
             humanName: humanName,
             cpuNames: cpuNames,
             playerNames: playerNames,
           ),
           isHuman: allPlayersHuman || localViewerColor == PlayerColor.yellow,
           tokenCount: MatchRules.forFormat(matchFormat).tokenCount,
           initialTokenProgress: MatchRules.forFormat(
             matchFormat,
           ).initialTokenProgress,
           initialStackIntact: !MatchRules.forFormat(
             matchFormat,
           ).initialStackFormsBarrier,
         ),
         PlayerState(
           PlayerColor.blue,
           _resolvedPlayerName(
             color: PlayerColor.blue,
             localViewerColor: localViewerColor,
             humanName: humanName,
             cpuNames: cpuNames,
             playerNames: playerNames,
           ),
           isHuman: allPlayersHuman || localViewerColor == PlayerColor.blue,
           tokenCount: MatchRules.forFormat(matchFormat).tokenCount,
           initialTokenProgress: MatchRules.forFormat(
             matchFormat,
           ).initialTokenProgress,
           initialStackIntact: !MatchRules.forFormat(
             matchFormat,
           ).initialStackFormsBarrier,
         ),
       ] {
    currentPlayerIndex = initialPlayerColor.index;
    message = currentPlayer.isHuman
        ? '¡Tu turno! Lanza los dados.'
        : 'Turno de ${currentPlayer.name}.';
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
  factory GameEngine.fromCheckpoint(
    Map<String, dynamic> checkpoint, {
    PlayerColor localViewerColor = PlayerColor.red,
  }) {
    final rawPlayers = (checkpoint['players'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .toList(growable: false);
    String playerName(PlayerColor color, String fallback) {
      final entry = rawPlayers.cast<Map?>().firstWhere(
        (player) => player?['color'] == color.name,
        orElse: () => null,
      );
      return entry?['name'] as String? ?? fallback;
    }

    String fallbackPlayerName(PlayerColor color) {
      if (color == localViewerColor) return 'Tú';
      final opponents = PlayerColor.values
          .where((candidate) => candidate != localViewerColor)
          .toList(growable: false);
      return 'CPU ${opponents.indexOf(color) + 1}';
    }

    final formatName = checkpoint['matchFormat'] as String?;
    final matchFormat = formatName == null
        ? MatchFormat.classic
        : MatchFormat.values.cast<MatchFormat?>().firstWhere(
            (format) => format?.name == formatName,
            orElse: () => null,
          );
    if (matchFormat == null) {
      throw FormatException('Unsupported match format: $formatName');
    }
    final rules = MatchRules.forFormat(matchFormat);
    final savedRulesVersion = checkpoint['rulesVersion'];
    if (savedRulesVersion != null && savedRulesVersion != rules.rulesVersion) {
      throw FormatException(
        'Unsupported rules version $savedRulesVersion for ${matchFormat.name}.',
      );
    }

    final modeName = checkpoint['mode'] as String?;
    final initialPlayerName = checkpoint['initialPlayer'] as String?;
    final initialPlayerColor = PlayerColor.values.firstWhere(
      (color) => color.name == initialPlayerName,
      orElse: () => PlayerColor.red,
    );
    final engine = GameEngine(
      cpuLevel: checkpoint['cpuLevel'] as String? ?? 'Normal',
      mode: modeName == GameMode.chaos.name
          ? GameMode.chaos
          : GameMode.traditional,
      matchFormat: matchFormat,
      localViewerColor: localViewerColor,
      initialPlayerColor: initialPlayerColor,
      humanName: playerName(localViewerColor, 'Tú'),
      playerNames: <PlayerColor, String>{
        for (final color in PlayerColor.values)
          color: playerName(color, fallbackPlayerName(color)),
      },
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
        player.tokens[index].progress =
            tokens[index] as int? ?? engine.rules.initialTokenProgress;
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
    final savedInitialStacks = checkpoint['initialStackIntact'] as Map?;
    for (final player in engine.players) {
      player.initialStackIntact = engine.rules.initialStackFormsBarrier
          ? false
          : savedInitialStacks?[player.color.name] as bool? ??
                player.tokens.every((token) => token.progress == 0);
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
    final savedConsecutiveDoubles = checkpoint['consecutiveDoubles'];
    engine.consecutiveDoubles = savedConsecutiveDoubles is int
        ? savedConsecutiveDoubles.clamp(0, 2)
        : 0;
    engine._lastTrapEffectTurn.clear();
    final savedTrapTurns = checkpoint['lastTrapEffectTurn'];
    if (savedTrapTurns is Map) {
      for (final entry in savedTrapTurns.entries) {
        final colorName = entry.key;
        final turn = entry.value;
        if (colorName is! String || turn is! int || turn < 0) continue;
        final color = PlayerColor.values
            .where((candidate) => candidate.name == colorName)
            .firstOrNull;
        if (color != null) engine._lastTrapEffectTurn[color] = turn;
      }
    }
    final restoredFinishOrder = <PlayerColor>[];
    final rawFinishOrder = checkpoint['finishOrder'];
    if (rawFinishOrder is List) {
      for (final rawColor in rawFinishOrder.whereType<String>()) {
        final color = PlayerColor.values
            .where((candidate) => candidate.name == rawColor)
            .firstOrNull;
        if (color == null || restoredFinishOrder.contains(color)) continue;
        engine._standings.recordFinish(color);
        restoredFinishOrder.add(color);
      }
    }
    if (restoredFinishOrder.isNotEmpty) {
      final winnerColor = restoredFinishOrder.first;
      engine.winner = engine.players.firstWhere(
        (player) => player.color == winnerColor,
      );
    }
    engine.spectatorContinuationActive =
        checkpoint['spectatorContinuationActive'] == true &&
        restoredFinishOrder.isNotEmpty &&
        !engine._standings.isComplete;
    engine.message = 'Partida reanudada.';
    engine.effectResolving = false;
    engine.pendingTrapPlacement = false;
    engine._eventHistory.clear();
    engine._nextEventSequence = 1;
    engine._recordEvent(
      type: GameEventType.matchStarted,
      description: 'La partida se reanudó desde el último punto guardado.',
    );
    // Timers are intentionally not serialized. Recreate the only pending
    // transition that can otherwise leave a restored match with no legal
    // input: a consumed roll, a no-move roll, or the third-double penalty.
    if (engine.hasRolled &&
        (engine.remainingDice.isEmpty || !engine.hasAnyMove())) {
      engine._scheduleEndTurn(Duration.zero);
    }
    return engine;
  }

  final String cpuLevel;
  final GameMode mode;
  final MatchFormat matchFormat;
  final PlayerColor localViewerColor;
  PlayerColor initialPlayerColor;
  final MatchRules rules;
  final List<PlayerState> players;
  final Random _random;
  final List<BoardTrap> traps = [];
  final Set<int> _itemLoopIndices = <int>{};
  int _chaosItemsPerSide = 1;
  final List<GameEvent> _eventHistory = <GameEvent>[];
  OnlineStandingsTracker<PlayerColor> _standings =
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

  /// Metadata that every durable checkpoint must persist alongside the board
  /// state. Legacy checkpoints without these keys migrate to Classic.
  Map<String, Object> get checkpointRuleMetadata => <String, Object>{
    'matchFormat': matchFormat.name,
    'rulesVersion': rules.rulesVersion,
    'initialPlayer': initialPlayerColor.name,
    'initialStackIntact': <String, bool>{
      for (final player in players)
        player.color.name: player.initialStackIntact,
    },
    'finishOrder': <String>[
      for (final color in _standings.finishOrder) color.name,
    ],
    'spectatorContinuationActive': spectatorContinuationActive,
    'consecutiveDoubles': consecutiveDoubles,
    'lastTrapEffectTurn': <String, int>{
      for (final entry in _lastTrapEffectTurn.entries)
        entry.key.name: entry.value,
    },
  };

  /// Complete, JSON-compatible engine state for persistence or an
  /// authoritative transport adapter.
  ///
  /// This trusted checkpoint includes held powers and hidden traps. A network
  /// service must redact information that the receiving viewer is not allowed
  /// to see before distributing it to an untrusted client.
  Map<String, Object?> createCheckpoint() => <String, Object?>{
    ...checkpointRuleMetadata,
    'mode': mode.name,
    'cpuLevel': cpuLevel,
    'turn': turnNumber,
    'currentPlayer': currentPlayer.color.name,
    'dice': List<int>.of(dice),
    'remainingDice': List<int>.of(remainingDice),
    'hasRolled': hasRolled,
    'rollSerial': rollSerial,
    'gameOver': gameOver,
    'winner': winner?.color.name,
    'message': message,
    'pendingTrapPlacement': pendingTrapPlacement,
    'chaosItemsPerSide': _chaosItemsPerSide,
    'players': <Map<String, Object?>>[
      for (final player in players)
        <String, Object?>{
          'color': player.color.name,
          'name': player.name,
          'tokens': <int>[for (final token in player.tokens) token.progress],
          'inventory': player.inventory?.name,
          'shielded': player.shielded,
          'skippedTurns': player.skippedTurns,
        },
    ],
    'traps': <Map<String, Object>>[
      for (final trap in traps)
        <String, Object>{
          'owner': trap.owner.name,
          'type': trap.type.name,
          'loopIndex': trap.loopIndex,
        },
    ],
    'items': _itemLoopIndices.toList(growable: false)..sort(),
    'effectSerial': effectSerial,
    'effectLoopIndex': effectLoopIndex,
    'effectBoardCell': effectBoardCell == null
        ? null
        : <String, double>{
            'dx': effectBoardCell!.dx,
            'dy': effectBoardCell!.dy,
          },
    'effectPowerUp': effectPowerUp?.name,
    'effectKind': effectKind?.name,
    'effectToken': _checkpointTokenReference(effectToken),
    'effectOwner': effectOwner?.name,
    'effectResolving': effectResolving,
    'lastCapturedToken': _checkpointTokenReference(_lastCapturedToken),
    'events': <Map<String, Object?>>[
      for (final event in _eventHistory)
        <String, Object?>{
          'sequence': event.sequence,
          'turn': event.turn,
          'type': event.type.name,
          'playerName': event.playerName,
          'playerColor': event.playerColor.name,
          'description': event.description,
          'dice': event.dice == null
              ? null
              : <int>[event.dice!.$1, event.dice!.$2],
          'tokenId': event.tokenId,
          'fromProgress': event.fromProgress,
          'toProgress': event.toProgress,
          'targetName': event.targetName,
          'targetColor': event.targetColor?.name,
        },
    ],
    'nextEventSequence': _nextEventSequence,
  };

  Map<String, Object>? _checkpointTokenReference(GameToken? token) =>
      token == null
      ? null
      : <String, Object>{'owner': token.owner.name, 'id': token.id};

  /// Replaces this engine's state with a complete authoritative checkpoint.
  ///
  /// No local transition timer is recreated: a network replica must wait for
  /// the authority to publish the next revision instead of advancing itself.
  /// The update is parsed into a temporary engine first, so an invalid payload
  /// cannot leave this instance half-mutated.
  void applyRemoteCheckpoint(Map<String, dynamic> checkpoint) {
    _validateRemoteCheckpoint(checkpoint);
    final incoming = GameEngine.fromCheckpoint(
      checkpoint,
      localViewerColor: localViewerColor,
    );
    try {
      incoming._turnTimer?.cancel();
      incoming._turnTimer = null;
      incoming._effectResolutionTimer?.cancel();
      incoming._effectResolutionTimer = null;
      incoming._restoreRemotePresentation(checkpoint);
      _copyRemoteStateFrom(incoming);
    } finally {
      incoming.dispose();
    }
    notifyListeners();
  }

  void _validateRemoteCheckpoint(Map<String, dynamic> checkpoint) {
    if (checkpoint['matchFormat'] != matchFormat.name) {
      throw const FormatException(
        'Remote checkpoint uses a different match format.',
      );
    }
    if (checkpoint['rulesVersion'] != rules.rulesVersion) {
      throw const FormatException(
        'Remote checkpoint uses a different rules version.',
      );
    }
    if (checkpoint['mode'] != mode.name) {
      throw const FormatException('Remote checkpoint uses a different mode.');
    }
    final rawRemainingDice = checkpoint['remainingDice'];
    if (checkpoint['currentPlayer'] is! String ||
        checkpoint['turn'] is! int ||
        checkpoint['dice'] is! List ||
        (rawRemainingDice != null && rawRemainingDice is! List) ||
        checkpoint['hasRolled'] is! bool) {
      throw const FormatException(
        'Remote checkpoint is missing required turn state.',
      );
    }

    final rawPlayers = checkpoint['players'];
    if (rawPlayers is! List || rawPlayers.length != players.length) {
      throw const FormatException(
        'Remote checkpoint must contain all four players.',
      );
    }
    final seenColors = <PlayerColor>{};
    for (final raw in rawPlayers) {
      if (raw is! Map) {
        throw const FormatException('Remote checkpoint has an invalid player.');
      }
      final color = _enumByName(PlayerColor.values, raw['color']);
      if (color == null || !seenColors.add(color)) {
        throw const FormatException(
          'Remote checkpoint has invalid player colors.',
        );
      }
      final tokens = raw['tokens'];
      if (tokens is! List ||
          tokens.length != players[color.index].tokens.length ||
          tokens.any((progress) => progress is! int)) {
        throw const FormatException(
          'Remote checkpoint has invalid token progress.',
        );
      }
    }
    if (seenColors.length != PlayerColor.values.length ||
        _enumByName(PlayerColor.values, checkpoint['currentPlayer']) == null) {
      throw const FormatException(
        'Remote checkpoint does not describe a complete board.',
      );
    }
  }

  void _restoreRemotePresentation(Map<String, dynamic> checkpoint) {
    rollSerial = checkpoint['rollSerial'] as int? ?? rollSerial;
    gameOver = checkpoint['gameOver'] as bool? ?? false;
    message = checkpoint['message'] as String? ?? message;
    pendingTrapPlacement = checkpoint['pendingTrapPlacement'] as bool? ?? false;
    final savedItemsPerSide = checkpoint['chaosItemsPerSide'];
    if (savedItemsPerSide is int && savedItemsPerSide > 0) {
      _chaosItemsPerSide = savedItemsPerSide;
    }

    final winnerColor = _enumByName(PlayerColor.values, checkpoint['winner']);
    winner = winnerColor == null ? null : players[winnerColor.index];

    effectSerial = checkpoint['effectSerial'] as int? ?? 0;
    effectLoopIndex = checkpoint['effectLoopIndex'] as int?;
    final rawBoardCell = checkpoint['effectBoardCell'];
    effectBoardCell =
        rawBoardCell is Map &&
            rawBoardCell['dx'] is num &&
            rawBoardCell['dy'] is num
        ? Offset(
            (rawBoardCell['dx'] as num).toDouble(),
            (rawBoardCell['dy'] as num).toDouble(),
          )
        : null;
    effectPowerUp = _enumByName(PowerUp.values, checkpoint['effectPowerUp']);
    effectKind = _enumByName(PowerEffectKind.values, checkpoint['effectKind']);
    effectToken = _tokenFromCheckpointReference(checkpoint['effectToken']);
    effectOwner = _enumByName(PlayerColor.values, checkpoint['effectOwner']);
    effectResolving = checkpoint['effectResolving'] as bool? ?? false;
    _lastCapturedToken = _tokenFromCheckpointReference(
      checkpoint['lastCapturedToken'],
    );

    _eventHistory.clear();
    final rawEvents = checkpoint['events'];
    if (rawEvents is List) {
      for (final raw in rawEvents) {
        if (raw is! Map) {
          throw const FormatException(
            'Remote checkpoint has an invalid event.',
          );
        }
        final type = _enumByName(GameEventType.values, raw['type']);
        final playerColor = _enumByName(PlayerColor.values, raw['playerColor']);
        final sequence = raw['sequence'];
        final turn = raw['turn'];
        final playerName = raw['playerName'];
        final description = raw['description'];
        if (type == null ||
            playerColor == null ||
            sequence is! int ||
            turn is! int ||
            playerName is! String ||
            description is! String) {
          throw const FormatException(
            'Remote checkpoint has incomplete event data.',
          );
        }
        final rawDice = raw['dice'];
        final eventDice =
            rawDice is List &&
                rawDice.length == 2 &&
                rawDice[0] is int &&
                rawDice[1] is int
            ? (rawDice[0] as int, rawDice[1] as int)
            : null;
        _eventHistory.add(
          GameEvent(
            sequence: sequence,
            turn: turn,
            type: type,
            playerName: playerName,
            playerColor: playerColor,
            description: description,
            dice: eventDice,
            tokenId: raw['tokenId'] as int?,
            fromProgress: raw['fromProgress'] as int?,
            toProgress: raw['toProgress'] as int?,
            targetName: raw['targetName'] as String?,
            targetColor: _enumByName(PlayerColor.values, raw['targetColor']),
          ),
        );
      }
    }
    final greatestEventSequence = _eventHistory.fold<int>(
      0,
      (greatest, event) =>
          event.sequence > greatest ? event.sequence : greatest,
    );
    final savedNextSequence = checkpoint['nextEventSequence'];
    _nextEventSequence =
        savedNextSequence is int && savedNextSequence > greatestEventSequence
        ? savedNextSequence
        : greatestEventSequence + 1;
  }

  void _copyRemoteStateFrom(GameEngine source) {
    if (source.mode != mode ||
        source.matchFormat != matchFormat ||
        source.rules.rulesVersion != rules.rulesVersion) {
      throw const FormatException(
        'Remote checkpoint is incompatible with this engine.',
      );
    }
    _turnTimer?.cancel();
    _turnTimer = null;
    _effectResolutionTimer?.cancel();
    _effectResolutionTimer = null;

    initialPlayerColor = source.initialPlayerColor;
    for (final color in PlayerColor.values) {
      final target = players[color.index];
      final incoming = source.players[color.index];
      target
        ..name = incoming.name
        ..initialStackIntact = incoming.initialStackIntact
        ..inventory = incoming.inventory
        ..shielded = incoming.shielded
        ..skippedTurns = incoming.skippedTurns;
      for (var index = 0; index < target.tokens.length; index++) {
        target.tokens[index].progress = incoming.tokens[index].progress;
      }
    }

    traps
      ..clear()
      ..addAll(source.traps);
    _itemLoopIndices
      ..clear()
      ..addAll(source._itemLoopIndices);
    _chaosItemsPerSide = source._chaosItemsPerSide;
    _lastTrapEffectTurn
      ..clear()
      ..addAll(source._lastTrapEffectTurn);
    _standings = OnlineStandingsTracker<PlayerColor>(
      competitors: PlayerColor.values,
    );
    for (final color in source.finishOrder) {
      _standings.recordFinish(color);
    }

    currentPlayerIndex = source.currentPlayerIndex;
    turnNumber = source.turnNumber;
    dice = List<int>.of(source.dice);
    rollSerial = source.rollSerial;
    remainingDice
      ..clear()
      ..addAll(source.remainingDice);
    hasRolled = source.hasRolled;
    gameOver = source.gameOver;
    spectatorContinuationActive = source.spectatorContinuationActive;
    consecutiveDoubles = source.consecutiveDoubles;
    message = source.message;
    winner = source.winner == null ? null : players[source.winner!.color.index];
    pendingTrapPlacement = source.pendingTrapPlacement;
    effectSerial = source.effectSerial;
    effectLoopIndex = source.effectLoopIndex;
    effectBoardCell = source.effectBoardCell;
    effectPowerUp = source.effectPowerUp;
    effectKind = source.effectKind;
    effectToken = _localTokenFor(source.effectToken);
    effectOwner = source.effectOwner;
    effectResolving = source.effectResolving;
    _lastCapturedToken = _localTokenFor(source._lastCapturedToken);
    _eventHistory
      ..clear()
      ..addAll(source._eventHistory);
    _nextEventSequence = source._nextEventSequence;
  }

  GameToken? _localTokenFor(GameToken? sourceToken) => sourceToken == null
      ? null
      : players[sourceToken.owner.index].tokens[sourceToken.id];

  GameToken? _tokenFromCheckpointReference(Object? raw) {
    if (raw is! Map) return null;
    final owner = _enumByName(PlayerColor.values, raw['owner']);
    final id = raw['id'];
    if (owner == null || id is! int || id < 0) return null;
    final tokens = players[owner.index].tokens;
    return id < tokens.length ? tokens[id] : null;
  }

  static T? _enumByName<T extends Enum>(Iterable<T> values, Object? raw) {
    if (raw is! String) return null;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }

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
      if (penalized != null) {
        if (penalized.progress != 0) {
          currentPlayer.initialStackIntact = false;
        }
        penalized.progress = rules.initialTokenProgress;
      }
      consecutiveDoubles = 0;
      dice = [dice[0], 0];
      hasRolled = true;
      message = penalized == null
          ? hasProtectedLaneToken
                ? 'Tres dobles: las fichas del pasillo final están protegidas.'
                : 'Tres dobles: no había una ficha en juego para penalizar.'
          : 'Tres dobles: la ficha ${penalized.id + 1} de '
                '${currentPlayer.name} volvió '
                '${rules.requiresFiveToExit ? 'a la cárcel' : 'a la salida'}.'
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
      return allowNestExit &&
          (!rules.requiresFiveToExit || amount == 5) &&
          !_startBlocked(token.owner);
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
    if (!rules.requiresFiveToExit) return false;
    final player = players.firstWhere((player) => player.color == owner);
    return player.tokens.any((token) => token.inNest) && !_startBlocked(owner);
  }

  List<int> legalDiceFor(GameToken token) =>
      remainingDice.where((die) => canMove(token, die)).toList();

  List<int> legalDieValuesFor(GameToken token) {
    final values = legalDiceFor(token).toSet().toList()..sort();
    return values;
  }

  /// Returns every distinct command the current player can legally submit.
  /// This intentionally counts `(token, die)` and `(token, all dice)` choices,
  /// not just movable tokens, so callers never auto-move through a real choice.
  List<LegalMoveCommand> legalMoveCommands() {
    if (!hasRolled || gameOver || effectResolving) {
      return const <LegalMoveCommand>[];
    }
    final commands = <LegalMoveCommand>[];
    for (final token in currentPlayer.tokens) {
      if (token.finished) continue;
      for (final die in legalDieValuesFor(token)) {
        final destination = destinationProgressFor(token, die);
        if (destination == null) continue;
        commands.add(
          LegalMoveCommand.singleDie(
            token: token,
            die: die,
            destinationProgress: destination,
          ),
        );
      }
      final combinedDice = _rolledDiceAvailableForCombinedMove();
      final combinedAmount = allDiceTotalFor(token);
      if (combinedDice != null && combinedAmount != null) {
        commands.add(
          LegalMoveCommand.allDice(
            token: token,
            amount: combinedAmount,
            dice: combinedDice,
            destinationProgress: token.progress + combinedAmount,
          ),
        );
      }
    }
    return UnmodifiableListView<LegalMoveCommand>(commands);
  }

  /// The sole legal command, or `null` when there are zero or multiple real
  /// choices. UI code may use this after the dice animation to auto-move once.
  LegalMoveCommand? get uniqueLegalMoveCommand {
    final commands = legalMoveCommands();
    return commands.length == 1 ? commands.single : null;
  }

  /// Applies a previously exposed command only if it is still legal.
  bool executeMoveCommand(LegalMoveCommand command) {
    if (!legalMoveCommands().any(command.representsSameChoice)) return false;
    return command.usesAllDice
        ? moveTokenUsingAllDice(command.token)
        : moveToken(command.token, die: command.die);
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

  /// The single visible rival this legal die choice is expected to capture.
  ///
  /// This is a pure preview of the board position. In Chaos mode, a hidden
  /// trap can still resolve before the capture; deliberately ignoring hidden
  /// traps here avoids leaking secret trap information through the UI.
  GameToken? captureTargetFor(GameToken token, int die) {
    if (!hasRolled ||
        gameOver ||
        effectResolving ||
        !remainingDice.contains(die)) {
      return null;
    }
    if (!canMove(token, die)) return null;
    if (_isHomeEntryCapture(token, die)) {
      return _capturableOpponentAt(
        token.owner,
        homeEntryOffset[token.owner]!,
        forcedSafeCapture: true,
      );
    }

    final destinationProgress = token.inNest ? 0 : token.progress + die;
    if (destinationProgress >= commonPathLength) return null;
    final destinationIndex = loopIndex(token.owner, destinationProgress);
    final capturesFromOwnStart =
        token.inNest && destinationIndex == startOffset[token.owner];
    return _capturableOpponentAt(
      token.owner,
      destinationIndex,
      forcedSafeCapture: capturesFromOwnStart,
    );
  }

  /// The single visible rival captured at the final combined-dice
  /// destination, or `null` when the combined move is unavailable or safe.
  GameToken? captureTargetUsingAllDice(GameToken token) {
    if (gameOver || effectResolving) return null;
    final total = allDiceTotalFor(token);
    if (total == null) return null;
    final destinationProgress = token.progress + total;
    if (destinationProgress >= commonPathLength) return null;
    return _capturableOpponentAt(
      token.owner,
      loopIndex(token.owner, destinationProgress),
    );
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
    if (_isProtectedInitialStackToken(token)) {
      currentPlayer.initialStackIntact = false;
    }
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
    if (_hasCompletedRequiredTokens(currentPlayer)) {
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
    final token = _capturableOpponentAt(
      owner,
      index,
      forcedSafeCapture: forcedSafeCapture,
    );
    if (token == null) return false;
    final player = players.firstWhere(
      (candidate) => candidate.color == token.owner,
    );

    final capturedProgress = token.progress;
    if (capturedProgress != 0) player.initialStackIntact = false;
    token.progress = rules.initialTokenProgress;
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

  GameToken? _capturableOpponentAt(
    PlayerColor owner,
    int index, {
    bool forcedSafeCapture = false,
  }) {
    if (safeLoopIndices.contains(index) && !forcedSafeCapture) return null;
    final targets = _opponentsAt(owner, index);

    // Capturing is strictly a one-versus-one action. A square containing two
    // rival tokens is a barrier and remains protected even if a special move
    // or a future caller reaches this central capture routine.
    return targets.length == 1 ? targets.single : null;
  }

  bool _isHomeEntryCapture(GameToken token, int die) {
    if (die != 5 || token.progress != commonPathLength - 2) return false;
    final entry = homeEntryOffset[token.owner]!;
    return !_isLoopBarrier(entry) &&
        _capturableOpponentAt(token.owner, entry, forcedSafeCapture: true) !=
            null;
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
      if (count >= 2 && !_isProtectedInitialStack(player, loopPosition)) {
        return true;
      }
    }
    return false;
  }

  bool _isProtectedInitialStack(PlayerState player, int loopPosition) =>
      !rules.initialStackFormsBarrier &&
      player.initialStackIntact &&
      loopPosition == startOffset[player.color] &&
      player.tokens.length >= 2 &&
      player.tokens.every((token) => token.progress == 0);

  bool _isProtectedInitialStackToken(GameToken token) {
    if (token.progress != 0) return false;
    final player = players.firstWhere((player) => player.color == token.owner);
    return _isProtectedInitialStack(player, startOffset[token.owner]!);
  }

  List<GameToken> _barrierTokensFor(GameToken token) {
    if (token.inNest || token.finished) return const <GameToken>[];
    final owner = players.firstWhere((player) => player.color == token.owner);
    if (token.progress < commonPathLength) {
      final index = loopIndex(token.owner, token.progress);
      if (_isProtectedInitialStack(owner, index)) {
        return const <GameToken>[];
      }
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
        (_hasCompletedRequiredTokens(players[currentPlayerIndex]) ||
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
        if (_isProtectedInitialStackToken(token)) {
          currentPlayer.initialStackIntact = false;
        }
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
    if (landingProgress != 0) player.initialStackIntact = false;
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
        token.progress = rules.initialTokenProgress;
        message = rules.requiresFiveToExit
            ? '¡TRAMPA CÁRCEL! ${player.name} volvió a la cárcel.'
            : '¡TRAMPA! ${player.name} volvió a la salida.';
      case PowerUp.bomb:
        token.progress = rules.initialTokenProgress;
        message = rules.requiresFiveToExit
            ? '¡BOMBA! ${player.name} volvió a la cárcel.'
            : '¡BOMBA! ${player.name} volvió a la salida.';
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
    _effectResolutionTimer = Timer(const Duration(milliseconds: 900), () {
      effectResolving = false;
      notifyListeners();
    });
  }

  void _checkWinner() {
    if (!_hasCompletedRequiredTokens(currentPlayer)) return;
    _finishGame();
  }

  bool _hasCompletedRequiredTokens(PlayerState player) =>
      player.tokens.where((token) => token.finished).length >=
      rules.tokensRequiredToWin;

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
