import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/firebase_online_transport.dart';
import 'package:parchesepop/online_lobby.dart';
import 'package:parchesepop/online_transport.dart';
import 'package:parchesepop/online_transport_models.dart';

import 'support/in_memory_online_realtime_store.dart';

OnlineTransportClient _client(
  OnlineRealtimeStore store,
  String uid, {
  String? name,
  String? roomCode,
}) => OnlineTransportClient(
  store: store,
  identity: OnlineTransportIdentity(uid: uid, displayName: name ?? uid),
  roomCodeFactory: roomCode == null ? null : (_) => RoomCode.parse(roomCode),
);

final class _DeletionLifecycleStore
    implements OnlineRealtimeStore, OnlineRealtimeStoreLifecycle {
  _DeletionLifecycleStore(this.delegate);

  final InMemoryOnlineRealtimeStore delegate;
  bool failProfileDelete = false;
  int shutdownCount = 0;

  @override
  Future<Object?> read(String path) => delegate.read(path);

  @override
  Stream<Object?> watch(String path) => delegate.watch(path);

  @override
  Future<void> set(String path, Object? value) {
    if (failProfileDelete &&
        path.startsWith('$onlineTransportRoot/profiles/') &&
        value == null) {
      throw StateError('temporary network failure');
    }
    return delegate.set(path, value);
  }

  @override
  Future<void> update(String path, Map<String, Object?> values) {
    if (failProfileDelete &&
        path == onlineTransportRoot &&
        values.entries.any(
          (entry) => entry.key.startsWith('profiles/') && entry.value == null,
        )) {
      throw StateError('temporary network failure');
    }
    return delegate.update(path, values);
  }

  @override
  Future<OnlineStoreTransactionResult> transaction(
    String path,
    OnlineStoreTransactionUpdater updater,
  ) => delegate.transaction(path, updater);

  @override
  Future<void> setOnDisconnect(String path, Object? value) =>
      delegate.setOnDisconnect(path, value);

  @override
  Future<void> cancelOnDisconnect(String path) =>
      delegate.cancelOnDisconnect(path);

  @override
  Future<int> serverNowMs() => delegate.serverNowMs();

  @override
  Future<void> shutdown() async {
    shutdownCount++;
  }
}

void main() {
  test(
    'durable index cleans safe owned data after a full client restart',
    () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 1000);
      final host = _client(store, 'host', name: 'Host', roomCode: 'ABC234');
      final secondHost = _client(
        store,
        'host-2',
        name: 'Host 2',
        roomCode: 'DEF234',
      );
      final player = _client(store, 'player', name: 'Player');
      await host.syncProfile();
      await secondHost.syncProfile();
      await player.syncProfile();

      final room = await host.createRoom(
        visibility: RoomVisibility.private,
        mode: 'traditional',
        matchFormat: 'quickTable',
      );
      expect(
        await store.read(
          '$onlineTransportRoot/$onlineAccountResourcesNode/host/'
          'hostedRooms/${room.id}',
        ),
        isNotNull,
      );
      final join = await player.requestRoomJoinByCode(room.code.value);
      await host.admitPendingJoinRequests(room.id);
      await player.waitForRoomAdmission(join);

      final pendingRoom = await secondHost.createRoom(
        visibility: RoomVisibility.private,
        mode: 'traditional',
        matchFormat: 'quickTable',
      );
      await player.requestRoomJoinByCode(pendingRoom.code.value);

      store.clearOperations();
      final ticket = await player.enqueueQuickPop(
        mode: 'traditional',
        matchFormat: 'quickPop',
      );
      expect(
        store.operations.where(
          (operation) =>
              operation.kind == InMemoryStoreOperationKind.update &&
              operation.path == onlineTransportRoot,
        ),
        hasLength(1),
        reason: 'queue ticket and durable UID index must be one atomic update',
      );
      expect(
        await store.read(
          '$onlineTransportRoot/$onlineAccountResourcesNode/player/'
          'presence/${room.id}',
        ),
        isNotNull,
      );
      await store.set(
        '$onlineTransportRoot/quickQueues/${ticket.queueKey}/other',
        QuickPopQueueTicket(
          ticketId: 'ticket_other',
          uid: 'other',
          displayName: 'Other',
          queueKey: ticket.queueKey,
          joinedAtMs: 1000,
          deadlineAtMs: 6000,
        ).toJson(),
      );

      // A fresh transport has no in-memory leases, join requests, or tickets.
      final restartedPlayer = _client(store, 'player', name: 'Player');
      final report = await restartedPlayer.deleteOwnOnlineData();

      expect(report.profileRemoved, isTrue);
      expect(report.queueTicketsRemoved, 1);
      expect(report.pendingJoinsRemoved, 1);
      expect(report.waitingMembershipsRemoved, 1);
      expect(report.presencesDisconnected, 1);
      expect(report.resourceIndexRemoved, isTrue);
      expect(await store.read('$onlineTransportRoot/profiles/player'), isNull);
      expect(
        await store.read(
          '$onlineTransportRoot/quickQueues/${ticket.queueKey}/player',
        ),
        isNull,
      );
      expect(
        await store.read(
          '$onlineTransportRoot/quickQueues/${ticket.queueKey}/other',
        ),
        isNotNull,
      );
      expect(
        await store.read(
          '$onlineTransportRoot/rooms/${room.id}/members/player',
        ),
        isNull,
      );
      expect(
        await store.read('$onlineTransportRoot/rooms/${room.id}/members/host'),
        isNotNull,
      );
      expect(
        await store.read(
          '$onlineTransportRoot/joinRequests/${pendingRoom.id}/player',
        ),
        isNull,
      );
      expect(
        await store.read(
          '$onlineTransportRoot/$onlineAccountResourcesNode/player',
        ),
        isNull,
      );
    },
  );

  test('resolved ticket and active-match ownership are preserved', () async {
    final store = InMemoryOnlineRealtimeStore(initialNowMs: 5000);
    final player = _client(store, 'player', name: 'Player');
    await player.syncProfile();
    await store.set(
      '$onlineTransportRoot/quickQueues/traditional_quickPop/player',
      const QuickPopQueueTicket(
        ticketId: 'ticket_resolved',
        uid: 'player',
        displayName: 'Player',
        queueKey: 'traditional_quickPop',
        joinedAtMs: 0,
        deadlineAtMs: 5000,
        state: QuickPopTicketState.matched,
        claimId: 'claim_resolved',
        roomId: 'room_resolved',
        opponentUid: 'other',
      ).toJson(),
    );

    final report = await player.deleteOwnOnlineData();

    expect(report.resolvedTicketsPreserved, 1);
    expect(
      await store.read(
        '$onlineTransportRoot/quickQueues/traditional_quickPop/player',
      ),
      isNotNull,
    );
  });

  test(
    'active shared room is disconnected but never deleted after restart',
    () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 8000);
      final host = _client(store, 'host', name: 'Host', roomCode: 'XYZ234');
      final player = _client(store, 'player', name: 'Player');
      await host.syncProfile();
      await player.syncProfile();
      final room = await host.createRoom(
        visibility: RoomVisibility.private,
        mode: 'traditional',
        matchFormat: 'quickTable',
      );
      final join = await player.requestRoomJoinByCode(room.code.value);
      await host.admitPendingJoinRequests(room.id);
      await player.waitForRoomAdmission(join);
      final active = onlineMap(
        await store.read('$onlineTransportRoot/rooms/${room.id}'),
      )..['status'] = RoomStatus.inGame.name;
      await store.set('$onlineTransportRoot/rooms/${room.id}', active);

      final restarted = _client(store, 'player', name: 'Player');
      final report = await restarted.deleteOwnOnlineData();

      expect(report.waitingMembershipsRemoved, 0);
      expect(
        await store.read(
          '$onlineTransportRoot/rooms/${room.id}/members/player',
        ),
        isNotNull,
      );
      expect(
        onlineMap(
          await store.read(
            '$onlineTransportRoot/rooms/${room.id}/presence/player',
          ),
        )['state'],
        LobbyPresence.disconnected.name,
      );
      expect(
        await store.read('$onlineTransportRoot/rooms/${room.id}/members/host'),
        isNotNull,
      );
    },
  );

  test(
    'legacy profile without complete index blocks Auth-safe cleanup',
    () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 9000);
      await store.set('$onlineTransportRoot/profiles/player', {
        'uid': 'player',
        'displayName': 'Legacy',
        'createdAt': 1,
        'updatedAt': 1,
      });
      final player = _client(store, 'player', name: 'Legacy');
      await player.syncProfile();

      await expectLater(
        player.deleteOwnOnlineData(),
        throwsA(isA<OnlineAccountCleanupRequiresBackend>()),
      );
      expect(
        await store.read('$onlineTransportRoot/profiles/player'),
        isNotNull,
      );
      expect(
        onlineMap(
          await store.read(
            '$onlineTransportRoot/$onlineAccountResourcesNode/player',
          ),
        )['requiresBackendCleanup'],
        isTrue,
      );
    },
  );

  test('identity deletion runs only after cleanup and shutdown', () async {
    final base = InMemoryOnlineRealtimeStore(initialNowMs: 1000);
    final store = _DeletionLifecycleStore(base);
    final player = _client(store, 'player', name: 'Player');
    await player.syncProfile();
    var identityDeleted = false;
    final coordinator = OnlineAnonymousAccountDeletionCoordinator(
      transports: [player],
      deleteAnonymousIdentity: () async {
        expect(await base.read('$onlineTransportRoot/profiles/player'), isNull);
        expect(store.shutdownCount, 1);
        identityDeleted = true;
      },
    );

    await coordinator.delete();

    expect(identityDeleted, isTrue);
  });

  test('cleanup failure keeps identity and can be retried', () async {
    final base = InMemoryOnlineRealtimeStore(initialNowMs: 1000);
    final store = _DeletionLifecycleStore(base)..failProfileDelete = true;
    final player = _client(store, 'player', name: 'Player');
    await player.syncProfile();
    var identityDeleteCalls = 0;

    final first = OnlineAnonymousAccountDeletionCoordinator(
      transports: [player],
      deleteAnonymousIdentity: () async => identityDeleteCalls++,
    );
    await expectLater(
      first.delete(),
      throwsA(
        isA<OnlineAccountDeletionException>().having(
          (error) => error.code,
          'code',
          OnlineAccountDeletionErrorCode.cleanupFailed,
        ),
      ),
    );
    expect(identityDeleteCalls, 0);
    expect(store.shutdownCount, 0);

    store.failProfileDelete = false;
    final retry = OnlineAnonymousAccountDeletionCoordinator(
      transports: [player],
      deleteAnonymousIdentity: () async => identityDeleteCalls++,
    );
    await retry.delete();
    expect(identityDeleteCalls, 1);
    expect(store.shutdownCount, 1);
  });

  test('legacy cleanup reports a non-retryable backend requirement', () async {
    final base = InMemoryOnlineRealtimeStore(initialNowMs: 1000);
    await base.set('$onlineTransportRoot/profiles/player', {
      'uid': 'player',
      'displayName': 'Legacy',
      'createdAt': 1,
      'updatedAt': 1,
    });
    final player = _client(base, 'player', name: 'Legacy');
    await player.syncProfile();
    var identityDeleteCalls = 0;
    final coordinator = OnlineAnonymousAccountDeletionCoordinator(
      transports: [player],
      deleteAnonymousIdentity: () async => identityDeleteCalls++,
    );

    await expectLater(
      coordinator.delete(),
      throwsA(
        isA<OnlineAccountDeletionException>().having(
          (error) => error.code,
          'code',
          OnlineAccountDeletionErrorCode.backendCleanupRequired,
        ),
      ),
    );
    expect(identityDeleteCalls, 0);
  });
}
