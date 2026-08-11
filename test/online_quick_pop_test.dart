import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/online_game_sync.dart';
import 'package:parchesepop/online_lobby.dart';
import 'package:parchesepop/online_match.dart';
import 'package:parchesepop/online_quick_pop.dart';
import 'package:parchesepop/online_transport.dart';
import 'package:parchesepop/online_transport_models.dart';

import 'support/in_memory_online_realtime_store.dart';

final class _SettlementRaceStore implements OnlineRealtimeStore {
  _SettlementRaceStore(this.delegate, {required this.statusPath});

  final InMemoryOnlineRealtimeStore delegate;
  final String statusPath;
  bool closeBeforeSettlementWrite = false;
  bool hangSettlementReads = false;
  bool rejectCloseAfterPeerSettlement = false;
  String? peerSettlementPath;
  Map<String, Object?>? peerSettlement;

  @override
  Future<Object?> read(String path) {
    if (hangSettlementReads &&
        (path == statusPath || path.contains('/quickClaims/'))) {
      return Completer<Object?>().future;
    }
    return delegate.read(path);
  }

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
    if (closeBeforeSettlementWrite && path.contains('/launchSettled/')) {
      closeBeforeSettlementWrite = false;
      await delegate.set(statusPath, RoomStatus.closed.name);
      throw StateError('The peer closed before settlement acknowledgement.');
    }
    if (rejectCloseAfterPeerSettlement && path == statusPath) {
      final current = await delegate.read(path);
      final decision = updater(current);
      if (decision is OnlineStoreCommit &&
          decision.value == RoomStatus.closed.name) {
        rejectCloseAfterPeerSettlement = false;
        await delegate.set(peerSettlementPath!, peerSettlement!);
        throw StateError(
          'Firebase denied close because the peer settlement won.',
        );
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
  test('two matched devices materialize one deterministic live room', () async {
    final store = InMemoryOnlineRealtimeStore(initialNowMs: 10000);
    final hostTransport = OnlineTransportClient(
      store: store,
      identity: OnlineTransportIdentity(
        uid: 'alpha-player',
        displayName: 'Ana',
      ),
    );
    final guestTransport = OnlineTransportClient(
      store: store,
      identity: OnlineTransportIdentity(
        uid: 'zeta-player',
        displayName: 'Luis',
      ),
    );
    await hostTransport.syncProfile();
    await guestTransport.syncProfile();
    const roomId = 'quick_1234567890abcdef12345678';
    const queueKey = 'traditional_quickPop';
    const claimId = 'claim-shared-room';
    const hostTicket = QuickPopQueueTicket(
      ticketId: 'ticket-host',
      uid: 'alpha-player',
      displayName: 'Ana',
      queueKey: queueKey,
      joinedAtMs: 10000,
      deadlineAtMs: 15000,
      state: QuickPopTicketState.matched,
      claimId: claimId,
      roomId: roomId,
      opponentUid: 'zeta-player',
    );
    const guestTicket = QuickPopQueueTicket(
      ticketId: 'ticket-guest',
      uid: 'zeta-player',
      displayName: 'Luis',
      queueKey: queueKey,
      joinedAtMs: 10000,
      deadlineAtMs: 15000,
      state: QuickPopTicketState.matched,
      claimId: claimId,
      roomId: roomId,
      opponentUid: 'alpha-player',
    );
    await store.set(
      '$onlineTransportRoot/quickQueues/$queueKey/alpha-player',
      hostTicket.toJson(),
    );
    await store.set(
      '$onlineTransportRoot/quickQueues/$queueKey/zeta-player',
      guestTicket.toJson(),
    );
    await store.set('$onlineTransportRoot/quickClaims/$queueKey/$claimId', {
      'claimId': claimId,
      'queueKey': queueKey,
      'leaderUid': 'alpha-player',
      'firstUid': 'alpha-player',
      'firstTicketId': hostTicket.ticketId,
      'secondUid': 'zeta-player',
      'secondTicketId': guestTicket.ticketId,
      'createdAt': 10000,
      'resolution': {
        'kind': 'human',
        'roomId': roomId,
        'resolvedAt': 10000,
        'firstUid': 'alpha-player',
        'secondUid': 'zeta-player',
      },
    });
    const hostResolution = QuickPopResolution(
      ticketId: 'ticket-host',
      roomId: roomId,
      kind: QuickPopResolutionKind.human,
      opponentUid: 'zeta-player',
      resolvedAtMs: 10000,
      queueKey: queueKey,
      claimId: claimId,
    );
    const guestResolution = QuickPopResolution(
      ticketId: 'ticket-guest',
      roomId: roomId,
      kind: QuickPopResolutionKind.human,
      opponentUid: 'alpha-player',
      resolvedAtMs: 10000,
      queueKey: queueKey,
      claimId: claimId,
    );

    final host = await OnlineQuickPopBootstrap.prepare(
      transport: hostTransport,
      ticket: hostTicket,
      resolution: hostResolution,
    );
    final guest = await OnlineQuickPopBootstrap.prepare(
      transport: guestTransport,
      ticket: guestTicket,
      resolution: guestResolution,
    );

    expect(host.room.id, roomId);
    expect(guest.room.toJson(), host.room.toJson());
    expect(host.room.members, hasLength(4));
    expect(host.room.presenceFor('alpha-player'), LobbyPresence.disconnected);
    expect(host.room.presenceFor('zeta-player'), LobbyPresence.disconnected);
    expect(
      host.room.presence.values
          .where((record) => record.uid.startsWith('cpu_'))
          .every((record) => record.presence == LobbyPresence.connected),
      isTrue,
    );
    expect(host.session.localColor, PlayerColor.red);
    expect(guest.session.localColor, PlayerColor.green);
    expect(host.sync.isHost, isTrue);
    expect(guest.sync.isHost, isFalse);
    expect(
      host.session.participants.where(
        (participant) => participant.kind == ParticipantKind.virtual,
      ),
      hasLength(2),
    );
    expect(
      guest.session.participantForColor(PlayerColor.red).kind,
      ParticipantKind.remoteHuman,
    );
    expect(host.engine.matchFormat, MatchFormat.quickPop);
    expect(guest.engine.matchFormat, MatchFormat.quickPop);

    await host.sync.start();
    await guest.sync.start();
    expect(
      await hostTransport.synchronizeQuickPopLaunch(
        ticket: hostTicket,
        resolution: hostResolution,
      ),
      isFalse,
    );
    expect(
      await guestTransport.synchronizeQuickPopLaunch(
        ticket: guestTicket,
        resolution: guestResolution,
      ),
      isFalse,
    );
    expect(
      await hostTransport.synchronizeQuickPopLaunch(
        ticket: hostTicket,
        resolution: hostResolution,
      ),
      isTrue,
    );
    expect(
      await guestTransport.synchronizeQuickPopLaunch(
        ticket: guestTicket,
        resolution: guestResolution,
      ),
      isTrue,
    );
    expect((await hostTransport.readRoom(roomId))?.status, RoomStatus.inGame);

    // `inGame` is provisional until both clients independently settle at the
    // shared deadline and then re-read the authoritative room status.
    store.setNowMs(15000);
    final settlements = await Future.wait([
      hostTransport.settleQuickPopLaunch(
        ticket: hostTicket,
        resolution: hostResolution,
        peerWait: const Duration(milliseconds: 200),
        operationTimeout: const Duration(seconds: 1),
      ),
      guestTransport.settleQuickPopLaunch(
        ticket: guestTicket,
        resolution: guestResolution,
        peerWait: const Duration(milliseconds: 200),
        operationTimeout: const Duration(seconds: 1),
      ),
    ]);
    expect(settlements, everyElement(QuickPopLaunchSettlement.human));
    expect((await hostTransport.readRoom(roomId))?.status, RoomStatus.inGame);
    expect(guest.engine.createCheckpoint(), host.engine.createCheckpoint());

    host.sync.dispose();
    guest.sync.dispose();
  });

  test('CPU resolution is not materialized as a network room', () async {
    final store = InMemoryOnlineRealtimeStore();
    final transport = OnlineTransportClient(
      store: store,
      identity: OnlineTransportIdentity(uid: 'solo', displayName: 'Solo'),
    );

    await expectLater(
      OnlineQuickPopBootstrap.prepare(
        transport: transport,
        ticket: const QuickPopQueueTicket(
          ticketId: 'ticket',
          uid: 'solo',
          displayName: 'Solo',
          queueKey: 'traditional_quickPop',
          joinedAtMs: 0,
          deadlineAtMs: 5000,
        ),
        resolution: const QuickPopResolution(
          ticketId: 'ticket',
          roomId: 'cpu-room',
          kind: QuickPopResolutionKind.cpu,
          resolvedAtMs: 5000,
        ),
      ),
      throwsA(anything),
    );
  });

  test('staggered clients settle at the shared minimum deadline', () async {
    final fixture = await _committedFixture(
      roomId: 'quick_staggered_room',
      claimId: 'quick_staggered_claim',
      firstJoinedAtMs: 10000,
      secondJoinedAtMs: 12000,
      nowMs: 12000,
    );

    final settlements = await Future.wait([
      fixture.hostTransport.settleQuickPopLaunch(
        ticket: fixture.hostTicket,
        resolution: fixture.hostResolution,
        peerWait: const Duration(milliseconds: 200),
        operationTimeout: const Duration(seconds: 1),
      ),
      fixture.guestTransport.settleQuickPopLaunch(
        ticket: fixture.guestTicket,
        resolution: fixture.guestResolution,
        peerWait: const Duration(milliseconds: 200),
        operationTimeout: const Duration(seconds: 1),
      ),
    ]);

    expect(fixture.store.nowMs, greaterThanOrEqualTo(15000));
    expect(settlements, everyElement(QuickPopLaunchSettlement.human));
    expect(
      (await fixture.hostTransport.readRoom(fixture.roomId))?.status,
      RoomStatus.inGame,
    );
    fixture.host.sync.dispose();
    fixture.guest.sync.dispose();
  });

  test(
    'peer cancellation after provisional commit makes both fallback',
    () async {
      final fixture = await _committedFixture(
        roomId: 'quick_peer_cancel_room',
        claimId: 'quick_peer_cancel_claim',
      );
      fixture.store.setNowMs(15000);

      await fixture.guestTransport.abandonQuickPopLaunch(
        ticket: fixture.guestTicket,
        resolution: fixture.guestResolution,
      );
      final hostDecision = await fixture.hostTransport.settleQuickPopLaunch(
        ticket: fixture.hostTicket,
        resolution: fixture.hostResolution,
        peerWait: const Duration(milliseconds: 50),
        operationTimeout: const Duration(milliseconds: 500),
      );

      expect(hostDecision, QuickPopLaunchSettlement.fallback);
      expect(
        (await fixture.hostTransport.readRoom(fixture.roomId))?.status,
        RoomStatus.closed,
      );
      fixture.host.sync.dispose();
      fixture.guest.sync.dispose();
    },
  );

  test(
    'peer close between status read and settlement write is fallback',
    () async {
      final fixture = await _committedFixture(
        roomId: 'quick_write_close_race_room',
        claimId: 'quick_write_close_race_claim',
      );
      fixture.store.setNowMs(15000);
      fixture.raceStore.closeBeforeSettlementWrite = true;

      final guestDecision = await fixture.guestTransport.settleQuickPopLaunch(
        ticket: fixture.guestTicket,
        resolution: fixture.guestResolution,
        peerWait: const Duration(milliseconds: 50),
        operationTimeout: const Duration(milliseconds: 500),
      );
      final hostDecision = await fixture.hostTransport.settleQuickPopLaunch(
        ticket: fixture.hostTicket,
        resolution: fixture.hostResolution,
        peerWait: const Duration(milliseconds: 50),
        operationTimeout: const Duration(milliseconds: 500),
      );

      expect(guestDecision, QuickPopLaunchSettlement.fallback);
      expect(hostDecision, QuickPopLaunchSettlement.fallback);
      fixture.host.sync.dispose();
      fixture.guest.sync.dispose();
    },
  );

  test(
    'abort tombstone blocks delayed room preparation after cleanup',
    () async {
      final fixture = await _committedFixture(
        roomId: 'quick_late_prepare_room',
        claimId: 'quick_late_prepare_claim',
      );
      await fixture.guestTransport.abandonQuickPopLaunch(
        ticket: fixture.guestTicket,
        resolution: fixture.guestResolution,
      );
      // Simulate retention removing the closed candidate before a delayed host
      // bootstrap resumes. The durable claim tombstone must still win.
      await fixture.store.set(
        '$onlineTransportRoot/rooms/${fixture.roomId}',
        null,
      );

      await expectLater(
        OnlineQuickPopBootstrap.prepare(
          transport: fixture.hostTransport,
          ticket: fixture.hostTicket,
          resolution: fixture.hostResolution,
        ),
        throwsA(isA<OnlineGameSyncException>()),
      );
      fixture.host.sync.dispose();
      fixture.guest.sync.dispose();
    },
  );

  test(
    'hung authoritative settlement is bounded and never guesses CPU',
    () async {
      final fixture = await _committedFixture(
        roomId: 'quick_hung_settlement_room',
        claimId: 'quick_hung_settlement_claim',
      );
      fixture.store.setNowMs(15000);
      fixture.raceStore.hangSettlementReads = true;

      final decision = await fixture.guestTransport.settleQuickPopLaunch(
        ticket: fixture.guestTicket,
        resolution: fixture.guestResolution,
        peerWait: const Duration(milliseconds: 10),
        operationTimeout: const Duration(milliseconds: 30),
      );

      expect(decision, QuickPopLaunchSettlement.unavailable);
      fixture.host.sync.dispose();
      fixture.guest.sync.dispose();
    },
  );

  test(
    'peer settlement winning a rejected close still resolves human',
    () async {
      final fixture = await _committedFixture(
        roomId: 'quick_close_rejected_room',
        claimId: 'quick_close_rejected_claim',
      );
      fixture.store.setNowMs(15000);
      fixture.raceStore
        ..rejectCloseAfterPeerSettlement = true
        ..peerSettlementPath =
            '$onlineTransportRoot/quickClaims/'
            '${fixture.hostTicket.queueKey}/'
            '${fixture.hostResolution.claimId}/launchSettled/'
            '${fixture.hostTicket.uid}'
        ..peerSettlement = <String, Object?>{
          'uid': fixture.hostTicket.uid,
          'ticketId': fixture.hostTicket.ticketId,
          'settledAt': 15000,
        };

      final guestDecision = await fixture.guestTransport.settleQuickPopLaunch(
        ticket: fixture.guestTicket,
        resolution: fixture.guestResolution,
        peerWait: const Duration(milliseconds: 10),
        operationTimeout: const Duration(milliseconds: 500),
      );
      final hostDecision = await fixture.hostTransport.settleQuickPopLaunch(
        ticket: fixture.hostTicket,
        resolution: fixture.hostResolution,
        peerWait: const Duration(milliseconds: 10),
        operationTimeout: const Duration(milliseconds: 500),
      );

      expect(guestDecision, QuickPopLaunchSettlement.human);
      expect(hostDecision, QuickPopLaunchSettlement.human);
      expect(
        (await fixture.hostTransport.readRoom(fixture.roomId))?.status,
        RoomStatus.inGame,
      );
      fixture.host.sync.dispose();
      fixture.guest.sync.dispose();
    },
  );
}

Future<
  ({
    InMemoryOnlineRealtimeStore store,
    _SettlementRaceStore raceStore,
    String roomId,
    OnlineTransportClient hostTransport,
    OnlineTransportClient guestTransport,
    QuickPopQueueTicket hostTicket,
    QuickPopQueueTicket guestTicket,
    QuickPopResolution hostResolution,
    QuickPopResolution guestResolution,
    OnlineQuickPopPreparedMatch host,
    OnlineQuickPopPreparedMatch guest,
  })
>
_committedFixture({
  required String roomId,
  required String claimId,
  int firstJoinedAtMs = 10000,
  int secondJoinedAtMs = 10000,
  int nowMs = 10000,
}) async {
  final store = InMemoryOnlineRealtimeStore(initialNowMs: nowMs);
  final statusPath = '$onlineTransportRoot/rooms/$roomId/status';
  final raceStore = _SettlementRaceStore(store, statusPath: statusPath);
  Future<void> advanceDelay(Duration duration) async {
    store.advance(duration);
    await Future<void>.delayed(Duration.zero);
  }

  final hostTransport = OnlineTransportClient(
    store: store,
    identity: OnlineTransportIdentity(uid: 'alpha-player', displayName: 'Ana'),
    delay: advanceDelay,
  );
  final guestTransport = OnlineTransportClient(
    store: raceStore,
    identity: OnlineTransportIdentity(uid: 'zeta-player', displayName: 'Luis'),
    delay: advanceDelay,
  );
  await hostTransport.syncProfile();
  await guestTransport.syncProfile();
  const queueKey = 'traditional_quickPop';
  final hostTicket = QuickPopQueueTicket(
    ticketId: 'ticket-host-$claimId',
    uid: 'alpha-player',
    displayName: 'Ana',
    queueKey: queueKey,
    joinedAtMs: firstJoinedAtMs,
    deadlineAtMs: firstJoinedAtMs + 5000,
    state: QuickPopTicketState.matched,
    claimId: claimId,
    roomId: roomId,
    opponentUid: 'zeta-player',
  );
  final guestTicket = QuickPopQueueTicket(
    ticketId: 'ticket-guest-$claimId',
    uid: 'zeta-player',
    displayName: 'Luis',
    queueKey: queueKey,
    joinedAtMs: secondJoinedAtMs,
    deadlineAtMs: secondJoinedAtMs + 5000,
    state: QuickPopTicketState.matched,
    claimId: claimId,
    roomId: roomId,
    opponentUid: 'alpha-player',
  );
  await store.set(
    '$onlineTransportRoot/quickQueues/$queueKey/alpha-player',
    hostTicket.toJson(),
  );
  await store.set(
    '$onlineTransportRoot/quickQueues/$queueKey/zeta-player',
    guestTicket.toJson(),
  );
  await store.set('$onlineTransportRoot/quickClaims/$queueKey/$claimId', {
    'claimId': claimId,
    'queueKey': queueKey,
    'leaderUid': 'alpha-player',
    'firstUid': 'alpha-player',
    'firstTicketId': hostTicket.ticketId,
    'secondUid': 'zeta-player',
    'secondTicketId': guestTicket.ticketId,
    'createdAt': firstJoinedAtMs,
    'resolution': {
      'kind': 'human',
      'roomId': roomId,
      'resolvedAt': nowMs,
      'firstUid': 'alpha-player',
      'secondUid': 'zeta-player',
    },
  });
  final hostResolution = QuickPopResolution(
    ticketId: hostTicket.ticketId,
    roomId: roomId,
    kind: QuickPopResolutionKind.human,
    opponentUid: 'zeta-player',
    resolvedAtMs: nowMs,
    queueKey: queueKey,
    claimId: claimId,
  );
  final guestResolution = QuickPopResolution(
    ticketId: guestTicket.ticketId,
    roomId: roomId,
    kind: QuickPopResolutionKind.human,
    opponentUid: 'alpha-player',
    resolvedAtMs: nowMs,
    queueKey: queueKey,
    claimId: claimId,
  );
  final host = await OnlineQuickPopBootstrap.prepare(
    transport: hostTransport,
    ticket: hostTicket,
    resolution: hostResolution,
  );
  final guest = await OnlineQuickPopBootstrap.prepare(
    transport: guestTransport,
    ticket: guestTicket,
    resolution: guestResolution,
  );
  await host.sync.start();
  await guest.sync.start();
  expect(
    await hostTransport.synchronizeQuickPopLaunch(
      ticket: hostTicket,
      resolution: hostResolution,
    ),
    isFalse,
  );
  expect(
    await guestTransport.synchronizeQuickPopLaunch(
      ticket: guestTicket,
      resolution: guestResolution,
    ),
    isFalse,
  );
  expect(
    await hostTransport.synchronizeQuickPopLaunch(
      ticket: hostTicket,
      resolution: hostResolution,
    ),
    isTrue,
  );
  return (
    store: store,
    raceStore: raceStore,
    roomId: roomId,
    hostTransport: hostTransport,
    guestTransport: guestTransport,
    hostTicket: hostTicket,
    guestTicket: guestTicket,
    hostResolution: hostResolution,
    guestResolution: guestResolution,
    host: host,
    guest: guest,
  );
}
