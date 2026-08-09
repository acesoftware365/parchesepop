import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/online_lobby.dart';
import 'package:parchesepop/online_room_ui.dart';
import 'package:parchesepop/online_transport.dart';
import 'package:parchesepop/online_transport_models.dart';
import 'package:parchesepop/realtime_online_room_controller.dart';

import 'support/in_memory_online_realtime_store.dart';

void main() {
  group('RealtimeOnlineRoomController', () {
    test(
      'four controllers create, join, ready, reroll a tie, and enter game',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 10_000);
        final host = _controller(
          store,
          uid: 'a-host',
          name: 'Host',
          transportSeed: 1,
          openingRollRandom: _SequenceRandom(<int>[5, 5, 1, 0, 3, 2]),
        );
        final green = _controller(
          store,
          uid: 'b-green',
          name: 'Green',
          transportSeed: 2,
        );
        final yellow = _controller(
          store,
          uid: 'c-yellow',
          name: 'Yellow',
          transportSeed: 3,
        );
        final blue = _controller(
          store,
          uid: 'd-blue',
          name: 'Blue',
          transportSeed: 4,
        );
        final controllers = <RealtimeOnlineRoomController>[
          host,
          green,
          yellow,
          blue,
        ];
        addTearDown(() async {
          for (final controller in controllers) {
            await controller.shutdown();
            controller.dispose();
          }
        });

        await host.createRoom(
          mode: OnlineRoomGameMode.chaos,
          visibility: RoomVisibility.public,
        );
        final roomId = host.lobby!.roomId;
        final code = host.lobby!.roomCode;

        await _eventually(
          () => green.publicRooms.any((room) => room.roomId == roomId),
        );
        await green.joinPublicRoom(roomId);
        await yellow.joinRoomByCode(code);
        await blue.joinRoomByCode(code);
        await _eventually(
          () => controllers.every(
            (controller) => controller.lobby?.occupiedSeatCount == 4,
          ),
        );

        expect(
          host.lobby!.participants.map((participant) => participant.seat),
          <LobbySeatColor>[
            LobbySeatColor.red,
            LobbySeatColor.green,
            LobbySeatColor.yellow,
            LobbySeatColor.blue,
          ],
        );

        for (final controller in controllers) {
          await controller.setReady(true);
        }
        await _eventually(
          () => controllers.every((controller) => controller.lobby!.allReady),
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
        await _eventually(() {
          final opening = host.lobby?.openingRoll;
          return opening?.round == 2 && opening!.history.length == 1;
        });

        final tied = host.lobby!.openingRoll!;
        expect(tied.history.single.rolls, <String, int>{
          'a-host': 6,
          'b-green': 6,
          'c-yellow': 2,
          'd-blue': 1,
        });
        expect(tied.eligibleParticipantIds, <String>['a-host', 'b-green']);

        store.advance(const Duration(milliseconds: 1));
        await host.rollOpeningDie();
        store.advance(const Duration(milliseconds: 1));
        await green.rollOpeningDie();
        await _eventually(
          () => controllers.every(
            (controller) => controller.lobby?.status == RoomStatus.starting,
          ),
        );

        final completed = host.lobby!.openingRoll!;
        expect(completed.winnerParticipantId, 'a-host');
        expect(completed.clockwiseParticipantIds, <String>[
          'a-host',
          'b-green',
          'c-yellow',
          'd-blue',
        ]);

        final gameReady = host.gameReady.first;
        await host.markGameStarted();
        expect(
          (await gameReady.timeout(const Duration(seconds: 1))).status,
          RoomStatus.inGame,
        );
        await _eventually(
          () => controllers.every(
            (controller) => controller.lobby?.status == RoomStatus.inGame,
          ),
        );

        final storedLobby = OnlineLobby.fromJson(
          onlineMap(
            await store.read('$onlineTransportRoot/rooms/$roomId/lobbyState'),
          ),
        );
        expect(storedLobby.status, RoomStatus.inGame);
        expect(
          onlineMap(
            await store.read(
              '$onlineTransportRoot/rooms/$roomId/openingRollRequests',
            ),
          ),
          isEmpty,
        );
        expect(
          (await host.transport.readRoom(roomId))!.status,
          RoomStatus.inGame,
        );
      },
    );

    test(
      'privacy, kick, leave, and close remain live across controllers',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 20_000);
        final host = _controller(
          store,
          uid: 'host',
          name: 'Host',
          transportSeed: 11,
        );
        final guest = _controller(
          store,
          uid: 'guest',
          name: 'Guest',
          transportSeed: 12,
        );
        addTearDown(() async {
          await host.shutdown();
          await guest.shutdown();
          host.dispose();
          guest.dispose();
        });

        await host.createRoom(
          mode: OnlineRoomGameMode.classic,
          visibility: RoomVisibility.public,
        );
        final code = host.lobby!.roomCode;
        await _eventually(() => guest.publicRooms.isNotEmpty);
        await guest.joinRoomByCode(code);
        await _eventually(() => host.lobby?.occupiedSeatCount == 2);

        await host.changeVisibility(RoomVisibility.private);
        await _eventually(
          () =>
              host.lobby?.visibility == RoomVisibility.private &&
              guest.lobby?.visibility == RoomVisibility.private &&
              guest.publicRooms.isEmpty,
        );
        await host.changeVisibility(RoomVisibility.public);
        await _eventually(() => guest.publicRooms.isNotEmpty);

        await host.kick('guest');
        await _eventually(
          () => host.lobby?.occupiedSeatCount == 1 && guest.lobby == null,
        );

        store.advance(const Duration(milliseconds: 1));
        await guest.joinRoomByCode(code);
        await _eventually(() => host.lobby?.occupiedSeatCount == 2);
        await guest.setReady(true);
        await _eventually(() => host.lobby!.participantById('guest').ready);
        await guest.leaveRoom();
        await _eventually(
          () => host.lobby?.occupiedSeatCount == 1 && guest.lobby == null,
        );

        await host.closeRoom();
        expect(host.lobby?.status, RoomStatus.closed);
        expect(await host.transport.listPublicRooms(), isEmpty);
      },
    );

    test(
      'closed room dismissal coalesces cleanup for host and guest',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 30_000);
        final host = _controller(
          store,
          uid: 'close-host',
          name: 'Host',
          transportSeed: 21,
        );
        final guest = _controller(
          store,
          uid: 'close-guest',
          name: 'Guest',
          transportSeed: 22,
        );
        addTearDown(() async {
          await host.shutdown();
          await guest.shutdown();
          host.dispose();
          guest.dispose();
        });

        await host.createRoom(
          mode: OnlineRoomGameMode.classic,
          visibility: RoomVisibility.private,
        );
        final roomId = host.lobby!.roomId;
        await guest.joinRoomByCode(host.lobby!.roomCode);
        await _eventually(() => host.lobby?.occupiedSeatCount == 2);

        store.clearOperations();
        await host.closeRoom();
        await _eventually(
          () =>
              host.lobby?.status == RoomStatus.closed &&
              guest.lobby?.status == RoomStatus.closed,
        );

        await Future.wait(<Future<void>>[
          host.dismissClosedRoom(),
          host.dismissClosedRoom(),
          guest.dismissClosedRoom(),
          guest.dismissClosedRoom(),
        ]);

        expect(host.lobby, isNull);
        expect(host.roomRecord, isNull);
        expect(guest.lobby, isNull);
        expect(guest.roomRecord, isNull);
        expect(
          store.operations.where(
            (operation) =>
                operation.kind == InMemoryStoreOperationKind.transaction &&
                operation.path == '$onlineTransportRoot/rooms/$roomId',
          ),
          hasLength(1),
        );

        await store.set(
          '$onlineTransportRoot/rooms/$roomId/lobbyState/status',
          RoomStatus.waiting.name,
        );
        await Future<void>.delayed(Duration.zero);
        expect(host.lobby, isNull);
        expect(guest.lobby, isNull);
      },
    );
  });
}

RealtimeOnlineRoomController _controller(
  InMemoryOnlineRealtimeStore store, {
  required String uid,
  required String name,
  required int transportSeed,
  Random? openingRollRandom,
}) {
  Future<void> advanceInsteadOfWaiting(Duration duration) async {
    store.advance(duration);
    await Future<void>.delayed(Duration.zero);
  }

  return RealtimeOnlineRoomController(
    transport: OnlineTransportClient(
      store: store,
      identity: OnlineTransportIdentity(uid: uid, displayName: name),
      random: Random(transportSeed),
      delay: advanceInsteadOfWaiting,
    ),
    openingRollRandom: openingRollRandom,
  );
}

Future<void> _eventually(
  bool Function() predicate, {
  int attempts = 300,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition did not become true after $attempts event-loop turns.');
}

final class _SequenceRandom implements Random {
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
