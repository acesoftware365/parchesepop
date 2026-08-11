import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';
import 'package:parchesepop/online_game_sync.dart';
import 'package:parchesepop/online_lobby.dart';
import 'package:parchesepop/online_match.dart';
import 'package:parchesepop/online_transport.dart';
import 'package:parchesepop/online_transport_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/in_memory_online_realtime_store.dart';

void main() {
  testWidgets(
    'host departure switches the remaining player to local CPU mode',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = InMemoryOnlineRealtimeStore(initialNowMs: 10000);
      final hostSession = _sessionFor(PlayerColor.red);
      final guestSession = _sessionFor(PlayerColor.green);
      final hostEngine = _engine(PlayerColor.red);
      final guestEngine = _engine(PlayerColor.green);
      final host = OnlineGameSyncClient(
        transport: _transport(store, 'host_red'),
        roomId: 'room_sync_001',
        session: hostSession,
        engine: hostEngine,
        isHost: true,
      );
      final guest = OnlineGameSyncClient(
        transport: _transport(store, 'guest_green'),
        roomId: 'room_sync_001',
        session: guestSession,
        engine: guestEngine,
        isHost: false,
        hostReconnectGrace: const Duration(milliseconds: 40),
      );

      await _seedInGameRoom(store, hostSession);
      await host.start();
      await guest.start();
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            opponent: 'Quick Table',
            onlineSession: guestSession,
            onlineGameSync: guest,
            cpuThinkDelayProvider: () => Duration.zero,
          ),
        ),
      );
      await tester.pump();

      host.dispose();
      for (var index = 0; index < 20; index++) {
        await tester.pump(const Duration(milliseconds: 10));
        if (guest.hostAvailability == OnlineHostAvailability.unavailable) {
          break;
        }
      }
      await tester.pump(const Duration(milliseconds: 10));

      expect(guest.hostAvailability, OnlineHostAvailability.unavailable);
      expect(
        find.byKey(const ValueKey('online-host-recovery-overlay')),
        findsNothing,
      );
      expect(
        find.text('El anfitrión salió. El CPU continúa la partida.'),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 2));
      guest.dispose();
      hostEngine.dispose();
      guestEngine.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

OnlineParticipant _participant({
  required String id,
  required PlayerColor color,
  required ParticipantKind kind,
}) => OnlineParticipant(
  id: id,
  displayName: 'Player ${color.name}',
  flag: '🇩🇴',
  avatarId: 'avatar_default',
  level: 1,
  color: color,
  kind: kind,
  loadout: const CosmeticLoadout(),
);

OnlineMatchSession _sessionFor(PlayerColor localColor) {
  const ids = <PlayerColor, String>{
    PlayerColor.red: 'host_red',
    PlayerColor.green: 'guest_green',
    PlayerColor.yellow: 'guest_yellow',
    PlayerColor.blue: 'guest_blue',
  };
  return OnlineMatchSession(
    matchId: 'room_sync_001_match',
    seed: 91827,
    mode: GameMode.traditional,
    participants: <OnlineParticipant>[
      for (final color in PlayerColor.values)
        _participant(
          id: ids[color]!,
          color: color,
          kind: color == localColor
              ? ParticipantKind.local
              : ParticipantKind.remoteHuman,
        ),
    ],
  );
}

OnlineTransportClient _transport(
  InMemoryOnlineRealtimeStore store,
  String uid,
) => OnlineTransportClient(
  store: store,
  identity: OnlineTransportIdentity(uid: uid, displayName: uid),
  random: Random(1),
);

GameEngine _engine(PlayerColor localColor) => GameEngine(
  localViewerColor: localColor,
  initialPlayerColor: PlayerColor.red,
  random: Random(7),
  humanName: 'Player ${localColor.name}',
  playerNames: <PlayerColor, String>{
    for (final color in PlayerColor.values) color: 'Player ${color.name}',
  },
);

Future<void> _seedInGameRoom(
  InMemoryOnlineRealtimeStore store,
  OnlineMatchSession session,
) async {
  final now = store.nowMs;
  final room = OnlineRoomRecord(
    id: 'room_sync_001',
    code: RoomCode.parse('ABC234'),
    hostUid: 'host_red',
    visibility: RoomVisibility.private,
    status: RoomStatus.inGame,
    mode: session.mode.name,
    matchFormat: MatchFormat.classic.name,
    members: <String, OnlineRoomMemberRecord>{
      for (final participant in session.participants)
        participant.id: OnlineRoomMemberRecord(
          uid: participant.id,
          displayName: participant.displayName,
          seat: LobbySeatColor.values[participant.color.index],
          joinedAtMs: now,
          ready: true,
        ),
    },
    presence: <String, OnlinePresenceRecord>{
      for (final participant in session.participants)
        participant.id: OnlinePresenceRecord(
          uid: participant.id,
          presence: LobbyPresence.connected,
          changedAtMs: now,
          connectionId: 'seed_${participant.id}',
        ),
    },
    revision: 0,
    createdAtMs: now,
    updatedAtMs: now,
  );
  await store.set('$onlineTransportRoot/rooms/${room.id}', room.toJson());
}
