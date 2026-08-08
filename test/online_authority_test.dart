import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/online_authority.dart';
import 'package:parchesepop/online_match.dart';

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

OnlineParticipant _participant({
  required String id,
  required PlayerColor color,
  required ParticipantKind kind,
}) => OnlineParticipant(
  id: id,
  displayName: 'Player ${color.name}',
  flag: '🇩🇴',
  avatarId: 'avatar_default',
  level: 10,
  color: color,
  kind: kind,
  loadout: const CosmeticLoadout(),
);

OnlineMatchSession _session({String matchId = 'match_authority_001'}) =>
    OnlineMatchSession(
      matchId: matchId,
      seed: 4182,
      mode: GameMode.traditional,
      participants: <OnlineParticipant>[
        _participant(
          id: 'player_red',
          color: PlayerColor.red,
          kind: ParticipantKind.local,
        ),
        _participant(
          id: 'player_green',
          color: PlayerColor.green,
          kind: ParticipantKind.remoteHuman,
        ),
        _participant(
          id: 'player_yellow',
          color: PlayerColor.yellow,
          kind: ParticipantKind.remoteHuman,
        ),
        _participant(
          id: 'player_blue',
          color: PlayerColor.blue,
          kind: ParticipantKind.remoteHuman,
        ),
      ],
    );

OnlineRollCommand _roll({
  String matchId = 'match_authority_001',
  String participantId = 'player_red',
  String actionId = 'roll_0001',
  int expectedRevision = 0,
}) => OnlineRollCommand(
  matchId: matchId,
  participantId: participantId,
  actionId: actionId,
  expectedRevision: expectedRevision,
);

class _TestGateway implements OnlineAuthorityGateway {
  _TestGateway({required this.authority, required this.now});

  final OnlineMatchAuthority authority;
  DateTime now;
  int publicJoins = 0;
  int privateCreates = 0;
  int privateJoins = 0;
  final Map<String, String> resumeTokens = <String, String>{};

  @override
  Future<OnlineQueueTicket> joinPublicQueue(PublicQueueRequest request) async {
    publicJoins++;
    return OnlineQueueTicket(ticketId: 'public_${request.participantId}');
  }

  @override
  Future<OnlinePrivateRoom> createPrivateRoom(
    PrivateRoomCreateRequest request,
  ) async {
    privateCreates++;
    return const OnlinePrivateRoom(roomCode: 'ROOM42');
  }

  @override
  Future<OnlineQueueTicket> joinPrivateRoom(
    PrivateRoomJoinRequest request,
  ) async {
    if (request.roomCode != 'ROOM42') throw StateError('Unknown room.');
    privateJoins++;
    return OnlineQueueTicket(ticketId: 'private_${request.participantId}');
  }

  @override
  Future<OnlineReconnectDecision> reconnect(
    GatewayReconnectRequest request,
  ) async {
    if (request.matchId != authority.session.matchId ||
        resumeTokens[request.participantId] != request.resumeToken) {
      throw StateError('Unauthenticated reconnect.');
    }
    return authority.reconnect(request.participantId, now: now);
  }

  @override
  Future<OnlineCommandResult> submit(OnlineActionCommand command) async =>
      authority.submit(command);

  @override
  Future<OnlineAuthoritySnapshot> fetchSnapshot(String matchId) async {
    if (matchId != authority.session.matchId) {
      throw StateError('Unknown match.');
    }
    return authority.snapshot();
  }
}

void main() {
  group('OnlineMatchAuthority commands', () {
    test('the trusted engine generates dice and advances one revision', () {
      final authority = OnlineMatchAuthority.fresh(
        session: _session(),
        serverRandom: _SequenceRandom(const <int>[4, 1]),
      );
      addTearDown(authority.dispose);

      final result = authority.submit(_roll());

      expect(result.status, OnlineCommandStatus.accepted);
      expect(result.rejection, isNull);
      expect(result.snapshot.revision, 1);
      expect(result.snapshot.dice, const <int>[5, 2]);
      expect(result.snapshot.remainingDice, const <int>[5, 2]);
      expect(result.snapshot.hasRolled, isTrue);
      expect(authority.engine.rollSerial, 1);
      expect(() => result.snapshot.dice.add(6), throwsUnsupportedError);
    });

    test(
      'wrong match, unknown client, wrong turn, and invalid IDs are rejected',
      () {
        final authority = OnlineMatchAuthority.fresh(
          session: _session(),
          serverRandom: _SequenceRandom(const <int>[4, 1]),
        );
        addTearDown(authority.dispose);

        expect(
          authority.submit(_roll(matchId: 'match_other_001')).rejection,
          OnlineCommandRejection.wrongMatch,
        );
        expect(
          authority.submit(_roll(participantId: 'intruder_001')).rejection,
          OnlineCommandRejection.unknownParticipant,
        );
        expect(
          authority.submit(_roll(participantId: 'player_green')).rejection,
          OnlineCommandRejection.notPlayersTurn,
        );
        expect(
          authority.submit(_roll(actionId: 'bad')).rejection,
          OnlineCommandRejection.invalidActionId,
        );
        expect(
          authority.submit(_roll(expectedRevision: -1)).rejection,
          OnlineCommandRejection.invalidRevision,
        );
        expect(authority.revision, 0);
        expect(authority.engine.rollSerial, 0);
      },
    );

    test('a stale revision cannot mutate authoritative state', () {
      final authority = OnlineMatchAuthority.fresh(
        session: _session(),
        serverRandom: _SequenceRandom(const <int>[4, 1]),
      );
      addTearDown(authority.dispose);
      expect(authority.submit(_roll()).accepted, isTrue);

      final stale = authority.submit(
        const OnlineMoveCommand(
          matchId: 'match_authority_001',
          participantId: 'player_red',
          actionId: 'move_stale_001',
          expectedRevision: 0,
          tokenId: 0,
          die: 5,
        ),
      );

      expect(stale.rejection, OnlineCommandRejection.staleRevision);
      expect(authority.revision, 1);
      expect(authority.engine.currentPlayer.tokens.first.inNest, isTrue);
      expect(authority.engine.remainingDice, const <int>[5, 2]);
    });

    test('fabricated dice and impossible moves are rejected by the engine', () {
      final authority = OnlineMatchAuthority.fresh(
        session: _session(),
        serverRandom: _SequenceRandom(const <int>[1, 2]),
      );
      addTearDown(authority.dispose);
      authority.submit(_roll());
      expect(authority.engine.dice, const <int>[2, 3]);

      final fabricated = authority.submit(
        const OnlineMoveCommand(
          matchId: 'match_authority_001',
          participantId: 'player_red',
          actionId: 'move_fake_die_001',
          expectedRevision: 1,
          tokenId: 0,
          die: 6,
        ),
      );
      final impossible = authority.submit(
        const OnlineMoveCommand(
          matchId: 'match_authority_001',
          participantId: 'player_red',
          actionId: 'move_illegal_001',
          expectedRevision: 1,
          tokenId: 0,
          die: 2,
        ),
      );
      final invalidToken = authority.submit(
        const OnlineMoveCommand(
          matchId: 'match_authority_001',
          participantId: 'player_red',
          actionId: 'move_bad_token_001',
          expectedRevision: 1,
          tokenId: 99,
          die: 2,
        ),
      );

      expect(fabricated.rejection, OnlineCommandRejection.fabricatedDie);
      expect(impossible.rejection, OnlineCommandRejection.illegalMove);
      expect(invalidToken.rejection, OnlineCommandRejection.invalidToken);
      expect(authority.revision, 1);
      expect(authority.engine.currentPlayer.tokens.first.inNest, isTrue);
    });

    test(
      'accepted move is idempotent and action ID conflicts are rejected',
      () {
        final authority = OnlineMatchAuthority.fresh(
          session: _session(),
          serverRandom: _SequenceRandom(const <int>[4, 1]),
        );
        addTearDown(authority.dispose);
        authority.submit(_roll());
        const move = OnlineMoveCommand(
          matchId: 'match_authority_001',
          participantId: 'player_red',
          actionId: 'move_exit_001',
          expectedRevision: 1,
          tokenId: 0,
          die: 5,
        );

        final accepted = authority.submit(move);
        final duplicate = authority.submit(move);
        final conflict = authority.submit(
          const OnlineMoveCommand(
            matchId: 'match_authority_001',
            participantId: 'player_red',
            actionId: 'move_exit_001',
            expectedRevision: 1,
            tokenId: 0,
            die: 2,
          ),
        );

        expect(accepted.status, OnlineCommandStatus.accepted);
        expect(duplicate.status, OnlineCommandStatus.duplicate);
        expect(duplicate.snapshot.revision, accepted.snapshot.revision);
        expect(conflict.rejection, OnlineCommandRejection.actionIdConflict);
        expect(authority.revision, 2);
        expect(authority.engine.currentPlayer.tokens.first.progress, 0);
        expect(authority.engine.remainingDice, const <int>[2]);
      },
    );

    test('moveAll uses only the engine-calculated combined move', () {
      final engine = GameEngine();
      addTearDown(engine.dispose);
      final token = engine.currentPlayer.tokens.first..progress = 0;
      engine.hasRolled = true;
      engine.dice = const <int>[1, 6];
      engine.remainingDice.addAll(const <int>[1, 6]);
      final authority = OnlineMatchAuthority(
        session: _session(),
        engine: engine,
      );

      final result = authority.submit(
        const OnlineMoveAllCommand(
          matchId: 'match_authority_001',
          participantId: 'player_red',
          actionId: 'move_all_001',
          expectedRevision: 0,
          tokenId: 0,
        ),
      );

      expect(result.accepted, isTrue);
      expect(token.progress, 7);
      expect(engine.remainingDice, isEmpty);
      expect(authority.revision, 1);
    });

    test('checkpoint restores state and accepted action idempotency', () {
      final first = OnlineMatchAuthority.fresh(
        session: _session(),
        serverRandom: _SequenceRandom(const <int>[4, 1]),
      );
      final roll = _roll();
      first.submit(roll);
      final disconnectedAt = DateTime.utc(2026, 8, 8, 13);
      first.markDisconnected('player_green', now: disconnectedAt);
      final encoded = jsonEncode(first.createCheckpoint());
      first.dispose();

      final restored = OnlineMatchAuthority.fromCheckpoint(
        session: _session(),
        checkpoint: jsonDecode(encoded) as Map<String, dynamic>,
      );
      addTearDown(restored.dispose);

      final snapshot = restored.snapshot();
      expect(snapshot.revision, 2);
      expect(snapshot.dice, const <int>[5, 2]);
      expect(snapshot.hasRolled, isTrue);
      expect(
        snapshot.connectionFor('player_green').presence,
        OnlineParticipantPresence.reconnecting,
      );
      expect(
        snapshot.connectionFor('player_green').reconnectDeadline,
        disconnectedAt.add(const Duration(seconds: 30)),
      );

      final duplicate = restored.submit(roll);
      expect(duplicate.status, OnlineCommandStatus.duplicate);
      expect(restored.revision, 2);
      expect(restored.engine.rollSerial, 0);
    });
  });

  group('disconnect and gateway contracts', () {
    test('grace reconnect succeeds and locked CPU takeover stays locked', () {
      const policy = OnlineDisconnectPolicy(
        gracePeriod: Duration(seconds: 10),
        afterGrace: DisconnectExpiryAction.cpuTakeover,
        allowReclaimAfterCpuTakeover: false,
      );
      final authority = OnlineMatchAuthority.fresh(
        session: _session(),
        serverRandom: _SequenceRandom(const <int>[4, 1]),
        disconnectPolicy: policy,
      );
      addTearDown(authority.dispose);
      final started = DateTime.utc(2026, 8, 8, 14);

      expect(
        authority.markDisconnected('player_red', now: started),
        PresenceMutationResult.changed,
      );
      expect(
        authority.submit(_roll(expectedRevision: 1)).rejection,
        OnlineCommandRejection.participantUnavailable,
      );
      expect(
        authority
            .reconnect(
              'player_red',
              now: started.add(const Duration(seconds: 5)),
            )
            .status,
        OnlineReconnectStatus.reconnected,
      );

      authority.markDisconnected(
        'player_red',
        now: started.add(const Duration(seconds: 6)),
      );
      final transitions = authority.enforceDisconnectPolicy(
        started.add(const Duration(seconds: 16)),
      );
      expect(transitions, hasLength(1));
      expect(transitions.single.to, OnlineParticipantPresence.cpuControlled);
      expect(
        authority
            .reconnect(
              'player_red',
              now: started.add(const Duration(seconds: 17)),
            )
            .status,
        OnlineReconnectStatus.takeoverLocked,
      );
    });

    test('forfeit policy is terminal for reconnect and commands', () {
      const policy = OnlineDisconnectPolicy(
        gracePeriod: Duration(seconds: 1),
        afterGrace: DisconnectExpiryAction.forfeit,
      );
      final authority = OnlineMatchAuthority.fresh(
        session: _session(),
        serverRandom: _SequenceRandom(const <int>[4, 1]),
        disconnectPolicy: policy,
      );
      addTearDown(authority.dispose);
      final now = DateTime.utc(2026, 8, 8, 15);
      authority.markDisconnected('player_red', now: now);

      authority.enforceDisconnectPolicy(now.add(const Duration(seconds: 2)));

      expect(
        authority.snapshot().connectionFor('player_red').presence,
        OnlineParticipantPresence.forfeited,
      );
      expect(
        authority
            .reconnect('player_red', now: now.add(const Duration(seconds: 3)))
            .status,
        OnlineReconnectStatus.forfeited,
      );
      expect(
        authority.submit(_roll(expectedRevision: 2)).rejection,
        OnlineCommandRejection.participantUnavailable,
      );
    });

    test(
      'test-only gateway routes public, private, reconnect, and commands',
      () async {
        final authority = OnlineMatchAuthority.fresh(
          session: _session(),
          serverRandom: _SequenceRandom(const <int>[4, 1]),
        );
        addTearDown(authority.dispose);
        final now = DateTime.utc(2026, 8, 8, 16);
        final gateway = _TestGateway(authority: authority, now: now)
          ..resumeTokens['player_red'] = 'resume_token_red_001';

        final publicTicket = await gateway.joinPublicQueue(
          const PublicQueueRequest(
            participantId: 'player_red',
            mode: GameMode.traditional,
            matchFormat: MatchFormat.quickPop,
          ),
        );
        final room = await gateway.createPrivateRoom(
          const PrivateRoomCreateRequest(
            hostParticipantId: 'player_red',
            mode: GameMode.traditional,
            matchFormat: MatchFormat.quickPop,
          ),
        );
        final privateTicket = await gateway.joinPrivateRoom(
          PrivateRoomJoinRequest(
            participantId: 'player_green',
            roomCode: room.roomCode,
          ),
        );

        authority.markDisconnected('player_red', now: now);
        gateway.now = now.add(const Duration(seconds: 2));
        final reconnected = await gateway.reconnect(
          const GatewayReconnectRequest(
            matchId: 'match_authority_001',
            participantId: 'player_red',
            resumeToken: 'resume_token_red_001',
            knownRevision: 1,
          ),
        );
        final roll = await gateway.submit(_roll(expectedRevision: 2));
        final snapshot = await gateway.fetchSnapshot('match_authority_001');

        expect(publicTicket.ticketId, 'public_player_red');
        expect(privateTicket.ticketId, 'private_player_green');
        expect(gateway.publicJoins, 1);
        expect(gateway.privateCreates, 1);
        expect(gateway.privateJoins, 1);
        expect(reconnected.accepted, isTrue);
        expect(roll.accepted, isTrue);
        expect(snapshot.revision, 3);
      },
    );
  });
}
