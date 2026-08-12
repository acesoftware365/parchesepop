import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/online_lobby.dart';

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

OnlineLobby _room({RoomVisibility visibility = RoomVisibility.private}) =>
    OnlineLobby.create(
      roomId: 'room-001',
      roomCode: RoomCode.parse('ABC234'),
      hostParticipantId: 'host',
      hostDisplayName: 'Host Player',
      visibility: visibility,
    );

void _fillRoom(OnlineLobby room) {
  room.join(participantId: 'green', displayName: 'Green Player');
  room.join(participantId: 'yellow', displayName: 'Yellow Player');
  room.join(participantId: 'blue', displayName: 'Blue Player');
}

void _readyEveryone(OnlineLobby room) {
  for (final participant in room.participants) {
    room.setReady(actorParticipantId: participant.participantId, ready: true);
  }
}

Matcher _lobbyError(LobbyErrorCode code) =>
    isA<LobbyException>().having((error) => error.code, 'code', code);

Map<String, Object?> _jsonCopy(Map<String, Object?> source) {
  final decoded = jsonDecode(jsonEncode(source));
  return Map<String, Object?>.from(decoded as Map);
}

void _roll(OnlineLobby room, String participantId, int zeroBasedDie) {
  room.rollOpeningDie(
    actorParticipantId: participantId,
    random: _SequenceRandom([zeroBasedDie]),
  );
}

void main() {
  test('room name survives lobby serialization and trims whitespace', () {
    final room = OnlineLobby.create(
      roomId: 'named-room',
      roomCode: RoomCode.parse('ABC234'),
      hostParticipantId: 'host',
      hostDisplayName: 'Host Player',
      roomName: '  Noche de amigos  ',
    );
    final restored = OnlineLobby.fromJson(room.toJson());
    expect(restored.roomName, 'Noche de amigos');
  });

  test('room name rejects oversized metadata', () {
    expect(
      () => OnlineLobby.create(
        roomId: 'named-room',
        roomCode: RoomCode.parse('ABC234'),
        hostParticipantId: 'host',
        hostDisplayName: 'Host Player',
        roomName: 'x' * 29,
      ),
      throwsA(isA<LobbyJsonException>()),
    );
  });

  group('RoomCode', () {
    test('normalizes pasted codes and rejects ambiguous characters', () {
      expect(RoomCode.parse(' ab-cd 23 ').value, 'ABCD23');
      expect(RoomCode.isValid('ABC234'), isTrue);
      expect(RoomCode.isValid('ABCI23'), isFalse);
      expect(RoomCode.isValid('ABCO23'), isFalse);
      expect(RoomCode.isValid('ABC123'), isFalse);
      expect(RoomCode.isValid('ABC023'), isFalse);
      expect(RoomCode.isValid('ABC23'), isFalse);
      expect(
        () => RoomCode.parse('ABC12O'),
        throwsA(_lobbyError(LobbyErrorCode.invalidRoomCode)),
      );
    });

    test('generates six deterministic characters with injected Random', () {
      final code = RoomCode.generate(_SequenceRandom([0, 1, 2, 3, 4, 5]));
      expect(code.value, 'ABCDEF');
      expect(RoomCode.isValid(code.value), isTrue);
    });
  });

  group('OnlineLobby seats and membership', () {
    test('uses four fixed clockwise colors and fills the first empty seat', () {
      final room = _room();
      _fillRoom(room);

      expect(OnlineLobby.fixedClockwiseSeats, [
        LobbySeatColor.red,
        LobbySeatColor.green,
        LobbySeatColor.yellow,
        LobbySeatColor.blue,
      ]);
      expect(
        room.participants.map((participant) => participant.seat),
        LobbySeatColor.values,
      );
      expect(
        room.participantForSeat(LobbySeatColor.red)?.participantId,
        'host',
      );
      expect(room.isFull, isTrue);
      expect(
        () => room.join(participantId: 'fifth', displayName: 'Fifth'),
        throwsA(_lobbyError(LobbyErrorCode.roomFull)),
      );
    });

    test('rejects duplicates and occupied preferred seats', () {
      final room = _room();
      room.join(participantId: 'green', displayName: 'Green Player');

      expect(
        () => room.join(participantId: 'green', displayName: 'Again'),
        throwsA(_lobbyError(LobbyErrorCode.duplicateParticipant)),
      );
      expect(
        () => room.join(
          participantId: 'other',
          displayName: 'Other',
          preferredSeat: LobbySeatColor.green,
        ),
        throwsA(_lobbyError(LobbyErrorCode.seatOccupied)),
      );
    });

    test('a host kick frees the same fixed seat for a replacement', () {
      final room = _room();
      _fillRoom(room);

      final kicked = room.kick(
        actorParticipantId: 'host',
        targetParticipantId: 'yellow',
      );
      final replacement = room.join(
        participantId: 'new-yellow',
        displayName: 'New Yellow',
      );

      expect(kicked.seat, LobbySeatColor.yellow);
      expect(replacement.seat, LobbySeatColor.yellow);
      expect(room.isFull, isTrue);
    });
  });

  group('OnlineLobby authorization and readiness', () {
    test('privacy, kick, close, and start are host-only', () {
      final room = _room();
      _fillRoom(room);

      expect(
        () => room.changeVisibility(
          actorParticipantId: 'green',
          visibility: RoomVisibility.public,
        ),
        throwsA(_lobbyError(LobbyErrorCode.notHost)),
      );
      expect(
        () => room.kick(
          actorParticipantId: 'green',
          targetParticipantId: 'yellow',
        ),
        throwsA(_lobbyError(LobbyErrorCode.notHost)),
      );
      expect(
        () => room.close(actorParticipantId: 'green'),
        throwsA(_lobbyError(LobbyErrorCode.notHost)),
      );
      expect(
        () => room.startOpeningRoll(actorParticipantId: 'green'),
        throwsA(_lobbyError(LobbyErrorCode.notHost)),
      );
      expect(
        () =>
            room.kick(actorParticipantId: 'host', targetParticipantId: 'host'),
        throwsA(_lobbyError(LobbyErrorCode.hostCannotBeKicked)),
      );
    });

    test('host can change visibility and close a waiting room', () {
      final room = _room();
      room.changeVisibility(
        actorParticipantId: 'host',
        visibility: RoomVisibility.public,
      );
      expect(room.visibility, RoomVisibility.public);

      room.close(actorParticipantId: 'host');
      expect(room.status, RoomStatus.closed);
      expect(
        () => room.join(participantId: 'late', displayName: 'Late Player'),
        throwsA(_lobbyError(LobbyErrorCode.roomNotJoinable)),
      );
    });

    test('two ready participants can start a Quick Table opening roll', () {
      final room = _room();
      room.join(participantId: 'green', displayName: 'Guest');
      room.setReady(actorParticipantId: 'host', ready: true);
      room.setReady(actorParticipantId: 'green', ready: true);

      expect(room.occupiedSeatCount, 2);
      expect(room.canStart, isTrue);
      final openingRoll = room.startOpeningRoll(actorParticipantId: 'host');

      expect(room.status, RoomStatus.openingRoll);
      expect(openingRoll.eligibleParticipantIds, [
        'host',
        'green',
        'cpu_ABC234_yellow',
        'cpu_ABC234_blue',
      ]);
      expect(room.participantForSeat(LobbySeatColor.yellow)?.ready, isTrue);
      expect(room.participantForSeat(LobbySeatColor.blue)?.ready, isTrue);
    });

    test('three ready participants can start a Quick Table opening roll', () {
      final room = _room();
      room.join(participantId: 'green', displayName: 'Guest');
      room.join(participantId: 'yellow', displayName: 'Guest Two');
      room.setReady(actorParticipantId: 'host', ready: true);
      room.setReady(actorParticipantId: 'green', ready: true);
      room.setReady(actorParticipantId: 'yellow', ready: true);

      expect(room.occupiedSeatCount, 3);
      expect(room.canStart, isTrue);
      final openingRoll = room.startOpeningRoll(actorParticipantId: 'host');

      expect(room.status, RoomStatus.openingRoll);
      expect(openingRoll.eligibleParticipantIds, [
        'host',
        'green',
        'yellow',
        'cpu_ABC234_blue',
      ]);
    });

    test('requires four connected and ready participants to start', () {
      final room = _room();
      expect(
        () => room.startOpeningRoll(actorParticipantId: 'host'),
        throwsA(_lobbyError(LobbyErrorCode.notEnoughPlayers)),
      );

      _fillRoom(room);
      expect(
        () => room.startOpeningRoll(actorParticipantId: 'host'),
        throwsA(_lobbyError(LobbyErrorCode.participantsNotReady)),
      );

      _readyEveryone(room);
      room.setPresence(
        participantId: 'blue',
        presence: LobbyPresence.disconnected,
      );
      expect(room.participantById('blue').ready, isFalse);
      expect(
        () => room.startOpeningRoll(actorParticipantId: 'host'),
        throwsA(_lobbyError(LobbyErrorCode.participantsDisconnected)),
      );

      room.setPresence(
        participantId: 'blue',
        presence: LobbyPresence.connected,
      );
      room.setReady(actorParticipantId: 'blue', ready: true);
      final openingRoll = room.startOpeningRoll(actorParticipantId: 'host');

      expect(room.status, RoomStatus.openingRoll);
      expect(openingRoll.eligibleParticipantIds, [
        'host',
        'green',
        'yellow',
        'blue',
      ]);
    });
  });

  group('OpeningRollState', () {
    test('only the highest tie rerolls, then play continues clockwise', () {
      final room = _room();
      _fillRoom(room);
      _readyEveryone(room);
      room.startOpeningRoll(actorParticipantId: 'host');
      final random = _SequenceRandom([
        5, // host -> 6
        5, // green -> 6
        3, // yellow -> 4
        1, // blue -> 2
        1, // host tie reroll -> 2
        4, // green tie reroll -> 5
      ]);

      expect(
        room.rollOpeningDie(actorParticipantId: 'host', random: random),
        6,
      );
      expect(
        () => room.rollOpeningDie(actorParticipantId: 'host', random: random),
        throwsA(_lobbyError(LobbyErrorCode.participantAlreadyRolled)),
      );
      expect(
        room.rollOpeningDie(actorParticipantId: 'green', random: random),
        6,
      );
      expect(
        room.rollOpeningDie(actorParticipantId: 'yellow', random: random),
        4,
      );
      expect(
        room.rollOpeningDie(actorParticipantId: 'blue', random: random),
        2,
      );

      expect(room.openingRoll?.round, 2);
      expect(room.openingRoll?.eligibleParticipantIds, ['host', 'green']);
      expect(
        () => room.rollOpeningDie(actorParticipantId: 'yellow', random: random),
        throwsA(_lobbyError(LobbyErrorCode.participantNotEligible)),
      );
      expect(
        room.rollOpeningDie(actorParticipantId: 'host', random: random),
        2,
      );
      expect(
        room.rollOpeningDie(actorParticipantId: 'green', random: random),
        5,
      );

      expect(room.status, RoomStatus.starting);
      expect(room.openingRoll?.winnerParticipantId, 'green');
      expect(room.openingRoll?.history, hasLength(2));
      expect(room.openingRoll?.clockwiseParticipantIds, [
        'green',
        'yellow',
        'blue',
        'host',
      ]);
    });

    test('only the host can transition a resolved roll into the game', () {
      final room = _room();
      _fillRoom(room);
      _readyEveryone(room);
      room.startOpeningRoll(actorParticipantId: 'host');
      final random = _SequenceRandom([5, 4, 3, 2]);
      for (final participantId in ['host', 'green', 'yellow', 'blue']) {
        room.rollOpeningDie(actorParticipantId: participantId, random: random);
      }

      expect(room.status, RoomStatus.starting);
      expect(
        () => room.markGameStarted(actorParticipantId: 'green'),
        throwsA(_lobbyError(LobbyErrorCode.notHost)),
      );
      room.markGameStarted(actorParticipantId: 'host');
      expect(room.status, RoomStatus.inGame);
      expect(
        () => room.close(actorParticipantId: 'host'),
        throwsA(_lobbyError(LobbyErrorCode.invalidStatus)),
      );
    });
  });

  group('OnlineLobby JSON restoration', () {
    test('round-trips waiting-room metadata, readiness, and presence', () {
      final room = _room(visibility: RoomVisibility.public);
      room.join(participantId: 'green', displayName: 'Green Player');
      room.join(participantId: 'yellow', displayName: 'Yellow Player');
      room.setReady(actorParticipantId: 'host', ready: true);
      room.setReady(actorParticipantId: 'green', ready: true);
      room.setPresence(
        participantId: 'yellow',
        presence: LobbyPresence.disconnected,
      );

      final restored = OnlineLobby.fromJson(_jsonCopy(room.toJson()));

      expect(restored.toJson(), equals(room.toJson()));
      expect(restored.roomId, 'room-001');
      expect(restored.roomCode.value, 'ABC234');
      expect(restored.hostParticipantId, 'host');
      expect(restored.visibility, RoomVisibility.public);
      expect(restored.status, RoomStatus.waiting);
      expect(restored.revision, room.revision);
      expect(restored.participantById('green').ready, isTrue);
      expect(
        restored.participantById('yellow').presence,
        LobbyPresence.disconnected,
      );
      expect(restored.openingRoll, isNull);
    });

    test('round-trips an unresolved first opening-roll round', () {
      final room = _room();
      _fillRoom(room);
      _readyEveryone(room);
      room.startOpeningRoll(actorParticipantId: 'host');
      _roll(room, 'host', 5);
      _roll(room, 'green', 1);

      final restored = OnlineLobby.fromJson(_jsonCopy(room.toJson()));

      expect(restored.toJson(), equals(room.toJson()));
      expect(restored.status, RoomStatus.openingRoll);
      expect(restored.openingRoll?.round, 1);
      expect(restored.openingRoll?.history, isEmpty);
      expect(restored.openingRoll?.currentRolls, {'host': 6, 'green': 2});
      expect(restored.openingRoll?.eligibleParticipantIds, [
        'host',
        'green',
        'yellow',
        'blue',
      ]);

      _roll(restored, 'yellow', 3);
      _roll(restored, 'blue', 0);
      expect(restored.status, RoomStatus.starting);
      expect(restored.openingRoll?.winnerParticipantId, 'host');
    });

    test('restores tie history and can continue only the current reround', () {
      final room = _room();
      _fillRoom(room);
      _readyEveryone(room);
      room.startOpeningRoll(actorParticipantId: 'host');
      _roll(room, 'host', 5);
      _roll(room, 'green', 5);
      _roll(room, 'yellow', 3);
      _roll(room, 'blue', 1);
      _roll(room, 'host', 1);

      final restored = OnlineLobby.fromJson(_jsonCopy(room.toJson()));

      expect(restored.toJson(), equals(room.toJson()));
      expect(restored.openingRoll?.round, 2);
      expect(restored.openingRoll?.history, hasLength(1));
      expect(restored.openingRoll?.eligibleParticipantIds, ['host', 'green']);
      expect(restored.openingRoll?.currentRolls, {'host': 2});
      expect(
        () => _roll(restored, 'yellow', 4),
        throwsA(_lobbyError(LobbyErrorCode.participantNotEligible)),
      );

      _roll(restored, 'green', 4);
      expect(restored.status, RoomStatus.starting);
      expect(restored.openingRoll?.winnerParticipantId, 'green');
      expect(restored.openingRoll?.clockwiseParticipantIds, [
        'green',
        'yellow',
        'blue',
        'host',
      ]);
    });

    test('round-trips resolved starting, in-game, and closed snapshots', () {
      final room = _room();
      _fillRoom(room);
      _readyEveryone(room);
      room.startOpeningRoll(actorParticipantId: 'host');
      _roll(room, 'host', 5);
      _roll(room, 'green', 4);
      _roll(room, 'yellow', 3);
      _roll(room, 'blue', 2);

      final starting = OnlineLobby.fromJson(_jsonCopy(room.toJson()));
      expect(starting.status, RoomStatus.starting);
      expect(starting.toJson(), equals(room.toJson()));

      starting.markGameStarted(actorParticipantId: 'host');
      final inGame = OnlineLobby.fromJson(_jsonCopy(starting.toJson()));
      expect(inGame.status, RoomStatus.inGame);
      expect(inGame.toJson(), equals(starting.toJson()));

      final closedRoom = _room()..close(actorParticipantId: 'host');
      final closed = OnlineLobby.fromJson(_jsonCopy(closedRoom.toJson()));
      expect(closed.status, RoomStatus.closed);
      expect(closed.toJson(), equals(closedRoom.toJson()));
    });

    test(
      'rejects duplicate IDs and seats without mutating the source lobby',
      () {
        final source = _room();
        _fillRoom(source);
        final before = source.toJson();

        final duplicateId = _jsonCopy(before);
        final duplicateIdPlayers = duplicateId['participants']! as List;
        (duplicateIdPlayers[1] as Map)['participantId'] = 'host';
        expect(
          () => OnlineLobby.fromJson(duplicateId),
          throwsA(isA<LobbyJsonException>()),
        );

        final duplicateSeat = _jsonCopy(before);
        final duplicateSeatPlayers = duplicateSeat['participants']! as List;
        (duplicateSeatPlayers[1] as Map)['seat'] = 'red';
        expect(
          () => OnlineLobby.fromJson(duplicateSeat),
          throwsA(isA<LobbyJsonException>()),
        );

        expect(source.toJson(), equals(before));
      },
    );

    test('rejects malformed room metadata and status relationships', () {
      final room = _room();
      final invalidCode = _jsonCopy(room.toJson())..['roomCode'] = 'ABCI23';
      final unknownHost = _jsonCopy(room.toJson())
        ..['hostParticipantId'] = 'missing';
      final impossibleOpeningStatus = _jsonCopy(room.toJson())
        ..['status'] = 'openingRoll';
      final badRevision = _jsonCopy(room.toJson())..['revision'] = -1;
      for (final snapshot in [
        invalidCode,
        unknownHost,
        impossibleOpeningStatus,
        badRevision,
      ]) {
        expect(
          () => OnlineLobby.fromJson(snapshot),
          throwsA(isA<LobbyJsonException>()),
        );
      }
    });

    test('treats an omitted null opening roll as a Firebase round-trip', () {
      final snapshot = _jsonCopy(_room().toJson())..remove('openingRoll');

      final restored = OnlineLobby.fromJson(snapshot);

      expect(restored.status, RoomStatus.waiting);
      expect(restored.openingRoll, isNull);
    });

    test(
      'rejects corrupt opening-roll dice, seats, eligibility, and order',
      () {
        final room = _room();
        _fillRoom(room);
        _readyEveryone(room);
        room.startOpeningRoll(actorParticipantId: 'host');
        _roll(room, 'host', 5);
        final partial = room.toJson();

        final badDie = _jsonCopy(partial);
        ((badDie['openingRoll'] as Map)['currentRolls'] as Map)['host'] = 7;

        final badSeat = _jsonCopy(partial);
        ((badSeat['openingRoll'] as Map)['seatByParticipantId']
                as Map)['green'] =
            'yellow';

        final badEligibility = _jsonCopy(partial);
        (badEligibility['openingRoll'] as Map)['eligibleParticipantIds'] = [
          'host',
          'missing',
        ];

        for (final snapshot in [badDie, badSeat, badEligibility]) {
          expect(
            () => OnlineLobby.fromJson(snapshot),
            throwsA(isA<LobbyJsonException>()),
          );
        }

        _roll(room, 'green', 4);
        _roll(room, 'yellow', 3);
        _roll(room, 'blue', 2);
        final badWinnerOrder = _jsonCopy(room.toJson());
        (badWinnerOrder['openingRoll'] as Map)['clockwiseParticipantIds'] = [
          'green',
          'yellow',
          'blue',
          'host',
        ];
        expect(
          () => OnlineLobby.fromJson(badWinnerOrder),
          throwsA(isA<LobbyJsonException>()),
        );
      },
    );
  });
}
