import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/app_language.dart';
import 'package:parchesepop/online_invite.dart';
import 'package:parchesepop/online_lobby.dart';
import 'package:parchesepop/online_room_ui.dart';
import 'package:parchesepop/online_transport.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SequenceRandom implements Random {
  _SequenceRandom(Iterable<int> values) : _values = List<int>.of(values);

  final List<int> _values;

  @override
  bool nextBool() => nextInt(2) == 1;

  @override
  double nextDouble() => nextInt(1 << 20) / (1 << 20);

  @override
  int nextInt(int max) {
    if (_values.isEmpty) throw StateError('Random sequence exhausted.');
    return _values.removeAt(0) % max;
  }
}

class _FakeOnlineRoomController extends ChangeNotifier
    implements OnlineRoomController {
  _FakeOnlineRoomController({this.localParticipantId = 'host', Random? random})
    : random = random ?? Random(42);

  @override
  final String localParticipantId;
  final Random random;

  OnlineLobby? _lobby;
  OnlineRoomGameMode? _roomMode;
  List<PublicRoomSummary> rooms = [];
  bool loading = false;
  String? roomsError;
  int refreshCalls = 0;
  RoomCode? joinedCode;
  String? joinedPublicRoomId;
  OnlineRoomGameMode? createdMode;
  RoomVisibility? createdVisibility;
  int leaveCalls = 0;
  int closeCalls = 0;
  int dismissClosedCalls = 0;

  @override
  OnlineLobby? get lobby => _lobby;

  @override
  OnlineRoomGameMode? get roomMode => _roomMode;

  @override
  List<PublicRoomSummary> get publicRooms => List.unmodifiable(rooms);

  @override
  bool get loadingPublicRooms => loading;

  @override
  String? get publicRoomsError => roomsError;

  @override
  Future<void> refreshPublicRooms() async {
    refreshCalls++;
    notifyListeners();
  }

  @override
  Future<void> createRoom({
    required OnlineRoomGameMode mode,
    required RoomVisibility visibility,
  }) async {
    createdMode = mode;
    createdVisibility = visibility;
    _roomMode = mode;
    _lobby = OnlineLobby.create(
      roomId: 'created-room',
      roomCode: RoomCode.parse('ABC234'),
      hostParticipantId: localParticipantId,
      hostDisplayName: 'Juan',
      visibility: visibility,
    );
    notifyListeners();
  }

  @override
  Future<void> joinRoomByCode(RoomCode roomCode) async {
    joinedCode = roomCode;
    _joinAsGuest(roomCode: roomCode, roomId: 'code-room');
  }

  @override
  Future<void> joinPublicRoom(String roomId) async {
    joinedPublicRoomId = roomId;
    final summary = rooms.firstWhere((room) => room.roomId == roomId);
    _joinAsGuest(roomCode: summary.roomCode, roomId: roomId);
  }

  void _joinAsGuest({required RoomCode roomCode, required String roomId}) {
    _roomMode = OnlineRoomGameMode.classic;
    _lobby = OnlineLobby.create(
      roomId: roomId,
      roomCode: roomCode,
      hostParticipantId: 'remote-host',
      hostDisplayName: 'Friend Host',
      visibility: RoomVisibility.private,
    )..join(participantId: localParticipantId, displayName: 'Juan');
    notifyListeners();
  }

  void createFullHostRoom({bool ready = false}) {
    _roomMode = OnlineRoomGameMode.classic;
    _lobby =
        OnlineLobby.create(
            roomId: 'full-room',
            roomCode: RoomCode.parse('ABC234'),
            hostParticipantId: localParticipantId,
            hostDisplayName: 'Juan',
            visibility: RoomVisibility.private,
          )
          ..join(participantId: 'green', displayName: 'Green Player')
          ..join(participantId: 'yellow', displayName: 'Yellow Player')
          ..join(participantId: 'blue', displayName: 'Blue Player');
    if (ready) {
      for (final participant in _lobby!.participants) {
        _lobby!.setReady(
          actorParticipantId: participant.participantId,
          ready: true,
        );
      }
    }
    notifyListeners();
  }

  @override
  Future<void> setReady(bool ready) async {
    _lobby!.setReady(actorParticipantId: localParticipantId, ready: ready);
    notifyListeners();
  }

  @override
  Future<void> changeVisibility(RoomVisibility visibility) async {
    _lobby!.changeVisibility(
      actorParticipantId: localParticipantId,
      visibility: visibility,
    );
    notifyListeners();
  }

  @override
  Future<void> kick(String participantId) async {
    _lobby!.kick(
      actorParticipantId: localParticipantId,
      targetParticipantId: participantId,
    );
    notifyListeners();
  }

  @override
  Future<void> leaveRoom() async {
    leaveCalls++;
    _lobby = null;
    notifyListeners();
  }

  @override
  Future<void> closeRoom() async {
    closeCalls++;
    _lobby!.close(actorParticipantId: localParticipantId);
    notifyListeners();
  }

  @override
  Future<void> dismissClosedRoom() async {
    dismissClosedCalls++;
    _lobby = null;
    _roomMode = null;
    notifyListeners();
  }

  void serverCloseRoom() {
    final current = _lobby!;
    current.close(actorParticipantId: current.hostParticipantId);
    notifyListeners();
  }

  @override
  Future<void> startOpeningRoll() async {
    _lobby!.startOpeningRoll(actorParticipantId: localParticipantId);
    notifyListeners();
  }

  @override
  Future<void> rollOpeningDie() async {
    _lobby!.rollOpeningDie(
      actorParticipantId: localParticipantId,
      random: random,
    );
    notifyListeners();
  }

  void serverRollFor(String participantId) {
    _lobby!.rollOpeningDie(actorParticipantId: participantId, random: random);
    notifyListeners();
  }

  @override
  Future<void> markGameStarted() async {
    _lobby!.markGameStarted(actorParticipantId: localParticipantId);
    notifyListeners();
  }
}

Future<void> _pumpPhone(WidgetTester tester, Widget home) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(393, 852);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(theme: ThemeData(useMaterial3: true), home: home),
  );
  await tester.pump();
}

Future<void> _pumpLobbyAboveEntry(
  WidgetTester tester,
  OnlineRoomController controller,
) async {
  await _pumpPhone(
    tester,
    const Scaffold(body: Center(child: Text('MESA RÁPIDA · ENTRADA'))),
  );
  final entryContext = tester.element(find.text('MESA RÁPIDA · ENTRADA'));
  unawaited(
    Navigator.of(entryContext).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RoomLobbyScreen(controller: controller),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectPrimaryVisible(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  expect(finder.hitTestable(), findsOneWidget);
  final rect = tester.getRect(finder);
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(852));
}

void main() {
  test('room errors use safe player copy instead of raw diagnostics', () {
    expect(
      onlineRoomErrorMessage(
        const OnlineTransportException(
          OnlineTransportErrorCode.joinTimedOut,
          '/onlineV2/rooms/private-user-id timed out',
        ),
      ),
      'El anfitrión no respondió a tiempo. Inténtalo otra vez.',
    );
    final unexpected = onlineRoomErrorMessage(
      StateError('/onlineV2/rooms/private-user-id'),
    );
    expect(unexpected, contains('No pudimos completar la acción online'));
    expect(unexpected, isNot(contains('/onlineV2')));
    expect(unexpected, isNot(contains('private-user-id')));
  });

  testWidgets('Quick Table follows the English language scope', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final language = AppLanguageController();
    final controller = _FakeOnlineRoomController();
    addTearDown(language.dispose);
    addTearDown(controller.dispose);
    await language.select(AppLanguagePreference.english);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      AppLanguageScope(
        controller: language,
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: QuickTableHubScreen(controller: controller, onPlayLocal: () {}),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('PLAY WITH FRIENDS'), findsOneWidget);
    expect(find.text('CREATE ROOM'), findsOneWidget);
    expect(find.text('JOIN WITH CODE'), findsOneWidget);
    expect(find.text('PUBLIC ROOMS'), findsOneWidget);
    expect(find.text('LOCAL MATCH'), findsOneWidget);
    expect(find.text('JUEGA CON AMIGOS'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hub keeps all four primary actions visible without scrolling', (
    tester,
  ) async {
    final controller = _FakeOnlineRoomController();
    var localStarted = false;
    await _pumpPhone(
      tester,
      QuickTableHubScreen(
        controller: controller,
        onPlayLocal: () => localStarted = true,
      ),
    );

    for (final key in [
      'quick-table-create-room',
      'quick-table-join-code',
      'quick-table-public-rooms',
      'quick-table-play-local',
    ]) {
      _expectPrimaryVisible(tester, find.byKey(ValueKey(key)));
    }
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('quick-table-play-local')));
    expect(localStarted, isTrue);
  });

  testWidgets('create flow selects Chaos/public and reaches its lobby', (
    tester,
  ) async {
    final controller = _FakeOnlineRoomController();
    await _pumpPhone(
      tester,
      QuickTableHubScreen(controller: controller, onPlayLocal: () {}),
    );

    await tester.tap(find.byKey(const ValueKey('quick-table-create-room')));
    await tester.pumpAndSettle();
    _expectPrimaryVisible(
      tester,
      find.byKey(const ValueKey('create-room-submit')),
    );
    expect(find.byType(SingleChildScrollView), findsNothing);

    await tester.tap(find.text('CAOS'));
    await tester.pump();
    await tester.tap(find.text('PÚBLICA'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('create-room-submit')));
    await tester.pumpAndSettle();

    expect(controller.createdMode, OnlineRoomGameMode.chaos);
    expect(controller.createdVisibility, RoomVisibility.public);
    expect(find.byType(RoomLobbyScreen), findsOneWidget);
    expect(find.text('ABC234'), findsOneWidget);
    _expectPrimaryVisible(tester, find.byKey(const ValueKey('lobby-ready')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('join code validates six characters before joining', (
    tester,
  ) async {
    final controller = _FakeOnlineRoomController(localParticipantId: 'local');
    await _pumpPhone(
      tester,
      QuickTableHubScreen(controller: controller, onPlayLocal: () {}),
    );
    await tester.tap(find.byKey(const ValueKey('quick-table-join-code')));
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey('join-room-code-field'));
    final submit = find.byKey(const ValueKey('join-room-code-submit'));
    _expectPrimaryVisible(tester, submit);
    expect(find.byType(SingleChildScrollView), findsNothing);

    await tester.enterText(field, 'abc12o');
    await tester.pump();
    expect(find.text('ABC12O'), findsOneWidget);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    expect(find.textContaining('sin I, O, 0 ni 1'), findsOneWidget);

    await tester.enterText(field, 'abc234');
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(controller.joinedCode?.value, 'ABC234');
    expect(find.byType(RoomLobbyScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('public directory joins a visible room', (tester) async {
    final controller = _FakeOnlineRoomController(localParticipantId: 'local')
      ..rooms = [
        PublicRoomSummary(
          roomId: 'public-1',
          roomCode: RoomCode.parse('BCD234'),
          hostDisplayName: 'Maria',
          mode: OnlineRoomGameMode.classic,
          occupiedSeats: 2,
        ),
      ];
    await _pumpPhone(
      tester,
      QuickTableHubScreen(controller: controller, onPlayLocal: () {}),
    );
    await tester.tap(find.byKey(const ValueKey('quick-table-public-rooms')));
    await tester.pumpAndSettle();

    expect(controller.refreshCalls, 1);
    expect(find.text('Maria'), findsOneWidget);
    final join = find.byKey(const ValueKey('join-public-room-public-1'));
    _expectPrimaryVisible(tester, join);
    await tester.tap(join);
    await tester.pumpAndSettle();

    expect(controller.joinedPublicRoomId, 'public-1');
    expect(find.byType(RoomLobbyScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('host controls share, privacy, kick, close, and start', (
    tester,
  ) async {
    final controller = _FakeOnlineRoomController()
      ..createFullHostRoom(ready: true);
    ShareParams? shared;
    final shareService = RoomInviteShareService(
      nativeShare: (params) async {
        shared = params;
        return const ShareResult('test', ShareResultStatus.success);
      },
    );
    await _pumpPhone(
      tester,
      RoomLobbyScreen(controller: controller, shareService: shareService),
    );

    _expectPrimaryVisible(
      tester,
      find.byKey(const ValueKey('lobby-start-opening-roll')),
    );
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byKey(const ValueKey('lobby-share-invite')), findsOneWidget);
    expect(find.byKey(const ValueKey('lobby-close-room')), findsOneWidget);
    expect(find.byKey(const ValueKey('kick-green')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('lobby-share-invite')));
    await tester.pumpAndSettle();
    expect(shared?.text, contains('ABC234'));

    await tester.tap(find.text('PÚBLICA'));
    await tester.pumpAndSettle();
    expect(controller.lobby?.visibility, RoomVisibility.public);

    await tester.tap(find.byKey(const ValueKey('kick-green')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-kick-player')));
    await tester.pumpAndSettle();
    expect(controller.lobby?.participantForSeat(LobbySeatColor.green), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening roll shows highest-only tie reround and winner order', (
    tester,
  ) async {
    final controller = _FakeOnlineRoomController(
      random: _SequenceRandom([5, 5, 3, 1, 1, 4]),
    )..createFullHostRoom(ready: true);
    await controller.startOpeningRoll();
    await _pumpPhone(tester, RoomLobbyScreen(controller: controller));

    final rollButton = find.byKey(const ValueKey('lobby-roll-opening-die'));
    _expectPrimaryVisible(tester, rollButton);
    expect(find.byType(SingleChildScrollView), findsNothing);
    await tester.tap(rollButton);
    await tester.pump();
    controller.serverRollFor('green');
    controller.serverRollFor('yellow');
    controller.serverRollFor('blue');
    await tester.pump();

    expect(find.text('DESEMPATE · RONDA 2'), findsOneWidget);
    expect(find.text('TIRAR DESEMPATE'), findsOneWidget);
    _expectPrimaryVisible(tester, rollButton);

    await tester.tap(rollButton);
    await tester.pump();
    controller.serverRollFor('green');
    await tester.pump();

    expect(controller.lobby?.openingRoll?.winnerParticipantId, 'green');
    expect(controller.lobby?.openingRoll?.clockwiseParticipantIds, [
      'green',
      'yellow',
      'blue',
      'host',
    ]);
    final start = find.byKey(const ValueKey('lobby-start-game'));
    _expectPrimaryVisible(tester, start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(controller.lobby?.status, RoomStatus.inGame);
    expect(tester.takeException(), isNull);
  });

  testWidgets('host can close a waiting room from the fixed header action', (
    tester,
  ) async {
    final controller = _FakeOnlineRoomController()..createFullHostRoom();
    await _pumpLobbyAboveEntry(tester, controller);

    await tester.tap(find.byKey(const ValueKey('lobby-close-room')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-close-room')));
    await tester.pumpAndSettle();

    expect(controller.closeCalls, 1);
    expect(controller.dismissClosedCalls, 1);
    expect(controller.lobby, isNull);
    expect(find.byType(RoomLobbyScreen), findsNothing);
    expect(find.text('MESA RÁPIDA · ENTRADA'), findsOneWidget);
    expect(find.text('Sala cerrada'), findsOneWidget);
    expect(find.byKey(const ValueKey('room-closed-feedback')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guest exits with feedback when the host closes the room', (
    tester,
  ) async {
    final controller = _FakeOnlineRoomController(localParticipantId: 'guest');
    await controller.joinRoomByCode(RoomCode.parse('ABC234'));
    await _pumpLobbyAboveEntry(tester, controller);

    controller.serverCloseRoom();
    await tester.pumpAndSettle();

    expect(controller.closeCalls, 0);
    expect(controller.leaveCalls, 0);
    expect(controller.dismissClosedCalls, 1);
    expect(controller.lobby, isNull);
    expect(find.byType(RoomLobbyScreen), findsNothing);
    expect(find.text('MESA RÁPIDA · ENTRADA'), findsOneWidget);
    expect(find.text('Sala cerrada'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guest can leave a waiting room from the fixed header action', (
    tester,
  ) async {
    final controller = _FakeOnlineRoomController(localParticipantId: 'guest');
    await controller.joinRoomByCode(RoomCode.parse('ABC234'));
    await _pumpPhone(
      tester,
      Material(
        child: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => RoomLobbyScreen(controller: controller),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('lobby-leave-room')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-leave-room')));
    await tester.pumpAndSettle();

    expect(controller.leaveCalls, 1);
    expect(controller.lobby, isNull);
    expect(tester.takeException(), isNull);
  });
}
