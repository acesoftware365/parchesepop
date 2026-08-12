import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'online_lobby.dart';
import 'online_room_ui.dart';
import 'online_transport.dart';
import 'online_transport_models.dart';

/// Realtime implementation of [OnlineRoomController].
///
/// Room membership, presence, privacy, and public discovery are delegated to
/// [OnlineTransportClient]. The host is the sole writer of the serialized
/// [OnlineLobby] aggregate and the sole generator of opening-roll dice.
final class RealtimeOnlineRoomController extends ChangeNotifier
    implements OnlineRoomController {
  RealtimeOnlineRoomController({
    required this.transport,
    Random? openingRollRandom,
    this.joinTimeout = const Duration(seconds: 15),
    this.onGameReady,
  }) : _openingRollRandom = openingRollRandom ?? Random.secure() {
    _listenToPublicRooms();
  }

  final OnlineTransportClient transport;
  final Duration joinTimeout;
  final ValueChanged<OnlineLobby>? onGameReady;
  final Random _openingRollRandom;

  final StreamController<OnlineLobby> _lobbySnapshots =
      StreamController<OnlineLobby>.broadcast(sync: true);
  final StreamController<OnlineLobby> _gameReadySnapshots =
      StreamController<OnlineLobby>.broadcast(sync: true);
  final Set<String> _announcedInGameRooms = <String>{};

  StreamSubscription<List<PublicOnlineRoomRecord>>? _publicRoomsSubscription;
  StreamSubscription<OnlineRoomRecord?>? _roomSubscription;
  StreamSubscription<Object?>? _lobbyStateSubscription;
  StreamSubscription<Object?>? _openingRollRequestsSubscription;
  OnlineHostRoomLease? _hostRoomLease;

  OnlineLobby? _lobby;
  OnlineRoomRecord? _roomRecord;
  OnlineRoomGameMode? _roomMode;
  List<PublicRoomSummary> _publicRooms = const <PublicRoomSummary>[];
  bool _loadingPublicRooms = true;
  String? _publicRoomsError;
  String? _roomError;
  bool _disposed = false;
  bool _drainingOpeningRollRequests = false;
  int _createAttempt = 0;
  int _joinAttempt = 0;
  OnlineRoomJoinRequestRecord? _pendingJoinRequest;
  int _roomEpoch = 0;
  String? _lastPublishedWaitingFingerprint;
  Future<void>? _closedRoomDismissal;

  @override
  String get localParticipantId => transport.identity.uid;

  @override
  OnlineLobby? get lobby => _lobby;

  OnlineRoomRecord? get roomRecord => _roomRecord;

  @override
  OnlineRoomGameMode? get roomMode => _roomMode;

  @override
  List<PublicRoomSummary> get publicRooms => _publicRooms;

  @override
  bool get loadingPublicRooms => _loadingPublicRooms;

  @override
  String? get publicRoomsError => _publicRoomsError;

  String? get roomError => _roomError;

  /// Every accepted lobby snapshot, including the final in-game snapshot.
  Stream<OnlineLobby> get lobbySnapshots => _lobbySnapshots.stream;

  /// Emits once per room when the opening-roll winner has been promoted to a
  /// live game. Main can use this to launch the synchronized match screen.
  Stream<OnlineLobby> get gameReady => _gameReadySnapshots.stream;

  String get _roomsPath => '$onlineTransportRoot/rooms';

  String _lobbyStatePath(String roomId) => '$_roomsPath/$roomId/lobbyState';

  String _openingRequestsPath(String roomId) =>
      '$_roomsPath/$roomId/openingRollRequests';

  void _listenToPublicRooms() {
    _publicRoomsSubscription = transport.watchPublicRooms().listen(
      (records) {
        if (_disposed) return;
        _publicRooms = _summaries(records);
        _loadingPublicRooms = false;
        _publicRoomsError = null;
        _notify();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_disposed) return;
        _loadingPublicRooms = false;
        _publicRoomsError = error.toString();
        _notify();
      },
    );
  }

  @override
  Future<void> refreshPublicRooms() async {
    _ensureActive();
    _loadingPublicRooms = true;
    _publicRoomsError = null;
    _notify();
    try {
      final records = await transport.listPublicRooms();
      if (_disposed) return;
      _publicRooms = _summaries(records);
      _loadingPublicRooms = false;
      _notify();
    } catch (error) {
      if (_disposed) rethrow;
      _loadingPublicRooms = false;
      _publicRoomsError = error.toString();
      _notify();
      rethrow;
    }
  }

  @override
  Future<void> createRoom({
    required OnlineRoomGameMode mode,
    required RoomVisibility visibility,
    String? roomName,
  }) async {
    _ensureActive();
    final attempt = ++_createAttempt;
    await transport.syncProfile();
    _throwIfCreateCancelled(attempt);
    final room = await transport.createRoom(
      visibility: visibility,
      mode: mode.name,
      matchFormat: 'quickTable',
      roomName: roomName,
    );
    if (_createCancelled(attempt)) {
      await _cleanupCancelledCreate(room);
      throw const OnlineRoomOperationCancelledException();
    }
    try {
      await _attachRoom(room);
    } catch (_) {
      if (_createCancelled(attempt)) {
        await _cleanupCancelledCreate(room);
        throw const OnlineRoomOperationCancelledException();
      }
      rethrow;
    }
    if (_createCancelled(attempt)) {
      await _cleanupCancelledCreate(room);
      throw const OnlineRoomOperationCancelledException();
    }
  }

  @override
  Future<void> reportPublicRoom({
    required String roomId,
    required String reason,
  }) => transport.reportPublicRoom(roomId: roomId, reason: reason);

  @override
  Future<void> cancelPendingCreate() async {
    _ensureActive();
    _createAttempt++;
  }

  bool _createCancelled(int attempt) => _disposed || attempt != _createAttempt;

  void _throwIfCreateCancelled(int attempt) {
    if (_createCancelled(attempt)) {
      throw const OnlineRoomOperationCancelledException();
    }
  }

  Future<void> _cleanupCancelledCreate(OnlineRoomRecord room) async {
    if (_roomRecord?.id == room.id) {
      await _detachRoom(clearState: true);
    }
    try {
      await transport.closeRoom(room.id);
    } catch (error) {
      debugPrint(
        'Late room-create cleanup was incomplete (${error.runtimeType}).',
      );
    }
  }

  @override
  Future<void> joinRoomByCode(RoomCode roomCode) async {
    _ensureActive();
    final attempt = ++_joinAttempt;
    await _joinRoomByCode(roomCode, attempt);
  }

  Future<void> _joinRoomByCode(RoomCode roomCode, int attempt) async {
    await transport.syncProfile();
    _throwIfJoinCancelled(attempt);
    final request = await transport.requestRoomJoinByCode(roomCode.value);
    if (_disposed || attempt != _joinAttempt) {
      await transport.cancelRoomJoinRequest(request);
      _throwJoinCancelled();
    }
    _pendingJoinRequest = request;
    try {
      late final OnlineRoomRecord room;
      try {
        room = await transport.waitForRoomAdmission(
          request,
          timeout: joinTimeout,
          cancelled: () => _disposed || attempt != _joinAttempt,
        );
      } on OnlineTransportException catch (error) {
        if (error.code == OnlineTransportErrorCode.joinCancelled) {
          await _cleanupCancelledJoinIfAdmitted(request);
        }
        rethrow;
      }
      if (_disposed || attempt != _joinAttempt) {
        await _cleanupCancelledJoin(room, request);
        _throwJoinCancelled();
      }
      try {
        await _attachRoom(room);
      } catch (_) {
        if (_disposed || attempt != _joinAttempt) {
          await _cleanupCancelledJoin(room, request);
          _throwJoinCancelled();
        }
        rethrow;
      }
      if (_disposed || attempt != _joinAttempt) {
        await _cleanupCancelledJoin(room, request);
        _throwJoinCancelled();
      }
    } finally {
      if (identical(_pendingJoinRequest, request)) {
        _pendingJoinRequest = null;
      }
    }
  }

  @override
  Future<void> joinPublicRoom(String roomId) async {
    _ensureActive();
    final attempt = ++_joinAttempt;
    var matching = _publicRooms.where((room) => room.roomId == roomId);
    if (matching.isEmpty) {
      await refreshPublicRooms();
      _throwIfJoinCancelled(attempt);
      matching = _publicRooms.where((room) => room.roomId == roomId);
    }
    _throwIfJoinCancelled(attempt);
    if (matching.isEmpty) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.roomNotFound,
        'The selected public room is no longer available.',
      );
    }
    await _joinRoomByCode(matching.single.roomCode, attempt);
  }

  @override
  Future<void> cancelPendingJoin() async {
    _ensureActive();
    _joinAttempt++;
    final pendingJoin = _pendingJoinRequest;
    _pendingJoinRequest = null;
    if (pendingJoin != null) {
      await transport.cancelRoomJoinRequest(pendingJoin);
    }
  }

  void _throwIfJoinCancelled(int attempt) {
    if (_disposed || attempt != _joinAttempt) _throwJoinCancelled();
  }

  Never _throwJoinCancelled() => throw const OnlineTransportException(
    OnlineTransportErrorCode.joinCancelled,
    'The room join was cancelled.',
  );

  Future<void> _cleanupCancelledJoin(
    OnlineRoomRecord room,
    OnlineRoomJoinRequestRecord request,
  ) async {
    if (_roomRecord?.id == room.id) {
      await _detachRoom(clearState: true);
    }
    try {
      await transport.cancelRoomJoinRequest(request);
    } catch (_) {
      // Admission may already have removed the pending request.
    }
    if (!room.members.containsKey(localParticipantId)) return;
    try {
      await transport.leaveRoom(room.id);
    } catch (error) {
      debugPrint(
        'Cancelled room-join cleanup was incomplete (${error.runtimeType}).',
      );
    }
  }

  Future<void> _cleanupCancelledJoinIfAdmitted(
    OnlineRoomJoinRequestRecord request,
  ) async {
    try {
      final room = await transport.readRoom(request.roomId);
      if (room != null && room.members.containsKey(localParticipantId)) {
        await _cleanupCancelledJoin(room, request);
      }
    } catch (error) {
      debugPrint(
        'Cancelled room-join verification was incomplete '
        '(${error.runtimeType}).',
      );
    }
  }

  @override
  Future<void> setReady(bool ready) async {
    final room = _requireRoom();
    final updated = await transport.updateReady(roomId: room.id, ready: ready);
    _acceptRoomRecord(updated, _roomEpoch);
  }

  @override
  Future<void> changeVisibility(RoomVisibility visibility) async {
    final room = _requireRoom();
    final updated = await transport.updatePrivacy(
      roomId: room.id,
      visibility: visibility,
    );
    _acceptRoomRecord(updated, _roomEpoch);
  }

  @override
  Future<void> kick(String participantId) async {
    final room = _requireRoom();
    final preview = _cloneLobby(_requireLobby());
    preview.kick(
      actorParticipantId: localParticipantId,
      targetParticipantId: participantId,
    );
    final now = await transport.store.serverNowMs();
    final result = await transport.store.transaction('$_roomsPath/${room.id}', (
      raw,
    ) {
      if (raw == null) {
        throw const OnlineTransportException(
          OnlineTransportErrorCode.roomNotFound,
          'The room no longer exists.',
        );
      }
      final current = OnlineRoomRecord.fromJson(raw);
      if (current.hostUid != localParticipantId) {
        throw const OnlineTransportException(
          OnlineTransportErrorCode.notHost,
          'Only the host can remove a room member.',
        );
      }
      if (current.status != RoomStatus.waiting) {
        throw const OnlineTransportException(
          OnlineTransportErrorCode.invalidRoomStatus,
          'Players can be removed only while the room is waiting.',
        );
      }
      if (participantId == current.hostUid) {
        throw const LobbyException(
          LobbyErrorCode.hostCannotBeKicked,
          'The host must close the room instead.',
        );
      }
      if (!current.members.containsKey(participantId)) {
        throw const OnlineTransportException(
          OnlineTransportErrorCode.unknownParticipant,
          'The selected player is not in this room.',
        );
      }
      final map = onlineMap(raw);
      final members = onlineMap(map['members'])..remove(participantId);
      final presence = onlineMap(map['presence'])..remove(participantId);
      map
        ..['members'] = members
        ..['presence'] = presence
        ..['revision'] = current.revision + 1
        ..['updatedAt'] = now;
      return OnlineStoreTransactionDecision.commit(map);
    });
    final updated = OnlineRoomRecord.fromJson(result.value);
    await transport.store.set(
      '${_openingRequestsPath(room.id)}/$participantId',
      null,
    );
    _acceptRoomRecord(updated, _roomEpoch);
  }

  /// Leaves a waiting lobby. If the local player is the host, leaving closes
  /// the room for everyone instead of transferring host authority.
  @override
  Future<void> leaveRoom() async {
    final room = _requireRoom();
    if (room.hostUid == localParticipantId) {
      await closeRoom();
      return;
    }
    await transport.leaveRoom(room.id);
    await _detachRoom(clearState: true);
  }

  @override
  Future<void> closeRoom() async {
    final room = _requireRoom();
    final epoch = _roomEpoch;
    final closedLobby = _cloneLobby(_requireLobby());
    closedLobby.close(actorParticipantId: localParticipantId);
    final updated = await transport.closeRoom(room.id);
    await transport.store.set(_lobbyStatePath(room.id), closedLobby.toJson());
    if (_disposed || epoch != _roomEpoch) return;
    _roomRecord = updated;
    _setLobby(closedLobby);
  }

  @override
  Future<void> dismissClosedRoom() {
    _ensureActive();
    final pending = _closedRoomDismissal;
    if (pending != null) return pending;
    late final Future<void> operation;
    operation = _dismissClosedRoom().whenComplete(() {
      if (identical(_closedRoomDismissal, operation)) {
        _closedRoomDismissal = null;
      }
    });
    _closedRoomDismissal = operation;
    return operation;
  }

  Future<void> _dismissClosedRoom() async {
    final room = _requireRoom();
    final currentLobby = _lobby;
    if (room.status != RoomStatus.closed &&
        currentLobby?.status != RoomStatus.closed) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.invalidRoomStatus,
        'Only a closed room can be dismissed.',
      );
    }
    try {
      // OnlineTransport treats leaving an already-closed room as presence-only
      // cleanup for both host and guests; it does not issue another close.
      await transport.leaveRoom(room.id);
    } finally {
      await _detachRoom(clearState: true);
    }
  }

  @override
  Future<void> startOpeningRoll() async {
    final room = _requireRoom();
    // Quick Table supports 2–4 humans. Before publishing the opening roll,
    // materialize any empty board colors as host-owned CPU seats so every
    // client receives the same four-color match and CPU commands pass the
    // realtime membership checks.
    final roomWithCpuSeats = await transport.ensureQuickTableCpuSeats(room.id);
    _roomRecord = roomWithCpuSeats;
    final waitingWithCpu = _lobbyFromRoom(
      roomWithCpuSeats,
      status: RoomStatus.waiting,
    );
    await transport.store.set(
      _lobbyStatePath(room.id),
      waitingWithCpu.toJson(),
    );
    _setLobby(waitingWithCpu);
    final lobby = await _mutateHostLobby(
      (snapshot) =>
          snapshot.startOpeningRoll(actorParticipantId: localParticipantId),
    );
    await _syncRoomStatus(lobby.status);
    // CPU seats have no device that can press the opening-roll button. The
    // host rolls those seats immediately, while human players still roll on
    // their own phones. This keeps a 2- or 3-player room from waiting for an
    // empty seat and leaves the same authoritative lobby for every client.
    await _rollCpuOpeningSeats(roomWithCpuSeats.id);
  }

  @override
  Future<void> rollOpeningDie() async {
    final room = _requireRoom();
    final opening = _requireLobby().openingRoll;
    if (_lobby?.status != RoomStatus.openingRoll || opening == null) {
      throw const LobbyException(
        LobbyErrorCode.openingRollUnavailable,
        'This room is not accepting opening rolls.',
      );
    }
    if (!opening.eligibleParticipantIds.contains(localParticipantId)) {
      throw LobbyException(
        LobbyErrorCode.participantNotEligible,
        '$localParticipantId is not eligible in this opening-roll round.',
      );
    }
    if (opening.currentRolls.containsKey(localParticipantId)) {
      throw LobbyException(
        LobbyErrorCode.participantAlreadyRolled,
        '$localParticipantId already rolled in this opening-roll round.',
      );
    }
    final now = await transport.store.serverNowMs();
    await transport.store.set(
      '${_openingRequestsPath(room.id)}/$localParticipantId',
      <String, Object?>{
        'uid': localParticipantId,
        'round': opening.round,
        'requestedAt': now,
      },
    );
  }

  @override
  Future<void> markGameStarted() async {
    final lobby = await _mutateHostLobby(
      (snapshot) =>
          snapshot.markGameStarted(actorParticipantId: localParticipantId),
    );
    await _syncRoomStatus(lobby.status);
  }

  Future<void> _attachRoom(OnlineRoomRecord room) async {
    await _detachRoom(clearState: false);
    _ensureActive();
    final epoch = ++_roomEpoch;
    _roomRecord = room;
    _roomMode = _parseMode(room.mode);
    _roomError = null;
    _lastPublishedWaitingFingerprint = null;

    if (room.status == RoomStatus.waiting) {
      final waiting = _lobbyFromRoom(room, status: RoomStatus.waiting);
      _setLobby(waiting);
      if (room.hostUid == localParticipantId) {
        await _publishWaitingLobby(waiting, epoch);
      }
    }

    if (_disposed || epoch != _roomEpoch) return;
    _lobbyStateSubscription = transport.store
        .watch(_lobbyStatePath(room.id))
        .listen(
          (raw) => _acceptLobbyState(raw, epoch),
          onError: (Object error, StackTrace stackTrace) =>
              _acceptRoomError(error, epoch),
        );
    _roomSubscription = transport
        .watchRoom(room.id)
        .listen(
          (snapshot) => _acceptRoomRecord(snapshot, epoch),
          onError: (Object error, StackTrace stackTrace) =>
              _acceptRoomError(error, epoch),
        );

    if (room.hostUid == localParticipantId) {
      _hostRoomLease = await transport.maintainHostedRoom(
        room.id,
        onError: (error, stackTrace) => _acceptRoomError(error, epoch),
      );
      if (_disposed || epoch != _roomEpoch) {
        await _hostRoomLease?.close();
        _hostRoomLease = null;
        return;
      }
      _openingRollRequestsSubscription = transport.store
          .watch(_openingRequestsPath(room.id))
          .listen(
            (_) => _scheduleOpeningRequestDrain(epoch),
            onError: (Object error, StackTrace stackTrace) =>
                _acceptRoomError(error, epoch),
          );
    }
    _notify();
  }

  void _acceptRoomRecord(OnlineRoomRecord? snapshot, int epoch) {
    if (_disposed || epoch != _roomEpoch) return;
    try {
      if (snapshot == null) {
        unawaited(_detachRoom(clearState: true));
        return;
      }
      if (!snapshot.members.containsKey(localParticipantId) &&
          snapshot.status != RoomStatus.closed) {
        unawaited(_detachRoom(clearState: true));
        return;
      }

      _roomRecord = snapshot;
      _roomMode = _parseMode(snapshot.mode);
      _roomError = null;
      if (snapshot.status == RoomStatus.waiting) {
        final waiting = _lobbyFromRoom(snapshot, status: RoomStatus.waiting);
        _setLobby(waiting);
        if (snapshot.hostUid == localParticipantId) {
          scheduleMicrotask(() {
            if (!_disposed && epoch == _roomEpoch) {
              unawaited(_publishWaitingLobby(waiting, epoch));
            }
          });
        }
      } else if (snapshot.status == RoomStatus.closed) {
        final current = _lobby;
        if (current == null || current.roomId != snapshot.id) {
          _setLobby(_lobbyFromRoom(snapshot, status: RoomStatus.closed));
        } else if (current.status != RoomStatus.closed) {
          final json = onlineMap(current.toJson());
          json
            ..['status'] = RoomStatus.closed.name
            ..['revision'] = max(current.revision + 1, snapshot.revision);
          _setLobby(OnlineLobby.fromJson(json));
        }
      }
      _notify();
    } catch (error) {
      _acceptRoomError(error, epoch);
    }
  }

  void _acceptLobbyState(Object? raw, int epoch) {
    if (_disposed || epoch != _roomEpoch || raw == null) return;
    try {
      final snapshot = OnlineLobby.fromJson(onlineMap(raw));
      if (snapshot.roomId != _roomRecord?.id) return;
      _roomError = null;
      _setLobby(snapshot);
    } catch (error) {
      _acceptRoomError(error, epoch);
    }
  }

  Future<void> _publishWaitingLobby(OnlineLobby lobby, int epoch) async {
    if (_disposed ||
        epoch != _roomEpoch ||
        lobby.hostParticipantId != localParticipantId ||
        lobby.status != RoomStatus.waiting) {
      return;
    }
    final json = lobby.toJson();
    final comparison = onlineMap(json)..remove('revision');
    final fingerprint = jsonEncode(comparison);
    if (_lastPublishedWaitingFingerprint == fingerprint) return;
    _lastPublishedWaitingFingerprint = fingerprint;
    try {
      await transport.store.set(_lobbyStatePath(lobby.roomId), json);
    } catch (error) {
      _acceptRoomError(error, epoch);
    }
  }

  OnlineLobby _lobbyFromRoom(
    OnlineRoomRecord room, {
    required RoomStatus status,
  }) {
    final previousRevision = _lobby?.roomId == room.id ? _lobby!.revision : 0;
    return OnlineLobby.fromJson(<String, Object?>{
      'schemaVersion': OnlineLobby.jsonSchemaVersion,
      'roomId': room.id,
      'roomCode': room.code.value,
      'hostParticipantId': room.hostUid,
      'visibility': room.visibility.name,
      if (room.roomName != null) 'roomName': room.roomName,
      'status': status.name,
      'revision': max(room.revision, previousRevision),
      'participants': <Object?>[
        for (final member in _membersBySeat(room))
          member
              .toLobbyParticipant(presence: room.presenceFor(member.uid))
              .copyWith(
                ready:
                    room.presenceFor(member.uid) == LobbyPresence.connected &&
                    member.ready,
              )
              .toJson(),
      ],
      'openingRoll': null,
    });
  }

  Future<OnlineLobby> _mutateHostLobby(
    void Function(OnlineLobby lobby) mutate,
  ) async {
    final room = _requireRoom();
    final fallback = _requireLobby().toJson();
    final result = await transport.store.transaction(_lobbyStatePath(room.id), (
      raw,
    ) {
      final snapshot = OnlineLobby.fromJson(
        raw == null ? onlineMap(fallback) : onlineMap(raw),
      );
      if (snapshot.hostParticipantId != localParticipantId) {
        throw const LobbyException(
          LobbyErrorCode.notHost,
          'Only the room host can change the authoritative lobby.',
        );
      }
      mutate(snapshot);
      return OnlineStoreTransactionDecision.commit(snapshot.toJson());
    });
    final updated = OnlineLobby.fromJson(onlineMap(result.value));
    _setLobby(updated);
    return updated;
  }

  void _scheduleOpeningRequestDrain(int epoch) {
    if (_disposed || epoch != _roomEpoch || _drainingOpeningRollRequests) {
      return;
    }
    _drainingOpeningRollRequests = true;
    unawaited(_drainOpeningRollRequests(epoch));
  }

  Future<void> _drainOpeningRollRequests(int epoch) async {
    try {
      while (!_disposed && epoch == _roomEpoch) {
        final room = _roomRecord;
        if (room == null || room.hostUid != localParticipantId) return;
        final path = _openingRequestsPath(room.id);
        final pending = onlineMap(await transport.store.read(path));
        if (pending.isEmpty) return;
        final requests = pending.entries.toList(growable: false)
          ..sort((left, right) {
            final leftTime = onlineMap(left.value)['requestedAt'];
            final rightTime = onlineMap(right.value)['requestedAt'];
            final byTime = (leftTime is num ? leftTime.toInt() : 0).compareTo(
              rightTime is num ? rightTime.toInt() : 0,
            );
            return byTime != 0 ? byTime : left.key.compareTo(right.key);
          });
        for (final request in requests) {
          if (_disposed || epoch != _roomEpoch) return;
          await _processOpeningRollRequest(
            roomId: room.id,
            uid: request.key,
            rawRequest: request.value,
          );
        }
      }
    } catch (error) {
      _acceptRoomError(error, epoch);
    } finally {
      _drainingOpeningRollRequests = false;
      if (!_disposed && epoch == _roomEpoch) {
        final room = _roomRecord;
        if (room != null) {
          try {
            final pending = onlineMap(
              await transport.store.read(_openingRequestsPath(room.id)),
            );
            if (pending.isNotEmpty) _scheduleOpeningRequestDrain(epoch);
          } catch (error) {
            _acceptRoomError(error, epoch);
          }
        }
      }
    }
  }

  Future<void> _processOpeningRollRequest({
    required String roomId,
    required String uid,
    required Object? rawRequest,
  }) async {
    final request = onlineMap(rawRequest);
    final requestedUid = request['uid'];
    final requestedRound = request['round'];
    final requestPath = '${_openingRequestsPath(roomId)}/$uid';
    final currentRaw = await transport.store.read(_lobbyStatePath(roomId));
    if (requestedUid != uid || requestedRound is! num || currentRaw == null) {
      await transport.store.set(requestPath, null);
      return;
    }
    final current = OnlineLobby.fromJson(onlineMap(currentRaw));
    final opening = current.openingRoll;
    if (current.status != RoomStatus.openingRoll ||
        opening == null ||
        requestedRound.toInt() != opening.round ||
        !opening.eligibleParticipantIds.contains(uid) ||
        opening.currentRolls.containsKey(uid)) {
      await transport.store.set(requestPath, null);
      return;
    }

    // Generate once outside the retryable transaction. Every transaction retry
    // receives the same host-generated value.
    final generatedValue = _openingRollRandom.nextInt(6) + 1;
    final result = await transport.store.transaction(_lobbyStatePath(roomId), (
      raw,
    ) {
      if (raw == null) return const OnlineStoreTransactionDecision.abort();
      final lobby = OnlineLobby.fromJson(onlineMap(raw));
      final state = lobby.openingRoll;
      if (lobby.status != RoomStatus.openingRoll ||
          state == null ||
          state.round != requestedRound.toInt() ||
          !state.eligibleParticipantIds.contains(uid) ||
          state.currentRolls.containsKey(uid)) {
        return const OnlineStoreTransactionDecision.abort();
      }
      lobby.rollOpeningDie(
        actorParticipantId: uid,
        random: _FixedOpeningRollRandom(generatedValue),
      );
      return OnlineStoreTransactionDecision.commit(lobby.toJson());
    });
    if (result.committed) {
      final updated = OnlineLobby.fromJson(onlineMap(result.value));
      _setLobby(updated);
      if (updated.status == RoomStatus.starting) {
        await _syncRoomStatus(RoomStatus.starting);
      } else {
        // A human roll can resolve a tie that promotes a CPU seat into the
        // next opening-roll round. Keep the CPU participant moving without
        // asking an empty seat to interact with the UI.
        await _rollCpuOpeningSeats(roomId);
      }
    }
    await transport.store.set(requestPath, null);
  }

  Future<void> _rollCpuOpeningSeats(String roomId) async {
    final epoch = _roomEpoch;
    while (!_disposed && epoch == _roomEpoch) {
      final raw = await transport.store.read(_lobbyStatePath(roomId));
      if (raw == null) return;
      final current = OnlineLobby.fromJson(onlineMap(raw));
      final opening = current.openingRoll;
      if (current.status != RoomStatus.openingRoll || opening == null) return;

      String? cpuParticipantId;
      for (final participantId in opening.eligibleParticipantIds) {
        if (participantId.startsWith('cpu_') &&
            !opening.currentRolls.containsKey(participantId)) {
          cpuParticipantId = participantId;
          break;
        }
      }
      if (cpuParticipantId == null) return;

      // Generate once outside the transaction so retries cannot change the
      // visible result for a CPU seat.
      final generatedValue = _openingRollRandom.nextInt(6) + 1;
      final result = await transport.store.transaction(
        _lobbyStatePath(roomId),
        (transactionRaw) {
          if (transactionRaw == null) {
            return const OnlineStoreTransactionDecision.abort();
          }
          final lobby = OnlineLobby.fromJson(onlineMap(transactionRaw));
          final state = lobby.openingRoll;
          if (lobby.status != RoomStatus.openingRoll ||
              state == null ||
              !state.eligibleParticipantIds.contains(cpuParticipantId) ||
              state.currentRolls.containsKey(cpuParticipantId)) {
            return const OnlineStoreTransactionDecision.abort();
          }
          lobby.rollOpeningDie(
            actorParticipantId: cpuParticipantId!,
            random: _FixedOpeningRollRandom(generatedValue),
          );
          return OnlineStoreTransactionDecision.commit(lobby.toJson());
        },
      );
      if (!result.committed) continue;

      final updated = OnlineLobby.fromJson(onlineMap(result.value));
      _setLobby(updated);
      if (updated.status == RoomStatus.starting) {
        await _syncRoomStatus(RoomStatus.starting);
        return;
      }
    }
  }

  Future<void> _syncRoomStatus(RoomStatus status) async {
    final room = _requireRoom();
    if (room.hostUid != localParticipantId) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.notHost,
        'Only the host can update room lifecycle state.',
      );
    }
    if (room.status == status) return;
    final now = await transport.store.serverNowMs();
    final result = await transport.store.transaction('$_roomsPath/${room.id}', (
      raw,
    ) {
      if (raw == null) {
        throw const OnlineTransportException(
          OnlineTransportErrorCode.roomNotFound,
          'The room no longer exists.',
        );
      }
      final current = OnlineRoomRecord.fromJson(raw);
      if (current.hostUid != localParticipantId) {
        throw const OnlineTransportException(
          OnlineTransportErrorCode.notHost,
          'Only the host can update room lifecycle state.',
        );
      }
      final map = onlineMap(raw);
      map
        ..['status'] = status.name
        ..['revision'] = current.revision + 1
        ..['updatedAt'] = now;
      return OnlineStoreTransactionDecision.commit(map);
    });
    _roomRecord = OnlineRoomRecord.fromJson(result.value);
    if (status != RoomStatus.waiting) {
      await transport.store.set(
        '$onlineTransportRoot/publicRooms/${room.id}',
        null,
      );
    }
    _notify();
  }

  void _setLobby(OnlineLobby snapshot) {
    if (_disposed) return;
    _lobby = snapshot;
    if (!_lobbySnapshots.isClosed) _lobbySnapshots.add(snapshot);
    if (snapshot.status == RoomStatus.inGame &&
        _announcedInGameRooms.add(snapshot.roomId)) {
      if (!_gameReadySnapshots.isClosed) _gameReadySnapshots.add(snapshot);
      onGameReady?.call(snapshot);
    }
    _notify();
  }

  void _acceptRoomError(Object error, int epoch) {
    if (_disposed || epoch != _roomEpoch) return;
    _roomError = error.toString();
    _notify();
  }

  OnlineRoomRecord _requireRoom() {
    _ensureActive();
    final room = _roomRecord;
    if (room == null) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.roomNotFound,
        'No online room is currently attached.',
      );
    }
    return room;
  }

  OnlineLobby _requireLobby() {
    _ensureActive();
    final current = _lobby;
    if (current == null) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.roomNotFound,
        'No online lobby snapshot is available.',
      );
    }
    return current;
  }

  OnlineLobby _cloneLobby(OnlineLobby source) =>
      OnlineLobby.fromJson(onlineMap(source.toJson()));

  Future<void> _detachRoom({required bool clearState}) async {
    _roomEpoch++;
    _drainingOpeningRollRequests = false;
    final roomSubscription = _roomSubscription;
    final lobbySubscription = _lobbyStateSubscription;
    final openingSubscription = _openingRollRequestsSubscription;
    final hostLease = _hostRoomLease;
    _roomSubscription = null;
    _lobbyStateSubscription = null;
    _openingRollRequestsSubscription = null;
    _hostRoomLease = null;
    await roomSubscription?.cancel();
    await lobbySubscription?.cancel();
    await openingSubscription?.cancel();
    await hostLease?.close();
    _lastPublishedWaitingFingerprint = null;
    if (clearState) {
      _lobby = null;
      _roomRecord = null;
      _roomMode = null;
      _roomError = null;
      _notify();
    }
  }

  /// Cancels realtime work deterministically before widget disposal or tests.
  Future<void> shutdown() async {
    if (_disposed) return;
    _createAttempt++;
    _joinAttempt++;
    final pendingJoin = _pendingJoinRequest;
    _pendingJoinRequest = null;
    if (pendingJoin != null) {
      await transport.cancelRoomJoinRequest(pendingJoin);
    }
    await _detachRoom(clearState: true);
    await _publicRoomsSubscription?.cancel();
    _publicRoomsSubscription = null;
  }

  List<PublicRoomSummary> _summaries(
    Iterable<PublicOnlineRoomRecord> records,
  ) => List<PublicRoomSummary>.unmodifiable(
    records.where((record) => record.matchFormat == 'quickTable').map((record) {
      final mode = _tryParseMode(record.mode);
      if (mode == null) return null;
      return PublicRoomSummary(
        roomId: record.roomId,
        roomCode: record.code,
        hostDisplayName: record.hostDisplayName,
        mode: mode,
        occupiedSeats: record.occupiedSeatCount,
        roomName: record.roomName,
      );
    }).whereType<PublicRoomSummary>(),
  );

  OnlineRoomGameMode _parseMode(String raw) =>
      _tryParseMode(raw) ?? OnlineRoomGameMode.classic;

  OnlineRoomGameMode? _tryParseMode(String raw) {
    for (final mode in OnlineRoomGameMode.values) {
      if (mode.name == raw) return mode;
    }
    return null;
  }

  List<OnlineRoomMemberRecord> _membersBySeat(OnlineRoomRecord room) {
    final members = room.members.values.toList(growable: false);
    members.sort((left, right) => left.seat.index.compareTo(right.seat.index));
    return members;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _ensureActive() {
    if (_disposed) throw StateError('The online room controller is disposed.');
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _createAttempt++;
    _joinAttempt++;
    final pendingJoin = _pendingJoinRequest;
    _pendingJoinRequest = null;
    if (pendingJoin != null) {
      unawaited(transport.cancelRoomJoinRequest(pendingJoin));
    }
    unawaited(_roomSubscription?.cancel());
    unawaited(_lobbyStateSubscription?.cancel());
    unawaited(_openingRollRequestsSubscription?.cancel());
    unawaited(_publicRoomsSubscription?.cancel());
    unawaited(_hostRoomLease?.close());
    unawaited(_lobbySnapshots.close());
    unawaited(_gameReadySnapshots.close());
    super.dispose();
  }
}

final class _FixedOpeningRollRandom implements Random {
  const _FixedOpeningRollRandom(this.value);

  final int value;

  @override
  int nextInt(int max) {
    if (max <= 0) throw RangeError.range(max, 1, null, 'max');
    return (value - 1) % max;
  }

  @override
  bool nextBool() => nextInt(2) == 1;

  @override
  double nextDouble() => (value - 1) / 6;
}
