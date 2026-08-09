import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/online_lobby.dart';
import 'package:parchesepop/online_transport.dart';
import 'package:parchesepop/online_transport_models.dart';

import 'support/in_memory_online_realtime_store.dart';

OnlineTransportClient _client(
  OnlineRealtimeStore store,
  String uid,
  String name, {
  int seed = 1,
  OnlineRoomCodeFactory? codeFactory,
  OnlineDelay? delay,
}) => OnlineTransportClient(
  store: store,
  identity: OnlineTransportIdentity(uid: uid, displayName: name),
  random: Random(seed),
  roomCodeFactory: codeFactory,
  delay: delay,
);

Matcher _transportError(OnlineTransportErrorCode code) =>
    isA<OnlineTransportException>().having((error) => error.code, 'code', code);

final class _DelayedClaimCreationStore implements OnlineRealtimeStore {
  _DelayedClaimCreationStore(this.delegate, {this.rejectAfterRelease = false});

  final OnlineRealtimeStore delegate;
  final bool rejectAfterRelease;
  final Completer<void> claimCreationStarted = Completer<void>();
  final Completer<void> releaseClaimCreation = Completer<void>();
  bool _delayed = false;

  bool _isClaimRoot(String path) {
    final prefix = '$onlineTransportRoot/quickClaims/';
    if (!path.startsWith(prefix)) return false;
    return path.substring(prefix.length).split('/').length == 2;
  }

  @override
  Future<Object?> read(String path) => delegate.read(path);

  @override
  Stream<Object?> watch(String path) => delegate.watch(path);

  @override
  Future<void> set(String path, Object? value) => delegate.set(path, value);

  @override
  Future<void> update(String path, Map<String, Object?> values) =>
      delegate.update(path, values);

  @override
  Future<OnlineStoreTransactionResult> transaction(
    String path,
    OnlineStoreTransactionUpdater updater,
  ) async {
    if (!_delayed && _isClaimRoot(path)) {
      _delayed = true;
      claimCreationStarted.complete();
      await releaseClaimCreation.future;
      if (rejectAfterRelease) {
        throw StateError('simulated claim permission denial after CPU');
      }
    }
    return delegate.transaction(path, updater);
  }

  @override
  Future<void> setOnDisconnect(String path, Object? value) =>
      delegate.setOnDisconnect(path, value);

  @override
  Future<void> cancelOnDisconnect(String path) =>
      delegate.cancelOnDisconnect(path);

  @override
  Future<int> serverNowMs() => delegate.serverNowMs();
}

final class _RejectFirstCpuFallbackStore implements OnlineRealtimeStore {
  _RejectFirstCpuFallbackStore(this.delegate, {this.beforeReject});

  final OnlineRealtimeStore delegate;
  final Future<void> Function()? beforeReject;
  bool rejected = false;

  bool _isQuickQueueTicket(String path) {
    final prefix = '$onlineTransportRoot/quickQueues/';
    if (!path.startsWith(prefix)) return false;
    return path.substring(prefix.length).split('/').length == 2;
  }

  @override
  Future<Object?> read(String path) => delegate.read(path);

  @override
  Stream<Object?> watch(String path) => delegate.watch(path);

  @override
  Future<void> set(String path, Object? value) => delegate.set(path, value);

  @override
  Future<void> update(String path, Map<String, Object?> values) =>
      delegate.update(path, values);

  @override
  Future<OnlineStoreTransactionResult> transaction(
    String path,
    OnlineStoreTransactionUpdater updater,
  ) async {
    if (!rejected && _isQuickQueueTicket(path)) {
      final current = await delegate.read(path);
      final decision = updater(current);
      if (decision is OnlineStoreCommit &&
          onlineMap(decision.value)['state'] ==
              QuickPopTicketState.cpuFallback.name) {
        rejected = true;
        await beforeReject?.call();
        throw StateError('simulated Firebase deadline permission denial');
      }
    }
    return delegate.transaction(path, updater);
  }

  @override
  Future<void> setOnDisconnect(String path, Object? value) =>
      delegate.setOnDisconnect(path, value);

  @override
  Future<void> cancelOnDisconnect(String path) =>
      delegate.cancelOnDisconnect(path);

  @override
  Future<int> serverNowMs() => delegate.serverNowMs();
}

final class _RejectExpiredClaimedWaitingRewriteStore
    implements OnlineRealtimeStore {
  _RejectExpiredClaimedWaitingRewriteStore(this.delegate);

  final OnlineRealtimeStore delegate;
  int rejectedRewrites = 0;

  bool _isQuickQueueTicket(String path) {
    final prefix = '$onlineTransportRoot/quickQueues/';
    if (!path.startsWith(prefix)) return false;
    return path.substring(prefix.length).split('/').length == 2;
  }

  @override
  Future<Object?> read(String path) => delegate.read(path);

  @override
  Stream<Object?> watch(String path) => delegate.watch(path);

  @override
  Future<void> set(String path, Object? value) => delegate.set(path, value);

  @override
  Future<void> update(String path, Map<String, Object?> values) =>
      delegate.update(path, values);

  @override
  Future<OnlineStoreTransactionResult> transaction(
    String path,
    OnlineStoreTransactionUpdater updater,
  ) async {
    if (_isQuickQueueTicket(path)) {
      final current = onlineMap(await delegate.read(path));
      final deadlineAt = current['deadlineAt'];
      if (current['state'] == QuickPopTicketState.waiting.name &&
          current['claimId'] is String &&
          deadlineAt is num &&
          await delegate.serverNowMs() >= deadlineAt.toInt()) {
        final decision = updater(current);
        if (decision is OnlineStoreCommit &&
            onlineMap(decision.value)['state'] ==
                QuickPopTicketState.waiting.name) {
          rejectedRewrites++;
          throw StateError(
            'simulated Firebase rejection of an expired claimed rewrite',
          );
        }
      }
    }
    return delegate.transaction(path, updater);
  }

  @override
  Future<void> setOnDisconnect(String path, Object? value) =>
      delegate.setOnDisconnect(path, value);

  @override
  Future<void> cancelOnDisconnect(String path) =>
      delegate.cancelOnDisconnect(path);

  @override
  Future<int> serverNowMs() => delegate.serverNowMs();
}

void main() {
  group('profile synchronization', () {
    test('preserves creation time while updating the shared profile', () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 100);
      final first = _client(store, 'player-a', 'Ana');
      final initial = await first.syncProfile();

      store.setNowMs(250);
      final renamed = _client(store, 'player-a', 'Ana Pop');
      final updated = await renamed.syncProfile();

      expect(initial.createdAtMs, 100);
      expect(updated.createdAtMs, 100);
      expect(updated.updatedAtMs, 250);
      expect(updated.displayName, 'Ana Pop');
      expect(
        await renamed.watchProfile('player-a').first,
        isA<SyncedOnlineProfile>().having(
          (profile) => profile.displayName,
          'display name',
          'Ana Pop',
        ),
      );
    });
  });

  group('room transport', () {
    test(
      'reserves unique room codes without overwriting a live code',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 1000);
        final first = _client(
          store,
          'host-a',
          'Host A',
          seed: 10,
          codeFactory: (_) => RoomCode.parse('ABCDEF'),
        );
        final candidateCodes = <String>['ABCDEF', 'GHJKLM'];
        final second = _client(
          store,
          'host-b',
          'Host B',
          seed: 20,
          codeFactory: (_) => RoomCode.parse(candidateCodes.removeAt(0)),
        );

        final firstRoom = await first.createRoom(
          visibility: RoomVisibility.private,
          mode: 'classic',
          matchFormat: 'traditional',
        );
        final secondRoom = await second.createRoom(
          visibility: RoomVisibility.private,
          mode: 'classic',
          matchFormat: 'traditional',
        );

        expect(firstRoom.code.value, 'ABCDEF');
        expect(secondRoom.code.value, 'GHJKLM');
        final firstPointer = onlineMap(
          await store.read('$onlineTransportRoot/roomCodes/ABCDEF'),
        );
        final secondPointer = onlineMap(
          await store.read('$onlineTransportRoot/roomCodes/GHJKLM'),
        );
        expect(firstPointer['roomId'], firstRoom.id);
        expect(secondPointer['roomId'], secondRoom.id);
        expect(firstPointer['state'], 'active');
        expect(secondPointer['state'], 'active');
      },
    );

    test(
      'create, join, ready, privacy, leave, watch, and close agree',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 2000);
        final host = _client(
          store,
          'red-player',
          'Red',
          seed: 1,
          codeFactory: (_) => RoomCode.parse('PAPP24'),
        );
        final green = _client(store, 'green-player', 'Green', seed: 2);
        final yellow = _client(store, 'yellow-player', 'Yellow', seed: 3);
        final blue = _client(store, 'blue-player', 'Blue', seed: 4);

        final room = await host.createRoom(
          visibility: RoomVisibility.public,
          mode: 'chaos',
          matchFormat: 'traditional',
        );
        expect((await host.listPublicRooms()).single.roomId, room.id);

        store.advance(const Duration(milliseconds: 10));
        store.clearOperations();
        final greenRequest = await green.requestRoomJoinByCode('papp-24');
        expect(
          store.operations,
          contains(
            isA<InMemoryStoreOperation>()
                .having(
                  (operation) => operation.kind,
                  'kind',
                  InMemoryStoreOperationKind.update,
                )
                .having(
                  (operation) => operation.path,
                  'atomic online root',
                  onlineTransportRoot,
                ),
          ),
        );
        expect(
          await store.read(
            '$onlineTransportRoot/$onlineAccountResourcesNode/green-player/'
            'joinRequests/${room.id}',
          ),
          greenRequest.toJson(),
        );
        expect(
          store.operations.where(
            (operation) =>
                operation.kind == InMemoryStoreOperationKind.transaction &&
                operation.path == '$onlineTransportRoot/rooms/${room.id}',
          ),
          isEmpty,
        );
        await host.admitPendingJoinRequests(room.id);
        await green.waitForRoomAdmission(greenRequest);
        store.advance(const Duration(milliseconds: 10));
        final yellowRequest = await yellow.requestRoomJoinByCode('PAPP24');
        await host.admitPendingJoinRequests(room.id);
        await yellow.waitForRoomAdmission(yellowRequest);
        store.advance(const Duration(milliseconds: 10));
        final blueRequest = await blue.requestRoomJoinByCode('PAPP24');
        await host.admitPendingJoinRequests(room.id);
        final full = await blue.waitForRoomAdmission(blueRequest);

        expect(
          full.lobbyParticipants.map((participant) => participant.seat),
          LobbySeatColor.values,
        );
        expect(await host.listPublicRooms(), isEmpty);
        expect(
          await store.read('$onlineTransportRoot/publicRooms/${room.id}'),
          isNull,
        );

        await host.updateReady(roomId: room.id, ready: true);
        await green.updateReady(roomId: room.id, ready: true);
        await yellow.updateReady(roomId: room.id, ready: true);
        final allReady = await blue.updateReady(roomId: room.id, ready: true);
        expect(allReady.members.values.every((member) => member.ready), isTrue);
        expect(
          await host.watchRoom(room.id).first,
          isA<OnlineRoomRecord>().having(
            (record) => record.members.length,
            'member count',
            4,
          ),
        );

        final afterLeave = await blue.leaveRoom(room.id);
        expect(afterLeave.members, isNot(contains('blue-player')));
        await host.admitPendingJoinRequests(room.id);
        expect((await host.listPublicRooms()).single.occupiedSeatCount, 3);

        final privateRoom = await host.updatePrivacy(
          roomId: room.id,
          visibility: RoomVisibility.private,
        );
        expect(privateRoom.visibility, RoomVisibility.private);
        expect(await host.listPublicRooms(), isEmpty);
        await expectLater(
          green.updatePrivacy(
            roomId: room.id,
            visibility: RoomVisibility.public,
          ),
          throwsA(_transportError(OnlineTransportErrorCode.notHost)),
        );

        final publicAgain = await host.updatePrivacy(
          roomId: room.id,
          visibility: RoomVisibility.public,
        );
        expect(publicAgain.visibility, RoomVisibility.public);
        expect((await host.listPublicRooms()).single.roomId, room.id);

        final closed = await host.closeRoom(room.id);
        expect(closed.status, RoomStatus.closed);
        expect(await host.listPublicRooms(), isEmpty);
        await expectLater(
          blue.joinRoomByCode('PAPP24'),
          throwsA(_transportError(OnlineTransportErrorCode.roomNotFound)),
        );
      },
    );

    test(
      'room-root mutations preserve realtime synchronizer children',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 2600);
        final host = _client(
          store,
          'preserving-host',
          'Host',
          codeFactory: (_) => RoomCode.parse('KEEP24'),
        );
        final guest = _client(store, 'preserving-guest', 'Guest');
        final room = await host.createRoom(
          visibility: RoomVisibility.private,
          mode: 'classic',
          matchFormat: 'quickTable',
        );
        final roomPath = '$onlineTransportRoot/rooms/${room.id}';
        final nestedChildren = <String, Object?>{
          'lobbyState': <String, Object?>{'revision': 7},
          'openingRollRequests': <String, Object?>{
            'someone': <String, Object?>{'round': 1},
          },
          'commands': <String, Object?>{
            'someone': <String, Object?>{'action': true},
          },
          'match': <String, Object?>{'stateRevision': 3},
        };
        for (final entry in nestedChildren.entries) {
          await store.set('$roomPath/${entry.key}', entry.value);
        }

        final request = await guest.requestRoomJoinByCode('KEEP24');
        await host.admitPendingJoinRequests(room.id);
        await guest.waitForRoomAdmission(request);
        await host.updatePrivacy(
          roomId: room.id,
          visibility: RoomVisibility.public,
        );

        final raw = onlineMap(await store.read(roomPath));
        for (final entry in nestedChildren.entries) {
          expect(raw[entry.key], entry.value, reason: entry.key);
        }
      },
    );

    test('on-disconnect presence is visible to every room watcher', () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 3000);
      final host = _client(
        store,
        'host',
        'Host',
        codeFactory: (_) => RoomCode.parse('PRES24'),
      );
      final room = await host.createRoom(
        visibility: RoomVisibility.private,
        mode: 'classic',
        matchFormat: 'traditional',
      );
      final path =
          '$onlineTransportRoot/rooms/${room.id}/presence/${host.identity.uid}';

      await store.simulateDisconnect(path: path);

      final disconnected = await host.watchRoom(room.id).first;
      expect(
        disconnected?.presenceFor(host.identity.uid),
        LobbyPresence.disconnected,
      );
    });

    test('host maintenance admits join-by-code and can be cancelled', () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 4000);
      final host = _client(
        store,
        'maintaining-host',
        'Host',
        seed: 41,
        codeFactory: (_) => RoomCode.parse('HAST24'),
      );
      final guest = _client(store, 'joining-guest', 'Guest', seed: 42);
      final room = await host.createRoom(
        visibility: RoomVisibility.public,
        mode: 'classic',
        matchFormat: 'traditional',
      );
      final errors = <Object>[];
      final maintenance = await host.maintainHostedRoom(
        room.id,
        onError: (error, _) => errors.add(error),
      );

      final joined = await guest.joinRoomByCode(
        room.code.value,
        timeout: const Duration(seconds: 2),
      );
      await maintenance.close();

      expect(joined.members, contains('joining-guest'));
      expect(errors, isEmpty);
    });

    test('a timed-out join request is removed from the queue', () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 5000);
      final host = _client(
        store,
        'timeout-host',
        'Host',
        codeFactory: (_) => RoomCode.parse('TYME24'),
      );
      final guest = _client(
        store,
        'timeout-guest',
        'Guest',
        delay: (duration) async => store.advance(duration),
      );
      final room = await host.createRoom(
        visibility: RoomVisibility.private,
        mode: 'classic',
        matchFormat: 'quickTable',
      );
      final request = await guest.requestRoomJoinByCode(room.code.value);

      await expectLater(
        guest.waitForRoomAdmission(
          request,
          timeout: const Duration(seconds: 1),
          pollInterval: const Duration(milliseconds: 200),
        ),
        throwsA(_transportError(OnlineTransportErrorCode.joinTimedOut)),
      );
      expect(
        await store.read(
          '$onlineTransportRoot/joinRequests/${room.id}/timeout-guest',
        ),
        isNull,
      );
    });

    test(
      'a cancelled join request cannot leave a pending queue entry',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 6000);
        final host = _client(
          store,
          'cancel-host',
          'Host',
          codeFactory: (_) => RoomCode.parse('STAP24'),
        );
        final guest = _client(store, 'cancel-guest', 'Guest');
        final room = await host.createRoom(
          visibility: RoomVisibility.private,
          mode: 'classic',
          matchFormat: 'quickTable',
        );
        final request = await guest.requestRoomJoinByCode(room.code.value);

        await expectLater(
          guest.waitForRoomAdmission(request, cancelled: () => true),
          throwsA(_transportError(OnlineTransportErrorCode.joinCancelled)),
        );
        expect(
          await store.read(
            '$onlineTransportRoot/joinRequests/${room.id}/cancel-guest',
          ),
          isNull,
        );
        expect(
          (await host.readRoom(room.id))?.members,
          isNot(contains('cancel-guest')),
        );
      },
    );

    test('a guest can detach cleanly after the host closes the room', () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 7000);
      final host = _client(
        store,
        'closed-host',
        'Host',
        codeFactory: (_) => RoomCode.parse('CLAS24'),
      );
      final guest = _client(store, 'closed-guest', 'Guest');
      final room = await host.createRoom(
        visibility: RoomVisibility.private,
        mode: 'classic',
        matchFormat: 'quickTable',
      );
      final request = await guest.requestRoomJoinByCode(room.code.value);
      await host.admitPendingJoinRequests(room.id);
      await guest.waitForRoomAdmission(request);
      await host.closeRoom(room.id);

      final detached = await guest.leaveRoom(room.id);

      expect(detached.status, RoomStatus.closed);
      expect(detached.members, contains('closed-guest'));
      final latest = await host.readRoom(room.id);
      expect(latest?.presenceFor('closed-guest'), LobbyPresence.disconnected);
    });
  });

  group('Quick Pop queue', () {
    test('two searches receive the same deterministic human room', () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 10_000);
      final first = _client(store, 'first', 'First', seed: 11);
      final second = _client(store, 'second', 'Second', seed: 12);
      final firstTicket = await first.enqueueQuickPop(mode: 'classic');
      store.advance(const Duration(seconds: 1));
      final secondTicket = await second.enqueueQuickPop(mode: 'classic');

      store.clearOperations();
      expect(await first.resolveQuickPop(firstTicket), isNull);
      expect(
        store.operations.where(
          (operation) =>
              operation.kind == InMemoryStoreOperationKind.transaction &&
              operation.path ==
                  '$onlineTransportRoot/quickQueues/${firstTicket.queueKey}',
        ),
        isEmpty,
      );
      expect(
        store.operations,
        isNot(
          contains(
            isA<InMemoryStoreOperation>().having(
              (operation) => operation.path,
              'premature claim or acceptance path',
              startsWith(
                '$onlineTransportRoot/quickClaims/${firstTicket.queueKey}/',
              ),
            ),
          ),
        ),
      );
      expect(await second.resolveQuickPop(secondTicket), isNull);
      expect(await first.resolveQuickPop(firstTicket), isNull);
      final secondResolution = await second.resolveQuickPop(secondTicket);
      final firstResolution = await first.resolveQuickPop(firstTicket);

      expect(firstResolution?.kind, QuickPopResolutionKind.human);
      expect(secondResolution?.kind, QuickPopResolutionKind.human);
      expect(firstResolution?.roomId, secondResolution?.roomId);
      expect(firstResolution?.opponentUid, 'second');
      expect(secondResolution?.opponentUid, 'first');
      expect(firstResolution?.roomId, startsWith('quick_'));
    });

    test('follower waits for the exact leader claim before accepting', () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 12_000);
      final delayedLeaderStore = _DelayedClaimCreationStore(store);
      final leader = _client(delayedLeaderStore, 'leader', 'Leader', seed: 13);
      final follower = _client(store, 'follower', 'Follower', seed: 14);
      final leaderTicket = await leader.enqueueQuickPop(mode: 'classic');
      store.advance(const Duration(milliseconds: 100));
      final followerTicket = await follower.enqueueQuickPop(mode: 'classic');

      expect(await leader.resolveQuickPop(leaderTicket), isNull);
      expect(await follower.resolveQuickPop(followerTicket), isNull);
      final pendingLeaderResolution = leader.resolveQuickPop(leaderTicket);
      await delayedLeaderStore.claimCreationStarted.future;

      expect(await follower.resolveQuickPop(followerTicket), isNull);
      final followerCurrent = QuickPopQueueTicket.fromJson(
        await store.read(
          '$onlineTransportRoot/quickQueues/'
          '${followerTicket.queueKey}/${followerTicket.uid}',
        ),
        uid: followerTicket.uid,
      );
      final claimId = followerCurrent.claimId;
      expect(claimId, isNotNull);
      final claimPath =
          '$onlineTransportRoot/quickClaims/${followerTicket.queueKey}/$claimId';
      expect(await store.read(claimPath), isNull);
      expect(
        store.operations.where(
          (operation) =>
              operation.kind == InMemoryStoreOperationKind.set &&
              operation.path == '$claimPath/acceptances/${followerTicket.uid}',
        ),
        isEmpty,
      );

      delayedLeaderStore.releaseClaimCreation.complete();
      expect(await pendingLeaderResolution, isNull);
      final followerResolution = await follower.resolveQuickPop(followerTicket);
      final leaderResolution = await leader.resolveQuickPop(leaderTicket);

      expect(leaderResolution?.kind, QuickPopResolutionKind.human);
      expect(followerResolution?.kind, QuickPopResolutionKind.human);
      expect(leaderResolution?.roomId, followerResolution?.roomId);
    });

    test(
      'a staggered accepted claim resolves after the leader deadline',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 50_000);
        final guardedLeaderStore = _RejectExpiredClaimedWaitingRewriteStore(
          store,
        );
        final leader = _client(
          guardedLeaderStore,
          'production-leader',
          'Leader',
          seed: 501,
        );
        final follower = _client(
          store,
          'production-follower',
          'Follower',
          seed: 502,
        );
        final leaderTicket = await leader.enqueueQuickPop(mode: 'traditional');
        store.advance(const Duration(milliseconds: 2881));
        final followerTicket = await follower.enqueueQuickPop(
          mode: 'traditional',
        );

        // Both clients bind to the same deterministic claim, then the leader
        // creates it and publishes the first acceptance.
        expect(await leader.resolveQuickPop(leaderTicket), isNull);
        expect(await follower.resolveQuickPop(followerTicket), isNull);
        store.advance(const Duration(milliseconds: 913));
        expect(await leader.resolveQuickPop(leaderTicket), isNull);

        // Reproduce the production timing: the reciprocal acceptance crosses
        // the network after the leader's five seconds, but still before the
        // follower's own deadline.
        store.setNowMs(leaderTicket.deadlineAtMs + 1536);
        store.clearOperations();
        expect(await leader.resolveQuickPop(leaderTicket), isNull);
        final leaderTicketPath =
            '$onlineTransportRoot/quickQueues/${leaderTicket.queueKey}/'
            '${leaderTicket.uid}';
        expect(
          store.operations.where(
            (operation) =>
                operation.kind == InMemoryStoreOperationKind.transaction &&
                operation.path == leaderTicketPath,
          ),
          isEmpty,
          reason: 'an already attached expired ticket must never be rewritten',
        );
        expect(guardedLeaderStore.rejectedRewrites, 0);

        final followerResolution = await follower.resolveQuickPop(
          followerTicket,
        );
        final leaderResolution = await leader.resolveQuickPop(leaderTicket);

        expect(followerResolution?.kind, QuickPopResolutionKind.human);
        expect(leaderResolution?.kind, QuickPopResolutionKind.human);
        expect(followerResolution?.roomId, leaderResolution?.roomId);
        expect(followerResolution?.opponentUid, leaderTicket.uid);
        expect(leaderResolution?.opponentUid, followerTicket.uid);
      },
    );

    test(
      'a late rejected leader claim lets both expired tickets use CPU',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 13_000);
        final delayedLeaderStore = _DelayedClaimCreationStore(
          store,
          rejectAfterRelease: true,
        );
        final leader = _client(
          delayedLeaderStore,
          'late-leader',
          'Leader',
          seed: 131,
        );
        final follower = _client(store, 'late-follower', 'Follower', seed: 132);
        final leaderTicket = await leader.enqueueQuickPop(mode: 'classic');
        store.advance(const Duration(milliseconds: 100));
        final followerTicket = await follower.enqueueQuickPop(mode: 'classic');

        expect(await leader.resolveQuickPop(leaderTicket), isNull);
        expect(await follower.resolveQuickPop(followerTicket), isNull);
        final pendingLeader = leader.resolveQuickPop(leaderTicket);
        await delayedLeaderStore.claimCreationStarted.future;

        store.setNowMs(followerTicket.deadlineAtMs);
        final followerResolution = await follower.resolveQuickPop(
          followerTicket,
        );
        expect(followerResolution?.kind, QuickPopResolutionKind.cpu);

        delayedLeaderStore.releaseClaimCreation.complete();
        final leaderResolution = await pendingLeader;
        expect(leaderResolution?.kind, QuickPopResolutionKind.cpu);
        expect(
          await store.read(
            '$onlineTransportRoot/quickClaims/${leaderTicket.queueKey}',
          ),
          isNull,
        );
      },
    );

    test(
      'an inactive leader without a claim cannot block follower CPU fallback',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 14_000);
        final inactiveLeader = _client(
          store,
          'inactive-leader',
          'Inactive',
          seed: 15,
        );
        final follower = _client(store, 'active-follower', 'Active', seed: 16);
        await inactiveLeader.enqueueQuickPop(mode: 'classic');
        store.advance(const Duration(milliseconds: 100));
        final followerTicket = await follower.enqueueQuickPop(mode: 'classic');

        expect(await follower.resolveQuickPop(followerTicket), isNull);
        final claimedFollower = QuickPopQueueTicket.fromJson(
          await store.read(
            '$onlineTransportRoot/quickQueues/'
            '${followerTicket.queueKey}/${followerTicket.uid}',
          ),
          uid: followerTicket.uid,
        );
        expect(claimedFollower.claimId, isNotNull);
        final claimPath =
            '$onlineTransportRoot/quickClaims/${followerTicket.queueKey}/'
            '${claimedFollower.claimId}';
        expect(await store.read(claimPath), isNull);
        store.clearOperations();
        store.setNowMs(followerTicket.deadlineAtMs);
        final resolution = await follower.resolveQuickPop(followerTicket);

        expect(resolution?.kind, QuickPopResolutionKind.cpu);
        expect(resolution?.resolvedAtMs, followerTicket.deadlineAtMs);
        expect(
          QuickPopQueueTicket.fromJson(
            await store.read(
              '$onlineTransportRoot/quickQueues/'
              '${followerTicket.queueKey}/${followerTicket.uid}',
            ),
            uid: followerTicket.uid,
          ).state,
          QuickPopTicketState.cpuFallback,
        );
        expect(
          store.operations.where(
            (operation) =>
                operation.kind == InMemoryStoreOperationKind.set &&
                operation.path ==
                    '$claimPath/acceptances/${followerTicket.uid}',
          ),
          isEmpty,
        );
      },
    );

    test('a claimed ticket cannot be stolen by a later third player', () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 16_000);
      final originalLeader = _client(store, 'original-leader', 'Leader');
      final claimedPlayer = _client(store, 'claimed-player', 'Claimed');
      final thirdPlayer = _client(store, 'third-player', 'Third');
      final leaderTicket = await originalLeader.enqueueQuickPop(
        mode: 'classic',
      );
      store.advance(const Duration(milliseconds: 100));
      final claimedTicket = await claimedPlayer.enqueueQuickPop(
        mode: 'classic',
      );

      expect(await originalLeader.resolveQuickPop(leaderTicket), isNull);
      expect(await claimedPlayer.resolveQuickPop(claimedTicket), isNull);
      final boundTicket = QuickPopQueueTicket.fromJson(
        await store.read(
          '$onlineTransportRoot/quickQueues/'
          '${claimedTicket.queueKey}/${claimedTicket.uid}',
        ),
        uid: claimedTicket.uid,
      );
      expect(boundTicket.claimId, isNotNull);
      await originalLeader.cancelQuickPop(leaderTicket);

      store.advance(const Duration(milliseconds: 100));
      final thirdTicket = await thirdPlayer.enqueueQuickPop(mode: 'classic');
      expect(await claimedPlayer.resolveQuickPop(claimedTicket), isNull);
      expect(await thirdPlayer.resolveQuickPop(thirdTicket), isNull);
      final stillBound = QuickPopQueueTicket.fromJson(
        await store.read(
          '$onlineTransportRoot/quickQueues/'
          '${claimedTicket.queueKey}/${claimedTicket.uid}',
        ),
        uid: claimedTicket.uid,
      );
      expect(stillBound.claimId, boundTicket.claimId);

      store.setNowMs(claimedTicket.deadlineAtMs);
      final resolution = await claimedPlayer.resolveQuickPop(claimedTicket);
      expect(resolution?.kind, QuickPopResolutionKind.cpu);
      expect(resolution?.opponentUid, isNull);
    });

    test(
      'CPU fallback begins at exactly five seconds, never earlier',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 20_000);
        final player = _client(store, 'solo', 'Solo', seed: 20);
        final ticket = await player.enqueueQuickPop(mode: 'classic');

        store.setNowMs(ticket.deadlineAtMs - 1);
        expect(await player.resolveQuickPop(ticket), isNull);

        store.setNowMs(ticket.deadlineAtMs);
        final resolution = await player.resolveQuickPop(ticket);
        expect(resolution?.kind, QuickPopResolutionKind.cpu);
        expect(resolution?.resolvedAtMs, ticket.deadlineAtMs);
        expect(resolution?.opponentUid, isNull);
      },
    );

    test(
      'a server deadline denial is retried once after a bounded guard',
      () async {
        final baseStore = InMemoryOnlineRealtimeStore(initialNowMs: 25_000);
        final rejectingStore = _RejectFirstCpuFallbackStore(baseStore);
        var guardedMs = 0;
        final player = _client(
          rejectingStore,
          'skewed-solo',
          'Skewed Solo',
          seed: 25,
          delay: (duration) async {
            guardedMs += duration.inMilliseconds;
            baseStore.advance(duration);
          },
        );
        final ticket = await player.enqueueQuickPop(mode: 'classic');
        baseStore.setNowMs(ticket.deadlineAtMs);

        final resolution = await player.resolveQuickPop(ticket);

        expect(rejectingStore.rejected, isTrue);
        expect(guardedMs, 250);
        expect(resolution?.kind, QuickPopResolutionKind.cpu);
        expect(resolution?.resolvedAtMs, ticket.deadlineAtMs + 250);
      },
    );

    test(
      'a human arriving just before the deadline wins over CPU fallback',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 30_000);
        final first = _client(store, 'first-edge', 'First', seed: 30);
        final second = _client(store, 'second-edge', 'Second', seed: 31);
        final firstTicket = await first.enqueueQuickPop(mode: 'classic');
        store.setNowMs(firstTicket.deadlineAtMs - 1);
        final secondTicket = await second.enqueueQuickPop(mode: 'classic');

        expect(await first.resolveQuickPop(firstTicket), isNull);
        expect(await second.resolveQuickPop(secondTicket), isNull);
        expect(await first.resolveQuickPop(firstTicket), isNull);
        final secondResolution = await second.resolveQuickPop(secondTicket);
        final firstResolution = await first.resolveQuickPop(firstTicket);

        expect(firstResolution?.kind, QuickPopResolutionKind.human);
        expect(secondResolution?.kind, QuickPopResolutionKind.human);
        expect(firstResolution?.roomId, secondResolution?.roomId);
      },
    );

    test(
      'a human resolution that wins the CPU transaction race is preserved',
      () async {
        final baseStore = InMemoryOnlineRealtimeStore(initialNowMs: 35_000);
        late String claimPath;
        late QuickPopClaimResolution injectedResolution;
        final followerStore = _RejectFirstCpuFallbackStore(
          baseStore,
          beforeReject: () async {
            await baseStore.set(
              '$claimPath/resolution',
              injectedResolution.toJson(),
            );
          },
        );
        final leader = _client(baseStore, 'race-leader', 'Leader', seed: 32);
        final follower = _client(
          followerStore,
          'race-follower',
          'Follower',
          seed: 33,
          delay: (duration) async => baseStore.advance(duration),
        );
        final leaderTicket = await leader.enqueueQuickPop(mode: 'classic');
        baseStore.advance(const Duration(milliseconds: 100));
        final followerTicket = await follower.enqueueQuickPop(mode: 'classic');

        expect(await leader.resolveQuickPop(leaderTicket), isNull);
        expect(await follower.resolveQuickPop(followerTicket), isNull);
        expect(await leader.resolveQuickPop(leaderTicket), isNull);
        final followerCurrent = QuickPopQueueTicket.fromJson(
          await baseStore.read(
            '$onlineTransportRoot/quickQueues/'
            '${followerTicket.queueKey}/${followerTicket.uid}',
          ),
          uid: followerTicket.uid,
        );
        claimPath =
            '$onlineTransportRoot/quickClaims/${followerTicket.queueKey}/'
            '${followerCurrent.claimId}';
        injectedResolution = QuickPopClaimResolution(
          kind: QuickPopResolutionKind.human,
          roomId: 'quick_human_race_room',
          resolvedAtMs: followerTicket.deadlineAtMs,
          firstUid: leaderTicket.uid,
          secondUid: followerTicket.uid,
        );
        // Keep this test focused on the CPU transaction reconciliation path.
        // Without both acceptances, the follower cannot resolve the claim
        // itself; the simulated server winner is injected during the denied
        // CPU write below.
        await baseStore.set('$claimPath/acceptances/${leaderTicket.uid}', null);
        baseStore.setNowMs(followerTicket.deadlineAtMs);

        final resolution = await follower.resolveQuickPop(followerTicket);

        expect(followerStore.rejected, isTrue);
        expect(resolution?.kind, QuickPopResolutionKind.human);
        expect(resolution?.roomId, injectedResolution.roomId);
        expect(resolution?.opponentUid, leaderTicket.uid);
        final storedFollower = QuickPopQueueTicket.fromJson(
          await baseStore.read(
            '$onlineTransportRoot/quickQueues/'
            '${followerTicket.queueKey}/${followerTicket.uid}',
          ),
          uid: followerTicket.uid,
        );
        expect(storedFollower.state, QuickPopTicketState.matched);
        expect(storedFollower.state, isNot(QuickPopTicketState.cpuFallback));
      },
    );

    test(
      'findQuickPop waits a deterministic total of exactly five seconds',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 0);
        var delayedMs = 0;
        final player = _client(
          store,
          'waiting-player',
          'Waiting',
          seed: 40,
          delay: (duration) async {
            delayedMs += duration.inMilliseconds;
            store.advance(duration);
          },
        );

        final resolution = await player.findQuickPop(
          mode: 'classic',
          pollInterval: const Duration(milliseconds: 700),
        );

        expect(delayedMs, quickPopSearchWindow.inMilliseconds);
        expect(store.nowMs, quickPopSearchWindow.inMilliseconds);
        expect(resolution.kind, QuickPopResolutionKind.cpu);
        expect(resolution.resolvedAtMs, quickPopSearchWindow.inMilliseconds);
      },
    );

    test('an unresponsive ticket cannot block CPU fallback forever', () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 40_000);
      final active = _client(store, 'active-player', 'Active', seed: 35);
      final stale = _client(store, 'stale-player', 'Stale', seed: 36);
      final activeTicket = await active.enqueueQuickPop(mode: 'classic');
      store.advance(const Duration(seconds: 1));
      await stale.enqueueQuickPop(mode: 'classic');

      expect(await active.resolveQuickPop(activeTicket), isNull);
      store.setNowMs(activeTicket.deadlineAtMs);
      final resolution = await active.resolveQuickPop(activeTicket);

      expect(resolution?.kind, QuickPopResolutionKind.cpu);
      expect(resolution?.resolvedAtMs, activeTicket.deadlineAtMs);
    });
  });

  test('wire room serialization preserves lobby enums and participants', () {
    final room = OnlineRoomRecord(
      id: 'room-wire',
      code: RoomCode.parse('WAVE24'),
      hostUid: 'host-wire',
      visibility: RoomVisibility.public,
      status: RoomStatus.waiting,
      mode: 'chaos',
      matchFormat: 'traditional',
      members: <String, OnlineRoomMemberRecord>{
        'host-wire': const OnlineRoomMemberRecord(
          uid: 'host-wire',
          displayName: 'Host',
          seat: LobbySeatColor.red,
          joinedAtMs: 1,
          ready: true,
        ),
      },
      presence: <String, OnlinePresenceRecord>{
        'host-wire': const OnlinePresenceRecord(
          uid: 'host-wire',
          presence: LobbyPresence.connected,
          changedAtMs: 2,
          connectionId: 'connection-wire',
        ),
      },
      revision: 3,
      createdAtMs: 1,
      updatedAtMs: 2,
    );

    final decoded = OnlineRoomRecord.fromJson(room.toJson());

    expect(decoded.visibility, RoomVisibility.public);
    expect(decoded.status, RoomStatus.waiting);
    expect(decoded.lobbyParticipants.single.seat, LobbySeatColor.red);
    expect(decoded.lobbyParticipants.single.ready, isTrue);
    expect(decoded.lobbyParticipants.single.connected, isTrue);
  });
}
