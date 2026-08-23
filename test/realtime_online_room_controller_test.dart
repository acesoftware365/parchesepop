import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/online_lobby.dart';
import 'package:parchesepop/online_room_ui.dart';
import 'package:parchesepop/online_transport.dart';
import 'package:parchesepop/online_transport_models.dart';
import 'package:parchesepop/realtime_online_room_controller.dart';

import 'support/in_memory_online_realtime_store.dart';

final class _ControlledRealtimeStore implements OnlineRealtimeStore {
  _ControlledRealtimeStore(
    this.delegate, {
    this.suppressPublicRoomWatch = false,
    this.publicRoomReadGate,
    this.presenceRegistrationGate,
  });

  final InMemoryOnlineRealtimeStore delegate;
  final bool suppressPublicRoomWatch;
  final Completer<void>? publicRoomReadGate;
  final Completer<void>? presenceRegistrationGate;
  final Completer<void> publicRoomReadStarted = Completer<void>();
  final Completer<void> presenceRegistrationStarted = Completer<void>();

  String get _publicRoomsPath => '$onlineTransportRoot/publicRooms';

  @override
  Future<Object?> read(String path) async {
    if (path == _publicRoomsPath && publicRoomReadGate != null) {
      if (!publicRoomReadStarted.isCompleted) publicRoomReadStarted.complete();
      await publicRoomReadGate!.future;
    }
    return delegate.read(path);
  }

  @override
  Stream<Object?> watch(String path) {
    if (suppressPublicRoomWatch && path == _publicRoomsPath) {
      return const Stream<Object?>.empty();
    }
    return delegate.watch(path);
  }

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
  Future<void> setOnDisconnect(String path, Object? value) async {
    if (presenceRegistrationGate != null && path.contains('/presence/')) {
      if (!presenceRegistrationStarted.isCompleted) {
        presenceRegistrationStarted.complete();
      }
      await presenceRegistrationGate!.future;
    }
    await delegate.setOnDisconnect(path, value);
  }

  @override
  Future<void> cancelOnDisconnect(String path) =>
      delegate.cancelOnDisconnect(path);

  @override
  Future<int> serverNowMs() => delegate.serverNowMs();
}

final class _DelayedWaitingRoomSnapshotStore implements OnlineRealtimeStore {
  _DelayedWaitingRoomSnapshotStore(this.delegate);

  final InMemoryOnlineRealtimeStore delegate;
  final List<StreamController<Object?>> _roomWatchers =
      <StreamController<Object?>>[];
  Object? _lastWaitingRoom;

  void emitDelayedWaitingRoom() {
    final snapshot = _lastWaitingRoom;
    if (snapshot == null) return;
    for (final watcher in List<StreamController<Object?>>.of(_roomWatchers)) {
      if (!watcher.isClosed) watcher.add(snapshot);
    }
  }

  @override
  Future<Object?> read(String path) => delegate.read(path);

  @override
  Stream<Object?> watch(String path) {
    final isRoomRoot =
        path.startsWith('$onlineTransportRoot/rooms/') &&
        path.split('/').length == 3;
    if (!isRoomRoot) return delegate.watch(path);
    late final StreamController<Object?> controller;
    StreamSubscription<Object?>? subscription;
    controller = StreamController<Object?>.broadcast(
      sync: true,
      onListen: () {
        subscription = delegate.watch(path).listen((value) {
          final room = value == null
              ? null
              : OnlineRoomRecord.fromJson(onlineMap(value));
          if (room?.status == RoomStatus.waiting) _lastWaitingRoom = value;
          controller.add(value);
        }, onError: controller.addError);
      },
      onCancel: () async {
        _roomWatchers.remove(controller);
        await subscription?.cancel();
      },
    );
    _roomWatchers.add(controller);
    return controller.stream;
  }

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
}

/// Simulates an Android Firebase child listener that misses the lifecycle
/// event while the room-root listener continues to receive the atomic room.
final class _DroppedAdvancedLobbyWatchStore implements OnlineRealtimeStore {
  _DroppedAdvancedLobbyWatchStore(this.delegate);

  final InMemoryOnlineRealtimeStore delegate;

  @override
  Future<Object?> read(String path) => delegate.read(path);

  @override
  Stream<Object?> watch(String path) {
    final isLobbyState =
        path.startsWith('$onlineTransportRoot/rooms/') &&
        path.endsWith('/lobbyState');
    if (!isLobbyState) return delegate.watch(path);
    return delegate.watch(path).where((raw) {
      if (raw == null) return true;
      return OnlineLobby.fromJson(onlineMap(raw)).status == RoomStatus.waiting;
    });
  }

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
}

/// Simulates a native Firebase socket that stops delivering both room
/// listeners after the initial waiting snapshot while direct reads still
/// reach the server.
final class _DroppedAdvancedRoomListenersStore implements OnlineRealtimeStore {
  _DroppedAdvancedRoomListenersStore(this.delegate);

  final InMemoryOnlineRealtimeStore delegate;

  @override
  Future<Object?> read(String path) => delegate.read(path);

  @override
  Stream<Object?> watch(String path) {
    final isRoomPath = path.startsWith('$onlineTransportRoot/rooms/');
    if (!isRoomPath) return delegate.watch(path);
    return delegate.watch(path).where((raw) {
      if (raw == null) return true;
      if (path.endsWith('/lobbyState')) {
        return OnlineLobby.fromJson(onlineMap(raw)).status ==
            RoomStatus.waiting;
      }
      if (path.split('/').length == 3) {
        return OnlineRoomRecord.fromJson(onlineMap(raw)).status ==
            RoomStatus.waiting;
      }
      return true;
    });
  }

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
}

final class _StalledServerClockStore implements OnlineRealtimeStore {
  _StalledServerClockStore(this.delegate);

  final InMemoryOnlineRealtimeStore delegate;
  int allowedClockReads = 1 << 30;
  int _clockReads = 0;

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
  Future<int> serverNowMs() {
    if (_clockReads++ >= allowedClockReads) return Completer<int>().future;
    return delegate.serverNowMs();
  }
}

void main() {
  group('RealtimeOnlineRoomController', () {
    test(
      'opening roll does not stall when Firebase server clock is unavailable',
      () async {
        final memory = InMemoryOnlineRealtimeStore(initialNowMs: 9_500);
        final store = _StalledServerClockStore(memory);
        final host = RealtimeOnlineRoomController(
          transport: OnlineTransportClient(
            store: store,
            identity: OnlineTransportIdentity(
              uid: 'clock-host',
              displayName: 'Host',
            ),
            random: Random(95),
          ),
        );
        final guest = RealtimeOnlineRoomController(
          transport: OnlineTransportClient(
            store: memory,
            identity: OnlineTransportIdentity(
              uid: 'clock-guest',
              displayName: 'Guest',
            ),
            random: Random(96),
          ),
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
        await guest.joinRoomByCode(host.lobby!.roomCode);
        await _eventually(() => host.lobby?.occupiedSeatCount == 2);
        await host.setReady(true);
        await guest.setReady(true);
        await _eventually(() => host.lobby?.canStart == true);

        // Reserving the two CPU seats needs one valid clock read. The next
        // read is the lifecycle sample that Android may never deliver.
        store.allowedClockReads = store._clockReads + 1;
        await host.startOpeningRoll();

        expect(host.lobby?.status, RoomStatus.openingRoll);
        expect(host.roomRecord?.status, RoomStatus.openingRoll);
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );

    test(
      'a delayed waiting room snapshot cannot roll back the opening roll',
      () async {
        final memory = InMemoryOnlineRealtimeStore(initialNowMs: 9_000);
        final store = _DelayedWaitingRoomSnapshotStore(memory);
        final host = RealtimeOnlineRoomController(
          transport: OnlineTransportClient(
            store: store,
            identity: OnlineTransportIdentity(
              uid: 'race-host',
              displayName: 'Host',
            ),
            random: Random(90),
          ),
        );
        final guest = RealtimeOnlineRoomController(
          transport: OnlineTransportClient(
            store: store,
            identity: OnlineTransportIdentity(
              uid: 'race-guest',
              displayName: 'Guest',
            ),
            random: Random(91),
          ),
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
        await guest.joinRoomByCode(host.lobby!.roomCode);
        await _eventually(() => host.lobby?.occupiedSeatCount == 2);
        await host.setReady(true);
        await guest.setReady(true);
        await _eventually(() => host.lobby?.canStart == true);

        memory.clearOperations();
        await host.startOpeningRoll();
        await _eventually(() => host.lobby?.status == RoomStatus.openingRoll);
        store.emitDelayedWaitingRoom();
        await Future<void>.delayed(Duration.zero);

        expect(host.lobby?.status, RoomStatus.openingRoll);
        expect(host.lobby?.openingRoll, isNotNull);
        expect(host.roomRecord?.status, RoomStatus.openingRoll);
        expect(
          memory.operations.where(
            (operation) =>
                operation.kind == InMemoryStoreOperationKind.update &&
                operation.path ==
                    '$onlineTransportRoot/rooms/${host.roomRecord!.id}',
          ),
          // One atomic update reserves the two CPU seats for this two-human
          // room; the second advances the room lifecycle to openingRoll.
          hasLength(2),
        );
        expect(
          memory.operations.where(
            (operation) =>
                operation.kind == InMemoryStoreOperationKind.transaction &&
                operation.path ==
                    '$onlineTransportRoot/rooms/${host.roomRecord!.id}',
          ),
          isEmpty,
        );
      },
    );

    test(
      'room-root snapshot advances a guest when child lobby event is dropped',
      () async {
        final memory = InMemoryOnlineRealtimeStore(initialNowMs: 9_250);
        final guestStore = _DroppedAdvancedLobbyWatchStore(memory);
        final host = RealtimeOnlineRoomController(
          transport: OnlineTransportClient(
            store: memory,
            identity: OnlineTransportIdentity(
              uid: 'root-host',
              displayName: 'Host',
            ),
            random: Random(92),
          ),
        );
        final guest = RealtimeOnlineRoomController(
          transport: OnlineTransportClient(
            store: guestStore,
            identity: OnlineTransportIdentity(
              uid: 'root-guest',
              displayName: 'Guest',
            ),
            random: Random(93),
          ),
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
        await guest.joinRoomByCode(host.lobby!.roomCode);
        await _eventually(() => host.lobby?.occupiedSeatCount == 2);
        await host.setReady(true);
        await guest.setReady(true);
        await _eventually(() => host.lobby?.canStart == true);

        await host.startOpeningRoll();

        await _eventually(() => guest.lobby?.status == RoomStatus.openingRoll);
        expect(guest.lobby?.openingRoll, isNotNull);
        expect(guest.roomRecord?.status, RoomStatus.openingRoll);
      },
    );

    test(
      'authoritative reconciliation advances a guest when both listeners drop',
      () async {
        final memory = InMemoryOnlineRealtimeStore(initialNowMs: 9_500);
        final guestStore = _DroppedAdvancedRoomListenersStore(memory);
        final host = RealtimeOnlineRoomController(
          transport: OnlineTransportClient(
            store: memory,
            identity: OnlineTransportIdentity(
              uid: 'poll-host',
              displayName: 'Host',
            ),
            random: Random(94),
          ),
          roomReconciliationInterval: const Duration(milliseconds: 5),
        );
        final guest = RealtimeOnlineRoomController(
          transport: OnlineTransportClient(
            store: guestStore,
            identity: OnlineTransportIdentity(
              uid: 'poll-guest',
              displayName: 'Guest',
            ),
            random: Random(95),
          ),
          roomReconciliationInterval: const Duration(milliseconds: 5),
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
        await guest.joinRoomByCode(host.lobby!.roomCode);
        await _eventually(() => host.lobby?.occupiedSeatCount == 2);
        await host.setReady(true);
        await guest.setReady(true);
        await _eventually(() => host.lobby?.canStart == true);

        await host.startOpeningRoll();

        await _eventually(
          () => guest.lobby?.status == RoomStatus.openingRoll,
          delay: const Duration(milliseconds: 5),
        );
        expect(guest.lobby?.openingRoll, isNotNull);
        expect(guest.roomRecord?.status, RoomStatus.openingRoll);
      },
    );

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
      'two humans start with deterministic CPU seats and complete the opening roll',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 15_000);
        final host = _controller(
          store,
          uid: 'two-host',
          name: 'Host',
          transportSeed: 15,
          openingRollRandom: _SequenceRandom(<int>[0, 1, 2, 3]),
        );
        final guest = _controller(
          store,
          uid: 'two-guest',
          name: 'Guest',
          transportSeed: 16,
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
        await guest.joinRoomByCode(host.lobby!.roomCode);
        await _eventually(() => host.lobby?.occupiedSeatCount == 2);

        await host.setReady(true);
        await guest.setReady(true);
        await _eventually(
          () => host.lobby?.canStart == true && guest.lobby?.canStart == true,
        );

        await host.startOpeningRoll();
        await _eventually(
          () =>
              host.lobby?.status == RoomStatus.openingRoll &&
              guest.lobby?.status == RoomStatus.openingRoll &&
              host.lobby?.occupiedSeatCount == 4,
        );
        expect(host.lobby!.participants.map((p) => p.participantId), [
          'two-host',
          'two-guest',
          'cpu_${host.lobby!.roomCode.value}_yellow',
          'cpu_${host.lobby!.roomCode.value}_blue',
        ]);
        expect(
          host.lobby!.openingRoll!.currentRolls.keys,
          containsAll([
            'cpu_${host.lobby!.roomCode.value}_yellow',
            'cpu_${host.lobby!.roomCode.value}_blue',
          ]),
        );

        await host.rollOpeningDie();
        await guest.rollOpeningDie();
        await _eventually(
          () =>
              host.lobby?.status == RoomStatus.starting &&
              guest.lobby?.status == RoomStatus.starting &&
              host.lobby?.openingRoll?.clockwiseParticipantIds.length == 4,
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

    test(
      'cancelPendingJoin invalidates and cleans up an in-flight join',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 50_000);
        final hostTransport = OnlineTransportClient(
          store: store,
          identity: OnlineTransportIdentity(
            uid: 'host-cancel',
            displayName: 'Host',
          ),
          random: Random(50),
        );
        final room = await hostTransport.createRoom(
          visibility: RoomVisibility.private,
          mode: OnlineRoomGameMode.classic.name,
          matchFormat: 'quickTable',
        );
        final pollGate = Completer<void>();
        final guest = RealtimeOnlineRoomController(
          transport: OnlineTransportClient(
            store: store,
            identity: OnlineTransportIdentity(
              uid: 'guest-cancel',
              displayName: 'Guest',
            ),
            random: Random(51),
            delay: (_) => pollGate.future,
          ),
        );
        addTearDown(guest.dispose);

        final join = guest.joinRoomByCode(room.code);
        await _eventually(() {
          final root = onlineMap(store.debugSnapshot[onlineTransportRoot]);
          final requests = onlineMap(root['joinRequests']);
          return onlineMap(requests[room.id]).containsKey('guest-cancel');
        });
        await guest.cancelPendingJoin();
        pollGate.complete();

        await expectLater(
          join,
          throwsA(
            isA<OnlineTransportException>().having(
              (error) => error.code,
              'code',
              OnlineTransportErrorCode.joinCancelled,
            ),
          ),
        );
        expect(guest.lobby, isNull);
        expect(
          await store.read(
            '$onlineTransportRoot/joinRequests/${room.id}/guest-cancel',
          ),
          isNull,
        );
      },
    );

    test(
      'public join cancellation survives a pending directory refresh',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 60_000);
        final hostTransport = OnlineTransportClient(
          store: store,
          identity: OnlineTransportIdentity(
            uid: 'public-refresh-host',
            displayName: 'Host',
          ),
          random: Random(60),
        );
        final room = await hostTransport.createRoom(
          visibility: RoomVisibility.public,
          mode: OnlineRoomGameMode.classic.name,
          matchFormat: 'quickTable',
        );
        final readGate = Completer<void>();
        final controlledStore = _ControlledRealtimeStore(
          store,
          suppressPublicRoomWatch: true,
          publicRoomReadGate: readGate,
        );
        final guest = RealtimeOnlineRoomController(
          transport: OnlineTransportClient(
            store: controlledStore,
            identity: OnlineTransportIdentity(
              uid: 'public-refresh-guest',
              displayName: 'Guest',
            ),
            random: Random(61),
          ),
        );
        addTearDown(() async {
          await guest.shutdown();
          guest.dispose();
          await hostTransport.closeRoom(room.id);
        });

        final join = guest.joinPublicRoom(room.id);
        await controlledStore.publicRoomReadStarted.future;
        await guest.cancelPendingJoin();
        readGate.complete();

        await expectLater(
          join,
          throwsA(
            isA<OnlineTransportException>().having(
              (error) => error.code,
              'code',
              OnlineTransportErrorCode.joinCancelled,
            ),
          ),
        );
        expect(guest.lobby, isNull);
        final storedRoom = await hostTransport.readRoom(room.id);
        expect(storedRoom!.members, isNot(contains('public-refresh-guest')));
        expect(
          await store.read(
            '$onlineTransportRoot/joinRequests/${room.id}/public-refresh-guest',
          ),
          isNull,
        );
      },
    );

    test('cancel removes membership admitted during a pending poll', () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 65_000);
      final hostTransport = OnlineTransportClient(
        store: store,
        identity: OnlineTransportIdentity(
          uid: 'late-admission-host',
          displayName: 'Host',
        ),
        random: Random(65),
      );
      final room = await hostTransport.createRoom(
        visibility: RoomVisibility.private,
        mode: OnlineRoomGameMode.classic.name,
        matchFormat: 'quickTable',
      );
      final pollGate = Completer<void>();
      final pollStarted = Completer<void>();
      final guest = RealtimeOnlineRoomController(
        transport: OnlineTransportClient(
          store: store,
          identity: OnlineTransportIdentity(
            uid: 'late-admission-guest',
            displayName: 'Guest',
          ),
          random: Random(66),
          delay: (_) {
            if (!pollStarted.isCompleted) pollStarted.complete();
            return pollGate.future;
          },
        ),
      );
      addTearDown(() async {
        await guest.shutdown();
        guest.dispose();
        await hostTransport.closeRoom(room.id);
      });

      final join = guest.joinRoomByCode(room.code);
      await pollStarted.future;
      await hostTransport.admitPendingJoinRequests(room.id);
      expect(
        (await hostTransport.readRoom(room.id))!.members,
        contains('late-admission-guest'),
      );
      await guest.cancelPendingJoin();
      pollGate.complete();

      await expectLater(
        join,
        throwsA(
          isA<OnlineTransportException>().having(
            (error) => error.code,
            'code',
            OnlineTransportErrorCode.joinCancelled,
          ),
        ),
      );
      expect(guest.lobby, isNull);
      expect(
        (await hostTransport.readRoom(room.id))!.members,
        isNot(contains('late-admission-guest')),
      );
    });

    test(
      'cancelled late room creation closes every published artifact',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 70_000);
        final presenceGate = Completer<void>();
        final controlledStore = _ControlledRealtimeStore(
          store,
          presenceRegistrationGate: presenceGate,
        );
        final controller = RealtimeOnlineRoomController(
          transport: OnlineTransportClient(
            store: controlledStore,
            identity: OnlineTransportIdentity(
              uid: 'cancel-create-host',
              displayName: 'Host',
            ),
            random: Random(70),
          ),
        );
        addTearDown(() async {
          await controller.shutdown();
          controller.dispose();
        });

        final creation = controller.createRoom(
          mode: OnlineRoomGameMode.classic,
          visibility: RoomVisibility.public,
        );
        await controlledStore.presenceRegistrationStarted.future;
        await controller.cancelPendingCreate();
        presenceGate.complete();

        await expectLater(
          creation,
          throwsA(isA<OnlineRoomOperationCancelledException>()),
        );
        expect(controller.lobby, isNull);
        expect(controller.roomRecord, isNull);
        final rooms = onlineMap(await store.read('$onlineTransportRoot/rooms'));
        expect(rooms, hasLength(1));
        final room = OnlineRoomRecord.fromJson(rooms.values.single);
        expect(room.status, RoomStatus.closed);
        expect(await controller.transport.listPublicRooms(), isEmpty);
        expect(
          await store.read('$onlineTransportRoot/roomCodes/${room.code.value}'),
          isNull,
        );
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
  Duration delay = Duration.zero,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(delay);
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
