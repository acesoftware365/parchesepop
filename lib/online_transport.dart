import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'online_lobby.dart';
import 'online_transport_models.dart';

sealed class OnlineStoreTransactionDecision {
  const OnlineStoreTransactionDecision();

  const factory OnlineStoreTransactionDecision.commit(Object? value) =
      OnlineStoreCommit;
  const factory OnlineStoreTransactionDecision.abort() = OnlineStoreAbort;
}

final class OnlineStoreCommit extends OnlineStoreTransactionDecision {
  const OnlineStoreCommit(this.value);

  final Object? value;
}

final class OnlineStoreAbort extends OnlineStoreTransactionDecision {
  const OnlineStoreAbort();
}

final class OnlineStoreTransactionResult {
  const OnlineStoreTransactionResult({
    required this.committed,
    required this.value,
  });

  final bool committed;
  final Object? value;
}

typedef OnlineStoreTransactionUpdater =
    OnlineStoreTransactionDecision Function(Object? currentValue);

/// Minimal realtime storage boundary used by Firebase and deterministic tests.
abstract interface class OnlineRealtimeStore {
  Future<Object?> read(String path);

  Stream<Object?> watch(String path);

  Future<void> set(String path, Object? value);

  Future<void> update(String path, Map<String, Object?> values);

  Future<OnlineStoreTransactionResult> transaction(
    String path,
    OnlineStoreTransactionUpdater updater,
  );

  Future<void> setOnDisconnect(String path, Object? value);

  Future<void> cancelOnDisconnect(String path);

  Future<int> serverNowMs();
}

/// Optional ordered-query boundary used by the production Firebase adapter.
///
/// In-memory stores intentionally keep the minimal API above. Firebase uses
/// this capability so Security Rules can enforce that Quick Pop downloads only
/// active queue entries instead of treating rules as post-download filters.
abstract interface class OnlineRealtimeQueryStore {
  Future<Object?> readOrderedChildren(
    String path, {
    required String orderByChild,
    required num startAt,
    required int limitToFirst,
  });
}

/// Production adapters may need to defer exact opponent reads until the
/// deterministic claim root exists. Firebase rules use the claim metadata to
/// authorize that read; deterministic in-memory stores can continue to read
/// both ticket records while exercising the same transport logic.
abstract interface class OnlineRealtimeExactReadPolicy {
  bool get opponentTicketExactReadRequiresClaim;
}

/// Optional lifecycle implemented by realtime adapters that own sockets or
/// subscriptions. Account deletion uses it to stop every authenticated
/// listener before the Firebase identity disappears.
abstract interface class OnlineRealtimeStoreLifecycle {
  Future<void> shutdown();
}

enum OnlineTransportErrorCode {
  invalidIdentity,
  invalidPathSegment,
  roomCodeUnavailable,
  roomNotFound,
  roomClosed,
  roomFull,
  duplicateSeat,
  unknownParticipant,
  notHost,
  invalidRoomStatus,
  joinTimedOut,
  joinCancelled,
  invalidQueueTicket,
}

final class OnlineTransportException implements Exception {
  const OnlineTransportException(this.code, this.message);

  final OnlineTransportErrorCode code;
  final String message;

  @override
  String toString() => 'OnlineTransportException(${code.name}): $message';
}

final class OnlineTransportIdentity {
  OnlineTransportIdentity({
    required String uid,
    required String displayName,
    String? avatarId,
  }) : uid = _validatedSegment(uid, 'uid'),
       displayName = _validatedDisplayName(displayName),
       avatarId = _cleanOptional(avatarId);

  final String uid;
  final String displayName;
  final String? avatarId;
}

typedef OnlineDelay = Future<void> Function(Duration duration);
typedef OnlineRoomCodeFactory = RoomCode Function(Random random);

/// Durable, private resource index used to finish account deletion after an
/// app restart. The Firebase path is:
/// `onlineV2/accountResources/{uid}`.
const String onlineAccountResourcesNode = 'accountResources';
const int onlineAccountResourcesSchemaVersion = 1;

final class OnlinePresenceLease {
  OnlinePresenceLease._({
    required OnlineRealtimeStore store,
    required this.roomId,
    required this.uid,
    required this.connectionId,
    required String path,
  }) : _store = store,
       _path = path;

  final OnlineRealtimeStore _store;
  final String _path;
  final String roomId;
  final String uid;
  final String connectionId;
  bool _closed = false;

  bool get closed => _closed;

  Future<void> disconnect() async {
    if (_closed) return;
    _closed = true;
    await _store.cancelOnDisconnect(_path);
    final now = await _store.serverNowMs();
    await _store.set(
      _path,
      OnlinePresenceRecord(
        uid: uid,
        presence: LobbyPresence.disconnected,
        changedAtMs: now,
        connectionId: connectionId,
      ).toJson(),
    );
  }

  /// Cancels the server-side disconnect hook without writing a new presence
  /// record. This is used when a room was already removed concurrently.
  Future<void> cancel() async {
    if (_closed) return;
    _closed = true;
    await _store.cancelOnDisconnect(_path);
  }
}

final class OnlineHostRoomLease {
  const OnlineHostRoomLease._(this._subscriptions);

  final List<StreamSubscription<Object?>> _subscriptions;

  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}

/// Auditable summary of the client-owned realtime data removed before an
/// anonymous Firebase identity is deleted.
final class OnlineAccountCleanupReport {
  const OnlineAccountCleanupReport({
    required this.profileRemoved,
    required this.queueTicketsRemoved,
    required this.pendingJoinsRemoved,
    required this.waitingMembershipsRemoved,
    required this.roomsClosed,
    required this.presencesDisconnected,
    required this.resolvedTicketsPreserved,
    required this.resourceIndexRemoved,
  });

  final bool profileRemoved;
  final int queueTicketsRemoved;
  final int pendingJoinsRemoved;
  final int waitingMembershipsRemoved;
  final int roomsClosed;
  final int presencesDisconnected;

  /// Matched/CPU tickets are retained because they belong to an already
  /// resolved match and cannot be removed without a server retention policy.
  final int resolvedTicketsPreserved;
  final bool resourceIndexRemoved;
}

/// Signals that a pre-index or inconsistent account must be cleaned by a
/// trusted backend before its Firebase Auth identity can be removed safely.
final class OnlineAccountCleanupRequiresBackend implements Exception {
  const OnlineAccountCleanupRequiresBackend();
}

/// Transport-level room, profile, presence, and Quick Pop orchestration.
///
/// Match commands and dice remain outside this client. They must continue to be
/// accepted only by the trusted [OnlineAuthorityGateway] implementation.
final class OnlineTransportClient {
  OnlineTransportClient({
    required this.store,
    required this.identity,
    Random? random,
    OnlineDelay? delay,
    OnlineRoomCodeFactory? roomCodeFactory,
  }) : _random = random ?? Random.secure(),
       _delay = delay ?? Future<void>.delayed,
       _roomCodeFactory = roomCodeFactory ?? RoomCode.generate;

  static const int _maximumRoomCodeAttempts = 32;
  static const Duration _roomReservationLifetime = Duration(minutes: 2);
  static const Duration _quickClaimHandshakeGrace = Duration(milliseconds: 250);
  static const Duration _quickServerDeadlineRetry = Duration(milliseconds: 250);
  static const int _quickQueueReadLimit = 64;

  final OnlineRealtimeStore store;
  final OnlineTransportIdentity identity;
  final Random _random;
  final OnlineDelay _delay;
  final OnlineRoomCodeFactory _roomCodeFactory;
  final Map<String, OnlinePresenceLease> _presenceLeases = {};
  final Map<String, OnlineRoomJoinRequestRecord> _pendingJoinRequests = {};
  final Map<String, QuickPopQueueTicket> _ownedQuickTickets = {};

  static const Set<String> _knownQuickQueueKeys = <String>{
    'traditional_quickPop',
    'chaos_quickPop',
  };

  String get _profilesPath => '$onlineTransportRoot/profiles';
  String get _roomsPath => '$onlineTransportRoot/rooms';
  String get _roomCodesPath => '$onlineTransportRoot/roomCodes';
  String get _publicRoomsPath => '$onlineTransportRoot/publicRooms';
  String get _joinRequestsPath => '$onlineTransportRoot/joinRequests';
  String get _quickQueuesPath => '$onlineTransportRoot/quickQueues';
  String get _quickClaimsPath => '$onlineTransportRoot/quickClaims';
  String get _accountResourcesPath =>
      '$onlineTransportRoot/$onlineAccountResourcesNode/${identity.uid}';

  Future<SyncedOnlineProfile> syncProfile() async {
    final now = await store.serverNowMs();
    final path = '$_profilesPath/${identity.uid}';
    final existing = onlineMap(await store.read(path));
    final existingResources = onlineMap(
      await store.read(_accountResourcesPath),
    );
    final existingCreatedAt = existing['createdAt'];
    final profile = SyncedOnlineProfile(
      uid: identity.uid,
      displayName: identity.displayName,
      avatarId: identity.avatarId,
      createdAtMs: existingCreatedAt is num ? existingCreatedAt.toInt() : now,
      updatedAtMs: now,
    );
    final needsBackendCleanup =
        existingResources['requiresBackendCleanup'] == true ||
        (existing.isNotEmpty && existingResources.isEmpty);
    await store.update(onlineTransportRoot, <String, Object?>{
      'profiles/${identity.uid}': profile.toJson(),
      '$onlineAccountResourcesNode/${identity.uid}/schemaVersion':
          onlineAccountResourcesSchemaVersion,
      '$onlineAccountResourcesNode/${identity.uid}/updatedAt': now,
      '$onlineAccountResourcesNode/${identity.uid}/requiresBackendCleanup':
          needsBackendCleanup,
    });
    return profile;
  }

  Stream<SyncedOnlineProfile?> watchProfile(String uid) {
    final cleanUid = _validatedSegment(uid, 'uid');
    return store.watch('$_profilesPath/$cleanUid').map((raw) {
      if (raw == null) return null;
      return SyncedOnlineProfile.fromJson(raw, uid: cleanUid);
    });
  }

  Future<void> _updateAccountResources(
    Map<String, Object?> updates, {
    int? nowMs,
  }) async {
    final now = nowMs ?? await store.serverNowMs();
    await store.update(_accountResourcesPath, <String, Object?>{
      'schemaVersion': onlineAccountResourcesSchemaVersion,
      'updatedAt': now,
      ...updates,
    });
  }

  Map<String, Object?> _accountResourceRootUpdates(
    Map<String, Object?> updates, {
    required int nowMs,
  }) => <String, Object?>{
    '$onlineAccountResourcesNode/${identity.uid}/schemaVersion':
        onlineAccountResourcesSchemaVersion,
    '$onlineAccountResourcesNode/${identity.uid}/updatedAt': nowMs,
    for (final entry in updates.entries)
      '$onlineAccountResourcesNode/${identity.uid}/${entry.key}': entry.value,
  };

  Future<void> _indexRoom(OnlineRoomRecord room, {int? nowMs}) async {
    final now = nowMs ?? await store.serverNowMs();
    await _updateAccountResources(<String, Object?>{
      'rooms/${room.id}': <String, Object?>{
        'roomId': room.id,
        'role': room.hostUid == identity.uid ? 'host' : 'member',
        'indexedAt': now,
      },
      'presence/${room.id}': <String, Object?>{
        'roomId': room.id,
        'indexedAt': now,
      },
      'hostedRooms/${room.id}': room.hostUid == identity.uid
          ? <String, Object?>{'roomId': room.id, 'indexedAt': now}
          : null,
    }, nowMs: now);
  }

  Future<OnlineRoomRecord> createRoom({
    required RoomVisibility visibility,
    required String mode,
    required String matchFormat,
  }) async {
    final cleanMode = _validatedSegment(mode, 'mode');
    final cleanFormat = _validatedSegment(matchFormat, 'matchFormat');
    final now = await store.serverNowMs();
    final roomId = _stableId(
      'room|${identity.uid}|$now|${_random.nextInt(0x7fffffff)}',
      prefix: 'r_',
    );
    final reservation = await _reserveRoomCode(roomId: roomId, nowMs: now);
    final code = reservation.code;
    final connectionId = _newConnectionId(roomId, now);
    final room = OnlineRoomRecord(
      id: roomId,
      code: code,
      hostUid: identity.uid,
      visibility: visibility,
      status: RoomStatus.waiting,
      mode: cleanMode,
      matchFormat: cleanFormat,
      members: <String, OnlineRoomMemberRecord>{
        identity.uid: OnlineRoomMemberRecord(
          uid: identity.uid,
          displayName: identity.displayName,
          seat: LobbySeatColor.red,
          joinedAtMs: now,
        ),
      },
      presence: <String, OnlinePresenceRecord>{
        identity.uid: OnlinePresenceRecord(
          uid: identity.uid,
          presence: LobbyPresence.connected,
          changedAtMs: now,
          connectionId: connectionId,
        ),
      },
      revision: 0,
      createdAtMs: now,
      updatedAtMs: now,
    );

    try {
      await store.update(onlineTransportRoot, <String, Object?>{
        'rooms/$roomId': <String, Object?>{
          ...room.toJson(),
          'creationState': 'initializing',
        },
        ..._accountResourceRootUpdates(<String, Object?>{
          'rooms/$roomId': <String, Object?>{
            'roomId': roomId,
            'role': 'host',
            'indexedAt': now,
          },
          'presence/$roomId': <String, Object?>{
            'roomId': roomId,
            'indexedAt': now,
          },
          'hostedRooms/$roomId': <String, Object?>{
            'roomId': roomId,
            'indexedAt': now,
          },
        }, nowMs: now),
      });
      await _connectRoomPresence(
        roomId: roomId,
        nowMs: now,
        connectionId: connectionId,
      );
      // A room is not joinable or discoverable until its host presence is
      // fully armed. This removes the publication window in which a guest
      // could target a room whose creator is about to fail.
      await _activateRoomCode(reservation);
      await _syncPublicRoom(room);
      await store.set('$_roomsPath/$roomId/creationState', 'ready');
      return room;
    } catch (error, stackTrace) {
      await _rollbackFailedRoomCreation(
        roomId: roomId,
        reservation: reservation,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Requests admission without writing another player's room aggregate.
  ///
  /// The host admits requests with [admitPendingJoinRequests], which assigns a
  /// unique seat in one host-authorized room transaction. This mirrors the
  /// narrow Firebase rules: guests own only their request, member, and presence
  /// paths; they never transact the room root.
  Future<OnlineRoomJoinRequestRecord> requestRoomJoinByCode(
    String rawCode,
  ) async {
    final code = RoomCode.parse(rawCode);
    final pointer = onlineMap(
      await store.read('$_roomCodesPath/${code.value}'),
    );
    final roomId = pointer['roomId'];
    if (roomId is! String || roomId.isEmpty || pointer['state'] != 'active') {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.roomNotFound,
        'The room code is not active.',
      );
    }
    final room = await readRoom(roomId);
    if (room == null) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.roomNotFound,
        'The room no longer exists.',
      );
    }
    if (room.status == RoomStatus.closed) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.roomClosed,
        'The room is closed.',
      );
    }
    if (room.status != RoomStatus.waiting) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.invalidRoomStatus,
        'Only waiting rooms accept new players.',
      );
    }
    if (!room.members.containsKey(identity.uid) &&
        room.members.length >= LobbySeatColor.values.length) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.roomFull,
        'All four room seats are occupied.',
      );
    }
    final now = await store.serverNowMs();
    final request = OnlineRoomJoinRequestRecord(
      roomId: roomId,
      roomCode: code,
      uid: identity.uid,
      displayName: identity.displayName,
      attemptId: _stableId(
        'join|$roomId|${identity.uid}|$now|${_random.nextInt(0x7fffffff)}',
        prefix: 'join_',
      ),
      requestedAtMs: now,
    );
    final fencePath = _joinFencePath(request);
    await store.set(fencePath, _joinFenceJson(request));
    try {
      await store.update(onlineTransportRoot, <String, Object?>{
        'joinRequests/$roomId/${identity.uid}': request.toJson(),
        ..._accountResourceRootUpdates(<String, Object?>{
          'joinRequests/$roomId': request.toJson(),
        }, nowMs: now),
      });
    } catch (error, stackTrace) {
      try {
        await _removeJoinFenceIfMatching(request);
      } catch (_) {
        // Preserve the publication failure. A fence without a matching
        // top-level request is inert and can be replaced by the next attempt.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    _pendingJoinRequests[roomId] = request;
    return request;
  }

  Stream<List<OnlineRoomJoinRequestRecord>> watchJoinRequests(String roomId) {
    final cleanRoomId = _validatedSegment(roomId, 'roomId');
    return store.watch('$_joinRequestsPath/$cleanRoomId').map((raw) {
      final requests = <OnlineRoomJoinRequestRecord>[];
      for (final entry in onlineMap(raw).entries) {
        try {
          requests.add(
            OnlineRoomJoinRequestRecord.fromJson(entry.value, uid: entry.key),
          );
        } on FormatException {
          // The host ignores malformed requests instead of admitting them.
        }
      }
      requests.sort((left, right) {
        final byTime = left.requestedAtMs.compareTo(right.requestedAtMs);
        return byTime != 0 ? byTime : left.uid.compareTo(right.uid);
      });
      return requests;
    });
  }

  /// Keeps host-only admission and the denormalized public index current.
  Future<OnlineHostRoomLease> maintainHostedRoom(
    String roomId, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    final cleanRoomId = _validatedSegment(roomId, 'roomId');
    final room = await readRoom(cleanRoomId);
    if (room == null) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.roomNotFound,
        'The room no longer exists.',
      );
    }
    _requireHost(room);

    Future<void> reportable(Future<void> Function() operation) async {
      try {
        await operation();
      } catch (error, stackTrace) {
        if (onError != null) {
          onError(error, stackTrace);
        } else {
          Zone.current.handleUncaughtError(error, stackTrace);
        }
      }
    }

    final roomSubscription = watchRoom(cleanRoomId).listen((snapshot) {
      if (snapshot == null) return;
      unawaited(reportable(() => _syncPublicRoom(snapshot)));
    });
    final requestSubscription = watchJoinRequests(cleanRoomId).listen((
      requests,
    ) {
      if (requests.isEmpty) return;
      unawaited(
        reportable(() async {
          await admitPendingJoinRequests(cleanRoomId);
        }),
      );
    });
    return OnlineHostRoomLease._(<StreamSubscription<Object?>>[
      roomSubscription,
      requestSubscription,
    ]);
  }

  /// Host-only admission serializes seat allocation at the room root.
  Future<OnlineRoomRecord> admitPendingJoinRequests(String roomId) async {
    final cleanRoomId = _validatedSegment(roomId, 'roomId');
    final current = await readRoom(cleanRoomId);
    if (current == null) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.roomNotFound,
        'The room no longer exists.',
      );
    }
    _requireHost(current);
    final requestsRaw = onlineMap(
      await store.read('$_joinRequestsPath/$cleanRoomId'),
    );
    final requests = <OnlineRoomJoinRequestRecord>[];
    for (final entry in requestsRaw.entries) {
      try {
        final request = OnlineRoomJoinRequestRecord.fromJson(
          entry.value,
          uid: entry.key,
        );
        if (request.roomId == cleanRoomId && request.roomCode == current.code) {
          requests.add(request);
        }
      } on FormatException {
        // Invalid requests are never admitted.
      }
    }
    requests.sort((left, right) {
      final byTime = left.requestedAtMs.compareTo(right.requestedAtMs);
      return byTime != 0 ? byTime : left.uid.compareTo(right.uid);
    });
    final now = await store.serverNowMs();
    final result = await store.transaction('$_roomsPath/$cleanRoomId', (raw) {
      if (raw == null) {
        throw const OnlineTransportException(
          OnlineTransportErrorCode.roomNotFound,
          'The room no longer exists.',
        );
      }
      final room = OnlineRoomRecord.fromJson(raw);
      _requireHost(room);
      if (room.status != RoomStatus.waiting) {
        throw const OnlineTransportException(
          OnlineTransportErrorCode.invalidRoomStatus,
          'Only a waiting room can admit players.',
        );
      }
      // Preserve nested realtime children owned by the lobby and match
      // synchronizers (lobbyState, openingRollRequests, commands, match, ...).
      // Rebuilding from OnlineRoomRecord.toJson would silently delete them in
      // a room-root transaction.
      final map = onlineMap(raw);
      final members = onlineMap(map['members']);
      final joinFences = onlineMap(map['joinFences']);
      final occupied = room.members.values.map((member) => member.seat).toSet();
      var admitted = 0;
      for (final request in requests) {
        // The room-local fence participates in this room-root transaction.
        // Cancelling it at the child path forces Firebase to rerun this
        // updater and makes a stale request snapshot inadmissible.
        if (!_joinFenceMatches(joinFences[request.uid], request)) continue;
        if (members.containsKey(request.uid)) continue;
        if (members.length >= LobbySeatColor.values.length) break;
        final seat = LobbySeatColor.values.firstWhere(
          (candidate) => !occupied.contains(candidate),
          orElse: () => throw const OnlineTransportException(
            OnlineTransportErrorCode.duplicateSeat,
            'The room does not contain a free clockwise seat.',
          ),
        );
        occupied.add(seat);
        members[request.uid] = OnlineRoomMemberRecord(
          uid: request.uid,
          displayName: request.displayName,
          seat: seat,
          joinedAtMs: request.requestedAtMs,
        ).toJson();
        admitted++;
      }
      if (admitted == 0) return OnlineStoreTransactionDecision.abort();
      map['members'] = members;
      map['revision'] = room.revision + 1;
      map['updatedAt'] = now;
      return OnlineStoreTransactionDecision.commit(map);
    });
    var admittedRoom = OnlineRoomRecord.fromJson(result.value);
    for (final request in requests) {
      final member = admittedRoom.members[request.uid];
      if (!_memberMatchesJoinRequest(member, request)) continue;
      final fence = await store.read(_joinFencePath(request));
      final liveRequest = await store.read(
        '$_joinRequestsPath/$cleanRoomId/${request.uid}',
      );
      if (!_joinFenceMatches(fence, request) ||
          !_joinRequestMatches(liveRequest, request)) {
        // Defense in depth for stores that do not implement Firebase's
        // parent/child transaction retry semantics. Production Firebase
        // already linearizes the fence deletion against the transaction.
        admittedRoom = await _removeCancelledAdmissionAsHost(
          admittedRoom,
          request,
        );
      }
      await _removeTopLevelJoinRequestIfMatching(request);
    }
    admittedRoom = (await readRoom(cleanRoomId)) ?? admittedRoom;
    await _syncPublicRoom(admittedRoom);
    return admittedRoom;
  }

  Future<OnlineRoomRecord> waitForRoomAdmission(
    OnlineRoomJoinRequestRecord request, {
    Duration timeout = const Duration(seconds: 15),
    Duration pollInterval = const Duration(milliseconds: 150),
    bool Function()? cancelled,
  }) async {
    final startedAt = await store.serverNowMs();
    final expiresAt = startedAt + timeout.inMilliseconds;
    while (true) {
      if (cancelled?.call() ?? false) {
        await cancelRoomJoinRequest(request);
        throw const OnlineTransportException(
          OnlineTransportErrorCode.joinCancelled,
          'The room join was cancelled.',
        );
      }
      final room = await readRoom(request.roomId);
      if (room == null || room.status == RoomStatus.closed) {
        await _discardJoinRequest(request);
        throw const OnlineTransportException(
          OnlineTransportErrorCode.roomClosed,
          'The room closed before admission.',
        );
      }
      if (room.members.containsKey(identity.uid)) {
        if (cancelled?.call() ?? false) {
          await cancelRoomJoinRequest(request);
          throw const OnlineTransportException(
            OnlineTransportErrorCode.joinCancelled,
            'The room join was cancelled.',
          );
        }
        final now = await store.serverNowMs();
        await _connectRoomPresence(
          roomId: room.id,
          nowMs: now,
          connectionId: _newConnectionId(room.id, now),
        );
        await _updateAccountResources(<String, Object?>{
          'rooms/${room.id}': <String, Object?>{
            'roomId': room.id,
            'role': room.hostUid == identity.uid ? 'host' : 'member',
            'indexedAt': now,
          },
          'presence/${room.id}': <String, Object?>{
            'roomId': room.id,
            'indexedAt': now,
          },
          'hostedRooms/${room.id}': room.hostUid == identity.uid
              ? <String, Object?>{'roomId': room.id, 'indexedAt': now}
              : null,
        }, nowMs: now);
        await _finishSuccessfulJoin(request);
        _pendingJoinRequests.remove(request.roomId);
        return (await readRoom(room.id))!;
      }
      final now = await store.serverNowMs();
      if (now >= expiresAt) {
        await _discardJoinRequest(request);
        throw const OnlineTransportException(
          OnlineTransportErrorCode.joinTimedOut,
          'The host did not admit this player before the request expired.',
        );
      }
      await _delay(
        Duration(
          milliseconds: min(pollInterval.inMilliseconds, expiresAt - now),
        ),
      );
    }
  }

  String _joinFencePath(OnlineRoomJoinRequestRecord request) =>
      '$_roomsPath/${request.roomId}/joinFences/${request.uid}';

  Map<String, Object?> _joinFenceJson(OnlineRoomJoinRequestRecord request) =>
      <String, Object?>{
        'uid': request.uid,
        'attemptId': request.attemptId,
        'requestedAt': request.requestedAtMs,
      };

  bool _joinFenceMatches(Object? raw, OnlineRoomJoinRequestRecord request) {
    final fence = onlineMap(raw);
    return fence['uid'] == request.uid &&
        fence['attemptId'] == request.attemptId &&
        fence['requestedAt'] == request.requestedAtMs;
  }

  bool _joinRequestMatches(Object? raw, OnlineRoomJoinRequestRecord request) {
    if (raw == null) return false;
    try {
      final current = OnlineRoomJoinRequestRecord.fromJson(
        raw,
        uid: request.uid,
      );
      return current.roomId == request.roomId &&
          current.roomCode == request.roomCode &&
          current.attemptId == request.attemptId &&
          current.requestedAtMs == request.requestedAtMs;
    } on FormatException {
      return false;
    }
  }

  bool _memberMatchesJoinRequest(
    OnlineRoomMemberRecord? member,
    OnlineRoomJoinRequestRecord request,
  ) =>
      member != null &&
      member.uid == request.uid &&
      member.displayName == request.displayName &&
      member.joinedAtMs == request.requestedAtMs;

  Future<_JoinFenceRemoval> _removeJoinFenceIfMatching(
    OnlineRoomJoinRequestRecord request,
  ) async {
    final result = await store.transaction(_joinFencePath(request), (raw) {
      if (raw == null) return const OnlineStoreTransactionDecision.abort();
      if (!_joinFenceMatches(raw, request)) {
        return const OnlineStoreTransactionDecision.abort();
      }
      return const OnlineStoreTransactionDecision.commit(null);
    });
    if (result.committed) return _JoinFenceRemoval.removed;
    return result.value == null
        ? _JoinFenceRemoval.absent
        : _JoinFenceRemoval.mismatched;
  }

  Future<void> _removeTopLevelJoinRequestIfMatching(
    OnlineRoomJoinRequestRecord request,
  ) async {
    await store.transaction(
      '$_joinRequestsPath/${request.roomId}/${request.uid}',
      (raw) {
        if (!_joinRequestMatches(raw, request)) {
          return const OnlineStoreTransactionDecision.abort();
        }
        return const OnlineStoreTransactionDecision.commit(null);
      },
    );
  }

  Future<void> _removeAccountJoinRequestIfMatching(
    OnlineRoomJoinRequestRecord request,
  ) async {
    await store.transaction(
      '$_accountResourcesPath/joinRequests/${request.roomId}',
      (raw) {
        if (!_joinRequestMatches(raw, request)) {
          return const OnlineStoreTransactionDecision.abort();
        }
        return const OnlineStoreTransactionDecision.commit(null);
      },
    );
  }

  Future<void> _finishSuccessfulJoin(
    OnlineRoomJoinRequestRecord request,
  ) async {
    await _removeTopLevelJoinRequestIfMatching(request);
    await _removeAccountJoinRequestIfMatching(request);
    await _removeJoinFenceIfMatching(request);
  }

  Future<void> _removeCancelledOwnMembership(
    OnlineRoomJoinRequestRecord request,
  ) async {
    final room = await readRoom(request.roomId);
    final member = room?.members[request.uid];
    final ownsCancelledMembership = _memberMatchesJoinRequest(member, request);
    final waitingMembership =
        ownsCancelledMembership && room?.status == RoomStatus.waiting;
    final lease = _presenceLeases.remove(request.roomId);
    if (lease != null) await lease.cancel();

    final updates = <String, Object?>{
      '$onlineAccountResourcesNode/${identity.uid}/rooms/${request.roomId}':
          null,
      '$onlineAccountResourcesNode/${identity.uid}/presence/${request.roomId}':
          null,
    };
    if (waitingMembership) {
      updates
        ..['rooms/${request.roomId}/presence/${request.uid}'] = null
        ..['rooms/${request.roomId}/members/${request.uid}'] = null;
    }
    if (waitingMembership || room == null || member == null) {
      await store.update(onlineTransportRoot, updates);
    } else if (ownsCancelledMembership && lease != null) {
      // The lobby advanced concurrently. Preserve immutable membership and
      // publish a disconnect instead of attempting an illegal late removal.
      await connectRoomPresence(
        request.roomId,
      ).then((replacement) => replacement.disconnect());
    }
  }

  Future<OnlineRoomRecord> _removeCancelledAdmissionAsHost(
    OnlineRoomRecord fallback,
    OnlineRoomJoinRequestRecord request,
  ) async {
    final now = await store.serverNowMs();
    final result = await store.transaction('$_roomsPath/${request.roomId}', (
      raw,
    ) {
      if (raw == null) return const OnlineStoreTransactionDecision.abort();
      final room = OnlineRoomRecord.fromJson(raw);
      _requireHost(room);
      final map = onlineMap(raw);
      final member = room.members[request.uid];
      if (room.status != RoomStatus.waiting ||
          !_memberMatchesJoinRequest(member, request)) {
        return const OnlineStoreTransactionDecision.abort();
      }
      final members = onlineMap(map['members'])..remove(request.uid);
      final presence = onlineMap(map['presence'])..remove(request.uid);
      final joinFences = onlineMap(map['joinFences'])..remove(request.uid);
      map
        ..['members'] = members
        ..['presence'] = presence
        ..['joinFences'] = joinFences
        ..['revision'] = room.revision + 1
        ..['updatedAt'] = now;
      return OnlineStoreTransactionDecision.commit(map);
    });
    if (result.value == null) return fallback;
    return OnlineRoomRecord.fromJson(result.value);
  }

  Future<void> _discardJoinRequest(OnlineRoomJoinRequestRecord request) async {
    final fenceResult = await _removeJoinFenceIfMatching(request);
    if (fenceResult != _JoinFenceRemoval.mismatched) {
      await _removeCancelledOwnMembership(request);
    }
    await _removeTopLevelJoinRequestIfMatching(request);
    await _removeAccountJoinRequestIfMatching(request);
    final pending = _pendingJoinRequests[request.roomId];
    if (pending?.attemptId == request.attemptId) {
      _pendingJoinRequests.remove(request.roomId);
    }
  }

  Future<void> cancelRoomJoinRequest(
    OnlineRoomJoinRequestRecord request,
  ) async {
    await _discardJoinRequest(request);
  }

  Future<OnlineRoomRecord> joinRoomByCode(
    String rawCode, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final request = await requestRoomJoinByCode(rawCode);
    return waitForRoomAdmission(request, timeout: timeout);
  }

  Future<OnlineRoomRecord?> readRoom(String roomId) async {
    final cleanRoomId = _validatedSegment(roomId, 'roomId');
    final raw = await store.read('$_roomsPath/$cleanRoomId');
    return raw == null ? null : OnlineRoomRecord.fromJson(raw);
  }

  Stream<OnlineRoomRecord?> watchRoom(String roomId) {
    final cleanRoomId = _validatedSegment(roomId, 'roomId');
    return store
        .watch('$_roomsPath/$cleanRoomId')
        .map((raw) => raw == null ? null : OnlineRoomRecord.fromJson(raw));
  }

  Future<List<PublicOnlineRoomRecord>> listPublicRooms() async =>
      _decodePublicRooms(await store.read(_publicRoomsPath));

  Stream<List<PublicOnlineRoomRecord>> watchPublicRooms() =>
      store.watch(_publicRoomsPath).map(_decodePublicRooms);

  Future<OnlineRoomRecord> updateReady({
    required String roomId,
    required bool ready,
  }) async {
    final cleanRoomId = _validatedSegment(roomId, 'roomId');
    final room = await readRoom(cleanRoomId);
    if (room == null) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.roomNotFound,
        'The room no longer exists.',
      );
    }
    if (room.status != RoomStatus.waiting) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.invalidRoomStatus,
        'Ready can change only while the room is waiting.',
      );
    }
    final member = room.members[identity.uid];
    if (member == null) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.unknownParticipant,
        'The current player is not in this room.',
      );
    }
    await store.transaction(
      '$_roomsPath/$cleanRoomId/members/${identity.uid}',
      (raw) {
        if (raw == null) {
          throw const OnlineTransportException(
            OnlineTransportErrorCode.unknownParticipant,
            'The current player is not in this room.',
          );
        }
        final current = OnlineRoomMemberRecord.fromJson(raw, uid: identity.uid);
        return OnlineStoreTransactionDecision.commit(
          current.copyWith(ready: ready).toJson(),
        );
      },
    );
    return (await readRoom(cleanRoomId))!;
  }

  Future<OnlineRoomRecord> updatePrivacy({
    required String roomId,
    required RoomVisibility visibility,
  }) async {
    final updated = await _mutateRoom(roomId, (room, map, now) {
      _requireHost(room);
      if (room.status != RoomStatus.waiting) {
        throw const OnlineTransportException(
          OnlineTransportErrorCode.invalidRoomStatus,
          'Privacy can change only while the room is waiting.',
        );
      }
      map['visibility'] = visibility.name;
    });
    await _syncPublicRoom(updated);
    return updated;
  }

  Future<OnlineRoomRecord> closeRoom(String roomId) async {
    final updated = await _mutateRoom(roomId, (room, map, now) {
      _requireHost(room);
      if (room.status == RoomStatus.inGame) {
        throw const OnlineTransportException(
          OnlineTransportErrorCode.invalidRoomStatus,
          'An active match must finish through match rules.',
        );
      }
      map['status'] = RoomStatus.closed.name;
    });
    await store.set('$_publicRoomsPath/${updated.id}', null);
    await _removeCodeIfOwned(updated.code, updated.id);
    await _presenceLeases.remove(updated.id)?.disconnect();
    return updated;
  }

  Future<OnlineRoomRecord> leaveRoom(String roomId) async {
    final existing = await readRoom(roomId);
    if (existing == null) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.roomNotFound,
        'The room no longer exists.',
      );
    }
    if (existing.hostUid == identity.uid) {
      if (existing.status == RoomStatus.inGame ||
          existing.status == RoomStatus.closed) {
        await _presenceLeases.remove(existing.id)?.disconnect();
        return existing;
      }
      return closeRoom(roomId);
    }
    if (!existing.members.containsKey(identity.uid)) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.unknownParticipant,
        'The current player is not in this room.',
      );
    }
    final lease = _presenceLeases.remove(existing.id);
    if (lease != null) await lease.disconnect();
    if (existing.status != RoomStatus.waiting) return existing;
    final now = await store.serverNowMs();
    await store.update(onlineTransportRoot, <String, Object?>{
      'rooms/${existing.id}/presence/${identity.uid}': null,
      'rooms/${existing.id}/members/${identity.uid}': null,
      ..._accountResourceRootUpdates(<String, Object?>{
        'rooms/${existing.id}': null,
        'presence/${existing.id}': null,
      }, nowMs: now),
    });
    return (await readRoom(existing.id))!;
  }

  Future<OnlinePresenceLease> connectRoomPresence(String roomId) async {
    final cleanRoomId = _validatedSegment(roomId, 'roomId');
    final existingLease = _presenceLeases[cleanRoomId];
    if (existingLease != null && !existingLease.closed) return existingLease;
    final room = await readRoom(cleanRoomId);
    if (room == null || !room.members.containsKey(identity.uid)) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.unknownParticipant,
        'Presence requires room membership.',
      );
    }
    final now = await store.serverNowMs();
    final lease = await _connectRoomPresence(
      roomId: cleanRoomId,
      nowMs: now,
      connectionId: _newConnectionId(cleanRoomId, now),
    );
    await _indexRoom(room, nowMs: now);
    return lease;
  }

  Future<QuickPopQueueTicket> enqueueQuickPop({
    required String mode,
    String matchFormat = 'quickPop',
    Duration searchWindow = quickPopSearchWindow,
  }) async {
    if (searchWindow <= Duration.zero || searchWindow > quickPopSearchWindow) {
      throw ArgumentError.value(
        searchWindow,
        'searchWindow',
        'Quick Pop search budget must be between 1 ms and 10 seconds.',
      );
    }
    final queueKey = _queueKey(mode, matchFormat);
    final now = await store.serverNowMs();
    final ticketId = _stableId(
      '$queueKey|${identity.uid}|$now|${_random.nextInt(0x7fffffff)}',
      prefix: 't_',
    );
    final ticket = QuickPopQueueTicket(
      ticketId: ticketId,
      uid: identity.uid,
      displayName: identity.displayName,
      queueKey: queueKey,
      joinedAtMs: now,
      deadlineAtMs: now + searchWindow.inMilliseconds,
    );
    await store.update(onlineTransportRoot, <String, Object?>{
      'quickQueues/$queueKey/${identity.uid}': ticket.toJson(),
      ..._accountResourceRootUpdates(<String, Object?>{
        'quickQueues/$queueKey': <String, Object?>{
          'queueKey': queueKey,
          'ticketId': ticketId,
          'indexedAt': now,
        },
      }, nowMs: now),
    });
    _ownedQuickTickets[queueKey] = ticket;
    return ticket;
  }

  Future<QuickPopResolution?> resolveQuickPop(
    QuickPopQueueTicket ticket,
  ) async {
    _validateTicketOwner(ticket);
    var current = await _readOwnedTicket(ticket);
    var now = await store.serverNowMs();
    final immediate = _resolutionFor(current, now);
    if (immediate != null) return immediate;

    if (current.claimId != null) {
      final existingResolution = await _readClaimResolution(
        current.queueKey,
        current.claimId!,
      );
      if (existingResolution?.kind == QuickPopResolutionKind.human) {
        current = await _finalizeHumanTicket(current, existingResolution!);
        return _resolutionFor(current, existingResolution.resolvedAtMs);
      }
    }

    now = await store.serverNowMs();
    final _QuickPopPair? pair;
    if (now >= current.deadlineAtMs) {
      // Queue enumeration is intentionally unavailable after this player's
      // search expires. An already attached, verified claim may still finish
      // through exact-record reads while the peer's overlapping window is
      // open; otherwise CPU fallback can be committed immediately.
      pair = await _readAttachedClaimPair(current);
      if (pair == null) return _finalizeCpuOrLateHuman(current, now);
    } else {
      final queue = onlineMap(
        await _readActiveQuickQueue(
          ticket.queueKey,
          startAtJoinedAtMs: current.joinedAtMs,
        ),
      );
      pair = _deterministicPairFor(current, queue);
    }
    if (pair != null) {
      final claimId = _sharedQuickClaimId(pair.first, pair.second);
      // A claim permanently binds this ticket to one opponent. Re-pairing a
      // claimed ticket would violate the immutable Firebase ticket contract
      // and could let a late third player steal an in-flight handshake.
      final compatibleClaim =
          current.claimId == null || current.claimId == claimId;
      // Once this client's five-second window has expired, production rules
      // intentionally reject a first claim attachment. An already attached
      // handshake may still finish as a human match.
      final canAttachClaim =
          current.claimId == claimId || now < current.deadlineAtMs;
      if (compatibleClaim && canAttachClaim) {
        // Firebase exact reads are authorized by the claim root, so use the
        // ordered snapshot's claim markers until that root exists. In-memory
        // stores do not have that rules race and retain the direct check used
        // by the deterministic transport tests.
        final pairAttached =
            store is OnlineRealtimeExactReadPolicy &&
                (store as OnlineRealtimeExactReadPolicy)
                    .opponentTicketExactReadRequiresClaim
            ? pair.first.claimId == claimId && pair.second.claimId == claimId
            : await _pairTicketsAttachedToClaim(pair, claimId);
        current = await _attachClaimToOwnedTicket(current, claimId);
        var claimReady = false;
        if (pair.leader.uid == identity.uid) {
          // The claim validator is the authoritative check that both queue
          // tickets advertise this claim. Do not read the opponent ticket
          // before creating the claim: Firebase rules intentionally permit an
          // exact opponent read only after the claim root exists, so that
          // pre-claim read would race the leader's own claim transaction.
          if (pairAttached) {
            claimReady = await _ensureLeaderClaim(pair, claimId, now);
          }
        } else {
          claimReady = await _claimReadyForAcceptance(pair, claimId);
        }

        if (claimReady) {
          await store.set(
            '$_quickClaimsPath/${ticket.queueKey}/$claimId/acceptances/${identity.uid}',
            QuickPopClaimAcceptance(
              uid: identity.uid,
              ticketId: current.ticketId,
              opponentUid: pair.opponentOf(identity.uid).uid,
              opponentTicketId: pair.opponentOf(identity.uid).ticketId,
              acceptedAtMs: now,
            ).toJson(),
          );
          // Either accepted participant may finish the deterministic claim.
          // This matters when the follower's acceptance arrives after the
          // leader's own five-second deadline: the leader may no longer be
          // polling, but the two verified acceptances must still become one
          // human match instead of two conflicting CPU fallbacks.
          await _resolveHumanClaimIfAccepted(pair, claimId);
          final claimResolution = await _readClaimResolution(
            current.queueKey,
            claimId,
          );
          if (claimResolution?.kind == QuickPopResolutionKind.human) {
            current = await _finalizeHumanTicket(current, claimResolution!);
            return _resolutionFor(current, claimResolution.resolvedAtMs);
          }
        }
        // A compatible human ticket was present inside the five-second
        // window. Give a last-millisecond arrival a bounded chance to publish
        // its claim and reciprocal acceptance instead of racing them with a
        // CPU result. A stale or unresponsive ticket cannot hold the search.
        now = await store.serverNowMs();
        final latestJoin = max(pair.first.joinedAtMs, pair.second.joinedAtMs);
        // Once both tickets advertise the same claim, a real opponent was
        // found inside both search windows. Keep that handshake alive only
        // until the later participant's original deadline. This gives the
        // reciprocal acceptance time to cross the network without allowing
        // an abandoned claim to block CPU fallback indefinitely.
        final handshakeUntil = pairAttached
            ? max(pair.first.deadlineAtMs, pair.second.deadlineAtMs)
            : max(
                current.deadlineAtMs,
                latestJoin + _quickClaimHandshakeGrace.inMilliseconds,
              );
        if (now < handshakeUntil) return null;
      }
    }

    now = await store.serverNowMs();
    if (now < current.deadlineAtMs) return null;
    return _finalizeCpuOrLateHuman(current, now);
  }

  Future<Object?> _readActiveQuickQueue(
    String queueKey, {
    required int startAtJoinedAtMs,
  }) {
    final path = '$_quickQueuesPath/$queueKey';
    final currentStore = store;
    if (currentStore is OnlineRealtimeQueryStore) {
      return (currentStore as OnlineRealtimeQueryStore).readOrderedChildren(
        path,
        orderByChild: 'activeUntil',
        startAt: startAtJoinedAtMs,
        limitToFirst: _quickQueueReadLimit,
      );
    }
    return currentStore.read(path);
  }

  Future<QuickPopQueueTicket> _readOwnedTicket(
    QuickPopQueueTicket expected,
  ) async {
    final raw = await store.read(
      '$_quickQueuesPath/${expected.queueKey}/${identity.uid}',
    );
    if (raw == null) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.invalidQueueTicket,
        'The Quick Pop ticket is no longer in its queue.',
      );
    }
    final current = QuickPopQueueTicket.fromJson(raw, uid: identity.uid);
    if (current.ticketId != expected.ticketId) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.invalidQueueTicket,
        'A newer Quick Pop search replaced this ticket.',
      );
    }
    return current;
  }

  Future<QuickPopResolution> findQuickPop({
    required String mode,
    String matchFormat = 'quickPop',
    Duration pollInterval = const Duration(milliseconds: 200),
  }) async {
    if (pollInterval <= Duration.zero) {
      throw ArgumentError.value(pollInterval, 'pollInterval');
    }
    final ticket = await enqueueQuickPop(mode: mode, matchFormat: matchFormat);
    while (true) {
      final resolution = await resolveQuickPop(ticket);
      if (resolution != null) return resolution;
      final now = await store.serverNowMs();
      final remaining = ticket.deadlineAtMs - now;
      if (remaining <= 0) continue;
      final waitMs = min(remaining, pollInterval.inMilliseconds);
      await _delay(Duration(milliseconds: waitMs));
    }
  }

  Future<void> cancelQuickPop(QuickPopQueueTicket ticket) async {
    _validateTicketOwner(ticket);
    final path = '$_quickQueuesPath/${ticket.queueKey}/${identity.uid}';
    await store.transaction(path, (raw) {
      if (raw == null) return OnlineStoreTransactionDecision.abort();
      final current = QuickPopQueueTicket.fromJson(raw, uid: identity.uid);
      if (current.ticketId != ticket.ticketId || current.resolved) {
        return OnlineStoreTransactionDecision.abort();
      }
      final map = onlineMap(current.toJson());
      map
        ..['state'] = QuickPopTicketState.cancelled.name
        ..['activeUntil'] = 0;
      return OnlineStoreTransactionDecision.commit(map);
    });
    // Keep the durable queue locator until the cancelled record itself is
    // removed (account deletion or retention). Dropping the index first would
    // create an undiscoverable record if the app terminated between writes.
    _ownedQuickTickets.remove(ticket.queueKey);
  }

  /// Publishes this device's prepared-and-synchronized acknowledgement and
  /// tries to commit the candidate room from `starting` to `inGame`.
  ///
  /// Returning `true` means both human clients reached a playable sync state
  /// before their shared server deadline. Returning `false` means the peer is
  /// not ready yet; callers may poll while their local tap deadline remains.
  Future<bool> synchronizeQuickPopLaunch({
    required QuickPopQueueTicket ticket,
    required QuickPopResolution resolution,
  }) async {
    final context = _quickPopLaunchContext(ticket, resolution);
    final claimPath =
        '$_quickClaimsPath/${context.queueKey}/${context.claimId}';
    final readyAt = await store.serverNowMs();
    final readyPath = '$claimPath/launchReady/${identity.uid}';
    final ready = <String, Object?>{
      'uid': identity.uid,
      'ticketId': ticket.ticketId,
      'readyAt': readyAt,
    };
    final readyResult = await store.transaction(readyPath, (raw) {
      if (raw != null) return const OnlineStoreTransactionDecision.abort();
      return OnlineStoreTransactionDecision.commit(ready);
    });
    if (!readyResult.committed) {
      final existing = onlineMap(readyResult.value);
      if (existing['uid'] != identity.uid ||
          existing['ticketId'] != ticket.ticketId) {
        throw const OnlineTransportException(
          OnlineTransportErrorCode.invalidQueueTicket,
          'The Quick Pop launch acknowledgement is inconsistent.',
        );
      }
    }

    final claim = onlineMap(await store.read(claimPath));
    _validateQuickPopLaunchClaim(claim, context, resolution);
    final firstUid = claim['firstUid']! as String;
    final secondUid = claim['secondUid']! as String;
    final readyMap = onlineMap(claim['launchReady']);
    if (!_validQuickPopLaunchReady(
          readyMap[firstUid],
          uid: firstUid,
          ticketId: claim['firstTicketId']! as String,
        ) ||
        !_validQuickPopLaunchReady(
          readyMap[secondUid],
          uid: secondUid,
          ticketId: claim['secondTicketId']! as String,
        )) {
      return false;
    }

    final room = await readRoom(resolution.roomId);
    if (room == null) return false;
    if (room.status == RoomStatus.closed) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.invalidQueueTicket,
        'The other Quick Pop player left before launch.',
      );
    }
    if (room.status == RoomStatus.inGame) return true;
    if (room.status != RoomStatus.starting) return false;
    // The two launch-ready markers are validated against each ticket's
    // original five-second deadline by Firebase Rules. The actual status
    // transition may arrive a little later because preparing the replicated
    // engine and opening presence sockets is asynchronous; rejecting it on a
    // second client-side deadline check would turn a verified human match into
    // CPU merely because the network handshake crossed that boundary.
    if (room.presenceFor(firstUid) != LobbyPresence.connected ||
        room.presenceFor(secondUid) != LobbyPresence.connected) {
      return false;
    }
    if (room.hostUid != identity.uid) return false;
    await store.transaction('$_roomsPath/${resolution.roomId}/status', (raw) {
      if (raw == RoomStatus.inGame.name) {
        return const OnlineStoreTransactionDecision.abort();
      }
      if (raw != RoomStatus.starting.name) {
        return const OnlineStoreTransactionDecision.abort();
      }
      return OnlineStoreTransactionDecision.commit(RoomStatus.inGame.name);
    });
    return await _readQuickPopStatus(
          '$_roomsPath/${resolution.roomId}/status',
        ) ==
        RoomStatus.inGame;
  }

  /// Resolves the provisional Quick Pop launch into one authoritative result.
  ///
  /// `inGame` alone is not enough to navigate: one client may observe that
  /// pre-deadline commit while the other is concurrently cancelling at its
  /// local five-second boundary. Each participant therefore publishes a
  /// one-shot settlement commitment at its own boundary. Human play is final
  /// only after both commitments exist and a fresh room-status read still
  /// says `inGame`.
  ///
  /// If the peer does not settle within [peerWait], this client races the
  /// missing commitment with an atomic close. Firebase rules serialize that
  /// race: close wins and both use CPU, or the second commitment wins and both
  /// use the human room. A hung/offline store returns [unavailable] after the
  /// bounded [operationTimeout]; it never guesses CPU after a human commit may
  /// exist, because doing so would recreate the split this barrier prevents.
  Future<QuickPopLaunchSettlement> settleQuickPopLaunch({
    required QuickPopQueueTicket ticket,
    required QuickPopResolution resolution,
    Duration peerWait = quickPopSettlementPeerWait,
    Duration operationTimeout = quickPopSettlementOperationTimeout,
  }) {
    if (peerWait <= Duration.zero || operationTimeout <= Duration.zero) {
      throw ArgumentError('Quick Pop settlement durations must be positive.');
    }
    final context = _quickPopLaunchContext(ticket, resolution);
    return _settleQuickPopLaunch(
      ticket: ticket,
      resolution: resolution,
      context: context,
      peerWait: peerWait,
    ).timeout(
      operationTimeout,
      onTimeout: () => QuickPopLaunchSettlement.unavailable,
    );
  }

  Future<QuickPopLaunchSettlement> _settleQuickPopLaunch({
    required QuickPopQueueTicket ticket,
    required QuickPopResolution resolution,
    required ({String queueKey, String claimId}) context,
    required Duration peerWait,
  }) async {
    final claimPath =
        '$_quickClaimsPath/${context.queueKey}/${context.claimId}';
    var claim = onlineMap(await store.read(claimPath));
    _validateQuickPopLaunchClaim(claim, context, resolution);
    final sharedDeadline = await _quickPopSharedDeadline(claim, context);
    final beforeDeadline = await store.serverNowMs();
    if (beforeDeadline < sharedDeadline) {
      await _delay(Duration(milliseconds: sharedDeadline - beforeDeadline));
    }

    claim = onlineMap(await store.read(claimPath));
    _validateQuickPopLaunchClaim(claim, context, resolution);

    final statusPath = '$_roomsPath/${resolution.roomId}/status';
    if (_quickPopLaunchWasAborted(claim)) {
      return _closeAndResolveQuickPopSettlement(
        statusPath: statusPath,
        claimPath: claimPath,
        context: context,
        resolution: resolution,
      );
    }
    final status = await _readQuickPopStatus(statusPath);
    if (status == RoomStatus.starting) {
      return _closeAndResolveQuickPopSettlement(
        statusPath: statusPath,
        claimPath: claimPath,
        context: context,
        resolution: resolution,
      );
    }
    if (status == RoomStatus.closed) {
      return QuickPopLaunchSettlement.fallback;
    }
    if (status != RoomStatus.inGame) {
      return QuickPopLaunchSettlement.unavailable;
    }

    final settledAt = await store.serverNowMs();
    final settledPath = '$claimPath/launchSettled/${identity.uid}';
    final settlement = <String, Object?>{
      'uid': identity.uid,
      'ticketId': ticket.ticketId,
      'settledAt': settledAt,
    };
    late final OnlineStoreTransactionResult settledResult;
    try {
      settledResult = await store.transaction(settledPath, (raw) {
        if (raw != null) return const OnlineStoreTransactionDecision.abort();
        return OnlineStoreTransactionDecision.commit(settlement);
      });
    } catch (_) {
      // A peer can close the provisional room after our `inGame` read but
      // before this exact-ticket acknowledgement reaches Firebase. Resolve
      // that expected write-vs-close race authoritatively instead of turning a
      // known cancellation into an ambiguous network result.
      final racedStatus = await _readQuickPopStatus(statusPath);
      final racedClaim = onlineMap(await store.read(claimPath));
      _validateQuickPopLaunchClaim(racedClaim, context, resolution);
      if (racedStatus == RoomStatus.closed ||
          _quickPopLaunchWasAborted(racedClaim)) {
        return QuickPopLaunchSettlement.fallback;
      }
      rethrow;
    }
    if (!settledResult.committed) {
      final existing = onlineMap(settledResult.value);
      if (existing['uid'] != identity.uid ||
          existing['ticketId'] != ticket.ticketId) {
        throw const OnlineTransportException(
          OnlineTransportErrorCode.invalidQueueTicket,
          'The Quick Pop settlement acknowledgement is inconsistent.',
        );
      }
    }

    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < peerWait) {
      final snapshot = await _quickPopSettlementSnapshot(
        statusPath: statusPath,
        claimPath: claimPath,
        context: context,
        resolution: resolution,
      );
      if (snapshot.status == RoomStatus.closed) {
        return QuickPopLaunchSettlement.fallback;
      }
      if (snapshot.aborted) {
        return _closeAndResolveQuickPopSettlement(
          statusPath: statusPath,
          claimPath: claimPath,
          context: context,
          resolution: resolution,
        );
      }
      if (snapshot.status == RoomStatus.inGame && snapshot.bothSettled) {
        // The second read is intentional. It closes the observation-vs-cancel
        // interleaving before either client may navigate.
        final finalStatus = await _readQuickPopStatus(statusPath);
        return finalStatus == RoomStatus.inGame
            ? QuickPopLaunchSettlement.human
            : finalStatus == RoomStatus.closed
            ? QuickPopLaunchSettlement.fallback
            : QuickPopLaunchSettlement.unavailable;
      }
      final remaining = peerWait - stopwatch.elapsed;
      if (remaining <= Duration.zero) break;
      const interval = Duration(milliseconds: 100);
      await _delay(remaining < interval ? remaining : interval);
    }

    // Missing peer settlement: atomically close provisional play. If the peer
    // commitment won this exact race, rules deny the close and the fresh reads
    // below observe the now-stable human result instead.
    return _closeAndResolveQuickPopSettlement(
      statusPath: statusPath,
      claimPath: claimPath,
      context: context,
      resolution: resolution,
    );
  }

  Future<QuickPopLaunchSettlement> _closeAndResolveQuickPopSettlement({
    required String statusPath,
    required String claimPath,
    required ({String queueKey, String claimId}) context,
    required QuickPopResolution resolution,
  }) async {
    try {
      await _closeQuickPopStatus(statusPath);
    } catch (_) {
      // Firebase rules reject this close when the peer's second exact-ticket
      // settlement wins the same transaction race. A rejection is not itself
      // a terminal result: always re-read both authoritative records below so
      // unrelated failures become `unavailable` instead of being mistaken for
      // either a human launch or a CPU fallback.
    }
    final finalSnapshot = await _quickPopSettlementSnapshot(
      statusPath: statusPath,
      claimPath: claimPath,
      context: context,
      resolution: resolution,
    );
    if (finalSnapshot.status == RoomStatus.closed || finalSnapshot.aborted) {
      return QuickPopLaunchSettlement.fallback;
    }
    if (finalSnapshot.status == RoomStatus.inGame &&
        finalSnapshot.bothSettled) {
      return QuickPopLaunchSettlement.human;
    }
    return QuickPopLaunchSettlement.unavailable;
  }

  Future<({RoomStatus? status, bool bothSettled, bool aborted})>
  _quickPopSettlementSnapshot({
    required String statusPath,
    required String claimPath,
    required ({String queueKey, String claimId}) context,
    required QuickPopResolution resolution,
  }) async {
    final status = await _readQuickPopStatus(statusPath);
    final claim = onlineMap(await store.read(claimPath));
    _validateQuickPopLaunchClaim(claim, context, resolution);
    return (
      status: status,
      bothSettled: _bothQuickPopParticipantsSettled(claim),
      aborted: _quickPopLaunchWasAborted(claim),
    );
  }

  Future<RoomStatus?> _readQuickPopStatus(String statusPath) async {
    final raw = await store.read(statusPath);
    if (raw is! String) return null;
    for (final status in RoomStatus.values) {
      if (status.name == raw) return status;
    }
    return null;
  }

  Future<void> _closeQuickPopStatus(String statusPath) async {
    await store.transaction(statusPath, (current) {
      if (current != RoomStatus.starting.name &&
          current != RoomStatus.inGame.name) {
        return const OnlineStoreTransactionDecision.abort();
      }
      return OnlineStoreTransactionDecision.commit(RoomStatus.closed.name);
    });
  }

  /// Marks an unresolved Quick Pop launch as abandoned. A participant may
  /// also close a provisionally committed `inGame` room until both devices
  /// have published their final settlement commitment.
  Future<void> abandonQuickPopLaunch({
    required QuickPopQueueTicket ticket,
    required QuickPopResolution resolution,
  }) async {
    final context = _quickPopLaunchContext(ticket, resolution);
    await _publishQuickPopLaunchAbort(
      ticket: ticket,
      resolution: resolution,
      context: context,
    );
    await _closeAbandonedQuickPopRoom(context: context, resolution: resolution);
  }

  /// Used by room bootstrap to avoid creating a room after either device has
  /// already honored its local five-second fallback.
  Future<bool> isQuickPopLaunchAbandoned({
    required QuickPopQueueTicket ticket,
    required QuickPopResolution resolution,
  }) async {
    final context = _quickPopLaunchContext(ticket, resolution);
    final claim = onlineMap(
      await store.read(
        '$_quickClaimsPath/${context.queueKey}/${context.claimId}',
      ),
    );
    _validateQuickPopLaunchClaim(claim, context, resolution);
    if (_quickPopLaunchWasAborted(claim)) return true;
    final room = await readRoom(resolution.roomId);
    return room?.status == RoomStatus.closed;
  }

  /// Immutable metadata attached to a candidate Quick Pop room. Firebase
  /// rules use it to authorize the single `starting -> inGame|closed` launch
  /// decision against the exact matched tickets.
  Future<Map<String, Object?>> quickPopLaunchMetadata({
    required QuickPopQueueTicket ticket,
    required QuickPopResolution resolution,
  }) async {
    final context = _quickPopLaunchContext(ticket, resolution);
    final claim = onlineMap(
      await store.read(
        '$_quickClaimsPath/${context.queueKey}/${context.claimId}',
      ),
    );
    _validateQuickPopLaunchClaim(claim, context, resolution);
    return <String, Object?>{
      'queueKey': context.queueKey,
      'claimId': context.claimId,
      'firstUid': claim['firstUid'],
      'firstTicketId': claim['firstTicketId'],
      'secondUid': claim['secondUid'],
      'secondTicketId': claim['secondTicketId'],
      'sharedDeadlineAt': await _quickPopSharedDeadline(claim, context),
    };
  }

  ({String queueKey, String claimId}) _quickPopLaunchContext(
    QuickPopQueueTicket ticket,
    QuickPopResolution resolution,
  ) {
    _validateTicketOwner(ticket);
    final queueKey = resolution.queueKey ?? ticket.queueKey;
    final claimId = resolution.claimId ?? ticket.claimId;
    if (resolution.kind != QuickPopResolutionKind.human ||
        resolution.ticketId != ticket.ticketId ||
        resolution.opponentUid == null ||
        queueKey != ticket.queueKey ||
        claimId == null ||
        claimId.isEmpty) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.invalidQueueTicket,
        'Quick Pop launch requires a verified human claim.',
      );
    }
    return (
      queueKey: _validatedSegment(queueKey, 'queueKey'),
      claimId: _validatedSegment(claimId, 'claimId'),
    );
  }

  void _validateQuickPopLaunchClaim(
    Map<String, Object?> claim,
    ({String queueKey, String claimId}) context,
    QuickPopResolution resolution,
  ) {
    final firstUid = claim['firstUid'];
    final secondUid = claim['secondUid'];
    final participant = firstUid == identity.uid || secondUid == identity.uid;
    final opponentMatches =
        (firstUid == identity.uid && secondUid == resolution.opponentUid) ||
        (secondUid == identity.uid && firstUid == resolution.opponentUid);
    final claimResolution = onlineMap(claim['resolution']);
    if (claim['claimId'] != context.claimId ||
        claim['queueKey'] != context.queueKey ||
        !participant ||
        !opponentMatches ||
        claimResolution['kind'] != QuickPopResolutionKind.human.name ||
        claimResolution['roomId'] != resolution.roomId) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.invalidQueueTicket,
        'The Quick Pop launch claim does not match the resolved pair.',
      );
    }
  }

  bool _validQuickPopLaunchReady(
    Object? raw, {
    required String uid,
    required String ticketId,
  }) {
    final map = onlineMap(raw);
    return map['uid'] == uid &&
        map['ticketId'] == ticketId &&
        map['readyAt'] is num;
  }

  bool _bothQuickPopParticipantsSettled(Map<String, Object?> claim) {
    final firstUid = claim['firstUid'];
    final secondUid = claim['secondUid'];
    final firstTicketId = claim['firstTicketId'];
    final secondTicketId = claim['secondTicketId'];
    if (firstUid is! String ||
        secondUid is! String ||
        firstTicketId is! String ||
        secondTicketId is! String) {
      return false;
    }
    final settled = onlineMap(claim['launchSettled']);
    return _validQuickPopLaunchSettled(
          settled[firstUid],
          uid: firstUid,
          ticketId: firstTicketId,
        ) &&
        _validQuickPopLaunchSettled(
          settled[secondUid],
          uid: secondUid,
          ticketId: secondTicketId,
        );
  }

  bool _quickPopLaunchWasAborted(Map<String, Object?> claim) =>
      onlineMap(claim['launchAborted']).isNotEmpty;

  Future<void> _publishQuickPopLaunchAbort({
    required QuickPopQueueTicket ticket,
    required QuickPopResolution resolution,
    required ({String queueKey, String claimId}) context,
  }) async {
    final claimPath =
        '$_quickClaimsPath/${context.queueKey}/${context.claimId}';
    final claim = onlineMap(await store.read(claimPath));
    _validateQuickPopLaunchClaim(claim, context, resolution);
    if (_bothQuickPopParticipantsSettled(claim)) return;
    final abortedAt = await store.serverNowMs();
    final path = '$claimPath/launchAborted/${identity.uid}';
    final abort = <String, Object?>{
      'uid': identity.uid,
      'ticketId': ticket.ticketId,
      'abortedAt': abortedAt,
    };
    final result = await store.transaction(path, (raw) {
      if (raw != null) return const OnlineStoreTransactionDecision.abort();
      return OnlineStoreTransactionDecision.commit(abort);
    });
    if (!result.committed) {
      final existing = onlineMap(result.value);
      if (existing['uid'] != identity.uid ||
          existing['ticketId'] != ticket.ticketId) {
        throw const OnlineTransportException(
          OnlineTransportErrorCode.invalidQueueTicket,
          'The Quick Pop cancellation marker is inconsistent.',
        );
      }
    }
  }

  bool _validQuickPopLaunchSettled(
    Object? raw, {
    required String uid,
    required String ticketId,
  }) {
    final map = onlineMap(raw);
    return map['uid'] == uid &&
        map['ticketId'] == ticketId &&
        map['settledAt'] is num;
  }

  Future<int> _quickPopSharedDeadline(
    Map<String, Object?> claim,
    ({String queueKey, String claimId}) context,
  ) async {
    final firstUid = claim['firstUid']! as String;
    final secondUid = claim['secondUid']! as String;
    final firstRaw = await store.read(
      '$_quickQueuesPath/${context.queueKey}/$firstUid',
    );
    final secondRaw = await store.read(
      '$_quickQueuesPath/${context.queueKey}/$secondUid',
    );
    final first = QuickPopQueueTicket.fromJson(firstRaw, uid: firstUid);
    final second = QuickPopQueueTicket.fromJson(secondRaw, uid: secondUid);
    if (first.ticketId != claim['firstTicketId'] ||
        second.ticketId != claim['secondTicketId']) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.invalidQueueTicket,
        'The Quick Pop launch tickets no longer match the claim.',
      );
    }
    return min(first.deadlineAtMs, second.deadlineAtMs);
  }

  Future<void> _closeAbandonedQuickPopRoom({
    required ({String queueKey, String claimId}) context,
    required QuickPopResolution resolution,
  }) async {
    final room = await readRoom(resolution.roomId);
    if (room == null) return;
    if (room.status == RoomStatus.closed) {
      await _presenceLeases.remove(room.id)?.disconnect();
      return;
    }
    if ((room.status != RoomStatus.starting &&
            room.status != RoomStatus.inGame) ||
        room.matchFormat != 'quickPop') {
      return;
    }
    final raw = onlineMap(await store.read('$_roomsPath/${room.id}'));
    final launch = onlineMap(raw['quickPopLaunch']);
    if (launch['queueKey'] != context.queueKey ||
        launch['claimId'] != context.claimId ||
        (launch['firstUid'] != identity.uid &&
            launch['secondUid'] != identity.uid)) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.invalidRoomStatus,
        'The Quick Pop room launch metadata is inconsistent.',
      );
    }
    final statusPath = '$_roomsPath/${room.id}/status';
    await store.transaction(statusPath, (current) {
      if (current != RoomStatus.starting.name &&
          current != RoomStatus.inGame.name) {
        return const OnlineStoreTransactionDecision.abort();
      }
      return OnlineStoreTransactionDecision.commit(RoomStatus.closed.name);
    });
    // A peer settlement can win the exact transaction race. Only tear down
    // this room lease after a fresh authoritative read confirms cancellation.
    if (await _readQuickPopStatus(statusPath) == RoomStatus.closed) {
      await _presenceLeases.remove(room.id)?.disconnect();
    }
  }

  Future<bool> _markStoredPresenceDisconnected(OnlineRoomRecord room) async {
    final presence = room.presence[identity.uid];
    if (presence == null) return false;
    final now = await store.serverNowMs();
    await store.set(
      '$_roomsPath/${room.id}/presence/${identity.uid}',
      OnlinePresenceRecord(
        uid: identity.uid,
        presence: LobbyPresence.disconnected,
        changedAtMs: now,
        connectionId: presence.connectionId,
      ).toJson(),
    );
    return true;
  }

  /// Removes only data owned by this authenticated player that the current
  /// client-side Firebase contract can safely delete.
  ///
  /// Active match records, resolved queue tickets, immutable chat, and a host
  /// membership embedded in its room are intentionally preserved. Removing
  /// those safely requires a trusted backend retention job because they also
  /// contain state belonging to other players.
  Future<OnlineAccountCleanupReport> deleteOwnOnlineData() async {
    var pendingJoinsRemoved = 0;
    var waitingMembershipsRemoved = 0;
    var roomsClosed = 0;
    var presencesDisconnected = 0;
    var queueTicketsRemoved = 0;
    var resolvedTicketsPreserved = 0;

    final profileRaw = await store.read('$_profilesPath/${identity.uid}');
    final resourcesRaw = await store.read(_accountResourcesPath);
    final resources = onlineMap(resourcesRaw);
    if (resources.isEmpty && profileRaw != null) {
      throw const OnlineAccountCleanupRequiresBackend();
    }
    if (resources.isNotEmpty) {
      const allowedRootKeys = <String>{
        'schemaVersion',
        'updatedAt',
        'requiresBackendCleanup',
        'rooms',
        'presence',
        'hostedRooms',
        'joinRequests',
        'quickQueues',
      };
      if (resources['schemaVersion'] != onlineAccountResourcesSchemaVersion ||
          resources['updatedAt'] is! num ||
          resources['requiresBackendCleanup'] is! bool ||
          resources['requiresBackendCleanup'] == true ||
          resources.keys.any((key) => !allowedRootKeys.contains(key))) {
        throw const OnlineAccountCleanupRequiresBackend();
      }
    }

    final indexedJoinRequests = <String, OnlineRoomJoinRequestRecord>{
      for (final request in _pendingJoinRequests.values)
        request.roomId: request,
    };
    for (final entry in onlineMap(resources['joinRequests']).entries) {
      final request = OnlineRoomJoinRequestRecord.fromJson(
        entry.value,
        uid: identity.uid,
      );
      if (request.roomId != entry.key || request.uid != identity.uid) {
        throw StateError('The durable join-request index is inconsistent.');
      }
      indexedJoinRequests[entry.key] = request;
    }
    for (final request in indexedJoinRequests.values) {
      await cancelRoomJoinRequest(request);
      pendingJoinsRemoved++;
    }

    final queueKeys = <String>{
      ..._knownQuickQueueKeys,
      ..._ownedQuickTickets.keys,
    };
    for (final entry in onlineMap(resources['quickQueues']).entries) {
      final record = onlineMap(entry.value);
      if (record['queueKey'] != entry.key ||
          record['ticketId'] is! String ||
          record['indexedAt'] is! num) {
        throw StateError('The durable Quick Pop index is inconsistent.');
      }
      queueKeys.add(entry.key);
    }

    final indexedRoomIds = <String>{..._presenceLeases.keys};
    for (final queueKey in queueKeys) {
      final raw = await store.read(
        '$_quickQueuesPath/$queueKey/${identity.uid}',
      );
      if (raw == null) continue;
      final ticket = QuickPopQueueTicket.fromJson(raw, uid: identity.uid);
      if (ticket.roomId case final roomId?) indexedRoomIds.add(roomId);
    }
    for (final entry in onlineMap(resources['rooms']).entries) {
      final record = onlineMap(entry.value);
      if (record['roomId'] != entry.key ||
          (record['role'] != 'host' && record['role'] != 'member') ||
          record['indexedAt'] is! num) {
        throw StateError('The durable room index is inconsistent.');
      }
      indexedRoomIds.add(entry.key);
    }
    for (final collectionName in const <String>['presence', 'hostedRooms']) {
      for (final entry in onlineMap(resources[collectionName]).entries) {
        final record = onlineMap(entry.value);
        if (record['roomId'] != entry.key || record['indexedAt'] is! num) {
          throw StateError(
            'The durable $collectionName index is inconsistent.',
          );
        }
        indexedRoomIds.add(entry.key);
      }
    }
    for (final roomId in indexedRoomIds) {
      final room = await readRoom(roomId);
      if (room == null) {
        await _presenceLeases.remove(roomId)?.cancel();
        continue;
      }
      if (!room.members.containsKey(identity.uid)) {
        await _presenceLeases.remove(roomId)?.cancel();
        continue;
      }
      final wasWaitingGuest =
          room.hostUid != identity.uid && room.status == RoomStatus.waiting;
      final shouldCloseOwnedRoom =
          room.hostUid == identity.uid && room.status != RoomStatus.inGame;
      final hadPresenceLease = _presenceLeases.containsKey(roomId);
      if (!hadPresenceLease && await _markStoredPresenceDisconnected(room)) {
        presencesDisconnected++;
      }
      await leaveRoom(roomId);
      if (hadPresenceLease) presencesDisconnected++;
      if (wasWaitingGuest) waitingMembershipsRemoved++;
      if (shouldCloseOwnedRoom && room.status != RoomStatus.closed) {
        roomsClosed++;
      }
    }

    for (final queueKey in queueKeys) {
      final path = '$_quickQueuesPath/$queueKey/${identity.uid}';
      final raw = await store.read(path);
      if (raw == null) continue;
      final ticket = QuickPopQueueTicket.fromJson(raw, uid: identity.uid);
      if (ticket.resolved) {
        resolvedTicketsPreserved++;
        continue;
      }
      if (ticket.claimId case final claimId?) {
        final resolution = await _readClaimResolution(queueKey, claimId);
        if (resolution != null) {
          resolvedTicketsPreserved++;
          continue;
        }
        await _removeOwnClaimAcceptance(ticket);
        // Re-check after withdrawing acceptance so a resolution that won the
        // race is never converted into a cancellation by account cleanup.
        if (await _readClaimResolution(queueKey, claimId) != null) {
          resolvedTicketsPreserved++;
          continue;
        }
      }
      if (ticket.state == QuickPopTicketState.waiting) {
        await cancelQuickPop(ticket);
      }
      await store.set(path, null);
      _ownedQuickTickets.remove(queueKey);
      queueTicketsRemoved++;
    }

    await store.update(onlineTransportRoot, <String, Object?>{
      'profiles/${identity.uid}': null,
      '$onlineAccountResourcesNode/${identity.uid}': null,
    });
    return OnlineAccountCleanupReport(
      profileRemoved: true,
      queueTicketsRemoved: queueTicketsRemoved,
      pendingJoinsRemoved: pendingJoinsRemoved,
      waitingMembershipsRemoved: waitingMembershipsRemoved,
      roomsClosed: roomsClosed,
      presencesDisconnected: presencesDisconnected,
      resolvedTicketsPreserved: resolvedTicketsPreserved,
      resourceIndexRemoved: true,
    );
  }

  /// Stops all owned presence hooks and the underlying realtime adapter.
  Future<void> shutdown() async {
    for (final lease in List<OnlinePresenceLease>.of(_presenceLeases.values)) {
      await lease.cancel();
    }
    _presenceLeases.clear();
    if (store case final OnlineRealtimeStoreLifecycle lifecycle) {
      await lifecycle.shutdown();
    }
  }

  Future<OnlineRoomRecord> _mutateRoom(
    String roomId,
    void Function(
      OnlineRoomRecord room,
      Map<String, Object?> mutableMap,
      int nowMs,
    )
    mutate,
  ) async {
    final cleanRoomId = _validatedSegment(roomId, 'roomId');
    final now = await store.serverNowMs();
    final result = await store.transaction('$_roomsPath/$cleanRoomId', (raw) {
      if (raw == null) {
        throw const OnlineTransportException(
          OnlineTransportErrorCode.roomNotFound,
          'The room no longer exists.',
        );
      }
      final room = OnlineRoomRecord.fromJson(raw);
      // Room records intentionally model only the transport aggregate. Keep
      // every unmodeled child when a host mutates that aggregate at its root.
      final map = onlineMap(raw);
      mutate(room, map, now);
      map['revision'] = room.revision + 1;
      map['updatedAt'] = now;
      return OnlineStoreTransactionDecision.commit(map);
    });
    return OnlineRoomRecord.fromJson(result.value);
  }

  Future<void> _rollbackFailedRoomCreation({
    required String roomId,
    required _RoomCodeReservation reservation,
  }) async {
    final presencePath = '$_roomsPath/$roomId/presence/${identity.uid}';

    Future<void> bestEffort(Future<void> Function() operation) async {
      try {
        await operation();
      } catch (_) {
        // Rollback must attempt every independently owned artifact and must
        // never replace the original create-room failure.
      }
    }

    final lease = _presenceLeases.remove(roomId);
    if (lease != null) await bestEffort(lease.cancel);
    await bestEffort(() => store.cancelOnDisconnect(presencePath));
    await bestEffort(() => _releaseRoomCode(reservation));

    final rollback = <String, Object?>{
      'publicRooms/$roomId': null,
      'rooms/$roomId': null,
      '$onlineAccountResourcesNode/${identity.uid}/rooms/$roomId': null,
      '$onlineAccountResourcesNode/${identity.uid}/presence/$roomId': null,
      '$onlineAccountResourcesNode/${identity.uid}/hostedRooms/$roomId': null,
    };
    await bestEffort(() => store.update(onlineTransportRoot, rollback));

    // Keep the fallback operations independent. Firebase applies the root
    // update atomically, while a custom adapter may fail only one child.
    await bestEffort(() => store.set('$_publicRoomsPath/$roomId', null));
    await bestEffort(() => store.set(presencePath, null));
    await bestEffort(() => store.set('$_roomsPath/$roomId', null));
    await bestEffort(
      () => store.update(_accountResourcesPath, <String, Object?>{
        'rooms/$roomId': null,
        'presence/$roomId': null,
        'hostedRooms/$roomId': null,
      }),
    );
  }

  Future<OnlinePresenceLease> _connectRoomPresence({
    required String roomId,
    required int nowMs,
    required String connectionId,
  }) async {
    final path = '$_roomsPath/$roomId/presence/${identity.uid}';
    final connected = OnlinePresenceRecord(
      uid: identity.uid,
      presence: LobbyPresence.connected,
      changedAtMs: nowMs,
      connectionId: connectionId,
    );
    final disconnected = OnlinePresenceRecord(
      uid: identity.uid,
      presence: LobbyPresence.disconnected,
      changedAtMs: nowMs,
      connectionId: connectionId,
    );
    await store.setOnDisconnect(path, disconnected.toJson());
    try {
      await store.set(path, connected.toJson());
    } catch (error, stackTrace) {
      try {
        await store.cancelOnDisconnect(path);
      } catch (_) {
        // The enclosing create/join cleanup will retry cancellation. Preserve
        // the presence write error so callers receive the real failure.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    final lease = OnlinePresenceLease._(
      store: store,
      roomId: roomId,
      uid: identity.uid,
      connectionId: connectionId,
      path: path,
    );
    _presenceLeases[roomId] = lease;
    return lease;
  }

  Future<void> _syncPublicRoom(OnlineRoomRecord room) async {
    final path = '$_publicRoomsPath/${room.id}';
    if (!room.isPublic ||
        room.status != RoomStatus.waiting ||
        !room.isJoinable) {
      await store.set(path, null);
      return;
    }
    await store.set(path, PublicOnlineRoomRecord.fromRoom(room).toJson());
  }

  List<PublicOnlineRoomRecord> _decodePublicRooms(Object? raw) {
    final records = <PublicOnlineRoomRecord>[];
    for (final value in onlineMap(raw).values) {
      try {
        final record = PublicOnlineRoomRecord.fromJson(value);
        if (record.occupiedSeatCount < LobbySeatColor.values.length) {
          records.add(record);
        }
      } on FormatException {
        // Ignore malformed/stale public index entries; the room remains source
        // of truth and the host will refresh its summary on the next mutation.
      }
    }
    records.sort((left, right) {
      final byUpdated = right.updatedAtMs.compareTo(left.updatedAtMs);
      return byUpdated != 0 ? byUpdated : left.roomId.compareTo(right.roomId);
    });
    return records;
  }

  Future<_RoomCodeReservation> _reserveRoomCode({
    required String roomId,
    required int nowMs,
  }) async {
    for (var attempt = 0; attempt < _maximumRoomCodeAttempts; attempt++) {
      final code = _roomCodeFactory(_random);
      final reservationId = _stableId(
        '${code.value}|$roomId|$nowMs|$attempt',
        prefix: 'reserve_',
      );
      final reservation = _RoomCodeReservation(
        code: code,
        roomId: roomId,
        hostUid: identity.uid,
        reservationId: reservationId,
        reservedAtMs: nowMs,
        expiresAtMs: nowMs + _roomReservationLifetime.inMilliseconds,
      );
      final result = await store.transaction('$_roomCodesPath/${code.value}', (
        raw,
      ) {
        final current = onlineMap(raw);
        final expiresAt = current['expiresAt'];
        final isExpired =
            current.isNotEmpty &&
            current['state'] == 'reserved' &&
            expiresAt is num &&
            expiresAt.toInt() <= nowMs;
        if (current.isNotEmpty && !isExpired) {
          return OnlineStoreTransactionDecision.abort();
        }
        return OnlineStoreTransactionDecision.commit(reservation.toJson());
      });
      if (result.committed) return reservation;
    }
    throw const OnlineTransportException(
      OnlineTransportErrorCode.roomCodeUnavailable,
      'A unique room code could not be reserved safely.',
    );
  }

  Future<void> _activateRoomCode(_RoomCodeReservation reservation) async {
    final path = '$_roomCodesPath/${reservation.code.value}';
    final result = await store.transaction(path, (raw) {
      final current = onlineMap(raw);
      if (current['reservationId'] != reservation.reservationId ||
          current['roomId'] != reservation.roomId) {
        return OnlineStoreTransactionDecision.abort();
      }
      current['state'] = 'active';
      current['expiresAt'] = 0;
      return OnlineStoreTransactionDecision.commit(current);
    });
    if (!result.committed) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.roomCodeUnavailable,
        'The room code reservation was lost before activation.',
      );
    }
  }

  Future<void> _releaseRoomCode(_RoomCodeReservation reservation) async {
    final path = '$_roomCodesPath/${reservation.code.value}';
    await store.transaction(path, (raw) {
      final current = onlineMap(raw);
      if (current['reservationId'] != reservation.reservationId ||
          current['roomId'] != reservation.roomId) {
        return OnlineStoreTransactionDecision.abort();
      }
      return OnlineStoreTransactionDecision.commit(null);
    });
  }

  Future<void> _removeCodeIfOwned(RoomCode code, String roomId) async {
    await store.transaction('$_roomCodesPath/${code.value}', (raw) {
      final current = onlineMap(raw);
      if (current['roomId'] != roomId) {
        return OnlineStoreTransactionDecision.abort();
      }
      return OnlineStoreTransactionDecision.commit(null);
    });
  }

  _QuickPopPair? _deterministicPairFor(
    QuickPopQueueTicket current,
    Map<String, Object?> queue,
  ) {
    final tickets = <QuickPopQueueTicket>[];
    for (final entry in queue.entries) {
      try {
        final ticket = QuickPopQueueTicket.fromJson(
          entry.value,
          uid: entry.key,
        );
        if (ticket.queueKey == current.queueKey &&
            ticket.state == QuickPopTicketState.waiting) {
          tickets.add(ticket);
        }
      } on FormatException {
        // An invalid ticket cannot participate in matching.
      }
    }
    tickets.sort((left, right) {
      final byTime = left.joinedAtMs.compareTo(right.joinedAtMs);
      return byTime != 0 ? byTime : left.ticketId.compareTo(right.ticketId);
    });
    final consumed = <String>{};
    for (var leftIndex = 0; leftIndex < tickets.length; leftIndex++) {
      final left = tickets[leftIndex];
      if (consumed.contains(left.uid)) continue;
      QuickPopQueueTicket? right;
      for (
        var rightIndex = leftIndex + 1;
        rightIndex < tickets.length;
        rightIndex++
      ) {
        final candidate = tickets[rightIndex];
        if (consumed.contains(candidate.uid) || candidate.uid == left.uid) {
          continue;
        }
        final windowsOverlap =
            max(left.joinedAtMs, candidate.joinedAtMs) <=
            min(left.deadlineAtMs, candidate.deadlineAtMs);
        if (windowsOverlap) {
          right = candidate;
          break;
        }
      }
      if (right == null) continue;
      consumed
        ..add(left.uid)
        ..add(right.uid);
      if (left.uid == current.uid || right.uid == current.uid) {
        return _QuickPopPair(first: left, second: right);
      }
    }
    return null;
  }

  Future<_QuickPopPair?> _readAttachedClaimPair(
    QuickPopQueueTicket current,
  ) async {
    final claimId = current.claimId;
    if (claimId == null) return null;
    final claim = onlineMap(
      await store.read('$_quickClaimsPath/${current.queueKey}/$claimId'),
    );
    if (claim.isEmpty) return null;

    final firstUid = claim['firstUid'];
    final firstTicketId = claim['firstTicketId'];
    final secondUid = claim['secondUid'];
    final secondTicketId = claim['secondTicketId'];
    final currentIsFirst =
        firstUid == current.uid && firstTicketId == current.ticketId;
    final currentIsSecond =
        secondUid == current.uid && secondTicketId == current.ticketId;
    if (claim['claimId'] != claimId ||
        claim['queueKey'] != current.queueKey ||
        (!currentIsFirst && !currentIsSecond)) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.invalidQueueTicket,
        'The attached Quick Pop claim does not match this ticket.',
      );
    }

    final opponentUid = currentIsFirst ? secondUid : firstUid;
    final opponentTicketId = currentIsFirst ? secondTicketId : firstTicketId;
    if (opponentUid is! String || opponentTicketId is! String) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.invalidQueueTicket,
        'The attached Quick Pop claim has invalid opponent metadata.',
      );
    }
    final rawOpponent = await store.read(
      '$_quickQueuesPath/${current.queueKey}/$opponentUid',
    );
    if (rawOpponent == null) return null;
    final opponent = QuickPopQueueTicket.fromJson(
      rawOpponent,
      uid: opponentUid,
    );
    if (opponent.ticketId != opponentTicketId ||
        opponent.queueKey != current.queueKey ||
        opponent.claimId != claimId) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.invalidQueueTicket,
        'The attached Quick Pop opponent ticket does not match the claim.',
      );
    }

    final pair = currentIsFirst
        ? _QuickPopPair(first: current, second: opponent)
        : _QuickPopPair(first: opponent, second: current);
    if (!_matchesClaimMetadata(claim, pair: pair, claimId: claimId)) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.invalidQueueTicket,
        'The attached Quick Pop claim metadata is inconsistent.',
      );
    }
    return pair;
  }

  Future<QuickPopQueueTicket> _attachClaimToOwnedTicket(
    QuickPopQueueTicket expected,
    String claimId,
  ) async {
    // [expected] always comes from a fresh wire read. Do not rewrite an
    // already attached waiting ticket: after its individual deadline the
    // Firebase contract correctly rejects new waiting writes, even when the
    // payload is byte-for-byte identical. The no-op transaction previously
    // surfaced as a permission error while a valid two-player handshake was
    // still finishing.
    if (expected.claimId == claimId) return expected;
    final path = '$_quickQueuesPath/${expected.queueKey}/${identity.uid}';
    final result = await store.transaction(path, (raw) {
      if (raw == null) {
        throw const OnlineTransportException(
          OnlineTransportErrorCode.invalidQueueTicket,
          'The Quick Pop ticket is no longer in its queue.',
        );
      }
      final current = QuickPopQueueTicket.fromJson(raw, uid: identity.uid);
      if (current.ticketId != expected.ticketId) {
        throw const OnlineTransportException(
          OnlineTransportErrorCode.invalidQueueTicket,
          'A newer Quick Pop search replaced this ticket.',
        );
      }
      if (current.resolved || current.state == QuickPopTicketState.cancelled) {
        return OnlineStoreTransactionDecision.abort();
      }
      final map = onlineMap(current.toJson())..['claimId'] = claimId;
      return OnlineStoreTransactionDecision.commit(map);
    });
    return QuickPopQueueTicket.fromJson(result.value, uid: identity.uid);
  }

  Future<bool> _ensureLeaderClaim(
    _QuickPopPair pair,
    String claimId,
    int nowMs,
  ) async {
    if (pair.leader.uid != identity.uid) return false;
    final path = '$_quickClaimsPath/${pair.leader.queueKey}/$claimId';
    late final OnlineStoreTransactionResult result;
    try {
      result = await store.transaction(path, (raw) {
        final map = onlineMap(raw);
        if (map.isNotEmpty) {
          // Claim metadata is immutable in production rules. Abort a retry and
          // validate the returned snapshot below instead of rewriting the
          // claim root (which could otherwise bypass narrow acceptance
          // permissions).
          return OnlineStoreTransactionDecision.abort();
        }
        map
          ..['claimId'] = claimId
          ..['queueKey'] = pair.leader.queueKey
          ..['leaderUid'] = pair.leader.uid
          ..['firstUid'] = pair.first.uid
          ..['firstTicketId'] = pair.first.ticketId
          ..['secondUid'] = pair.second.uid
          ..['secondTicketId'] = pair.second.ticketId
          ..putIfAbsent('createdAt', () => nowMs);
        return OnlineStoreTransactionDecision.commit(map);
      });
    } on OnlineTransportException {
      rethrow;
    } catch (_) {
      // The follower can reach its CPU deadline between the readiness read and
      // this transaction. Production rules then reject creation because both
      // tickets are no longer waiting. Treat that expected race as an
      // unavailable claim; preserve genuine storage failures while the pair
      // is still eligible.
      final existing = onlineMap(await store.read(path));
      if (_matchesClaimMetadata(existing, pair: pair, claimId: claimId)) {
        return true;
      }
      if (existing.isNotEmpty) {
        throw const OnlineTransportException(
          OnlineTransportErrorCode.invalidQueueTicket,
          'The deterministic Quick Pop claim belongs to another leader.',
        );
      }
      if (store is OnlineRealtimeExactReadPolicy &&
          (store as OnlineRealtimeExactReadPolicy)
              .opponentTicketExactReadRequiresClaim) {
        // A follower may not have published its claim attachment yet. The
        // leader retries on the next poll; reading the opponent ticket here
        // would be rejected by the exact-read rule until the claim exists.
        return false;
      }
      if (!await _pairTicketsAttachedToClaim(pair, claimId)) return false;
      rethrow;
    }
    if (!result.committed &&
        !_matchesClaimMetadata(
          onlineMap(result.value),
          pair: pair,
          claimId: claimId,
        )) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.invalidQueueTicket,
        'The deterministic Quick Pop claim belongs to another leader.',
      );
    }
    return true;
  }

  bool _matchesClaimMetadata(
    Map<String, Object?> claim, {
    required _QuickPopPair pair,
    required String claimId,
  }) =>
      claim['claimId'] == claimId &&
      claim['queueKey'] == pair.leader.queueKey &&
      claim['leaderUid'] == pair.leader.uid &&
      claim['firstUid'] == pair.first.uid &&
      claim['firstTicketId'] == pair.first.ticketId &&
      claim['secondUid'] == pair.second.uid &&
      claim['secondTicketId'] == pair.second.ticketId;

  Future<bool> _claimReadyForAcceptance(
    _QuickPopPair pair,
    String claimId,
  ) async {
    final raw = await store.read(
      '$_quickClaimsPath/${pair.leader.queueKey}/$claimId',
    );
    if (raw == null) return false;
    if (!_matchesClaimMetadata(onlineMap(raw), pair: pair, claimId: claimId)) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.invalidQueueTicket,
        'The deterministic Quick Pop claim metadata does not match the queue.',
      );
    }
    return true;
  }

  Future<void> _removeOwnClaimAcceptance(QuickPopQueueTicket ticket) async {
    final claimId = ticket.claimId;
    if (claimId == null) return;
    final claimPath = '$_quickClaimsPath/${ticket.queueKey}/$claimId';
    final claim = onlineMap(await store.read(claimPath));
    final ownsFirst =
        claim['claimId'] == claimId &&
        claim['queueKey'] == ticket.queueKey &&
        claim['firstUid'] == identity.uid &&
        claim['firstTicketId'] == ticket.ticketId;
    final ownsSecond =
        claim['claimId'] == claimId &&
        claim['queueKey'] == ticket.queueKey &&
        claim['secondUid'] == identity.uid &&
        claim['secondTicketId'] == ticket.ticketId;
    if (!ownsFirst && !ownsSecond) return;
    await store.set('$claimPath/acceptances/${identity.uid}', null);
  }

  Future<void> _resolveHumanClaimIfAccepted(
    _QuickPopPair pair,
    String claimId,
  ) async {
    final claimPath = '$_quickClaimsPath/${pair.leader.queueKey}/$claimId';
    final claim = onlineMap(await store.read(claimPath));
    final acceptances = onlineMap(claim['acceptances']);
    final firstAcceptance = _validAcceptance(
      acceptances[pair.first.uid],
      participant: pair.first,
      opponent: pair.second,
    );
    final secondAcceptance = _validAcceptance(
      acceptances[pair.second.uid],
      participant: pair.second,
      opponent: pair.first,
    );
    if (!firstAcceptance || !secondAcceptance) return;

    final firstCurrent = await _readQueueTicket(pair.first);
    final secondCurrent = await _readQueueTicket(pair.second);
    if (firstCurrent?.state != QuickPopTicketState.waiting ||
        secondCurrent?.state != QuickPopTicketState.waiting ||
        firstCurrent?.claimId != claimId ||
        secondCurrent?.claimId != claimId) {
      return;
    }
    final now = await store.serverNowMs();
    final resolution = QuickPopClaimResolution(
      kind: QuickPopResolutionKind.human,
      roomId: _sharedQuickRoomId(pair.first, pair.second),
      resolvedAtMs: now,
      firstUid: pair.first.uid,
      secondUid: pair.second.uid,
    );
    await store.transaction('$claimPath/resolution', (raw) {
      if (raw != null) return OnlineStoreTransactionDecision.abort();
      return OnlineStoreTransactionDecision.commit(resolution.toJson());
    });
  }

  bool _validAcceptance(
    Object? raw, {
    required QuickPopQueueTicket participant,
    required QuickPopQueueTicket opponent,
  }) {
    if (raw == null) return false;
    try {
      final acceptance = QuickPopClaimAcceptance.fromJson(
        raw,
        uid: participant.uid,
      );
      return acceptance.ticketId == participant.ticketId &&
          acceptance.opponentUid == opponent.uid &&
          acceptance.opponentTicketId == opponent.ticketId;
    } on FormatException {
      return false;
    }
  }

  Future<bool> _pairTicketsAttachedToClaim(
    _QuickPopPair pair,
    String claimId,
  ) async {
    final first = await _readQueueTicket(pair.first);
    final second = await _readQueueTicket(pair.second);
    return first != null &&
        second != null &&
        first.state == QuickPopTicketState.waiting &&
        second.state == QuickPopTicketState.waiting &&
        first.claimId == claimId &&
        second.claimId == claimId &&
        first.ticketId == pair.first.ticketId &&
        second.ticketId == pair.second.ticketId;
  }

  Future<QuickPopQueueTicket?> _readQueueTicket(
    QuickPopQueueTicket expected,
  ) async {
    final raw = await store.read(
      '$_quickQueuesPath/${expected.queueKey}/${expected.uid}',
    );
    if (raw == null) return null;
    final current = QuickPopQueueTicket.fromJson(raw, uid: expected.uid);
    return current.ticketId == expected.ticketId ? current : null;
  }

  Future<QuickPopClaimResolution?> _readClaimResolution(
    String queueKey,
    String claimId,
  ) async {
    final raw = await store.read(
      '$_quickClaimsPath/$queueKey/$claimId/resolution',
    );
    return raw == null ? null : QuickPopClaimResolution.fromJson(raw);
  }

  Future<QuickPopQueueTicket> _finalizeHumanTicket(
    QuickPopQueueTicket expected,
    QuickPopClaimResolution resolution,
  ) async {
    final opponentUid = resolution.firstUid == identity.uid
        ? resolution.secondUid
        : resolution.firstUid;
    if (opponentUid == null) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.invalidQueueTicket,
        'The human match resolution has no opponent.',
      );
    }
    final path = '$_quickQueuesPath/${expected.queueKey}/${identity.uid}';
    final result = await store.transaction(path, (raw) {
      if (raw == null) {
        throw const OnlineTransportException(
          OnlineTransportErrorCode.invalidQueueTicket,
          'The Quick Pop ticket is no longer in its queue.',
        );
      }
      final current = QuickPopQueueTicket.fromJson(raw, uid: identity.uid);
      if (current.ticketId != expected.ticketId) {
        throw const OnlineTransportException(
          OnlineTransportErrorCode.invalidQueueTicket,
          'A newer Quick Pop search replaced this ticket.',
        );
      }
      if (current.state == QuickPopTicketState.cpuFallback ||
          current.state == QuickPopTicketState.cancelled) {
        return OnlineStoreTransactionDecision.abort();
      }
      final map = onlineMap(current.toJson())
        ..['state'] = QuickPopTicketState.matched.name
        ..['activeUntil'] = 0
        ..['roomId'] = resolution.roomId
        ..['opponentUid'] = opponentUid;
      return OnlineStoreTransactionDecision.commit(map);
    });
    return QuickPopQueueTicket.fromJson(result.value, uid: identity.uid);
  }

  Future<QuickPopQueueTicket> _finalizeCpuTicket(
    QuickPopQueueTicket expected,
  ) async {
    final path = '$_quickQueuesPath/${expected.queueKey}/${identity.uid}';
    final result = await store.transaction(path, (raw) {
      if (raw == null) {
        throw const OnlineTransportException(
          OnlineTransportErrorCode.invalidQueueTicket,
          'The Quick Pop ticket is no longer in its queue.',
        );
      }
      final current = QuickPopQueueTicket.fromJson(raw, uid: identity.uid);
      if (current.ticketId != expected.ticketId) {
        throw const OnlineTransportException(
          OnlineTransportErrorCode.invalidQueueTicket,
          'A newer Quick Pop search replaced this ticket.',
        );
      }
      if (current.resolved) return OnlineStoreTransactionDecision.abort();
      final map = onlineMap(current.toJson())
        ..['state'] = QuickPopTicketState.cpuFallback.name
        ..['activeUntil'] = 0
        ..['roomId'] = _cpuQuickRoomId(current)
        ..remove('opponentUid');
      return OnlineStoreTransactionDecision.commit(map);
    });
    return QuickPopQueueTicket.fromJson(result.value, uid: identity.uid);
  }

  Future<QuickPopResolution?> _finalizeHumanClaimIfAvailable(
    QuickPopQueueTicket current,
  ) async {
    final claimId = current.claimId;
    if (claimId == null ||
        current.state == QuickPopTicketState.cpuFallback ||
        current.state == QuickPopTicketState.cancelled) {
      return null;
    }
    final resolution = await _readClaimResolution(current.queueKey, claimId);
    if (resolution?.kind != QuickPopResolutionKind.human) return null;
    if (current.state == QuickPopTicketState.waiting) {
      current = await _finalizeHumanTicket(current, resolution!);
    }
    return _resolutionFor(current, resolution!.resolvedAtMs);
  }

  Future<QuickPopResolution?> _finalizeCpuOrLateHuman(
    QuickPopQueueTicket current,
    int nowMs,
  ) async {
    final humanBeforeCpu = await _finalizeHumanClaimIfAvailable(current);
    if (humanBeforeCpu != null) return humanBeforeCpu;

    try {
      current = await _finalizeCpuTicket(current);
    } on OnlineTransportException {
      rethrow;
    } catch (_) {
      // Firebase's transaction-side `now` can trail the offset-derived client
      // clock by a few milliseconds. It can also reject CPU fallback because
      // a human resolution won the race. One short bounded retry lets either
      // authoritative outcome become visible without extending matchmaking.
      await _delay(_quickServerDeadlineRetry);
      current = await _readOwnedTicket(current);
      final lateHuman = await _finalizeHumanClaimIfAvailable(current);
      if (lateHuman != null) return lateHuman;
      if (current.resolved) {
        final resolvedNow = await store.serverNowMs();
        await _removeOwnClaimAcceptance(current);
        return _resolutionFor(current, resolvedNow);
      }
      nowMs = await store.serverNowMs();
      current = await _finalizeCpuTicket(current);
    }

    final concurrentHuman = await _finalizeHumanClaimIfAvailable(current);
    if (concurrentHuman != null) return concurrentHuman;
    await _removeOwnClaimAcceptance(current);
    return _resolutionFor(current, nowMs);
  }

  QuickPopResolution? _resolutionFor(
    QuickPopQueueTicket ticket,
    int resolvedAtMs,
  ) {
    final roomId = ticket.roomId;
    if (roomId == null) return null;
    return switch (ticket.state) {
      QuickPopTicketState.matched => QuickPopResolution(
        ticketId: ticket.ticketId,
        roomId: roomId,
        kind: QuickPopResolutionKind.human,
        opponentUid: ticket.opponentUid,
        resolvedAtMs: resolvedAtMs,
        queueKey: ticket.queueKey,
        claimId: ticket.claimId,
      ),
      QuickPopTicketState.cpuFallback => QuickPopResolution(
        ticketId: ticket.ticketId,
        roomId: roomId,
        kind: QuickPopResolutionKind.cpu,
        resolvedAtMs: resolvedAtMs,
      ),
      QuickPopTicketState.waiting || QuickPopTicketState.cancelled => null,
    };
  }

  void _validateTicketOwner(QuickPopQueueTicket ticket) {
    if (ticket.uid != identity.uid ||
        ticket.queueKey != _validatedSegment(ticket.queueKey, 'queueKey')) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.invalidQueueTicket,
        'The Quick Pop ticket does not belong to this player.',
      );
    }
  }

  void _requireHost(OnlineRoomRecord room) {
    if (room.hostUid != identity.uid) {
      throw const OnlineTransportException(
        OnlineTransportErrorCode.notHost,
        'Only the room host can perform this action.',
      );
    }
  }

  String _queueKey(String mode, String matchFormat) =>
      '${_validatedSegment(mode, 'mode')}_${_validatedSegment(matchFormat, 'matchFormat')}';

  String _newConnectionId(String roomId, int nowMs) => _stableId(
    '$roomId|${identity.uid}|$nowMs|${_random.nextInt(0x7fffffff)}',
    prefix: 'c_',
  );

  static String _sharedQuickRoomId(
    QuickPopQueueTicket left,
    QuickPopQueueTicket right,
  ) {
    final ids = <String>[left.ticketId, right.ticketId]..sort();
    return _stableId('${left.queueKey}|${ids.join('|')}', prefix: 'quick_');
  }

  static String _sharedQuickClaimId(
    QuickPopQueueTicket left,
    QuickPopQueueTicket right,
  ) {
    final ids = <String>[left.ticketId, right.ticketId]..sort();
    return _stableId('${left.queueKey}|${ids.join('|')}', prefix: 'claim_');
  }

  static String _cpuQuickRoomId(QuickPopQueueTicket ticket) =>
      _stableId('${ticket.queueKey}|${ticket.ticketId}|cpu', prefix: 'quick_');

  static String _stableId(String source, {required String prefix}) {
    final digest = sha256.convert(utf8.encode(source)).toString();
    return '$prefix${digest.substring(0, 24)}';
  }
}

enum _JoinFenceRemoval { removed, absent, mismatched }

final class _QuickPopPair {
  const _QuickPopPair({required this.first, required this.second});

  final QuickPopQueueTicket first;
  final QuickPopQueueTicket second;

  QuickPopQueueTicket get leader => first;

  QuickPopQueueTicket opponentOf(String uid) {
    if (first.uid == uid) return second;
    if (second.uid == uid) return first;
    throw const OnlineTransportException(
      OnlineTransportErrorCode.invalidQueueTicket,
      'The player is not part of this deterministic Quick Pop pair.',
    );
  }
}

final class _RoomCodeReservation {
  const _RoomCodeReservation({
    required this.code,
    required this.roomId,
    required this.hostUid,
    required this.reservationId,
    required this.reservedAtMs,
    required this.expiresAtMs,
  });

  final RoomCode code;
  final String roomId;
  final String hostUid;
  final String reservationId;
  final int reservedAtMs;
  final int expiresAtMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'roomId': roomId,
    'hostUid': hostUid,
    'reservationId': reservationId,
    'state': 'reserved',
    'reservedAt': reservedAtMs,
    'expiresAt': expiresAtMs,
  };
}

String _validatedSegment(String value, String label) {
  final clean = value.trim();
  if (clean.isEmpty || RegExp(r'[.#$\[\]/]').hasMatch(clean)) {
    throw OnlineTransportException(
      OnlineTransportErrorCode.invalidPathSegment,
      '$label is not a safe realtime-database path segment.',
    );
  }
  return clean;
}

String _validatedDisplayName(String value) {
  final clean = value.trim();
  if (clean.isEmpty || clean.length > 24) {
    throw const OnlineTransportException(
      OnlineTransportErrorCode.invalidIdentity,
      'Display names must contain between 1 and 24 characters.',
    );
  }
  return clean;
}

String? _cleanOptional(String? value) {
  final clean = value?.trim();
  return clean == null || clean.isEmpty ? null : clean;
}
