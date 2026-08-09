import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/online_lobby.dart';
import 'package:parchesepop/online_match.dart';
import 'package:parchesepop/online_quick_pop.dart';
import 'package:parchesepop/online_transport.dart';
import 'package:parchesepop/online_transport_models.dart';

import 'support/in_memory_online_realtime_store.dart';

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
    const hostResolution = QuickPopResolution(
      ticketId: 'ticket-host',
      roomId: roomId,
      kind: QuickPopResolutionKind.human,
      opponentUid: 'zeta-player',
      resolvedAtMs: 10000,
    );
    const guestResolution = QuickPopResolution(
      ticketId: 'ticket-guest',
      roomId: roomId,
      kind: QuickPopResolutionKind.human,
      opponentUid: 'alpha-player',
      resolvedAtMs: 10000,
    );

    final host = await OnlineQuickPopBootstrap.prepare(
      transport: hostTransport,
      resolution: hostResolution,
    );
    final guest = await OnlineQuickPopBootstrap.prepare(
      transport: guestTransport,
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
}
