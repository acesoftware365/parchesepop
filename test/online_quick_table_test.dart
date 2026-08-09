import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/online_lobby.dart';
import 'package:parchesepop/online_match.dart';
import 'package:parchesepop/online_quick_table.dart';
import 'package:parchesepop/online_room_ui.dart';
import 'package:parchesepop/online_transport.dart';
import 'package:parchesepop/online_transport_models.dart';
import 'package:parchesepop/realtime_online_room_controller.dart';

import 'support/in_memory_online_realtime_store.dart';

void main() {
  test(
    'four realtime lobby snapshots prepare the same classic live match',
    () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 40_000);
      final host = _controller(
        store,
        uid: 'host-red',
        name: 'Host Red',
        seed: 1,
        openingRandom: _SequenceRandom(<int>[0, 5, 1, 2]),
      );
      final green = _controller(
        store,
        uid: 'player-green',
        name: 'Player Green',
        seed: 2,
      );
      final yellow = _controller(
        store,
        uid: 'player-yellow',
        name: 'Player Yellow',
        seed: 3,
      );
      final blue = _controller(
        store,
        uid: 'player-blue',
        name: 'Player Blue',
        seed: 4,
      );
      final controllers = <RealtimeOnlineRoomController>[
        host,
        green,
        yellow,
        blue,
      ];
      final prepared = <PreparedOnlineQuickTableMatch>[];
      addTearDown(() async {
        for (final match in prepared) {
          match.sync.dispose();
          match.engine.dispose();
        }
        for (final controller in controllers) {
          await controller.shutdown();
          controller.dispose();
        }
      });

      await host.createRoom(
        mode: OnlineRoomGameMode.chaos,
        visibility: RoomVisibility.private,
      );
      final code = host.lobby!.roomCode;
      await green.joinRoomByCode(code);
      await yellow.joinRoomByCode(code);
      await blue.joinRoomByCode(code);
      await _eventually(
        () => controllers.every(
          (controller) => controller.lobby?.occupiedSeatCount == 4,
        ),
      );
      for (final controller in controllers) {
        await controller.setReady(true);
      }
      await _eventually(
        () => controllers.every(
          (controller) => controller.lobby?.allReady == true,
        ),
      );
      await host.startOpeningRoll();
      await _eventually(
        () => controllers.every(
          (controller) => controller.lobby?.status == RoomStatus.openingRoll,
        ),
      );
      for (final controller in controllers) {
        store.advance(const Duration(milliseconds: 1));
        await controller.rollOpeningDie();
      }
      await _eventually(
        () => controllers.every(
          (controller) => controller.lobby?.status == RoomStatus.starting,
        ),
      );
      expect(host.lobby!.openingRoll!.winnerParticipantId, 'player-green');
      expect(host.lobby!.openingRoll!.clockwiseParticipantIds, <String>[
        'player-green',
        'player-yellow',
        'player-blue',
        'host-red',
      ]);
      await host.markGameStarted();
      await _eventually(
        () => controllers.every(
          (controller) =>
              controller.lobby?.status == RoomStatus.inGame &&
              controller.roomRecord?.status == RoomStatus.inGame,
        ),
      );

      for (var index = 0; index < controllers.length; index++) {
        prepared.add(
          prepareOnlineQuickTableMatch(
            controllers[index],
            engineRandom: Random(100 + index),
          ),
        );
      }
      final hostMatch = prepared[0];
      expect(hostMatch.isHost, isTrue);
      expect(hostMatch.localColor, PlayerColor.red);
      expect(hostMatch.initialPlayerColor, PlayerColor.green);
      expect(hostMatch.engine.currentPlayer.color, PlayerColor.green);
      expect(hostMatch.engine.localViewerColor, PlayerColor.red);
      expect(hostMatch.engine.mode, GameMode.chaos);
      expect(hostMatch.engine.matchFormat, MatchFormat.classic);
      expect(hostMatch.engine.players.first.tokens, hasLength(4));
      expect(
        hostMatch.session.participantForColor(PlayerColor.green).displayName,
        'Player Green',
      );

      for (var index = 0; index < prepared.length; index++) {
        final match = prepared[index];
        expect(match.session.matchId, hostMatch.session.matchId);
        expect(match.session.seed, hostMatch.session.seed);
        expect(match.initialPlayerColor, PlayerColor.green);
        expect(match.localColor, PlayerColor.values[index]);
        expect(
          match.session.participants
              .where((participant) => participant.kind == ParticipantKind.local)
              .single
              .id,
          controllers[index].localParticipantId,
        );
        expect(
          match.session.participants
              .where(
                (participant) =>
                    participant.kind == ParticipantKind.remoteHuman,
              )
              .length,
          3,
        );
        expect(match.engine.currentPlayer.color, PlayerColor.green);
        expect(match.isHost, index == 0);
      }

      await hostMatch.sync.start();
      await prepared[1].sync.start();
      expect(
        jsonEncode(prepared[1].engine.createCheckpoint()),
        jsonEncode(hostMatch.engine.createCheckpoint()),
      );

      final room = host.roomRecord!;
      final wrongStatus = _copyRoom(room, status: RoomStatus.starting);
      expect(
        () => prepareOnlineQuickTableMatchFromSnapshot(
          transport: host.transport,
          localParticipantId: host.localParticipantId,
          lobby: host.lobby!,
          room: wrongStatus,
          roomMode: OnlineRoomGameMode.chaos,
        ),
        throwsA(isA<OnlineQuickTablePreparationException>()),
      );

      final missingMember = Map<String, OnlineRoomMemberRecord>.of(room.members)
        ..remove('player-blue');
      expect(
        () => prepareOnlineQuickTableMatchFromSnapshot(
          transport: host.transport,
          localParticipantId: host.localParticipantId,
          lobby: host.lobby!,
          room: _copyRoom(room, members: missingMember),
          roomMode: OnlineRoomGameMode.chaos,
        ),
        throwsA(isA<OnlineQuickTablePreparationException>()),
      );

      final incomplete = _incompleteOpeningLobby(room);
      expect(
        () => prepareOnlineQuickTableMatchFromSnapshot(
          transport: host.transport,
          localParticipantId: host.localParticipantId,
          lobby: incomplete,
          room: room,
          roomMode: OnlineRoomGameMode.chaos,
        ),
        throwsA(
          isA<OnlineQuickTablePreparationException>().having(
            (error) => error.message,
            'message',
            contains('opening roll'),
          ),
        ),
      );
    },
  );

  test('seat mapping is explicit and exhaustive', () {
    expect(
      LobbySeatColor.values.map(playerColorForLobbySeat),
      PlayerColor.values,
    );
  });
}

RealtimeOnlineRoomController _controller(
  InMemoryOnlineRealtimeStore store, {
  required String uid,
  required String name,
  required int seed,
  Random? openingRandom,
}) => RealtimeOnlineRoomController(
  transport: OnlineTransportClient(
    store: store,
    identity: OnlineTransportIdentity(uid: uid, displayName: name),
    random: Random(seed),
    delay: (duration) async {
      store.advance(duration);
      await Future<void>.delayed(Duration.zero);
    },
  ),
  openingRollRandom: openingRandom,
);

OnlineRoomRecord _copyRoom(
  OnlineRoomRecord room, {
  RoomStatus? status,
  Map<String, OnlineRoomMemberRecord>? members,
}) => OnlineRoomRecord(
  id: room.id,
  code: room.code,
  hostUid: room.hostUid,
  visibility: room.visibility,
  status: status ?? room.status,
  mode: room.mode,
  matchFormat: room.matchFormat,
  members: members ?? room.members,
  presence: room.presence,
  revision: room.revision,
  createdAtMs: room.createdAtMs,
  updatedAtMs: room.updatedAtMs,
);

OnlineLobby _incompleteOpeningLobby(OnlineRoomRecord room) {
  final hostMember = room.members[room.hostUid]!;
  final lobby = OnlineLobby.create(
    roomId: room.id,
    roomCode: room.code,
    hostParticipantId: room.hostUid,
    hostDisplayName: hostMember.displayName,
    visibility: room.visibility,
  );
  for (final member in room.members.values) {
    if (member.uid == room.hostUid) continue;
    lobby.join(
      participantId: member.uid,
      displayName: member.displayName,
      preferredSeat: member.seat,
    );
  }
  for (final participant in lobby.participants) {
    lobby.setReady(actorParticipantId: participant.participantId, ready: true);
  }
  lobby.startOpeningRoll(actorParticipantId: room.hostUid);
  lobby.status = RoomStatus.inGame;
  return lobby;
}

Future<void> _eventually(
  bool Function() predicate, {
  int attempts = 500,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition did not become true after $attempts event-loop turns.');
}

class _SequenceRandom implements Random {
  _SequenceRandom(this.values);

  final List<int> values;
  int _index = 0;

  @override
  int nextInt(int max) {
    if (_index >= values.length) {
      throw StateError('The deterministic random sequence is exhausted.');
    }
    final value = values[_index++];
    if (value < 0 || value >= max) {
      throw RangeError.range(value, 0, max - 1, 'sequence value');
    }
    return value;
  }

  @override
  bool nextBool() => nextInt(2) == 1;

  @override
  double nextDouble() => nextInt(1 << 20) / (1 << 20);
}
