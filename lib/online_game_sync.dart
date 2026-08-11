import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'game_engine.dart';
import 'online_authority.dart';
import 'online_lobby.dart';
import 'online_match.dart';
import 'online_transport.dart';
import 'online_transport_models.dart';
import 'safe_chat.dart';

/// Version of the active-host realtime match document.
const int onlineGameSyncSchemaVersion = 1;

/// Security model used by this transport adapter.
///
/// The room host owns the [OnlineMatchAuthority] and validates every command.
/// This prevents accidental desynchronization and ordinary client-side dice
/// fabrication, but the host device is not a trusted anti-cheat server. A
/// competitive production mode must move the exact same command contract into
/// a trusted backend process.
const String onlineGameSyncAuthorityModel = 'activeHostV1';

enum OnlineGameConnectionState {
  idle,
  connecting,
  connected,
  reconnecting,
  failed,
  disposed,
}

/// Availability of the active-host authority from a guest's point of view.
///
/// `activeHostV1` cannot safely elect a different UID without a fenced server
/// lease. Guests therefore wait for the recorded host, then surface an
/// explicit recovery/exit state instead of remaining on a frozen board.
enum OnlineHostAvailability { available, reconnecting, unavailable }

enum OnlineGameCommandKind { roll, move, moveAll, powerUp }

class OnlineGameSyncException implements Exception {
  const OnlineGameSyncException(this.message);

  final String message;

  @override
  String toString() => 'OnlineGameSyncException: $message';
}

final class OnlineHostUnavailableException extends OnlineGameSyncException {
  const OnlineHostUnavailableException()
    : super(
        'The active host did not reconnect. This match must be recovered or exited.',
      );
}

@immutable
class OnlineGameCommandRecord {
  const OnlineGameCommandRecord({
    required this.kind,
    required this.matchId,
    required this.participantId,
    required this.submittedById,
    required this.actionId,
    required this.expectedRevision,
    required this.submittedAtMs,
    this.tokenId,
    this.die,
  });

  final OnlineGameCommandKind kind;
  final String matchId;
  final String participantId;
  final String submittedById;
  final String actionId;
  final int expectedRevision;
  final int submittedAtMs;
  final int? tokenId;
  final int? die;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'matchId': matchId,
    'participantId': participantId,
    'submittedById': submittedById,
    'actionId': actionId,
    'expectedRevision': expectedRevision,
    'submittedAt': submittedAtMs,
    if (tokenId != null) 'tokenId': tokenId,
    if (die != null) 'die': die,
  };

  factory OnlineGameCommandRecord.fromJson(
    Object? raw, {
    required String pathParticipantId,
    required String pathActionId,
  }) {
    final map = onlineMap(raw);
    final kindName = map['kind'];
    final matchId = map['matchId'];
    final participantId = map['participantId'];
    final submittedById = map['submittedById'] ?? participantId;
    final actionId = map['actionId'];
    final expectedRevision = map['expectedRevision'];
    final submittedAt = map['submittedAt'];
    if (kindName is! String ||
        matchId is! String ||
        participantId is! String ||
        submittedById is! String ||
        actionId is! String ||
        expectedRevision is! num ||
        submittedAt is! num ||
        participantId != pathParticipantId ||
        actionId != pathActionId) {
      throw const FormatException('Invalid online command envelope.');
    }
    final kind = OnlineGameCommandKind.values
        .where((candidate) => candidate.name == kindName)
        .firstOrNull;
    if (kind == null) {
      throw const FormatException('Unknown online command kind.');
    }
    final tokenId = map['tokenId'];
    final die = map['die'];
    if ((kind == OnlineGameCommandKind.move ||
            kind == OnlineGameCommandKind.moveAll) &&
        tokenId is! num) {
      throw const FormatException('A move command requires a token.');
    }
    if (kind == OnlineGameCommandKind.move && die is! num) {
      throw const FormatException('A single-die move requires an issued die.');
    }
    return OnlineGameCommandRecord(
      kind: kind,
      matchId: matchId,
      participantId: participantId,
      submittedById: submittedById,
      actionId: actionId,
      expectedRevision: expectedRevision.toInt(),
      submittedAtMs: submittedAt.toInt(),
      tokenId: tokenId is num ? tokenId.toInt() : null,
      die: die is num ? die.toInt() : null,
    );
  }

  OnlineActionCommand toAuthorityCommand() => switch (kind) {
    OnlineGameCommandKind.roll => OnlineRollCommand(
      matchId: matchId,
      participantId: participantId,
      actionId: actionId,
      expectedRevision: expectedRevision,
    ),
    OnlineGameCommandKind.move => OnlineMoveCommand(
      matchId: matchId,
      participantId: participantId,
      actionId: actionId,
      expectedRevision: expectedRevision,
      tokenId: tokenId!,
      die: die!,
    ),
    OnlineGameCommandKind.moveAll => OnlineMoveAllCommand(
      matchId: matchId,
      participantId: participantId,
      actionId: actionId,
      expectedRevision: expectedRevision,
      tokenId: tokenId!,
    ),
    OnlineGameCommandKind.powerUp => OnlineUsePowerUpCommand(
      matchId: matchId,
      participantId: participantId,
      actionId: actionId,
      expectedRevision: expectedRevision,
    ),
  };

  bool representsSameAction(OnlineGameCommandRecord other) =>
      kind == other.kind &&
      matchId == other.matchId &&
      participantId == other.participantId &&
      submittedById == other.submittedById &&
      actionId == other.actionId &&
      expectedRevision == other.expectedRevision &&
      tokenId == other.tokenId &&
      die == other.die;
}

@immutable
class OnlineGameCommandResultRecord {
  const OnlineGameCommandResultRecord({
    required this.actionId,
    required this.participantId,
    required this.status,
    required this.authorityRevision,
    required this.stateRevision,
    required this.processedAtMs,
    this.rejection,
  });

  final String actionId;
  final String participantId;
  final OnlineCommandStatus status;
  final OnlineCommandRejection? rejection;
  final int authorityRevision;
  final int stateRevision;
  final int processedAtMs;

  bool get accepted =>
      status == OnlineCommandStatus.accepted ||
      status == OnlineCommandStatus.duplicate;

  Map<String, Object?> toJson() => <String, Object?>{
    'actionId': actionId,
    'participantId': participantId,
    'status': status.name,
    if (rejection != null) 'rejection': rejection!.name,
    'authorityRevision': authorityRevision,
    'stateRevision': stateRevision,
    'processedAt': processedAtMs,
  };

  factory OnlineGameCommandResultRecord.fromJson(Object? raw) {
    final map = onlineMap(raw);
    final actionId = map['actionId'];
    final participantId = map['participantId'];
    final statusName = map['status'];
    final authorityRevision = map['authorityRevision'];
    final stateRevision = map['stateRevision'];
    final processedAt = map['processedAt'];
    final status = OnlineCommandStatus.values
        .where((candidate) => candidate.name == statusName)
        .firstOrNull;
    if (actionId is! String ||
        participantId is! String ||
        status == null ||
        authorityRevision is! num ||
        stateRevision is! num ||
        processedAt is! num) {
      throw const FormatException('Invalid online command result.');
    }
    final rejectionName = map['rejection'];
    final rejection = rejectionName is String
        ? OnlineCommandRejection.values
              .where((candidate) => candidate.name == rejectionName)
              .firstOrNull
        : null;
    return OnlineGameCommandResultRecord(
      actionId: actionId,
      participantId: participantId,
      status: status,
      rejection: rejection,
      authorityRevision: authorityRevision.toInt(),
      stateRevision: stateRevision.toInt(),
      processedAtMs: processedAt.toInt(),
    );
  }
}

/// Backend-agnostic live match synchronization over [OnlineRealtimeStore].
///
/// Commands are append-only at
/// `onlineV2/rooms/{roomId}/commands/{participantId}/{actionId}`. The active
/// host consumes them serially with [OnlineMatchAuthority] and publishes a
/// complete engine checkpoint at `onlineV2/rooms/{roomId}/match`. Replicas only
/// call [GameEngine.applyRemoteCheckpoint], which deliberately cancels local
/// transition timers.
class OnlineGameSyncClient extends ChangeNotifier {
  OnlineGameSyncClient({
    required this.transport,
    required this.roomId,
    required this.session,
    required GameEngine engine,
    required this.isHost,
    OnlineMatchAuthority? authority,
    Random? random,
    this.commandTimeout = const Duration(seconds: 12),
    this.hostReconnectGrace = const Duration(seconds: 30),
  }) : _engine = authority?.engine ?? engine,
       _authority = authority,
       _random = random ?? Random.secure() {
    if (roomId.trim().isEmpty || roomId.contains('/')) {
      throw ArgumentError.value(roomId, 'roomId', 'Invalid room ID.');
    }
    if (session.localParticipant.id != transport.identity.uid) {
      throw ArgumentError(
        'The session local participant must match the transport identity.',
      );
    }
    if (hostReconnectGrace.isNegative) {
      throw ArgumentError.value(
        hostReconnectGrace,
        'hostReconnectGrace',
        'The host reconnect grace period cannot be negative.',
      );
    }
    if (isHost) {
      _authority ??= OnlineMatchAuthority(session: session, engine: _engine);
    } else if (_authority != null) {
      throw ArgumentError('A guest cannot own the match authority.');
    }
  }

  final OnlineTransportClient transport;
  final String roomId;
  final OnlineMatchSession session;
  final bool isHost;
  final Duration commandTimeout;
  final Duration hostReconnectGrace;
  final Random _random;

  GameEngine _engine;
  OnlineMatchAuthority? _authority;
  StreamSubscription<Object?>? _matchSubscription;
  StreamSubscription<Object?>? _commandSubscription;
  StreamSubscription<Object?>? _presenceSubscription;
  StreamSubscription<Object?>? _safeChatSubscription;
  OnlinePresenceLease? _presenceLease;
  final Map<String, Timer> _disconnectGraceTimers = <String, Timer>{};
  Timer? _hostResumeTurnTimer;
  Timer? _hostResumeEffectTimer;
  Timer? _hostRecoveryTimer;
  Future<void> _serial = Future<void>.value();
  final Map<String, Map<String, OnlineGameCommandResultRecord>> _results = {};
  final Set<String> _processingActionKeys = <String>{};
  final Set<String> _seenSafeChatMessageIds = <String>{};
  final StreamController<OnlineSafeChatMessage> _safeChatMessages =
      StreamController<OnlineSafeChatMessage>.broadcast(sync: true);
  bool _hostListenerAttached = false;
  bool _needsHostTransitionResume = false;
  bool _suppressHostEngineListener = false;
  bool _started = false;
  bool _initialized = false;
  bool _disposed = false;
  int _authorityRevision = 0;
  int _stateRevision = -1;
  int _createdAtMs = 0;
  String? _lastCheckpointJson;
  Object? _lastError;
  OnlineGameCommandResultRecord? _lastResult;
  OnlineParticipantPresence? _localAuthorityPresence;
  OnlineHostAvailability _hostAvailability = OnlineHostAvailability.available;
  DateTime? _hostReconnectDeadline;
  String? _activeHostUid;
  OnlineGameConnectionState _connectionState = OnlineGameConnectionState.idle;

  GameEngine get engine => _engine;
  PlayerColor get localColor => session.localColor;
  String get participantId => transport.identity.uid;
  int get revision => _authorityRevision;
  int get stateRevision => _stateRevision;
  Object? get lastError => _lastError;
  OnlineGameCommandResultRecord? get lastResult => _lastResult;
  OnlineParticipantPresence? get localAuthorityPresence =>
      _localAuthorityPresence;
  OnlineGameConnectionState get connectionState => _connectionState;
  OnlineHostAvailability get hostAvailability => _hostAvailability;
  DateTime? get hostReconnectDeadline => _hostReconnectDeadline;
  bool get requiresHostRecovery =>
      _hostAvailability == OnlineHostAvailability.unavailable;
  Stream<OnlineSafeChatMessage> get safeChatMessages =>
      _safeChatMessages.stream;
  String get matchPath => '$onlineTransportRoot/rooms/$roomId/match';
  String get _commandsPath => '$onlineTransportRoot/rooms/$roomId/commands';
  String get _presencePath => '$onlineTransportRoot/rooms/$roomId/presence';
  String get _safeChatPath => '$onlineTransportRoot/rooms/$roomId/chat';

  /// Whether this host may currently drive [candidateId]. This is true for an
  /// original virtual seat and for a remote human only after authoritative
  /// disconnect expiry changed that seat to CPU control.
  bool canHostDriveParticipant(String candidateId) {
    if (!isHost || _disposed || _authority == null) return false;
    final participant = session.participants
        .where((candidate) => candidate.id == candidateId)
        .firstOrNull;
    if (participant == null || participant.id == participantId) return false;
    return _authority!.snapshot().connectionFor(candidateId).presence ==
        OnlineParticipantPresence.cpuControlled;
  }

  Future<void> start() async {
    _ensureUsable();
    if (_started) return;
    _started = true;
    _setConnectionState(
      _initialized
          ? OnlineGameConnectionState.reconnecting
          : OnlineGameConnectionState.connecting,
    );
    try {
      if (isHost) {
        if (!_initialized) {
          await _initializeHost();
          _ensureStartActive();
        }
        _attachHostEngineListener();
        _resumeHostTransitionsIfNeeded();
        _commandSubscription = transport.store
            .watch(_commandsPath)
            .listen(_handleCommandSnapshot, onError: _handleStreamError);
        // Advertise the host as connected only after its authority and command
        // consumer are ready. This keeps returning guests from racing input
        // against a host that has not restored the durable checkpoint yet.
        final lease = await transport.connectRoomPresence(roomId);
        if (_disposed || !_started) {
          await lease.disconnect();
          _ensureStartActive();
        }
        _presenceLease = lease;
        _presenceSubscription = transport.store
            .watch(_presencePath)
            .listen(_handlePresenceSnapshot, onError: _handleStreamError);
      } else {
        final lease = await transport.connectRoomPresence(roomId);
        if (_disposed || !_started) {
          await lease.disconnect();
          _ensureStartActive();
        }
        _presenceLease = lease;
        await _readAndApplyMatchDocument(required: true);
        _ensureStartActive();
        _matchSubscription = transport.store
            .watch(matchPath)
            .listen(_handleMatchSnapshot, onError: _handleStreamError);
        _presenceSubscription = transport.store
            .watch(_presencePath)
            .listen(_handleGuestPresenceSnapshot, onError: _handleStreamError);
        final presence = await transport.store.read(_presencePath);
        _ensureStartActive();
        _handleGuestPresenceSnapshot(presence);
        await _waitForLocalAuthorityReconnect();
        _ensureStartActive();
      }
      _ensureStartActive();
      _safeChatSubscription = transport.store
          .watch(_safeChatPath)
          .listen(_handleSafeChatSnapshot, onError: _handleSafeChatStreamError);
      _initialized = true;
      if (_hostAvailability != OnlineHostAvailability.unavailable) {
        _lastError = null;
      }
      _setConnectionState(_connectionStateForHostAvailability);
    } catch (error) {
      _started = false;
      await _cancelSubscriptions(disconnectPresence: true);
      _lastError = error;
      _setConnectionState(OnlineGameConnectionState.failed);
      rethrow;
    }
  }

  /// Stops network watches without destroying the replicated engine.
  /// Calling [start] again reads the newest checkpoint and reconnects.
  Future<void> pause() async {
    if (_disposed || !_started) return;
    _started = false;
    await _cancelSubscriptions(disconnectPresence: true);
    if (!_disposed) _setConnectionState(OnlineGameConnectionState.idle);
  }

  Future<void> reconnect() async {
    _ensureUsable();
    if (_started) {
      _started = false;
      await _cancelSubscriptions(disconnectPresence: true);
    }
    await start();
  }

  /// Explicit recovery action for a guest after [requiresHostRecovery].
  ///
  /// Returns false while the recorded active host is still absent. A true
  /// result means the host is present and the newest durable checkpoint was
  /// applied, so the UI may dismiss its recovery dialog.
  Future<bool> retryHostRecovery() async {
    _ensureUsable();
    if (isHost) return true;
    if (!_started) await start();
    _handleGuestPresenceSnapshot(await transport.store.read(_presencePath));
    if (_hostAvailability != OnlineHostAvailability.available) return false;
    await _readAndApplyMatchDocument(required: true);
    _lastError = null;
    _setConnectionState(OnlineGameConnectionState.connected);
    return true;
  }

  /// Publishes one reviewed Quick Message as the authenticated local human.
  ///
  /// There is intentionally no `participantId` parameter: callers cannot
  /// impersonate another member or publish a response on behalf of a CPU.
  Future<OnlineSafeChatMessage> sendSafeChat(SafeChatPhraseId phraseId) async {
    _ensureUsable();
    if (!_started || connectionState != OnlineGameConnectionState.connected) {
      throw const OnlineGameSyncException('The online match is not connected.');
    }
    final localParticipant = session.localParticipant;
    if (!localParticipant.beganAsHuman ||
        localParticipant.id != participantId) {
      throw const OnlineGameSyncException(
        'Only the authenticated local human can send a Quick Message.',
      );
    }
    if (!SafeChatCatalog.contains(phraseId)) {
      throw const OnlineGameSyncException(
        'That Quick Message is not in the reviewed catalog.',
      );
    }

    final now = await transport.store.serverNowMs();
    final messageId = _newSafeChatMessageId(now);
    final message = OnlineSafeChatMessage(
      messageId: messageId,
      senderUid: participantId,
      phraseId: phraseId,
      sentAtMs: now,
    );
    final result = await transport.store.transaction(
      '$_safeChatPath/$messageId',
      (current) => current == null
          ? OnlineStoreTransactionDecision.commit(message.toJson())
          : const OnlineStoreTransactionDecision.abort(),
    );
    if (!result.committed) {
      throw const OnlineGameSyncException(
        'The Quick Message could not be published. Please try again.',
      );
    }
    return message;
  }

  Future<OnlineGameCommandResultRecord> submitRoll({
    String? actionId,
    int? expectedRevision,
  }) => _submit(
    kind: OnlineGameCommandKind.roll,
    actionId: actionId,
    expectedRevision: expectedRevision,
  );

  Future<OnlineGameCommandResultRecord> submitMove({
    required int tokenId,
    required int die,
    String? actionId,
    int? expectedRevision,
  }) => _submit(
    kind: OnlineGameCommandKind.move,
    tokenId: tokenId,
    die: die,
    actionId: actionId,
    expectedRevision: expectedRevision,
  );

  Future<OnlineGameCommandResultRecord> submitMoveAll({
    required int tokenId,
    String? actionId,
    int? expectedRevision,
  }) => _submit(
    kind: OnlineGameCommandKind.moveAll,
    tokenId: tokenId,
    actionId: actionId,
    expectedRevision: expectedRevision,
  );

  /// Activates the local participant's equipped power. No target or outcome
  /// is accepted from the client; the host authority resolves the effect.
  Future<OnlineGameCommandResultRecord> submitPowerUp({
    String? actionId,
    int? expectedRevision,
  }) => _submit(
    kind: OnlineGameCommandKind.powerUp,
    actionId: actionId,
    expectedRevision: expectedRevision,
  );

  /// Host-only roll for a CPU-controlled participant. This includes original
  /// virtual seats and a remote human after authoritative disconnect expiry.
  Future<OnlineGameCommandResultRecord> submitRollFor(
    String drivenParticipantId, {
    String? actionId,
    int? expectedRevision,
  }) {
    _requireHostDrivenParticipant(drivenParticipantId);
    return _submit(
      kind: OnlineGameCommandKind.roll,
      actingParticipantId: drivenParticipantId,
      actionId: actionId,
      expectedRevision: expectedRevision,
    );
  }

  /// Host-only single-die move for a CPU-controlled participant.
  Future<OnlineGameCommandResultRecord> submitMoveFor(
    String drivenParticipantId, {
    required int tokenId,
    required int die,
    String? actionId,
    int? expectedRevision,
  }) {
    _requireHostDrivenParticipant(drivenParticipantId);
    return _submit(
      kind: OnlineGameCommandKind.move,
      actingParticipantId: drivenParticipantId,
      tokenId: tokenId,
      die: die,
      actionId: actionId,
      expectedRevision: expectedRevision,
    );
  }

  /// Host-only combined-dice move for a CPU-controlled participant.
  Future<OnlineGameCommandResultRecord> submitMoveAllFor(
    String drivenParticipantId, {
    required int tokenId,
    String? actionId,
    int? expectedRevision,
  }) {
    _requireHostDrivenParticipant(drivenParticipantId);
    return _submit(
      kind: OnlineGameCommandKind.moveAll,
      actingParticipantId: drivenParticipantId,
      tokenId: tokenId,
      actionId: actionId,
      expectedRevision: expectedRevision,
    );
  }

  /// Host-only equipped-power activation for a CPU-controlled participant.
  Future<OnlineGameCommandResultRecord> submitPowerUpFor(
    String drivenParticipantId, {
    String? actionId,
    int? expectedRevision,
  }) {
    _requireHostDrivenParticipant(drivenParticipantId);
    return _submit(
      kind: OnlineGameCommandKind.powerUp,
      actingParticipantId: drivenParticipantId,
      actionId: actionId,
      expectedRevision: expectedRevision,
    );
  }

  Future<OnlineGameCommandResultRecord> _submit({
    required OnlineGameCommandKind kind,
    String? actingParticipantId,
    int? tokenId,
    int? die,
    String? actionId,
    int? expectedRevision,
  }) async {
    _ensureUsable();
    if (!_started || connectionState != OnlineGameConnectionState.connected) {
      throw const OnlineGameSyncException('The online match is not connected.');
    }
    final now = await transport.store.serverNowMs();
    final commandParticipantId = actingParticipantId ?? participantId;
    final resolvedActionId =
        actionId ?? _newActionId(now, commandParticipantId);
    final command = OnlineGameCommandRecord(
      kind: kind,
      matchId: session.matchId,
      participantId: commandParticipantId,
      submittedById: participantId,
      actionId: resolvedActionId,
      expectedRevision: expectedRevision ?? _authorityRevision,
      submittedAtMs: now,
      tokenId: tokenId,
      die: die,
    );
    final commandPath =
        '$_commandsPath/$commandParticipantId/$resolvedActionId';
    final transaction = await transport.store.transaction(commandPath, (raw) {
      if (raw == null) {
        return OnlineStoreTransactionDecision.commit(command.toJson());
      }
      return const OnlineStoreTransactionDecision.abort();
    });
    if (!transaction.committed) {
      OnlineGameCommandRecord? existing;
      try {
        existing = OnlineGameCommandRecord.fromJson(
          transaction.value,
          pathParticipantId: commandParticipantId,
          pathActionId: resolvedActionId,
        );
      } on FormatException {
        // The immutable path contains a malformed or unrelated command.
      }
      if (existing == null || !existing.representsSameAction(command)) {
        throw const OnlineGameSyncException(
          'That action ID already belongs to another command.',
        );
      }
    }
    return _waitForResult(commandParticipantId, resolvedActionId);
  }

  Future<OnlineGameCommandResultRecord> _waitForResult(
    String uid,
    String actionId,
  ) async {
    final cached = _results[uid]?[actionId];
    if (cached != null) return cached;
    final resultPath = '$matchPath/results/$uid/$actionId';
    final raw = await transport.store
        .watch(resultPath)
        .firstWhere((value) => value != null)
        .timeout(commandTimeout);
    final result = OnlineGameCommandResultRecord.fromJson(raw);
    _results.putIfAbsent(uid, () => {})[actionId] = result;
    _lastResult = result;
    notifyListeners();
    return result;
  }

  Future<void> _initializeHost() async {
    final raw = await transport.store.read(matchPath);
    if (raw != null) {
      _restoreHostDocument(raw);
      return;
    }
    final authority = _authority!;
    _authorityRevision = authority.revision;
    _stateRevision = 0;
    _createdAtMs = await transport.store.serverNowMs();
    final checkpoint = _engine.createCheckpoint();
    _lastCheckpointJson = jsonEncode(checkpoint);
    final document = await _hostDocument(checkpoint: checkpoint);
    final created = await transport.store.transaction(matchPath, (current) {
      if (current != null) {
        return const OnlineStoreTransactionDecision.abort();
      }
      return OnlineStoreTransactionDecision.commit(document);
    });
    if (!created.committed) _restoreHostDocument(created.value);
  }

  void _restoreHostDocument(Object? raw) {
    final document = onlineMap(raw);
    _validateMatchDocument(document);
    _activeHostUid = document['hostUid'] as String;
    if (document['hostUid'] != participantId) {
      throw const OnlineGameSyncException(
        'Only the recorded room host can resume this authority.',
      );
    }
    if (document['hostLocalColor'] != localColor.name) {
      throw const OnlineGameSyncException(
        'The host cannot resume with a different room seat.',
      );
    }
    final rawAuthority = onlineMap(document['authorityCheckpoint']);
    if (rawAuthority.isEmpty) {
      throw const FormatException('Missing authority checkpoint.');
    }
    final restored = OnlineMatchAuthority.fromCheckpoint(
      session: session,
      checkpoint: _dynamicMap(rawAuthority),
      localViewerColor: localColor,
      disconnectPolicy:
          _authority?.disconnectPolicy ?? const OnlineDisconnectPolicy(),
    );
    if (restored.engine.localViewerColor != localColor) {
      restored.dispose();
      throw const OnlineGameSyncException(
        'The restored authority uses a different local viewer seat.',
      );
    }
    final fullCheckpoint = onlineMap(document['checkpoint']);
    if (fullCheckpoint.isEmpty) {
      restored.dispose();
      throw const FormatException('Missing full engine checkpoint.');
    }
    restored.engine.applyRemoteCheckpoint(_dynamicMap(fullCheckpoint));
    _needsHostTransitionResume = true;
    _authority?.dispose();
    _authority = restored;
    _engine = restored.engine;
    _authorityRevision = restored.revision;
    _stateRevision = (document['stateRevision'] as num).toInt();
    _createdAtMs = (document['createdAt'] as num).toInt();
    final checkpoint = onlineMap(document['checkpoint']);
    _lastCheckpointJson = jsonEncode(checkpoint);
    _restoreResults(document['results']);
  }

  Future<void> _readAndApplyMatchDocument({required bool required}) async {
    final raw = await transport.store.read(matchPath);
    if (raw == null) {
      if (required) {
        throw const OnlineGameSyncException(
          'The host has not created the online match yet.',
        );
      }
      return;
    }
    _applyMatchDocument(raw);
  }

  void _handleMatchSnapshot(Object? raw) {
    if (!_started || raw == null) return;
    try {
      _applyMatchDocument(raw);
    } catch (error) {
      _lastError = error;
      _setConnectionState(OnlineGameConnectionState.failed);
    }
  }

  void _handleSafeChatSnapshot(Object? raw) {
    if (!_started || raw == null || _safeChatMessages.isClosed) return;
    final messages = <OnlineSafeChatMessage>[];
    for (final entry in onlineMap(raw).entries) {
      try {
        final message = OnlineSafeChatMessage.fromJson(
          entry.value,
          pathMessageId: entry.key,
        );
        final sender = session.participants
            .where((participant) => participant.id == message.senderUid)
            .firstOrNull;
        if (sender == null || !sender.beganAsHuman) continue;
        messages.add(message);
      } on FormatException {
        // Security rules reject malformed writes. Ignore an invalid legacy or
        // emulator record without taking the live match connection down.
      }
    }
    messages.sort((left, right) {
      final byTime = left.sentAtMs.compareTo(right.sentAtMs);
      return byTime != 0 ? byTime : left.messageId.compareTo(right.messageId);
    });
    for (final message in messages) {
      if (_seenSafeChatMessageIds.add(message.messageId)) {
        _safeChatMessages.add(message);
      }
    }
  }

  void _handleSafeChatStreamError(Object error, StackTrace stackTrace) {
    if (!_safeChatMessages.isClosed) {
      _safeChatMessages.addError(error, stackTrace);
    }
  }

  void _applyMatchDocument(Object? raw) {
    final document = onlineMap(raw);
    _validateMatchDocument(document);
    _activeHostUid = document['hostUid'] as String;
    _localAuthorityPresence = _authorityPresenceFromDocument(
      document,
      participantId,
    );
    _authorityRevision = (document['authorityRevision'] as num).toInt();
    _restoreResults(document['results']);
    final incomingStateRevision = (document['stateRevision'] as num).toInt();
    if (incomingStateRevision <= _stateRevision) return;
    final checkpoint = onlineMap(document['checkpoint']);
    if (checkpoint.isEmpty) {
      throw const FormatException('Missing full engine checkpoint.');
    }
    final encodedCheckpoint = jsonEncode(checkpoint);
    // Presence-only authority publications intentionally keep the board
    // checkpoint identical. Do not restart/cancel replica animations merely
    // because another player's reconnect state changed.
    if (encodedCheckpoint != _lastCheckpointJson) {
      _engine.applyRemoteCheckpoint(_dynamicMap(checkpoint));
    }
    _stateRevision = incomingStateRevision;
    _lastCheckpointJson = encodedCheckpoint;
    notifyListeners();
  }

  Future<void> _waitForLocalAuthorityReconnect() async {
    if (isHost ||
        _localAuthorityPresence == null ||
        _localAuthorityPresence == OnlineParticipantPresence.connected) {
      return;
    }
    if (_localAuthorityPresence == OnlineParticipantPresence.forfeited) {
      throw const OnlineGameSyncException(
        'This participant already forfeited the online match.',
      );
    }
    try {
      final acknowledged = await transport.store
          .watch(matchPath)
          .firstWhere((raw) {
            if (raw == null) return false;
            final presence = _authorityPresenceFromDocument(
              onlineMap(raw),
              participantId,
            );
            return presence == OnlineParticipantPresence.connected ||
                presence == OnlineParticipantPresence.forfeited;
          })
          .timeout(commandTimeout);
      _applyMatchDocument(acknowledged);
    } on TimeoutException {
      throw const OnlineGameSyncException(
        'The host did not acknowledge this participant reconnect.',
      );
    }
    if (_localAuthorityPresence != OnlineParticipantPresence.connected) {
      throw const OnlineGameSyncException(
        'This participant cannot reclaim the online match seat.',
      );
    }
  }

  void _handleCommandSnapshot(Object? raw) {
    if (!_started || !isHost) return;
    final batches = onlineMap(raw);
    final pending = <OnlineGameCommandRecord>[];
    final malformed = <(String, String)>[];
    for (final participantEntry in batches.entries) {
      final uid = participantEntry.key;
      for (final actionEntry in onlineMap(participantEntry.value).entries) {
        final actionId = actionEntry.key;
        if (_results[uid]?.containsKey(actionId) ?? false) continue;
        try {
          pending.add(
            OnlineGameCommandRecord.fromJson(
              actionEntry.value,
              pathParticipantId: uid,
              pathActionId: actionId,
            ),
          );
        } on FormatException {
          malformed.add((uid, actionId));
        }
      }
    }
    pending.sort((left, right) {
      final byTime = left.submittedAtMs.compareTo(right.submittedAtMs);
      if (byTime != 0) return byTime;
      final byParticipant = left.participantId.compareTo(right.participantId);
      return byParticipant != 0
          ? byParticipant
          : left.actionId.compareTo(right.actionId);
    });
    unawaited(
      _enqueue(() async {
        for (final pair in malformed) {
          await _rejectMalformed(pair.$1, pair.$2);
        }
        for (final command in pending) {
          await _processCommand(command);
        }
      }),
    );
  }

  Future<void> _rejectMalformed(String uid, String actionId) async {
    if (_results[uid]?.containsKey(actionId) ?? false) return;
    final now = await transport.store.serverNowMs();
    final result = OnlineGameCommandResultRecord(
      actionId: actionId,
      participantId: uid,
      status: OnlineCommandStatus.rejected,
      rejection: OnlineCommandRejection.invalidActionId,
      authorityRevision: _authority!.revision,
      stateRevision: _stateRevision + 1,
      processedAtMs: now,
    );
    await _publishHostState(result: result);
  }

  Future<void> _processCommand(OnlineGameCommandRecord command) async {
    final key = '${command.participantId}/${command.actionId}';
    if ((_results[command.participantId]?.containsKey(command.actionId) ??
            false) ||
        !_processingActionKeys.add(key)) {
      return;
    }
    try {
      _suppressHostEngineListener = true;
      final isHostDriven =
          command.submittedById == participantId &&
          command.participantId != participantId;
      final invalidSubmitter =
          command.submittedById != command.participantId && !isHostDriven;
      final hostMayDrive =
          isHostDriven && canHostDriveParticipant(command.participantId);
      final authorityResult =
          invalidSubmitter || (isHostDriven && !hostMayDrive)
          ? OnlineCommandResult.rejected(
              OnlineCommandRejection.participantUnavailable,
              _authority!.snapshot(),
            )
          : _authority!.submit(
              command.toAuthorityCommand(),
              allowCpuControlledParticipant: hostMayDrive,
            );
      _suppressHostEngineListener = false;
      final now = await transport.store.serverNowMs();
      final result = OnlineGameCommandResultRecord(
        actionId: command.actionId,
        participantId: command.participantId,
        status: authorityResult.status,
        rejection: authorityResult.rejection,
        authorityRevision: authorityResult.snapshot.revision,
        stateRevision: _stateRevision + 1,
        processedAtMs: now,
      );
      await _publishHostState(result: result);
    } finally {
      _suppressHostEngineListener = false;
      _processingActionKeys.remove(key);
    }
  }

  void _attachHostEngineListener() {
    if (_hostListenerAttached) return;
    _engine.addListener(_handleHostEngineMutation);
    _hostListenerAttached = true;
  }

  void _handleHostEngineMutation() {
    if (_disposed || !_started || !isHost || _suppressHostEngineListener) {
      return;
    }
    unawaited(_enqueue(() => _publishHostState()));
  }

  void _handlePresenceSnapshot(Object? raw) {
    if (!_started || !isHost) return;
    final records = onlineMap(raw);
    unawaited(_enqueue(() => _applyPresenceSnapshot(records)));
  }

  void _handleGuestPresenceSnapshot(Object? raw) {
    if (_disposed || !_started || isHost) return;
    final hostUid = _activeHostUid;
    if (hostUid == null) return;
    final hostRecord = onlineMap(onlineMap(raw)[hostUid]);
    final roomPresence = LobbyPresence.values
        .where((value) => value.name == hostRecord['state'])
        .firstOrNull;
    if (roomPresence == LobbyPresence.connected) {
      _markHostAvailable();
      return;
    }
    _markHostReconnecting();
  }

  void _markHostAvailable() {
    _hostRecoveryTimer?.cancel();
    _hostRecoveryTimer = null;
    _hostReconnectDeadline = null;
    if (_hostAvailability == OnlineHostAvailability.available) return;
    _hostAvailability = OnlineHostAvailability.available;
    if (_lastError is OnlineHostUnavailableException) _lastError = null;
    if (_started && !_disposed) {
      _setConnectionState(OnlineGameConnectionState.connected);
    }
  }

  void _markHostReconnecting() {
    if (_hostAvailability == OnlineHostAvailability.unavailable) return;
    if (_hostAvailability == OnlineHostAvailability.available) {
      _hostAvailability = OnlineHostAvailability.reconnecting;
      _hostReconnectDeadline = DateTime.now().add(hostReconnectGrace);
      _setConnectionState(OnlineGameConnectionState.reconnecting);
    }
    if (_hostRecoveryTimer != null) return;
    _hostReconnectDeadline ??= DateTime.now().add(hostReconnectGrace);
    _hostRecoveryTimer = Timer(hostReconnectGrace, () {
      _hostRecoveryTimer = null;
      if (_disposed ||
          !_started ||
          _hostAvailability != OnlineHostAvailability.reconnecting) {
        return;
      }
      _hostAvailability = OnlineHostAvailability.unavailable;
      _lastError = const OnlineHostUnavailableException();
      _setConnectionState(OnlineGameConnectionState.failed);
    });
  }

  Future<void> _applyPresenceSnapshot(Map<String, Object?> records) async {
    if (_disposed || !_started || !isHost) return;
    final nowMs = await transport.store.serverNowMs();
    final now = DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true);
    var changed = false;

    for (final participant in session.participants) {
      if (!participant.beganAsHuman || participant.id == participantId) {
        continue;
      }
      final rawRecord = onlineMap(records[participant.id]);
      final roomPresence = LobbyPresence.values
          .where((value) => value.name == rawRecord['state'])
          .firstOrNull;
      final beforeRevision = _authority!.revision;
      if (roomPresence == LobbyPresence.connected) {
        _disconnectGraceTimers.remove(participant.id)?.cancel();
        _authority!.reconnect(participant.id, now: now);
      } else {
        _authority!.markDisconnected(participant.id, now: now);
        _scheduleDisconnectGrace(participant.id, now);
      }
      changed = changed || _authority!.revision != beforeRevision;
    }

    if (changed) await _publishHostState(force: true);
  }

  void _scheduleDisconnectGrace(String candidateId, DateTime now) {
    _disconnectGraceTimers.remove(candidateId)?.cancel();
    final connection = _authority!.snapshot().connectionFor(candidateId);
    final deadline = connection.reconnectDeadline;
    if (connection.presence != OnlineParticipantPresence.reconnecting ||
        deadline == null) {
      return;
    }
    final remaining = deadline.difference(now);
    _disconnectGraceTimers[candidateId] = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      () {
        _disconnectGraceTimers.remove(candidateId);
        if (_disposed || !_started || !isHost) return;
        unawaited(_enqueue(() => _enforceDisconnectGrace(candidateId)));
      },
    );
  }

  Future<void> _enforceDisconnectGrace(String candidateId) async {
    if (_disposed || !_started || !isHost) return;
    final nowMs = await transport.store.serverNowMs();
    final now = DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true);
    final transitions = _authority!.enforceDisconnectPolicy(now);
    if (transitions.isNotEmpty) {
      for (final transition in transitions) {
        _disconnectGraceTimers.remove(transition.participantId)?.cancel();
      }
      await _publishHostState(force: true);
      return;
    }
    _scheduleDisconnectGrace(candidateId, now);
  }

  Future<void> _publishHostState({
    OnlineGameCommandResultRecord? result,
    bool force = false,
  }) async {
    final checkpoint = _engine.createCheckpoint();
    final encodedCheckpoint = jsonEncode(checkpoint);
    if (!force && result == null && encodedCheckpoint == _lastCheckpointJson) {
      return;
    }
    _stateRevision++;
    _authorityRevision = _authority!.revision;
    if (result != null) {
      final storedResult = OnlineGameCommandResultRecord(
        actionId: result.actionId,
        participantId: result.participantId,
        status: result.status,
        rejection: result.rejection,
        authorityRevision: result.authorityRevision,
        stateRevision: _stateRevision,
        processedAtMs: result.processedAtMs,
      );
      _results.putIfAbsent(
        storedResult.participantId,
        () => {},
      )[storedResult.actionId] = storedResult;
      _lastResult = storedResult;
    }
    await transport.store.set(
      matchPath,
      await _hostDocument(checkpoint: checkpoint),
    );
    _lastCheckpointJson = encodedCheckpoint;
    notifyListeners();
  }

  Future<Map<String, Object?>> _hostDocument({
    required Map<String, Object?> checkpoint,
  }) async {
    final now = await transport.store.serverNowMs();
    final authorityCheckpoint = _authority!.createCheckpoint();
    authorityCheckpoint['engine'] = checkpoint;
    return <String, Object?>{
      'schemaVersion': onlineGameSyncSchemaVersion,
      'authorityModel': onlineGameSyncAuthorityModel,
      'roomId': roomId,
      'matchId': session.matchId,
      'hostUid': participantId,
      'hostLocalColor': localColor.name,
      'authorityRevision': _authority!.revision,
      'stateRevision': _stateRevision,
      'checkpoint': checkpoint,
      'authorityCheckpoint': authorityCheckpoint,
      'results': <String, Object?>{
        for (final participantEntry in _results.entries)
          participantEntry.key: <String, Object?>{
            for (final resultEntry in participantEntry.value.entries)
              resultEntry.key: resultEntry.value.toJson(),
          },
      },
      'createdAt': _createdAtMs,
      'updatedAt': now,
    };
  }

  void _validateMatchDocument(Map<String, Object?> document) {
    if (document['schemaVersion'] != onlineGameSyncSchemaVersion ||
        document['authorityModel'] != onlineGameSyncAuthorityModel ||
        document['roomId'] != roomId ||
        document['matchId'] != session.matchId ||
        document['hostUid'] is! String ||
        document['hostLocalColor'] is! String ||
        document['authorityRevision'] is! num ||
        document['stateRevision'] is! num ||
        document['createdAt'] is! num) {
      throw const FormatException('Invalid online match document.');
    }
  }

  void _restoreResults(Object? raw) {
    for (final participantEntry in onlineMap(raw).entries) {
      final participantResults = _results.putIfAbsent(
        participantEntry.key,
        () => {},
      );
      for (final resultEntry in onlineMap(participantEntry.value).entries) {
        try {
          participantResults[resultEntry.key] =
              OnlineGameCommandResultRecord.fromJson(resultEntry.value);
        } on FormatException {
          // A malformed result is ignored; the authoritative checkpoint still
          // remains usable and a later host publication may replace it.
        }
      }
    }
  }

  Future<void> _cancelSubscriptions({bool disconnectPresence = false}) async {
    if (_hostListenerAttached) {
      _engine.removeListener(_handleHostEngineMutation);
      _hostListenerAttached = false;
    }
    _hostResumeTurnTimer?.cancel();
    _hostResumeEffectTimer?.cancel();
    _hostRecoveryTimer?.cancel();
    _hostResumeTurnTimer = null;
    _hostResumeEffectTimer = null;
    _hostRecoveryTimer = null;
    for (final timer in _disconnectGraceTimers.values) {
      timer.cancel();
    }
    _disconnectGraceTimers.clear();
    if (isHost && _hostHasPendingTransition) {
      final checkpoint = _engine.createCheckpoint();
      _engine.applyRemoteCheckpoint(_dynamicMap(checkpoint));
      _needsHostTransitionResume = true;
    }
    await _commandSubscription?.cancel();
    await _matchSubscription?.cancel();
    await _presenceSubscription?.cancel();
    await _safeChatSubscription?.cancel();
    _commandSubscription = null;
    _matchSubscription = null;
    _presenceSubscription = null;
    _safeChatSubscription = null;
    if (disconnectPresence) {
      final lease = _presenceLease;
      _presenceLease = null;
      await lease?.disconnect();
    }
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _serial.then((_) => operation());
    _serial = next.catchError((Object error, StackTrace stackTrace) {
      _lastError = error;
      if (!_disposed) notifyListeners();
    });
    return next;
  }

  void _handleStreamError(Object error, StackTrace stackTrace) {
    _lastError = error;
    _setConnectionState(OnlineGameConnectionState.failed);
  }

  bool get _hostHasPendingTransition =>
      !_engine.gameOver &&
      (_engine.effectResolving ||
          (_engine.hasRolled &&
              (_engine.remainingDice.isEmpty || !_engine.hasAnyMove())));

  OnlineGameConnectionState get _connectionStateForHostAvailability {
    if (isHost || _hostAvailability == OnlineHostAvailability.available) {
      return OnlineGameConnectionState.connected;
    }
    if (_hostAvailability == OnlineHostAvailability.reconnecting) {
      return OnlineGameConnectionState.reconnecting;
    }
    return OnlineGameConnectionState.failed;
  }

  /// GameEngine intentionally does not recreate timers on a remote
  /// checkpoint. When the active host itself reconnects, this controller owns
  /// the one pending transition and republishes its completion.
  void _resumeHostTransitionsIfNeeded() {
    if (!isHost || !_needsHostTransitionResume || !_hostHasPendingTransition) {
      _needsHostTransitionResume = false;
      return;
    }
    _needsHostTransitionResume = false;
    if (_engine.effectResolving) {
      _hostResumeEffectTimer = Timer(const Duration(milliseconds: 900), () {
        _hostResumeEffectTimer = null;
        if (_disposed || !_started || !_engine.effectResolving) return;
        final checkpoint = _engine.createCheckpoint();
        checkpoint['effectResolving'] = false;
        _engine.applyRemoteCheckpoint(_dynamicMap(checkpoint));
      });
    }
    if (_engine.hasRolled &&
        (_engine.remainingDice.isEmpty || !_engine.hasAnyMove())) {
      final delay = _engine.effectPowerUp != null
          ? const Duration(milliseconds: 2300)
          : _engine.effectResolving
          ? const Duration(milliseconds: 900)
          : const Duration(milliseconds: 650);
      _hostResumeTurnTimer = Timer(delay, () {
        _hostResumeTurnTimer = null;
        if (_disposed || !_started || _engine.gameOver) return;
        if (_engine.hasRolled &&
            (_engine.remainingDice.isEmpty || !_engine.hasAnyMove())) {
          _engine.endTurn();
        }
      });
    }
  }

  void _setConnectionState(OnlineGameConnectionState value) {
    if (_connectionState == value) return;
    _connectionState = value;
    if (!_disposed || value == OnlineGameConnectionState.disposed) {
      notifyListeners();
    }
  }

  void _requireHostDrivenParticipant(String candidateId) {
    if (!isHost) {
      throw const OnlineGameSyncException(
        'Only the room host can drive a CPU-controlled participant.',
      );
    }
    if (!canHostDriveParticipant(candidateId)) {
      throw const OnlineGameSyncException(
        'The requested participant is not under CPU control.',
      );
    }
  }

  String _newActionId(int now, String actingParticipantId) =>
      'a_${actingParticipantId.hashCode.abs()}_${now}_'
      '${_random.nextInt(0x7fffffff)}_${_random.nextInt(0x7fffffff)}';

  String _newSafeChatMessageId(int now) =>
      'm_${participantId.hashCode.abs()}_${now}_'
      '${_random.nextInt(0x7fffffff)}_${_random.nextInt(0x7fffffff)}';

  void _ensureUsable() {
    if (_disposed) {
      throw const OnlineGameSyncException(
        'The online match controller has been disposed.',
      );
    }
  }

  void _ensureStartActive() {
    if (_disposed || !_started) {
      throw const OnlineGameSyncException(
        'The online match start was cancelled before it completed.',
      );
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _started = false;
    if (_hostListenerAttached) {
      _engine.removeListener(_handleHostEngineMutation);
      _hostListenerAttached = false;
    }
    unawaited(_commandSubscription?.cancel());
    unawaited(_matchSubscription?.cancel());
    unawaited(_presenceSubscription?.cancel());
    unawaited(_safeChatSubscription?.cancel());
    unawaited(_safeChatMessages.close());
    final presenceLease = _presenceLease;
    _presenceLease = null;
    unawaited(presenceLease?.disconnect());
    _hostResumeTurnTimer?.cancel();
    _hostResumeEffectTimer?.cancel();
    _hostRecoveryTimer?.cancel();
    for (final timer in _disconnectGraceTimers.values) {
      timer.cancel();
    }
    _disconnectGraceTimers.clear();
    _hostRecoveryTimer = null;
    _commandSubscription = null;
    _matchSubscription = null;
    _presenceSubscription = null;
    _safeChatSubscription = null;
    _authority?.dispose();
    _connectionState = OnlineGameConnectionState.disposed;
    super.dispose();
  }
}

OnlineParticipantPresence? _authorityPresenceFromDocument(
  Map<String, Object?> document,
  String participantId,
) {
  final authority = onlineMap(document['authorityCheckpoint']);
  final connections = authority['connections'];
  if (connections is! List) return null;
  for (final raw in connections) {
    final connection = onlineMap(raw);
    if (connection['participantId'] != participantId) continue;
    final presenceName = connection['presence'];
    return OnlineParticipantPresence.values
        .where((value) => value.name == presenceName)
        .firstOrNull;
  }
  return null;
}

Map<String, dynamic> _dynamicMap(Map<String, Object?> map) => <String, dynamic>{
  for (final entry in map.entries)
    entry.key: entry.value is Map
        ? _dynamicMap(onlineMap(entry.value))
        : entry.value is List
        ? _dynamicList(entry.value as List)
        : entry.value,
};

List<dynamic> _dynamicList(List<dynamic> values) => values
    .map<dynamic>(
      (value) => value is Map
          ? _dynamicMap(onlineMap(value))
          : value is List
          ? _dynamicList(value)
          : value,
    )
    .toList(growable: false);
