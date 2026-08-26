import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:parchesepop/online_lobby.dart';
import 'package:parchesepop/online_match.dart';
import 'package:parchesepop/online_quick_pop.dart';
import 'package:parchesepop/online_transport.dart';
import 'package:parchesepop/online_transport_models.dart';

import 'support/in_memory_online_realtime_store.dart';

OnlineTransportClient _groupClient(OnlineRealtimeStore store, String uid) =>
    OnlineTransportClient(
      store: store,
      identity: OnlineTransportIdentity(
        uid: uid,
        displayName: uid.toUpperCase(),
      ),
    );

/// Mirrors Firebase's security rule at the search deadline: an active queue
/// query is no longer permitted once the caller's own ticket expires.  The
/// transport must use the exact ticket path for its CPU fallback instead of
/// trying to enumerate `quickQueues/$queueKey` again.
final class _QueueQueryDeniedAfterDeadlineStore
    implements OnlineRealtimeStore, OnlineRealtimeQueryStore {
  _QueueQueryDeniedAfterDeadlineStore(this.delegate);

  final InMemoryOnlineRealtimeStore delegate;
  int orderedReadCount = 0;

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
  Future<Object?> readOrderedChildren(
    String path, {
    required String orderByChild,
    required num startAt,
    required int limitToFirst,
  }) async {
    orderedReadCount++;
    throw StateError('active queue enumeration is closed at the deadline');
  }
}

/// Records the lower bound used by the production-style queue query while
/// delegating storage to the in-memory Firebase substitute.  A group search
/// must query from zero: the security rule permits that bound and every client
/// needs the same cohort, including players who joined just before it.
final class _RecordingGroupQueryStore
    implements OnlineRealtimeStore, OnlineRealtimeQueryStore {
  _RecordingGroupQueryStore(this.delegate);

  final InMemoryOnlineRealtimeStore delegate;
  final List<num> startAtValues = <num>[];

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
  ) =>
      delegate.transaction(path, updater);

  @override
  Future<void> setOnDisconnect(String path, Object? value) =>
      delegate.setOnDisconnect(path, value);

  @override
  Future<void> cancelOnDisconnect(String path) =>
      delegate.cancelOnDisconnect(path);

  @override
  Future<int> serverNowMs() => delegate.serverNowMs();

  @override
  Future<Object?> readOrderedChildren(
    String path, {
    required String orderByChild,
    required num startAt,
    required int limitToFirst,
  }) async {
    startAtValues.add(startAt);
    final children = onlineMap(await delegate.read(path));
    final ordered =
        children.entries
            .where((entry) {
              final value = onlineMap(entry.value)[orderByChild];
              return value is num && value >= startAt;
            })
            .toList(growable: false)
          ..sort((left, right) {
            final leftValue = onlineMap(left.value)[orderByChild] as num;
            final rightValue = onlineMap(right.value)[orderByChild] as num;
            return leftValue.compareTo(rightValue);
          });
    return <String, Object?>{
      for (final entry in ordered.take(limitToFirst)) entry.key: entry.value,
    };
  }
}

void main() {
  test(
    'Quick Pop group admits four humans before the shared deadline',
    () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 1000);
      final clients = [
        for (final uid in const ['a', 'b', 'c', 'd']) _groupClient(store, uid),
      ];
      final tickets = [
        for (final client in clients)
          await client.enqueueQuickPop(
            mode: 'traditional',
            matchFormat: 'quickPop',
          ),
      ];

      QuickPopResolution? resolution;
      for (var round = 0; round < 4; round++) {
        for (var index = 0; index < clients.length; index++) {
          final candidate = await clients[index].resolveQuickPop(
            tickets[index],
            waitForGroupWindow: true,
          );
          if (candidate != null) resolution = candidate;
        }
      }

      expect(resolution, isNotNull);
      expect(resolution!.kind, QuickPopResolutionKind.human);
      expect(resolution.participantUids, hasLength(4));
      expect(resolution.groupId, isNotNull);
      expect(resolution.opponentUid, isNotNull);
      expect(resolution.participantUids.toSet(), {'a', 'b', 'c', 'd'});
      for (var index = 0; index < clients.length; index++) {
        final other = await clients[index].resolveQuickPop(
          tickets[index],
          waitForGroupWindow: true,
        );
        expect(other?.roomId, resolution.roomId);
        expect(
          other?.participantUids.toSet(),
          resolution.participantUids.toSet(),
        );
        expect(other?.kind, QuickPopResolutionKind.human);
      }
    },
  );

  test(
    'all group clients use one queue lower bound and converge on one room',
    () async {
      final memory = InMemoryOnlineRealtimeStore(initialNowMs: 100_000);
      final store = _RecordingGroupQueryStore(memory);
      final clients = [
        for (final uid in const ['a', 'b', 'c', 'd']) _groupClient(store, uid),
      ];
      final tickets = <QuickPopQueueTicket>[];
      for (final client in clients) {
        tickets.add(
          await client.enqueueQuickPop(
            mode: 'traditional',
            matchFormat: 'quickPop',
          ),
        );
        memory.setNowMs(memory.nowMs + 250);
      }

      final resolutions = <QuickPopResolution>[];
      // The first polling pass must be enough to derive a common four-player
      // cohort even though each ticket was created at a different instant.
      // Depending on which client wins the root transaction, the resolution
      // may already be complete when the next client reads the root.
      for (var index = 0; index < clients.length; index++) {
        final resolution = await clients[index].resolveQuickPop(
          tickets[index],
          waitForGroupWindow: true,
        );
        if (resolution != null) resolutions.add(resolution);
      }
      memory.setNowMs(tickets.first.deadlineAtMs);
      for (var index = 0; index < clients.length; index++) {
        if (resolutions.any(
          (resolution) => resolution.ticketId == tickets[index].ticketId,
        )) {
          continue;
        }
        final resolution = await clients[index].resolveQuickPop(
          tickets[index],
          waitForGroupWindow: true,
        );
        expect(resolution?.kind, QuickPopResolutionKind.human);
        resolutions.add(resolution!);
      }

      expect(resolutions.map((item) => item.roomId).toSet(), hasLength(1));
      expect(
        resolutions.every(
          (item) =>
              item.participantUids.length == 4 &&
              item.participantUids.toSet().containsAll(const ['a', 'b', 'c', 'd']),
        ),
        isTrue,
      );
      expect(store.startAtValues, isNotEmpty);
      expect(store.startAtValues.every((value) => value == 0), isTrue);
    },
  );

  test('Quick Pop debug sink exposes the shared group lifecycle', () async {
    final store = InMemoryOnlineRealtimeStore(initialNowMs: 10_000);
    final steps = <String>[];
    final first = OnlineTransportClient(
      store: store,
      identity: OnlineTransportIdentity(uid: 'first', displayName: 'FIRST'),
      quickPopDebugSink:
          (step, {detail = '', path, success = false, error = false}) {
            steps.add(step);
          },
    );
    final second = _groupClient(store, 'second');
    final firstTicket = await first.enqueueQuickPop(
      mode: 'traditional',
      matchFormat: 'quickPop',
    );
    final secondTicket = await second.enqueueQuickPop(
      mode: 'traditional',
      matchFormat: 'quickPop',
    );

    await first.resolveQuickPop(firstTicket, waitForGroupWindow: true);
    await second.resolveQuickPop(secondTicket, waitForGroupWindow: true);
    store.setNowMs(firstTicket.deadlineAtMs);
    final resolution = await first.resolveQuickPop(
      firstTicket,
      waitForGroupWindow: true,
    );

    expect(resolution?.kind, QuickPopResolutionKind.human);
    expect(
      steps,
      containsAll(<String>[
        'QUEUE_SCAN_RESULT',
        'GROUP_DERIVED',
        'GROUP_ROOT_WRITE',
        'GROUP_ROOT_READ',
        'GROUP_MEMBER_JOIN',
        'GROUP_MEMBER_COUNT',
        'GROUP_RESOLUTION_WRITE',
        'GROUP_RESOLUTION_READ',
      ]),
    );
  });

  test(
    'Quick Pop group resolves when the deterministic leader stops polling',
    () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 15_000);
      final leader = _groupClient(store, 'leader');
      final follower = _groupClient(store, 'follower');
      final leaderTicket = await leader.enqueueQuickPop(
        mode: 'traditional',
        matchFormat: 'quickPop',
      );
      final followerTicket = await follower.enqueueQuickPop(
        mode: 'traditional',
        matchFormat: 'quickPop',
      );

      // The leader creates the deterministic group and then disappears. The
      // follower must still be able to publish the single shared resolution at
      // the deadline instead of falling back to a separate CPU room.
      expect(
        await leader.resolveQuickPop(leaderTicket, waitForGroupWindow: true),
        isNull,
      );
      expect(
        await follower.resolveQuickPop(
          followerTicket,
          waitForGroupWindow: true,
        ),
        isNull,
      );
      store.setNowMs(followerTicket.deadlineAtMs);

      final resolution = await follower.resolveQuickPop(
        followerTicket,
        waitForGroupWindow: true,
      );
      expect(resolution?.kind, QuickPopResolutionKind.human);
      expect(resolution?.participantUids.toSet(), {'leader', 'follower'});

      // A late leader resume reads the same committed group resolution rather
      // than creating a competing CPU fallback.
      final resumed = await leader.resolveQuickPop(
        leaderTicket,
        waitForGroupWindow: true,
      );
      expect(resumed?.kind, QuickPopResolutionKind.human);
      expect(resumed?.roomId, resolution?.roomId);
    },
  );

  test(
    'Quick Pop resumes a group from the durable locator at the deadline',
    () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 18_000);
      final leader = _groupClient(store, 'leader');
      final follower = _groupClient(store, 'follower');
      final leaderTicket = await leader.enqueueQuickPop(
        mode: 'traditional',
        matchFormat: 'quickPop',
      );
      final followerTicket = await follower.enqueueQuickPop(
        mode: 'traditional',
        matchFormat: 'quickPop',
      );

      // Both clients see the cohort and commit the shared root, but neither
      // needs to finish the resolution before the app is backgrounded.
      expect(
        await leader.resolveQuickPop(leaderTicket, waitForGroupWindow: true),
        isNull,
      );
      expect(
        await follower.resolveQuickPop(
          followerTicket,
          waitForGroupWindow: true,
        ),
        isNull,
      );

      // A new transport instance has an empty in-memory `_ownedQuickGroupIds`
      // map, just like a client returning from Home. It must recover the
      // group id from account resources before the expired queue query forces
      // CPU fallback.
      final resumedLeader = _groupClient(store, 'leader');
      store.setNowMs(leaderTicket.deadlineAtMs);
      final resolution = await resumedLeader.resolveQuickPop(
        leaderTicket,
        waitForGroupWindow: true,
      );

      expect(resolution?.kind, QuickPopResolutionKind.human);
      expect(resolution?.groupId, isNotNull);
      expect(resolution?.roomId, isNotNull);
      expect(resolution?.participantUids.toSet(), {'leader', 'follower'});
      expect(
        onlineMap(
          await store.read(
            '$onlineTransportRoot/accountResources/leader/quickQueues/${leaderTicket.queueKey}',
          ),
        )['groupId'],
        resolution?.groupId,
      );
    },
  );

  test(
    'Quick Pop resumes from the local locator when server indexing is unavailable',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 19_000);
      final leader = _groupClient(store, 'local-leader');
      final follower = _groupClient(store, 'local-follower');
      final leaderTicket = await leader.enqueueQuickPop(
        mode: 'traditional',
        matchFormat: 'quickPop',
      );
      final followerTicket = await follower.enqueueQuickPop(
        mode: 'traditional',
        matchFormat: 'quickPop',
      );

      await leader.resolveQuickPop(leaderTicket, waitForGroupWindow: true);
      await follower.resolveQuickPop(followerTicket, waitForGroupWindow: true);
      final accountPath =
          '$onlineTransportRoot/accountResources/local-leader/quickQueues/${leaderTicket.queueKey}';
      // Simulate the production deployment that rejects the optional
      // groupId/groupIndexedAt account-resource fields. The local cache must
      // still carry the verified ticket -> group relationship across a new
      // transport instance and prevent an unrelated CPU fallback.
      await store.update(accountPath, <String, Object?>{
        'groupId': null,
        'groupIndexedAt': null,
      });
      final resumedLeader = _groupClient(store, 'local-leader');
      store.setNowMs(leaderTicket.deadlineAtMs);
      final resolution = await resumedLeader.resolveQuickPop(
        leaderTicket,
        waitForGroupWindow: true,
      );

      expect(resolution?.kind, QuickPopResolutionKind.human);
      expect(resolution?.groupId, isNotNull);
      expect(resolution?.participantUids.toSet(), {
        'local-leader',
        'local-follower',
      });
    },
  );

  test(
    'Quick Pop ignores expired waiting tickets when deriving a group',
    () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 10_000);
      const queueKey = 'traditional_quickPop';
      await store.set(
        '$onlineTransportRoot/quickQueues/$queueKey/expired-player',
        <String, Object?>{
          'ticketId': 'expired-ticket',
          'uid': 'expired-player',
          'displayName': 'EXPIRED PLAYER',
          'queueKey': queueKey,
          'joinedAt': 1,
          'deadlineAt': 9_999,
          'activeUntil': 9_999,
          'state': 'waiting',
        },
      );
      final first = _groupClient(store, 'first');
      final second = _groupClient(store, 'second');
      final firstTicket = await first.enqueueQuickPop(
        mode: 'traditional',
        matchFormat: 'quickPop',
      );
      final secondTicket = await second.enqueueQuickPop(
        mode: 'traditional',
        matchFormat: 'quickPop',
      );

      await first.resolveQuickPop(firstTicket, waitForGroupWindow: true);
      await second.resolveQuickPop(secondTicket, waitForGroupWindow: true);
      store.setNowMs(firstTicket.deadlineAtMs);
      final firstResolution = await first.resolveQuickPop(
        firstTicket,
        waitForGroupWindow: true,
      );
      final secondResolution = await second.resolveQuickPop(
        secondTicket,
        waitForGroupWindow: true,
      );

      expect(firstResolution?.kind, QuickPopResolutionKind.human);
      expect(secondResolution?.kind, QuickPopResolutionKind.human);
      expect(firstResolution?.roomId, secondResolution?.roomId);
      expect(firstResolution?.participantUids.toSet(), {'first', 'second'});
    },
  );

  test(
    'Quick Pop keeps two humans and fills the remaining seats later',
    () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 20_000);
      final first = _groupClient(store, 'first');
      final second = _groupClient(store, 'second');
      final firstTicket = await first.enqueueQuickPop(
        mode: 'traditional',
        matchFormat: 'quickPop',
      );
      final secondTicket = await second.enqueueQuickPop(
        mode: 'traditional',
        matchFormat: 'quickPop',
      );

      await first.resolveQuickPop(firstTicket, waitForGroupWindow: true);
      await second.resolveQuickPop(secondTicket, waitForGroupWindow: true);
      await first.resolveQuickPop(firstTicket, waitForGroupWindow: true);
      await second.resolveQuickPop(secondTicket, waitForGroupWindow: true);
      store.setNowMs(firstTicket.deadlineAtMs);
      final firstResolution = await first.resolveQuickPop(
        firstTicket,
        waitForGroupWindow: true,
      );
      final secondResolution = await second.resolveQuickPop(
        secondTicket,
        waitForGroupWindow: true,
      );

      expect(firstResolution?.kind, QuickPopResolutionKind.human);
      expect(firstResolution?.participantUids, hasLength(2));
      expect(secondResolution?.roomId, firstResolution?.roomId);
    },
  );

  test(
    'Quick Pop uses CPU only when no human joins by fifteen seconds',
    () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 40_000);
      final solo = _groupClient(store, 'solo');
      final ticket = await solo.enqueueQuickPop(
        mode: 'traditional',
        matchFormat: 'quickPop',
      );
      store.setNowMs(ticket.deadlineAtMs - 1);
      expect(
        await solo.resolveQuickPop(ticket, waitForGroupWindow: true),
        isNull,
      );
      store.setNowMs(ticket.deadlineAtMs);
      final resolution = await solo.resolveQuickPop(
        ticket,
        waitForGroupWindow: true,
      );
      expect(resolution?.kind, QuickPopResolutionKind.cpu);
      expect(resolution?.groupId, isNull);
    },
  );

  test('Quick Pop does not enumerate the queue after its deadline', () async {
    final base = InMemoryOnlineRealtimeStore(initialNowMs: 50_000);
    final store = _QueueQueryDeniedAfterDeadlineStore(base);
    final solo = _groupClient(store, 'solo');
    final ticket = await solo.enqueueQuickPop(
      mode: 'traditional',
      matchFormat: 'quickPop',
    );
    base.setNowMs(ticket.deadlineAtMs);

    final resolution = await solo.resolveQuickPop(
      ticket,
      waitForGroupWindow: true,
    );

    expect(resolution?.kind, QuickPopResolutionKind.cpu);
    expect(store.orderedReadCount, 0);
  });

  test('group bootstrap assigns human seats before adding one CPU', () async {
    final store = InMemoryOnlineRealtimeStore(initialNowMs: 60_000);
    final clients = [
      for (final uid in const ['a', 'b', 'c']) _groupClient(store, uid),
    ];
    const queueKey = 'traditional_quickPop';
    const groupId = 'group-four-seat-test';
    const roomId = 'quick-four-seat-test-room';
    final tickets = [
      for (var index = 0; index < clients.length; index++)
        QuickPopQueueTicket(
          ticketId: 'ticket-${index + 1}',
          uid: String.fromCharCode(97 + index),
          displayName: String.fromCharCode(65 + index),
          queueKey: queueKey,
          joinedAtMs: 60_000,
          deadlineAtMs: 75_000,
          state: QuickPopTicketState.matched,
          groupId: groupId,
          roomId: roomId,
          opponentUid: index == 0 ? 'b' : 'a',
          opponentUids: const ['a', 'b', 'c'],
        ),
    ];
    for (final ticket in tickets) {
      await store.set(
        '$onlineTransportRoot/quickQueues/$queueKey/${ticket.uid}',
        ticket.toJson(),
      );
    }
    await store.set('$onlineTransportRoot/quickPopGroups/$queueKey/$groupId', {
      'groupId': groupId,
      'queueKey': queueKey,
      'leaderUid': 'a',
      'createdAt': 60_000,
      'members': {
        for (final ticket in tickets)
          ticket.uid: {
            'uid': ticket.uid,
            'ticketId': ticket.ticketId,
            'displayName': ticket.displayName,
            'joinedAt': ticket.joinedAtMs,
            'deadlineAt': ticket.deadlineAtMs,
          },
      },
      'resolution': {
        'kind': 'human',
        'roomId': roomId,
        'resolvedAt': 75_000,
        'memberUids': ['a', 'b', 'c'],
      },
    });
    final resolutions = [
      for (final ticket in tickets)
        QuickPopResolution(
          ticketId: ticket.ticketId,
          roomId: roomId,
          kind: QuickPopResolutionKind.human,
          resolvedAtMs: 75_000,
          queueKey: queueKey,
          groupId: groupId,
          participantUids: const ['a', 'b', 'c'],
          opponentUid: ticket.uid == 'a' ? 'b' : 'a',
        ),
    ];
    final prepared = <OnlineQuickPopPreparedMatch>[];
    for (var index = 0; index < clients.length; index++) {
      prepared.add(
        await OnlineQuickPopBootstrap.prepare(
          transport: clients[index],
          ticket: tickets[index],
          resolution: resolutions[index],
        ),
      );
    }
    expect(prepared.first.room.members, hasLength(4));
    expect(
      prepared.first.room.members.values.where(
        (member) => member.uid.startsWith('cpu_'),
      ),
      hasLength(1),
    );
    expect(
      prepared.first.session.participants.where(
        (participant) => participant.kind == ParticipantKind.remoteHuman,
      ),
      hasLength(2),
    );
  });

  test(
    'group bootstrap accepts the real waiting tickets and keeps all four humans',
    () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 100_000);
      final clients = [
        for (final uid in const ['a', 'b', 'c', 'd']) _groupClient(store, uid),
      ];
      final tickets = [
        for (final client in clients)
          await client.enqueueQuickPop(
            mode: 'traditional',
            matchFormat: 'quickPop',
          ),
      ];
      final groupId = 'group-${tickets.first.ticketId}';
      final roomId = 'room-${tickets.first.ticketId}';
      await store.set(
        '$onlineTransportRoot/quickPopGroups/traditional_quickPop/$groupId',
        <String, Object?>{
          'groupId': groupId,
          'queueKey': 'traditional_quickPop',
          'leaderUid': 'a',
          'createdAt': 100_000,
          'members': <String, Object?>{
            for (final ticket in tickets)
              ticket.uid: <String, Object?>{
                'uid': ticket.uid,
                'ticketId': ticket.ticketId,
                'displayName': ticket.displayName,
                'joinedAt': ticket.joinedAtMs,
                'deadlineAt': ticket.deadlineAtMs,
              },
          },
          'resolution': <String, Object?>{
            'kind': 'human',
            'roomId': roomId,
            'resolvedAt': tickets.first.deadlineAtMs,
            'memberUids': [for (final ticket in tickets) ticket.uid],
          },
        },
      );
      final resolutions = [
        for (final ticket in tickets)
          QuickPopResolution(
            ticketId: ticket.ticketId,
            roomId: roomId,
            kind: QuickPopResolutionKind.human,
            resolvedAtMs: tickets.first.deadlineAtMs,
            queueKey: 'traditional_quickPop',
            groupId: groupId,
            participantUids: [for (final member in tickets) member.uid],
            opponentUid: ticket.uid == 'a' ? 'b' : 'a',
          ),
      ];

      final prepared = <OnlineQuickPopPreparedMatch>[];
      for (var index = 0; index < clients.length; index++) {
        prepared.add(
          await OnlineQuickPopBootstrap.prepare(
            transport: clients[index],
            ticket: tickets[index],
            resolution: resolutions[index],
          ),
        );
      }

      for (final match in prepared) {
        expect(match.room.members, hasLength(4));
        expect(
          match.room.members.values.every(
            (member) => !member.uid.startsWith('cpu_'),
          ),
          isTrue,
        );
        expect(
          match.session.participants.where(
            (participant) => participant.kind == ParticipantKind.remoteHuman,
          ),
          hasLength(3),
        );
      }

      // The room shape alone is not enough: every human must also pass the
      // shared launch barrier before Quick Pop enters the playable state.
      for (final match in prepared) {
        await match.sync.start();
      }
      addTearDown(() {
        for (final match in prepared) {
          match.sync.dispose();
          match.engine.dispose();
        }
      });
      final launchResults = <bool>[
        for (var index = 0; index < prepared.length; index++)
          await clients[index].synchronizeQuickPopLaunch(
            ticket: tickets[index],
            resolution: resolutions[index],
          ),
      ];
      // Any verified member may commit the transition once all four launch
      // markers exist; the first caller can therefore complete the barrier.
      expect(launchResults, contains(isTrue));
      // A stale presence snapshot must not invalidate the verified four-player
      // launch barrier.  This mirrors the race seen when one client is still
      // publishing its presence listener while all launchReady markers exist.
      await store.set(
        '$onlineTransportRoot/rooms/$roomId/presence/d/state',
        LobbyPresence.disconnected.name,
      );
      expect(
        await clients.first.synchronizeQuickPopLaunch(
          ticket: tickets.first,
          resolution: resolutions.first,
        ),
        isTrue,
      );
      expect((await clients.first.readRoom(roomId))?.status, RoomStatus.inGame);
    },
  );
}
