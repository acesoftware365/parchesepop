import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'game_engine.dart';
import 'online_match.dart';

/// Shared backend contract for an authoritative online match.
///
/// This library is not a deployed server and does not claim to provide network
/// security by itself. A production host must run this contract in a trusted
/// process, authenticate every gateway connection, serialize commands per
/// match, persist checkpoints, and distribute the resulting snapshots.
const onlineAuthorityContractVersion = 1;

sealed class OnlineActionCommand {
  const OnlineActionCommand({
    required this.matchId,
    required this.participantId,
    required this.actionId,
    required this.expectedRevision,
  });

  final String matchId;
  final String participantId;
  final String actionId;
  final int expectedRevision;

  String get fingerprint;

  String fingerprintPrefix(String kind) =>
      '$kind|$matchId|$participantId|$expectedRevision';
}

/// The client requests a roll but never supplies either die value.
class OnlineRollCommand extends OnlineActionCommand {
  const OnlineRollCommand({
    required super.matchId,
    required super.participantId,
    required super.actionId,
    required super.expectedRevision,
  });

  @override
  String get fingerprint => fingerprintPrefix('roll');
}

/// The client identifies a token and one already-issued die. The authority
/// computes the route, destination, captures, bonuses, and effects.
class OnlineMoveCommand extends OnlineActionCommand {
  const OnlineMoveCommand({
    required super.matchId,
    required super.participantId,
    required super.actionId,
    required super.expectedRevision,
    required this.tokenId,
    required this.die,
  });

  final int tokenId;
  final int die;

  @override
  String get fingerprint => '${fingerprintPrefix('move')}|$tokenId|$die';
}

/// Requests the engine's legal combined-dice move. The client cannot supply a
/// claimed total or destination.
class OnlineMoveAllCommand extends OnlineActionCommand {
  const OnlineMoveAllCommand({
    required super.matchId,
    required super.participantId,
    required super.actionId,
    required super.expectedRevision,
    required this.tokenId,
  });

  final int tokenId;

  @override
  String get fingerprint => '${fingerprintPrefix('moveAll')}|$tokenId';
}

enum OnlineCommandStatus { accepted, duplicate, rejected }

enum OnlineCommandRejection {
  invalidActionId,
  invalidRevision,
  actionIdConflict,
  wrongMatch,
  unknownParticipant,
  participantUnavailable,
  staleRevision,
  matchFinished,
  actionInProgress,
  notPlayersTurn,
  illegalPhase,
  invalidToken,
  fabricatedDie,
  illegalMove,
}

@immutable
class OnlineCommandResult {
  const OnlineCommandResult._({
    required this.status,
    required this.snapshot,
    this.rejection,
  });

  factory OnlineCommandResult.accepted(OnlineAuthoritySnapshot snapshot) =>
      OnlineCommandResult._(
        status: OnlineCommandStatus.accepted,
        snapshot: snapshot,
      );

  factory OnlineCommandResult.rejected(
    OnlineCommandRejection rejection,
    OnlineAuthoritySnapshot snapshot,
  ) => OnlineCommandResult._(
    status: OnlineCommandStatus.rejected,
    rejection: rejection,
    snapshot: snapshot,
  );

  final OnlineCommandStatus status;
  final OnlineCommandRejection? rejection;
  final OnlineAuthoritySnapshot snapshot;

  bool get accepted => status == OnlineCommandStatus.accepted;
  bool get duplicate => status == OnlineCommandStatus.duplicate;

  OnlineCommandResult asDuplicate() => OnlineCommandResult._(
    status: OnlineCommandStatus.duplicate,
    snapshot: snapshot,
  );
}

enum OnlineParticipantPresence {
  connected,
  reconnecting,
  cpuControlled,
  forfeited,
}

enum DisconnectExpiryAction { cpuTakeover, forfeit }

@immutable
class OnlineDisconnectPolicy {
  const OnlineDisconnectPolicy({
    this.gracePeriod = const Duration(seconds: 30),
    this.afterGrace = DisconnectExpiryAction.cpuTakeover,
    this.allowReclaimAfterCpuTakeover = true,
  });

  final Duration gracePeriod;
  final DisconnectExpiryAction afterGrace;
  final bool allowReclaimAfterCpuTakeover;
}

enum PresenceMutationResult { changed, noChange, unknownParticipant, notHuman }

enum OnlineReconnectStatus {
  reconnected,
  alreadyConnected,
  unknownParticipant,
  notHuman,
  takeoverLocked,
  forfeited,
}

@immutable
class OnlineReconnectDecision {
  const OnlineReconnectDecision({required this.status, required this.snapshot});

  final OnlineReconnectStatus status;
  final OnlineAuthoritySnapshot snapshot;

  bool get accepted =>
      status == OnlineReconnectStatus.reconnected ||
      status == OnlineReconnectStatus.alreadyConnected;
}

@immutable
class OnlineDisconnectTransition {
  const OnlineDisconnectTransition({
    required this.participantId,
    required this.from,
    required this.to,
  });

  final String participantId;
  final OnlineParticipantPresence from;
  final OnlineParticipantPresence to;
}

@immutable
class OnlineParticipantConnectionSnapshot {
  const OnlineParticipantConnectionSnapshot({
    required this.participantId,
    required this.color,
    required this.presence,
    this.reconnectDeadline,
  });

  final String participantId;
  final PlayerColor color;
  final OnlineParticipantPresence presence;
  final DateTime? reconnectDeadline;
}

@immutable
class OnlineAuthoritySnapshot {
  OnlineAuthoritySnapshot({
    required this.matchId,
    required this.revision,
    required this.mode,
    required this.matchFormat,
    required this.rulesVersion,
    required this.turnNumber,
    required this.currentPlayer,
    required Iterable<int> dice,
    required Iterable<int> remainingDice,
    required this.hasRolled,
    required this.effectResolving,
    required this.gameOver,
    required this.winner,
    required Map<PlayerColor, Iterable<int>> tokenProgress,
    required Iterable<OnlineParticipantConnectionSnapshot> connections,
    required this.lastEventSequence,
  }) : dice = UnmodifiableListView<int>(List<int>.of(dice)),
       remainingDice = UnmodifiableListView<int>(List<int>.of(remainingDice)),
       tokenProgress =
           UnmodifiableMapView<PlayerColor, List<int>>(<PlayerColor, List<int>>{
             for (final entry in tokenProgress.entries)
               entry.key: List<int>.unmodifiable(entry.value),
           }),
       connections = UnmodifiableListView<OnlineParticipantConnectionSnapshot>(
         List<OnlineParticipantConnectionSnapshot>.of(connections)
           ..sort((a, b) => a.color.index.compareTo(b.color.index)),
       );

  final String matchId;
  final int revision;
  final GameMode mode;
  final MatchFormat matchFormat;
  final int rulesVersion;
  final int turnNumber;
  final PlayerColor currentPlayer;
  final UnmodifiableListView<int> dice;
  final UnmodifiableListView<int> remainingDice;
  final bool hasRolled;
  final bool effectResolving;
  final bool gameOver;
  final PlayerColor? winner;
  final UnmodifiableMapView<PlayerColor, List<int>> tokenProgress;
  final UnmodifiableListView<OnlineParticipantConnectionSnapshot> connections;
  final int lastEventSequence;

  OnlineParticipantConnectionSnapshot connectionFor(String participantId) =>
      connections.firstWhere(
        (connection) => connection.participantId == participantId,
      );
}

class _MutableConnection {
  _MutableConnection({required this.presence, this.disconnectedAt});

  OnlineParticipantPresence presence;
  DateTime? disconnectedAt;
}

class _ProcessedAction {
  const _ProcessedAction({
    required this.fingerprint,
    required this.acceptedRevision,
    required this.result,
  });

  final String fingerprint;
  final int acceptedRevision;
  final OnlineCommandResult result;
}

/// Synchronous authority for one match.
///
/// A real gateway must serialize calls to [submit] for the same match. Keeping
/// mutation synchronous makes one Dart isolate deterministic, but is not a
/// substitute for a database transaction or distributed lock.
class OnlineMatchAuthority {
  OnlineMatchAuthority({
    required this.session,
    required this.engine,
    this.disconnectPolicy = const OnlineDisconnectPolicy(),
  }) : _ownsEngine = false {
    _validateEngine();
    _initializeConnections();
  }

  OnlineMatchAuthority._owned({
    required this.session,
    required this.engine,
    required this.disconnectPolicy,
  }) : _ownsEngine = true {
    _validateEngine();
    _initializeConnections();
  }

  factory OnlineMatchAuthority.fresh({
    required OnlineMatchSession session,
    MatchFormat matchFormat = MatchFormat.classic,
    Random? serverRandom,
    OnlineDisconnectPolicy disconnectPolicy = const OnlineDisconnectPolicy(),
  }) {
    final ordered = <PlayerColor, OnlineParticipant>{
      for (final participant in session.participants)
        participant.color: participant,
    };
    final engine = GameEngine(
      mode: session.mode,
      matchFormat: matchFormat,
      random: serverRandom ?? Random.secure(),
      humanName: ordered[PlayerColor.red]!.displayName,
      cpuNames: <String>[
        ordered[PlayerColor.green]!.displayName,
        ordered[PlayerColor.yellow]!.displayName,
        ordered[PlayerColor.blue]!.displayName,
      ],
    );
    return OnlineMatchAuthority._owned(
      session: session,
      engine: engine,
      disconnectPolicy: disconnectPolicy,
    );
  }

  factory OnlineMatchAuthority.fromCheckpoint({
    required OnlineMatchSession session,
    required Map<String, dynamic> checkpoint,
    OnlineDisconnectPolicy disconnectPolicy = const OnlineDisconnectPolicy(),
  }) {
    if (checkpoint['authorityVersion'] != onlineAuthorityContractVersion) {
      throw const FormatException('Unsupported online authority checkpoint.');
    }
    if (checkpoint['matchId'] != session.matchId) {
      throw const FormatException('Checkpoint belongs to another match.');
    }
    final rawEngine = checkpoint['engine'];
    if (rawEngine is! Map) {
      throw const FormatException('Checkpoint is missing engine state.');
    }
    final engineCheckpoint = <String, dynamic>{
      for (final entry in rawEngine.entries) entry.key.toString(): entry.value,
    };
    final engine = GameEngine.fromCheckpoint(engineCheckpoint);
    engine.gameOver = engineCheckpoint['gameOver'] as bool? ?? false;
    final winnerName = engineCheckpoint['winner'] as String?;
    if (winnerName != null) {
      final winnerColor = PlayerColor.values.cast<PlayerColor?>().firstWhere(
        (color) => color?.name == winnerName,
        orElse: () => null,
      );
      if (winnerColor != null) {
        engine.winner = engine.players.firstWhere(
          (player) => player.color == winnerColor,
        );
      }
    }

    final authority = OnlineMatchAuthority._owned(
      session: session,
      engine: engine,
      disconnectPolicy: disconnectPolicy,
    );
    final savedRevision = checkpoint['revision'];
    if (savedRevision is! int || savedRevision < 0) {
      authority.dispose();
      throw const FormatException('Checkpoint has an invalid revision.');
    }
    authority._revision = savedRevision;

    final rawConnections = checkpoint['connections'];
    if (rawConnections is List) {
      for (final raw in rawConnections.whereType<Map>()) {
        final participantId = raw['participantId'];
        final presenceName = raw['presence'];
        if (participantId is! String ||
            !authority._connections.containsKey(participantId)) {
          continue;
        }
        final presence = OnlineParticipantPresence.values
            .cast<OnlineParticipantPresence?>()
            .firstWhere(
              (value) => value?.name == presenceName,
              orElse: () => null,
            );
        if (presence == null) continue;
        final disconnectedAtMilliseconds = raw['disconnectedAtMilliseconds'];
        authority._connections[participantId] = _MutableConnection(
          presence: presence,
          disconnectedAt: disconnectedAtMilliseconds is int
              ? DateTime.fromMillisecondsSinceEpoch(
                  disconnectedAtMilliseconds,
                  isUtc: true,
                )
              : null,
        );
      }
    }

    final rawActions = checkpoint['processedActions'];
    if (rawActions is List) {
      for (final raw in rawActions.whereType<Map>()) {
        final actionId = raw['actionId'];
        final fingerprint = raw['fingerprint'];
        final acceptedRevision = raw['acceptedRevision'];
        if (actionId is! String ||
            fingerprint is! String ||
            acceptedRevision is! int) {
          continue;
        }
        authority._processedActions[actionId] = _ProcessedAction(
          fingerprint: fingerprint,
          acceptedRevision: acceptedRevision,
          result: OnlineCommandResult.accepted(authority.snapshot()),
        );
      }
    }
    return authority;
  }

  final OnlineMatchSession session;
  final GameEngine engine;
  final OnlineDisconnectPolicy disconnectPolicy;
  final bool _ownsEngine;
  final Map<String, _MutableConnection> _connections =
      <String, _MutableConnection>{};
  final Map<String, _ProcessedAction> _processedActions =
      <String, _ProcessedAction>{};
  int _revision = 0;

  int get revision => _revision;

  OnlineAuthoritySnapshot snapshot() {
    final events = engine.eventHistory;
    return OnlineAuthoritySnapshot(
      matchId: session.matchId,
      revision: _revision,
      mode: engine.mode,
      matchFormat: engine.matchFormat,
      rulesVersion: engine.rules.rulesVersion,
      turnNumber: engine.turnNumber,
      currentPlayer: engine.currentPlayer.color,
      dice: engine.dice,
      remainingDice: engine.remainingDice,
      hasRolled: engine.hasRolled,
      effectResolving: engine.effectResolving,
      gameOver: engine.gameOver,
      winner: engine.winner?.color,
      tokenProgress: <PlayerColor, Iterable<int>>{
        for (final player in engine.players)
          player.color: player.tokens.map((token) => token.progress),
      },
      connections: <OnlineParticipantConnectionSnapshot>[
        for (final participant in session.participants)
          _connectionSnapshot(participant),
      ],
      lastEventSequence: events.isEmpty ? 0 : events.last.sequence,
    );
  }

  OnlineCommandResult submit(OnlineActionCommand command) {
    if (!_validActionId(command.actionId)) {
      return _reject(OnlineCommandRejection.invalidActionId);
    }
    if (command.expectedRevision < 0) {
      return _reject(OnlineCommandRejection.invalidRevision);
    }

    final previous = _processedActions[command.actionId];
    if (previous != null) {
      if (previous.fingerprint != command.fingerprint) {
        return _reject(OnlineCommandRejection.actionIdConflict);
      }
      return previous.result.asDuplicate();
    }

    if (command.matchId != session.matchId) {
      return _reject(OnlineCommandRejection.wrongMatch);
    }
    final participant = _participantOrNull(command.participantId);
    if (participant == null) {
      return _reject(OnlineCommandRejection.unknownParticipant);
    }
    if (_connections[participant.id]!.presence !=
        OnlineParticipantPresence.connected) {
      return _reject(OnlineCommandRejection.participantUnavailable);
    }
    if (command.expectedRevision != _revision) {
      return _reject(OnlineCommandRejection.staleRevision);
    }
    if (engine.gameOver) {
      return _reject(OnlineCommandRejection.matchFinished);
    }
    if (engine.effectResolving || engine.pendingTrapPlacement) {
      return _reject(OnlineCommandRejection.actionInProgress);
    }
    if (participant.color != engine.currentPlayer.color) {
      return _reject(OnlineCommandRejection.notPlayersTurn);
    }

    final rejection = _apply(command);
    if (rejection != null) return _reject(rejection);

    _revision++;
    final result = OnlineCommandResult.accepted(snapshot());
    _processedActions[command.actionId] = _ProcessedAction(
      fingerprint: command.fingerprint,
      acceptedRevision: _revision,
      result: result,
    );
    return result;
  }

  OnlineCommandRejection? _apply(OnlineActionCommand command) {
    if (command is OnlineRollCommand) {
      if (engine.hasRolled) return OnlineCommandRejection.illegalPhase;
      final previousSerial = engine.rollSerial;
      engine.roll();
      return engine.rollSerial == previousSerial
          ? OnlineCommandRejection.illegalPhase
          : null;
    }

    if (!engine.hasRolled) return OnlineCommandRejection.illegalPhase;

    if (command is OnlineMoveCommand) {
      final token = _currentTokenOrNull(command.tokenId);
      if (token == null) return OnlineCommandRejection.invalidToken;
      if (command.die <= 0 || !engine.remainingDice.contains(command.die)) {
        return OnlineCommandRejection.fabricatedDie;
      }
      if (!engine.canMove(token, command.die)) {
        return OnlineCommandRejection.illegalMove;
      }
      return engine.moveToken(token, die: command.die)
          ? null
          : OnlineCommandRejection.illegalMove;
    }

    if (command is OnlineMoveAllCommand) {
      final token = _currentTokenOrNull(command.tokenId);
      if (token == null) return OnlineCommandRejection.invalidToken;
      if (!engine.canMoveUsingAllDice(token)) {
        return OnlineCommandRejection.illegalMove;
      }
      return engine.moveTokenUsingAllDice(token)
          ? null
          : OnlineCommandRejection.illegalMove;
    }

    return OnlineCommandRejection.illegalMove;
  }

  PresenceMutationResult markDisconnected(
    String participantId, {
    required DateTime now,
  }) {
    final participant = _participantOrNull(participantId);
    if (participant == null) return PresenceMutationResult.unknownParticipant;
    if (!participant.beganAsHuman) return PresenceMutationResult.notHuman;
    final connection = _connections[participantId]!;
    if (connection.presence != OnlineParticipantPresence.connected) {
      return PresenceMutationResult.noChange;
    }
    connection
      ..presence = OnlineParticipantPresence.reconnecting
      ..disconnectedAt = now;
    _revision++;
    return PresenceMutationResult.changed;
  }

  OnlineReconnectDecision reconnect(
    String participantId, {
    required DateTime now,
  }) {
    final participant = _participantOrNull(participantId);
    if (participant == null) {
      return OnlineReconnectDecision(
        status: OnlineReconnectStatus.unknownParticipant,
        snapshot: snapshot(),
      );
    }
    if (!participant.beganAsHuman) {
      return OnlineReconnectDecision(
        status: OnlineReconnectStatus.notHuman,
        snapshot: snapshot(),
      );
    }
    final connection = _connections[participantId]!;
    if (connection.presence == OnlineParticipantPresence.connected) {
      return OnlineReconnectDecision(
        status: OnlineReconnectStatus.alreadyConnected,
        snapshot: snapshot(),
      );
    }
    if (connection.presence == OnlineParticipantPresence.forfeited) {
      return OnlineReconnectDecision(
        status: OnlineReconnectStatus.forfeited,
        snapshot: snapshot(),
      );
    }
    if (connection.presence == OnlineParticipantPresence.cpuControlled &&
        !disconnectPolicy.allowReclaimAfterCpuTakeover) {
      return OnlineReconnectDecision(
        status: OnlineReconnectStatus.takeoverLocked,
        snapshot: snapshot(),
      );
    }

    if (connection.presence == OnlineParticipantPresence.reconnecting &&
        _graceExpired(connection, now)) {
      if (disconnectPolicy.afterGrace == DisconnectExpiryAction.forfeit) {
        connection
          ..presence = OnlineParticipantPresence.forfeited
          ..disconnectedAt = null;
        _revision++;
        return OnlineReconnectDecision(
          status: OnlineReconnectStatus.forfeited,
          snapshot: snapshot(),
        );
      }
      if (!disconnectPolicy.allowReclaimAfterCpuTakeover) {
        connection
          ..presence = OnlineParticipantPresence.cpuControlled
          ..disconnectedAt = null;
        _revision++;
        return OnlineReconnectDecision(
          status: OnlineReconnectStatus.takeoverLocked,
          snapshot: snapshot(),
        );
      }
    }

    connection
      ..presence = OnlineParticipantPresence.connected
      ..disconnectedAt = null;
    _revision++;
    return OnlineReconnectDecision(
      status: OnlineReconnectStatus.reconnected,
      snapshot: snapshot(),
    );
  }

  List<OnlineDisconnectTransition> enforceDisconnectPolicy(DateTime now) {
    final transitions = <OnlineDisconnectTransition>[];
    for (final participant in session.participants) {
      final connection = _connections[participant.id]!;
      if (connection.presence != OnlineParticipantPresence.reconnecting ||
          !_graceExpired(connection, now)) {
        continue;
      }
      final next =
          disconnectPolicy.afterGrace == DisconnectExpiryAction.cpuTakeover
          ? OnlineParticipantPresence.cpuControlled
          : OnlineParticipantPresence.forfeited;
      transitions.add(
        OnlineDisconnectTransition(
          participantId: participant.id,
          from: connection.presence,
          to: next,
        ),
      );
      connection
        ..presence = next
        ..disconnectedAt = null;
      _revision++;
    }
    return List<OnlineDisconnectTransition>.unmodifiable(transitions);
  }

  /// JSON-compatible durable state. The host must encrypt/sign it as needed;
  /// this contract does not provide storage security.
  Map<String, Object?> createCheckpoint() {
    final processed = _processedActions.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return <String, Object?>{
      'authorityVersion': onlineAuthorityContractVersion,
      'matchId': session.matchId,
      'revision': _revision,
      'engine': <String, Object?>{
        ...engine.checkpointRuleMetadata,
        'mode': engine.mode.name,
        'cpuLevel': engine.cpuLevel,
        'turn': engine.turnNumber,
        'currentPlayer': engine.currentPlayer.color.name,
        'dice': List<int>.of(engine.dice),
        'remainingDice': List<int>.of(engine.remainingDice),
        'hasRolled': engine.hasRolled,
        'gameOver': engine.gameOver,
        'winner': engine.winner?.color.name,
        'players': <Map<String, Object?>>[
          for (final player in engine.players)
            <String, Object?>{
              'color': player.color.name,
              'name': player.name,
              'tokens': <int>[
                for (final token in player.tokens) token.progress,
              ],
              'inventory': player.inventory?.name,
              'shielded': player.shielded,
              'skippedTurns': player.skippedTurns,
            },
        ],
        'traps': <Map<String, Object>>[
          for (final trap in engine.traps)
            <String, Object>{
              'owner': trap.owner.name,
              'type': trap.type.name,
              'loopIndex': trap.loopIndex,
            },
        ],
        'items': engine.itemLoopIndices.toList(growable: false),
      },
      'connections': <Map<String, Object?>>[
        for (final participant in session.participants)
          <String, Object?>{
            'participantId': participant.id,
            'presence': _connections[participant.id]!.presence.name,
            'disconnectedAtMilliseconds': _connections[participant.id]!
                .disconnectedAt
                ?.millisecondsSinceEpoch,
          },
      ],
      'processedActions': <Map<String, Object>>[
        for (final entry in processed)
          <String, Object>{
            'actionId': entry.key,
            'fingerprint': entry.value.fingerprint,
            'acceptedRevision': entry.value.acceptedRevision,
          },
      ],
    };
  }

  void dispose() {
    if (_ownsEngine) engine.dispose();
  }

  OnlineCommandResult _reject(OnlineCommandRejection reason) =>
      OnlineCommandResult.rejected(reason, snapshot());

  GameToken? _currentTokenOrNull(int tokenId) {
    if (tokenId < 0 || tokenId >= engine.currentPlayer.tokens.length) {
      return null;
    }
    return engine.currentPlayer.tokens[tokenId];
  }

  OnlineParticipant? _participantOrNull(String participantId) {
    for (final participant in session.participants) {
      if (participant.id == participantId) return participant;
    }
    return null;
  }

  OnlineParticipantConnectionSnapshot _connectionSnapshot(
    OnlineParticipant participant,
  ) {
    final connection = _connections[participant.id]!;
    final disconnectedAt = connection.disconnectedAt;
    return OnlineParticipantConnectionSnapshot(
      participantId: participant.id,
      color: participant.color,
      presence: connection.presence,
      reconnectDeadline:
          connection.presence == OnlineParticipantPresence.reconnecting &&
              disconnectedAt != null
          ? disconnectedAt.add(disconnectPolicy.gracePeriod)
          : null,
    );
  }

  bool _graceExpired(_MutableConnection connection, DateTime now) {
    final disconnectedAt = connection.disconnectedAt;
    if (disconnectedAt == null) return false;
    return !now.isBefore(disconnectedAt.add(disconnectPolicy.gracePeriod));
  }

  void _initializeConnections() {
    for (final participant in session.participants) {
      _connections[participant.id] = _MutableConnection(
        presence: participant.isVirtuallyControlled
            ? OnlineParticipantPresence.cpuControlled
            : OnlineParticipantPresence.connected,
      );
    }
  }

  void _validateEngine() {
    if (disconnectPolicy.gracePeriod.isNegative) {
      throw ArgumentError.value(
        disconnectPolicy.gracePeriod,
        'disconnectPolicy.gracePeriod',
        'The reconnect grace period cannot be negative.',
      );
    }
    if (session.matchId.trim().isEmpty) {
      throw ArgumentError.value(session.matchId, 'session.matchId');
    }
    if (engine.mode != session.mode) {
      throw ArgumentError('Engine mode must match the online session mode.');
    }
    if (engine.players.length != PlayerColor.values.length ||
        engine.players.map((player) => player.color).toSet().length !=
            PlayerColor.values.length) {
      throw ArgumentError('Engine must contain one state for every color.');
    }
  }

  static bool _validActionId(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{8,80}$').hasMatch(value);
}

// ---------------------------------------------------------------------------
// Transport boundary
// ---------------------------------------------------------------------------

@immutable
class PublicQueueRequest {
  const PublicQueueRequest({
    required this.participantId,
    required this.mode,
    required this.matchFormat,
  });

  final String participantId;
  final GameMode mode;
  final MatchFormat matchFormat;
}

@immutable
class PrivateRoomCreateRequest {
  const PrivateRoomCreateRequest({
    required this.hostParticipantId,
    required this.mode,
    required this.matchFormat,
  });

  final String hostParticipantId;
  final GameMode mode;
  final MatchFormat matchFormat;
}

@immutable
class PrivateRoomJoinRequest {
  const PrivateRoomJoinRequest({
    required this.participantId,
    required this.roomCode,
  });

  final String participantId;
  final String roomCode;
}

@immutable
class OnlineQueueTicket {
  const OnlineQueueTicket({required this.ticketId});

  final String ticketId;
}

@immutable
class OnlinePrivateRoom {
  const OnlinePrivateRoom({required this.roomCode});

  final String roomCode;
}

@immutable
class GatewayReconnectRequest {
  const GatewayReconnectRequest({
    required this.matchId,
    required this.participantId,
    required this.resumeToken,
    required this.knownRevision,
  });

  final String matchId;
  final String participantId;
  final String resumeToken;
  final int knownRevision;
}

/// Network/storage adapter implemented by the future trusted backend.
///
/// Implementations must derive participant identity from an authenticated
/// connection and must not trust the raw IDs in request DTOs. An in-memory fake
/// belongs in tests only; using one in production would not create real online
/// play, matchmaking, persistence, or anti-cheat protection.
abstract interface class OnlineAuthorityGateway {
  Future<OnlineQueueTicket> joinPublicQueue(PublicQueueRequest request);

  Future<OnlinePrivateRoom> createPrivateRoom(PrivateRoomCreateRequest request);

  Future<OnlineQueueTicket> joinPrivateRoom(PrivateRoomJoinRequest request);

  Future<OnlineReconnectDecision> reconnect(GatewayReconnectRequest request);

  Future<OnlineCommandResult> submit(OnlineActionCommand command);

  Future<OnlineAuthoritySnapshot> fetchSnapshot(String matchId);
}
