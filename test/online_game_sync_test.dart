import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/online_authority.dart';
import 'package:parchesepop/online_game_sync.dart';
import 'package:parchesepop/online_lobby.dart';
import 'package:parchesepop/online_match.dart';
import 'package:parchesepop/online_transport.dart';
import 'package:parchesepop/online_transport_models.dart';
import 'package:parchesepop/safe_chat.dart';

import 'support/in_memory_online_realtime_store.dart';

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
  level: 1,
  color: color,
  kind: kind,
  loadout: const CosmeticLoadout(),
);

OnlineMatchSession _sessionFor(
  PlayerColor localColor, {
  GameMode mode = GameMode.traditional,
}) {
  const ids = <PlayerColor, String>{
    PlayerColor.red: 'host_red',
    PlayerColor.green: 'guest_green',
    PlayerColor.yellow: 'guest_yellow',
    PlayerColor.blue: 'guest_blue',
  };
  return OnlineMatchSession(
    matchId: 'room_sync_001_match',
    seed: 91827,
    mode: mode,
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

OnlineMatchSession _sessionWithVirtualGreen(
  PlayerColor localColor, {
  GameMode mode = GameMode.traditional,
}) {
  const ids = <PlayerColor, String>{
    PlayerColor.red: 'host_red',
    PlayerColor.green: 'cpu_green',
    PlayerColor.yellow: 'guest_yellow',
    PlayerColor.blue: 'guest_blue',
  };
  return OnlineMatchSession(
    matchId: 'room_sync_001_match',
    seed: 91827,
    mode: mode,
    participants: <OnlineParticipant>[
      for (final color in PlayerColor.values)
        _participant(
          id: ids[color]!,
          color: color,
          kind: color == localColor
              ? ParticipantKind.local
              : color == PlayerColor.green
              ? ParticipantKind.virtual
              : ParticipantKind.remoteHuman,
        ),
    ],
  );
}

OnlineMatchSession _quickPopSessionFor(
  PlayerColor localColor, {
  GameMode mode = GameMode.traditional,
}) {
  const ids = <PlayerColor, String>{
    PlayerColor.red: 'host_red',
    PlayerColor.green: 'guest_green',
    PlayerColor.yellow: 'cpu_yellow',
    PlayerColor.blue: 'cpu_blue',
  };
  return OnlineMatchSession(
    matchId: 'room_sync_001_match',
    seed: 91827,
    mode: mode,
    participants: <OnlineParticipant>[
      for (final color in PlayerColor.values)
        _participant(
          id: ids[color]!,
          color: color,
          kind: color == localColor
              ? ParticipantKind.local
              : color == PlayerColor.yellow || color == PlayerColor.blue
              ? ParticipantKind.virtual
              : ParticipantKind.remoteHuman,
        ),
    ],
  );
}

OnlineTransportClient _transport(
  OnlineRealtimeStore store, {
  required String uid,
}) => OnlineTransportClient(
  store: store,
  identity: OnlineTransportIdentity(uid: uid, displayName: uid),
  random: Random(1),
);

Map<PlayerColor, String> get _playerNames => <PlayerColor, String>{
  PlayerColor.red: 'Player red',
  PlayerColor.green: 'Player green',
  PlayerColor.yellow: 'Player yellow',
  PlayerColor.blue: 'Player blue',
};

GameEngine _engine({
  required PlayerColor localColor,
  required Random random,
  PlayerColor initialPlayer = PlayerColor.green,
  GameMode mode = GameMode.traditional,
  MatchFormat matchFormat = MatchFormat.classic,
}) => GameEngine(
  mode: mode,
  matchFormat: matchFormat,
  localViewerColor: localColor,
  initialPlayerColor: initialPlayer,
  random: random,
  humanName: _playerNames[localColor]!,
  playerNames: _playerNames,
);

String _checkpoint(GameEngine engine) => jsonEncode(engine.createCheckpoint());

/// Mirrors Realtime Database's JSON normalization closely enough for engine
/// checkpoints: null values and empty collections are omitted from objects.
/// In particular, a freshly created match loses its empty `remainingDice`
/// array when it crosses the Firebase wire.
Object? _firebaseNormalized(Object? value) {
  if (value is Map) {
    final normalized = <String, Object?>{};
    for (final entry in value.entries) {
      final child = _firebaseNormalized(entry.value);
      if (child != null) normalized[entry.key.toString()] = child;
    }
    return normalized.isEmpty ? null : normalized;
  }
  if (value is List) {
    if (value.isEmpty) return null;
    return value.map<Object?>(_firebaseNormalized).toList(growable: false);
  }
  return value;
}

/// Guest-side view of the shared fake that applies Realtime Database's wire
/// normalization to every read and stream event, not just the seeded value.
final class _FirebaseNormalizedStore implements OnlineRealtimeStore {
  const _FirebaseNormalizedStore(this.delegate);

  final OnlineRealtimeStore delegate;

  @override
  Future<Object?> read(String path) async =>
      _firebaseNormalized(await delegate.read(path));

  @override
  Stream<Object?> watch(String path) =>
      delegate.watch(path).map<Object?>(_firebaseNormalized);

  @override
  Future<void> set(String path, Object? value) => delegate.set(path, value);

  @override
  Future<void> update(String path, Map<String, Object?> values) =>
      delegate.update(path, values);

  @override
  Future<OnlineStoreTransactionResult> transaction(
    String path,
    OnlineStoreTransactionUpdater updater,
  ) => delegate.transaction(
    path,
    (current) => updater(_firebaseNormalized(current)),
  );

  @override
  Future<void> setOnDisconnect(String path, Object? value) =>
      delegate.setOnDisconnect(path, value);

  @override
  Future<void> cancelOnDisconnect(String path) =>
      delegate.cancelOnDisconnect(path);

  @override
  Future<int> serverNowMs() => delegate.serverNowMs();
}

Future<void> _seedInGameRoom(
  InMemoryOnlineRealtimeStore store,
  OnlineMatchSession session, {
  MatchFormat matchFormat = MatchFormat.classic,
}) async {
  final now = store.nowMs;
  final room = OnlineRoomRecord(
    id: 'room_sync_001',
    code: RoomCode.parse('ABC234'),
    hostUid: 'host_red',
    visibility: RoomVisibility.private,
    status: RoomStatus.inGame,
    mode: session.mode.name,
    matchFormat: matchFormat.name,
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
        if (participant.beganAsHuman)
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

Future<void> _eventually(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition was not satisfied before $timeout.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _eventuallyAsync(
  Future<bool> Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Async condition was not satisfied before $timeout.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<OnlineParticipantPresence> _persistedPresence(
  InMemoryOnlineRealtimeStore store,
  String participantId,
) async {
  final document = onlineMap(
    await store.read('$onlineTransportRoot/rooms/room_sync_001/match'),
  );
  final authority = onlineMap(document['authorityCheckpoint']);
  final connections = authority['connections'];
  if (connections is! List) {
    throw StateError('Missing persisted authority connections.');
  }
  for (final raw in connections) {
    final connection = onlineMap(raw);
    if (connection['participantId'] != participantId) continue;
    return OnlineParticipantPresence.values.singleWhere(
      (value) => value.name == connection['presence'],
    );
  }
  throw StateError('Missing authority connection for $participantId.');
}

void main() {
  group('OnlineGameSyncClient', () {
    test(
      'Quick Messages reach both humans once and reconnect delivers only missed messages',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 1775689984000);
        final hostEngine = _engine(
          localColor: PlayerColor.red,
          random: Random(301),
        );
        final guestEngine = _engine(
          localColor: PlayerColor.green,
          random: Random(302),
        );
        final host = OnlineGameSyncClient(
          transport: _transport(store, uid: 'host_red'),
          roomId: 'room_sync_001',
          session: _sessionFor(PlayerColor.red),
          engine: hostEngine,
          isHost: true,
        );
        final guest = OnlineGameSyncClient(
          transport: _transport(store, uid: 'guest_green'),
          roomId: 'room_sync_001',
          session: _sessionFor(PlayerColor.green),
          engine: guestEngine,
          isHost: false,
        );
        final hostMessages = <OnlineSafeChatMessage>[];
        final guestMessages = <OnlineSafeChatMessage>[];
        final hostChat = host.safeChatMessages.listen(hostMessages.add);
        final guestChat = guest.safeChatMessages.listen(guestMessages.add);
        addTearDown(() async {
          await guestChat.cancel();
          await hostChat.cancel();
          guest.dispose();
          host.dispose();
          guestEngine.dispose();
          hostEngine.dispose();
        });

        await _seedInGameRoom(store, host.session);
        await host.start();
        await guest.start();

        final hello = await guest.sendSafeChat(SafeChatPhraseId.hello);
        await _eventually(
          () => hostMessages.length == 1 && guestMessages.length == 1,
        );
        expect(hostMessages.single.messageId, hello.messageId);
        expect(guestMessages.single.messageId, hello.messageId);
        expect(hostMessages.single.senderUid, 'guest_green');
        expect(hostMessages.single.phraseId, SafeChatPhraseId.hello);
        expect(
          onlineMap(
            await store.read(
              '$onlineTransportRoot/rooms/room_sync_001/chat/${hello.messageId}',
            ),
          ),
          hello.toJson(),
        );

        await guest.pause();
        store.advance(const Duration(milliseconds: 250));
        final greatMove = await host.sendSafeChat(SafeChatPhraseId.greatMove);
        await _eventually(() => hostMessages.length == 2);
        expect(guestMessages, hasLength(1));

        await guest.reconnect();
        await _eventually(() => guestMessages.length == 2);
        expect(
          guestMessages.map((message) => message.messageId).toList(),
          <String>[hello.messageId, greatMove.messageId],
        );
        expect(
          guestMessages.map((message) => message.messageId).toSet(),
          hasLength(2),
        );
      },
    );

    test(
      'Quick Message stream ignores CPU-authored transport records',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 1775689985000);
        final hostEngine = _engine(
          localColor: PlayerColor.red,
          random: Random(303),
        );
        final host = OnlineGameSyncClient(
          transport: _transport(store, uid: 'host_red'),
          roomId: 'room_sync_001',
          session: _sessionWithVirtualGreen(PlayerColor.red),
          engine: hostEngine,
          isHost: true,
        );
        final messages = <OnlineSafeChatMessage>[];
        final chatSubscription = host.safeChatMessages.listen(messages.add);
        addTearDown(() async {
          await chatSubscription.cancel();
          host.dispose();
          hostEngine.dispose();
        });

        await _seedInGameRoom(store, host.session);
        await host.start();
        await store.set(
          '$onlineTransportRoot/rooms/room_sync_001/chat/m_cpu',
          const OnlineSafeChatMessage(
            messageId: 'm_cpu',
            senderUid: 'cpu_green',
            phraseId: SafeChatPhraseId.hello,
            sentAtMs: 1775689985000,
          ).toJson(),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(messages, isEmpty);
      },
    );

    test(
      'guest commands are host-validated and both replicas stay identical',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 1000);
        final hostEngine = _engine(
          localColor: PlayerColor.red,
          random: _SequenceRandom(const <int>[4, 0]),
        );
        final guestEngine = _engine(
          localColor: PlayerColor.green,
          random: Random(77),
        );
        final host = OnlineGameSyncClient(
          transport: _transport(store, uid: 'host_red'),
          roomId: 'room_sync_001',
          session: _sessionFor(PlayerColor.red),
          engine: hostEngine,
          isHost: true,
          commandTimeout: const Duration(seconds: 2),
        );
        final guest = OnlineGameSyncClient(
          transport: _transport(store, uid: 'guest_green'),
          roomId: 'room_sync_001',
          session: _sessionFor(PlayerColor.green),
          engine: guestEngine,
          isHost: false,
          commandTimeout: const Duration(seconds: 2),
        );
        addTearDown(() {
          guest.dispose();
          host.dispose();
          guestEngine.dispose();
          hostEngine.dispose();
        });

        await _seedInGameRoom(store, host.session);
        await host.start();
        await guest.start();
        expect(host.isHost, isTrue);
        expect(guest.isHost, isFalse);
        expect(guest.localColor, PlayerColor.green);

        final matchDocument = onlineMap(
          await store.read('$onlineTransportRoot/rooms/room_sync_001/match'),
        );
        expect(matchDocument['authorityModel'], onlineGameSyncAuthorityModel);
        expect(matchDocument['checkpoint'], isA<Map>());
        expect(matchDocument['authorityRevision'], 0);

        final roll = await guest.submitRoll(actionId: 'roll_green_0001');
        expect(roll.status, OnlineCommandStatus.accepted);
        expect(roll.authorityRevision, 1);
        await _eventually(() => guest.revision == 1);
        expect(host.engine.dice, const <int>[5, 1]);
        expect(guest.engine.dice, const <int>[5, 1]);
        expect(_checkpoint(guest.engine), _checkpoint(host.engine));

        final move = await guest.submitMove(
          tokenId: 0,
          die: 5,
          actionId: 'move_green_0001',
        );
        expect(move.status, OnlineCommandStatus.accepted);
        expect(move.authorityRevision, 2);
        await _eventually(() => guest.revision == 2);
        expect(
          host.engine.players[PlayerColor.green.index].tokens.first.progress,
          0,
        );
        expect(_checkpoint(guest.engine), _checkpoint(host.engine));
        expect(
          store.operations.where(
            (operation) =>
                operation.kind == InMemoryStoreOperationKind.transaction &&
                operation.path.contains('/commands/'),
          ),
          isEmpty,
          reason:
              'Append-only commands must use a normal write; native iOS '
              'transactions rejected otherwise valid move payloads.',
        );
        expect(
          store.operations.where(
            (operation) =>
                operation.kind == InMemoryStoreOperationKind.set &&
                operation.path.contains('/commands/'),
          ),
          hasLength(2),
        );

        final beforeRejected = _checkpoint(host.engine);
        final stale = await guest.submitMove(
          tokenId: 0,
          die: 1,
          actionId: 'move_green_stale_001',
          expectedRevision: 0,
        );
        expect(stale.status, OnlineCommandStatus.rejected);
        expect(stale.rejection, OnlineCommandRejection.staleRevision);
        expect(host.revision, 2);
        expect(_checkpoint(host.engine), beforeRejected);

        final fabricated = await guest.submitMove(
          tokenId: 0,
          die: 6,
          actionId: 'move_green_fake_001',
          expectedRevision: 2,
        );
        expect(fabricated.status, OnlineCommandStatus.rejected);
        expect(fabricated.rejection, OnlineCommandRejection.fabricatedDie);
        expect(_checkpoint(host.engine), beforeRejected);
        expect(_checkpoint(guest.engine), beforeRejected);

        final duplicate = await guest.submitRoll(
          actionId: 'roll_green_0001',
          expectedRevision: 0,
        );
        expect(duplicate.status, OnlineCommandStatus.accepted);
        expect(duplicate.authorityRevision, 1);
        expect(host.revision, 2);

        await expectLater(
          guest.submitMove(
            tokenId: 1,
            die: 5,
            actionId: 'roll_green_0001',
            expectedRevision: 0,
          ),
          throwsA(isA<OnlineGameSyncException>()),
        );
      },
    );

    test(
      'Quick Pop capture keeps the +20 bonus playable on both online replicas',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 1200);
        final hostEngine = _engine(
          localColor: PlayerColor.red,
          random: Random(401),
          initialPlayer: PlayerColor.green,
          matchFormat: MatchFormat.quickPop,
        );
        final guestEngine = _engine(
          localColor: PlayerColor.green,
          random: Random(402),
          initialPlayer: PlayerColor.green,
          matchFormat: MatchFormat.quickPop,
        );
        final mover = hostEngine.players[PlayerColor.green.index].tokens.first
          ..progress = 1;
        hostEngine.players[PlayerColor.green.index].tokens.last.progress = 12;
        final captureGlobal = hostEngine.loopIndex(mover.owner, 4);
        hostEngine.players[PlayerColor.red.index].tokens.first.progress =
            (captureGlobal - GameEngine.startOffset[PlayerColor.red]!) %
            GameEngine.loopLength;
        hostEngine
          ..currentPlayerIndex = PlayerColor.green.index
          ..hasRolled = true
          ..dice = const <int>[3, 6];
        hostEngine.remainingDice.addAll(const <int>[3, 6]);

        final host = OnlineGameSyncClient(
          transport: _transport(store, uid: 'host_red'),
          roomId: 'room_sync_001',
          session: _quickPopSessionFor(PlayerColor.red),
          engine: hostEngine,
          isHost: true,
        );
        final guest = OnlineGameSyncClient(
          transport: _transport(store, uid: 'guest_green'),
          roomId: 'room_sync_001',
          session: _quickPopSessionFor(PlayerColor.green),
          engine: guestEngine,
          isHost: false,
        );
        addTearDown(() {
          guest.dispose();
          host.dispose();
          guestEngine.dispose();
          hostEngine.dispose();
        });

        await _seedInGameRoom(
          store,
          host.session,
          matchFormat: MatchFormat.quickPop,
        );
        await host.start();
        await guest.start();
        expect(guest.engine.currentPlayer.color, PlayerColor.green);

        final capture = await guest.submitMove(
          tokenId: 0,
          die: 3,
          actionId: 'quick_pop_capture_20_001',
        );
        expect(capture.status, OnlineCommandStatus.accepted);

        final bonus = await guest.submitMove(
          tokenId: 0,
          die: 20,
          actionId: 'quick_pop_capture_20_play_001',
        );
        expect(bonus.status, OnlineCommandStatus.accepted);
        await _eventually(() => guest.revision == bonus.stateRevision);
        expect(host.engine.remainingDice, const <int>[6]);
        expect(guest.engine.remainingDice, const <int>[6]);
        expect(
          guest.engine.players[PlayerColor.green.index].tokens.first.progress,
          24,
        );
        expect(_checkpoint(guest.engine), _checkpoint(host.engine));
      },
    );

    test(
      'Quick Pop accepts a base exit with any rolled die on the online host',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 1250);
        final hostEngine = _engine(
          localColor: PlayerColor.red,
          random: Random(405),
          initialPlayer: PlayerColor.red,
          matchFormat: MatchFormat.quickPop,
        );
        final guestEngine = _engine(
          localColor: PlayerColor.green,
          random: Random(406),
          initialPlayer: PlayerColor.red,
          matchFormat: MatchFormat.quickPop,
        );
        hostEngine
          ..hasRolled = true
          ..dice = const <int>[4, 6];
        hostEngine.remainingDice.addAll(const <int>[4, 6]);
        final host = OnlineGameSyncClient(
          transport: _transport(store, uid: 'host_red'),
          roomId: 'room_sync_001',
          session: _quickPopSessionFor(PlayerColor.red),
          engine: hostEngine,
          isHost: true,
        );
        final guest = OnlineGameSyncClient(
          transport: _transport(store, uid: 'guest_green'),
          roomId: 'room_sync_001',
          session: _quickPopSessionFor(PlayerColor.green),
          engine: guestEngine,
          isHost: false,
        );
        addTearDown(() {
          guest.dispose();
          host.dispose();
          guestEngine.dispose();
          hostEngine.dispose();
        });

        await _seedInGameRoom(
          store,
          host.session,
          matchFormat: MatchFormat.quickPop,
        );
        await host.start();
        await guest.start();
        expect(host.engine.currentPlayer.color, PlayerColor.red);
        expect(
          host.engine.canMove(host.engine.currentPlayer.tokens.first, 4),
          isTrue,
        );
        expect(
          host.engine.canMove(host.engine.currentPlayer.tokens.first, 6),
          isTrue,
        );

        final exit = await host.submitMove(
          tokenId: 0,
          die: 4,
          actionId: 'quick_pop_host_base_exit_4_001',
        );
        expect(exit.status, OnlineCommandStatus.accepted);
        await _eventually(() => guest.revision == exit.stateRevision);
        expect(host.engine.currentPlayer.tokens.first.progress, 0);
        expect(
          guest.engine.players[PlayerColor.red.index].tokens.first.progress,
          0,
        );
        expect(_checkpoint(guest.engine), _checkpoint(host.engine));
      },
    );

    for (final format in MatchFormat.values) {
      for (final mode in GameMode.values) {
        test(
          '${format.name} ${mode.name} keeps the +10 goal bonus immediately playable online',
          () async {
            final store = InMemoryOnlineRealtimeStore(initialNowMs: 1300);
            final hostSession = format == MatchFormat.quickPop
                ? _quickPopSessionFor(PlayerColor.red, mode: mode)
                : _sessionFor(PlayerColor.red, mode: mode);
            final guestSession = format == MatchFormat.quickPop
                ? _quickPopSessionFor(PlayerColor.green, mode: mode)
                : _sessionFor(PlayerColor.green, mode: mode);
            final hostEngine = _engine(
              localColor: PlayerColor.red,
              random: Random(411),
              initialPlayer: PlayerColor.green,
              matchFormat: format,
              mode: mode,
            );
            final guestEngine = _engine(
              localColor: PlayerColor.green,
              random: Random(412),
              initialPlayer: PlayerColor.green,
              matchFormat: format,
              mode: mode,
            );
            final green = hostEngine.players[PlayerColor.green.index];
            green.tokens.first.progress = GameEngine.finishProgress - 1;
            green.tokens.last.progress = 4;
            hostEngine
              ..currentPlayerIndex = PlayerColor.green.index
              ..hasRolled = true
              ..dice = const <int>[1, 6];
            hostEngine.remainingDice.addAll(const <int>[1, 6]);

            final host = OnlineGameSyncClient(
              transport: _transport(store, uid: 'host_red'),
              roomId: 'room_sync_001',
              session: hostSession,
              engine: hostEngine,
              isHost: true,
            );
            final guest = OnlineGameSyncClient(
              transport: _transport(store, uid: 'guest_green'),
              roomId: 'room_sync_001',
              session: guestSession,
              engine: guestEngine,
              isHost: false,
            );
            addTearDown(() {
              guest.dispose();
              host.dispose();
              guestEngine.dispose();
              hostEngine.dispose();
            });

            await _seedInGameRoom(store, host.session, matchFormat: format);
            await host.start();
            await guest.start();

            final goalFuture = guest.submitMove(
              tokenId: 0,
              die: 1,
              actionId: '${format.name}_${mode.name}_goal_10_001',
            );
            await _eventually(() => guest.engine.remainingDice.contains(10));
            final bonusFuture = guest.submitMove(
              tokenId: green.tokens.last.id,
              die: 10,
              actionId: '${format.name}_${mode.name}_goal_10_play_001',
            );

            final goal = await goalFuture;
            expect(goal.status, OnlineCommandStatus.accepted);
            await _eventually(() => guest.revision == goal.authorityRevision);

            final bonus = await bonusFuture;
            expect(bonus.status, OnlineCommandStatus.accepted);
            await _eventually(() => guest.revision == bonus.authorityRevision);
            expect(host.engine.remainingDice, const <int>[6]);
            expect(guest.engine.remainingDice, const <int>[6]);
            expect(green.tokens.last.progress, 14);
            expect(
              guest
                  .engine
                  .players[PlayerColor.green.index]
                  .tokens
                  .last
                  .progress,
              14,
            );
            expect(_checkpoint(guest.engine), _checkpoint(host.engine));
          },
        );
      }
    }

    test('guest accepts a Firebase-normalized initial checkpoint', () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 1500);
      final firebaseGuestStore = _FirebaseNormalizedStore(store);
      final hostSession = _quickPopSessionFor(PlayerColor.red);
      final hostEngine = _engine(
        localColor: PlayerColor.red,
        random: Random(151),
        initialPlayer: PlayerColor.red,
        matchFormat: MatchFormat.quickPop,
      );
      final guestEngine = _engine(
        localColor: PlayerColor.green,
        random: Random(152),
        initialPlayer: PlayerColor.red,
        matchFormat: MatchFormat.quickPop,
      );
      final host = OnlineGameSyncClient(
        transport: _transport(store, uid: 'host_red'),
        roomId: 'room_sync_001',
        session: hostSession,
        engine: hostEngine,
        isHost: true,
      );
      final guest = OnlineGameSyncClient(
        transport: _transport(firebaseGuestStore, uid: 'guest_green'),
        roomId: 'room_sync_001',
        session: _quickPopSessionFor(PlayerColor.green),
        engine: guestEngine,
        isHost: false,
      );
      addTearDown(() {
        guest.dispose();
        host.dispose();
        guestEngine.dispose();
        hostEngine.dispose();
      });

      await _seedInGameRoom(
        store,
        hostSession,
        matchFormat: MatchFormat.quickPop,
      );
      for (final uid in const <String>['host_red', 'guest_green']) {
        await store.set(
          '$onlineTransportRoot/rooms/room_sync_001/presence/$uid',
          OnlinePresenceRecord(
            uid: uid,
            presence: LobbyPresence.disconnected,
            changedAtMs: store.nowMs,
            connectionId: 'quick_room_sync_001_$uid',
          ).toJson(),
        );
      }
      await host.start();
      await _eventuallyAsync(
        () async =>
            await _persistedPresence(store, 'guest_green') ==
            OnlineParticipantPresence.reconnecting,
      );
      const matchPath = '$onlineTransportRoot/rooms/room_sync_001/match';
      final normalized = _firebaseNormalized(await store.read(matchPath));
      expect(normalized, isA<Map>());
      final normalizedDocument = onlineMap(normalized);
      expect(
        onlineMap(
          normalizedDocument['checkpoint'],
        ).containsKey('remainingDice'),
        isFalse,
      );
      expect(
        onlineMap(
          onlineMap(normalizedDocument['authorityCheckpoint'])['engine'],
        ).containsKey('remainingDice'),
        isFalse,
      );
      await store.set(matchPath, normalizedDocument);

      await guest.start();

      expect(guest.connectionState, OnlineGameConnectionState.connected);
      expect(guest.engine.remainingDice, isEmpty);
      expect(
        OnlineRoomRecord.fromJson(
          await store.read('$onlineTransportRoot/rooms/room_sync_001'),
        ).status,
        RoomStatus.inGame,
      );
      expect(
        onlineMap(
          await store.read(
            '$onlineTransportRoot/rooms/room_sync_001/presence/guest_green',
          ),
        )['state'],
        LobbyPresence.connected.name,
      );
      expect(
        await _persistedPresence(store, 'guest_green'),
        OnlineParticipantPresence.connected,
      );
      expect(_checkpoint(guest.engine), _checkpoint(host.engine));
    });

    test(
      'only the host timer advances no-move turns and publishes the mutation',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 2000);
        final hostEngine = _engine(
          localColor: PlayerColor.red,
          random: _SequenceRandom(const <int>[0, 1]),
        );
        final guestEngine = _engine(
          localColor: PlayerColor.green,
          random: Random(91),
        );
        final host = OnlineGameSyncClient(
          transport: _transport(store, uid: 'host_red'),
          roomId: 'room_sync_001',
          session: _sessionFor(PlayerColor.red),
          engine: hostEngine,
          isHost: true,
          commandTimeout: const Duration(seconds: 2),
        );
        final guest = OnlineGameSyncClient(
          transport: _transport(store, uid: 'guest_green'),
          roomId: 'room_sync_001',
          session: _sessionFor(PlayerColor.green),
          engine: guestEngine,
          isHost: false,
          commandTimeout: const Duration(seconds: 2),
        );
        addTearDown(() {
          guest.dispose();
          host.dispose();
          guestEngine.dispose();
          hostEngine.dispose();
        });

        await _seedInGameRoom(store, host.session);
        await host.start();
        await guest.start();
        final result = await guest.submitRoll(actionId: 'roll_no_move_0001');
        expect(result.status, OnlineCommandStatus.accepted);
        expect(host.engine.currentPlayer.color, PlayerColor.green);
        expect(guest.engine.currentPlayer.color, PlayerColor.green);

        // A replica reconstructed from a no-move checkpoint would normally
        // schedule an immediate local turn. applyRemoteCheckpoint cancels it.
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(guest.engine.currentPlayer.color, PlayerColor.green);
        expect(host.stateRevision, 1);

        await _eventually(
          () =>
              host.engine.currentPlayer.color == PlayerColor.yellow &&
              guest.engine.currentPlayer.color == PlayerColor.yellow,
          timeout: const Duration(seconds: 2),
        );
        expect(host.revision, 1);
        expect(guest.revision, 1);
        expect(host.stateRevision, greaterThanOrEqualTo(2));
        expect(guest.stateRevision, host.stateRevision);
        expect(_checkpoint(guest.engine), _checkpoint(host.engine));
      },
    );

    test(
      'pause and reconnect catch a guest up from the durable checkpoint',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 3000);
        final hostEngine = _engine(
          localColor: PlayerColor.red,
          random: Random(3),
        );
        final guestEngine = _engine(
          localColor: PlayerColor.green,
          random: Random(4),
        );
        final host = OnlineGameSyncClient(
          transport: _transport(store, uid: 'host_red'),
          roomId: 'room_sync_001',
          session: _sessionFor(PlayerColor.red),
          engine: hostEngine,
          isHost: true,
        );
        final guest = OnlineGameSyncClient(
          transport: _transport(store, uid: 'guest_green'),
          roomId: 'room_sync_001',
          session: _sessionFor(PlayerColor.green),
          engine: guestEngine,
          isHost: false,
        );
        addTearDown(() {
          guest.dispose();
          host.dispose();
          guestEngine.dispose();
          hostEngine.dispose();
        });

        await _seedInGameRoom(store, host.session);
        await host.start();
        await guest.start();
        await guest.pause();
        expect(guest.connectionState, OnlineGameConnectionState.idle);
        host.engine.dice = const <int>[1, 2];
        host.engine.endTurn();
        await _eventually(() => host.stateRevision == 1);
        expect(guest.engine.currentPlayer.color, PlayerColor.green);

        await guest.reconnect();
        expect(guest.connectionState, OnlineGameConnectionState.connected);
        expect(guest.engine.currentPlayer.color, PlayerColor.yellow);
        expect(_checkpoint(guest.engine), _checkpoint(host.engine));
      },
    );

    test(
      'a replacement host resumes without replaying accepted commands',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 4000);
        final firstHostEngine = _engine(
          localColor: PlayerColor.red,
          random: _SequenceRandom(const <int>[4, 0]),
        );
        final guestEngine = _engine(
          localColor: PlayerColor.green,
          random: Random(5),
        );
        final firstHost = OnlineGameSyncClient(
          transport: _transport(store, uid: 'host_red'),
          roomId: 'room_sync_001',
          session: _sessionFor(PlayerColor.red),
          engine: firstHostEngine,
          isHost: true,
        );
        final guest = OnlineGameSyncClient(
          transport: _transport(store, uid: 'guest_green'),
          roomId: 'room_sync_001',
          session: _sessionFor(PlayerColor.green),
          engine: guestEngine,
          isHost: false,
        );

        await _seedInGameRoom(store, firstHost.session);
        await firstHost.start();
        await guest.start();
        final roll = await guest.submitRoll(actionId: 'roll_before_resume_001');
        expect(roll.status, OnlineCommandStatus.accepted);
        expect(firstHost.revision, 1);
        firstHost.dispose();

        final unusedFreshEngine = _engine(
          localColor: PlayerColor.red,
          random: Random(6),
        );
        final replacementHost = OnlineGameSyncClient(
          transport: _transport(store, uid: 'host_red'),
          roomId: 'room_sync_001',
          session: _sessionFor(PlayerColor.red),
          engine: unusedFreshEngine,
          isHost: true,
        );
        addTearDown(() {
          replacementHost.dispose();
          guest.dispose();
          unusedFreshEngine.dispose();
          guestEngine.dispose();
          firstHostEngine.dispose();
        });

        await replacementHost.start();
        expect(replacementHost.revision, 1);
        expect(_checkpoint(replacementHost.engine), _checkpoint(guest.engine));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(replacementHost.revision, 1);

        final move = await guest.submitMove(
          tokenId: 0,
          die: 5,
          actionId: 'move_after_resume_001',
        );
        expect(move.status, OnlineCommandStatus.accepted);
        expect(replacementHost.revision, 2);
        await _eventually(() => guest.revision == 2);
        expect(_checkpoint(replacementHost.engine), _checkpoint(guest.engine));
      },
    );

    test(
      'host drives a virtual seat but a guest cannot impersonate it',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 5000);
        final hostEngine = _engine(
          localColor: PlayerColor.red,
          random: _SequenceRandom(const <int>[4, 0]),
        );
        final guestEngine = _engine(
          localColor: PlayerColor.yellow,
          random: Random(8),
        );
        final host = OnlineGameSyncClient(
          transport: _transport(store, uid: 'host_red'),
          roomId: 'room_sync_001',
          session: _sessionWithVirtualGreen(PlayerColor.red),
          engine: hostEngine,
          isHost: true,
        );
        final guest = OnlineGameSyncClient(
          transport: _transport(store, uid: 'guest_yellow'),
          roomId: 'room_sync_001',
          session: _sessionWithVirtualGreen(PlayerColor.yellow),
          engine: guestEngine,
          isHost: false,
        );
        addTearDown(() {
          guest.dispose();
          host.dispose();
          guestEngine.dispose();
          hostEngine.dispose();
        });

        await _seedInGameRoom(store, host.session);
        await host.start();
        await guest.start();
        final roll = await host.submitRollFor(
          'cpu_green',
          actionId: 'roll_virtual_green_001',
        );
        expect(roll.status, OnlineCommandStatus.accepted);
        expect(host.engine.dice, const <int>[5, 1]);
        await _eventually(() => guest.revision == 1);
        expect(_checkpoint(guest.engine), _checkpoint(host.engine));

        expect(
          () => guest.submitRollFor(
            'cpu_green',
            actionId: 'guest_impersonation_001',
          ),
          throwsA(isA<OnlineGameSyncException>()),
        );

        final move = await host.submitMoveFor(
          'cpu_green',
          tokenId: 0,
          die: 5,
          actionId: 'move_virtual_green_001',
        );
        expect(move.status, OnlineCommandStatus.accepted);
        expect(host.revision, 2);
        await _eventually(() => guest.revision == 2);
        expect(_checkpoint(guest.engine), _checkpoint(host.engine));
      },
    );

    test(
      'host authority resolves a virtual Chaos power-up for every replica',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 6000);
        final hostEngine = _engine(
          localColor: PlayerColor.red,
          random: Random(11),
          mode: GameMode.chaos,
        );
        hostEngine.players[PlayerColor.green.index].tokens.first.progress = 0;
        hostEngine.players[PlayerColor.green.index].inventory = PowerUp.boost;
        final guestEngine = _engine(
          localColor: PlayerColor.yellow,
          random: Random(12),
          mode: GameMode.chaos,
        );
        final host = OnlineGameSyncClient(
          transport: _transport(store, uid: 'host_red'),
          roomId: 'room_sync_001',
          session: _sessionWithVirtualGreen(
            PlayerColor.red,
            mode: GameMode.chaos,
          ),
          engine: hostEngine,
          isHost: true,
        );
        final guest = OnlineGameSyncClient(
          transport: _transport(store, uid: 'guest_yellow'),
          roomId: 'room_sync_001',
          session: _sessionWithVirtualGreen(
            PlayerColor.yellow,
            mode: GameMode.chaos,
          ),
          engine: guestEngine,
          isHost: false,
        );
        addTearDown(() {
          guest.dispose();
          host.dispose();
          guestEngine.dispose();
          hostEngine.dispose();
        });

        await _seedInGameRoom(store, host.session);
        await host.start();
        await guest.start();
        final result = await host.submitPowerUpFor(
          'cpu_green',
          actionId: 'power_virtual_green_001',
        );
        expect(result.status, OnlineCommandStatus.accepted);
        expect(
          host.engine.players[PlayerColor.green.index].tokens.first.progress,
          3,
        );
        expect(host.engine.players[PlayerColor.green.index].inventory, isNull);
        await _eventually(() => guest.revision == 1);
        expect(_checkpoint(guest.engine), _checkpoint(host.engine));
      },
    );

    test('replacement host resumes an interrupted no-move timer', () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 7000);
      final firstHostEngine = _engine(
        localColor: PlayerColor.red,
        random: _SequenceRandom(const <int>[0, 1]),
      );
      final guestEngine = _engine(
        localColor: PlayerColor.green,
        random: Random(13),
      );
      final firstHost = OnlineGameSyncClient(
        transport: _transport(store, uid: 'host_red'),
        roomId: 'room_sync_001',
        session: _sessionFor(PlayerColor.red),
        engine: firstHostEngine,
        isHost: true,
      );
      final guest = OnlineGameSyncClient(
        transport: _transport(store, uid: 'guest_green'),
        roomId: 'room_sync_001',
        session: _sessionFor(PlayerColor.green),
        engine: guestEngine,
        isHost: false,
      );
      await _seedInGameRoom(store, firstHost.session);
      await firstHost.start();
      await guest.start();
      final roll = await guest.submitRoll(actionId: 'roll_resume_timer_001');
      expect(roll.status, OnlineCommandStatus.accepted);
      firstHost.dispose();

      final unusedFreshEngine = _engine(
        localColor: PlayerColor.red,
        random: Random(14),
      );
      final replacementHost = OnlineGameSyncClient(
        transport: _transport(store, uid: 'host_red'),
        roomId: 'room_sync_001',
        session: _sessionFor(PlayerColor.red),
        engine: unusedFreshEngine,
        isHost: true,
      );
      addTearDown(() {
        replacementHost.dispose();
        guest.dispose();
        unusedFreshEngine.dispose();
        guestEngine.dispose();
        firstHostEngine.dispose();
      });
      await replacementHost.start();
      expect(replacementHost.engine.currentPlayer.color, PlayerColor.green);

      await _eventually(
        () =>
            replacementHost.engine.currentPlayer.color == PlayerColor.yellow &&
            guest.engine.currentPlayer.color == PlayerColor.yellow,
        timeout: const Duration(seconds: 2),
      );
      expect(replacementHost.revision, 1);
      expect(_checkpoint(guest.engine), _checkpoint(replacementHost.engine));
    });

    test(
      'disconnect expires to CPU, host drives it, and reconnect reclaims it',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 8000);
        final hostSession = _sessionFor(PlayerColor.red);
        final hostEngine = _engine(
          localColor: PlayerColor.red,
          random: _SequenceRandom(const <int>[4, 0]),
        );
        final authority = OnlineMatchAuthority(
          session: hostSession,
          engine: hostEngine,
          disconnectPolicy: const OnlineDisconnectPolicy(
            gracePeriod: Duration(milliseconds: 40),
            afterGrace: DisconnectExpiryAction.cpuTakeover,
            allowReclaimAfterCpuTakeover: true,
          ),
        );
        final guestEngine = _engine(
          localColor: PlayerColor.green,
          random: Random(81),
        );
        final host = OnlineGameSyncClient(
          transport: _transport(store, uid: 'host_red'),
          roomId: 'room_sync_001',
          session: hostSession,
          engine: hostEngine,
          authority: authority,
          isHost: true,
          commandTimeout: const Duration(seconds: 2),
        );
        final guest = OnlineGameSyncClient(
          transport: _transport(store, uid: 'guest_green'),
          roomId: 'room_sync_001',
          session: _sessionFor(PlayerColor.green),
          engine: guestEngine,
          isHost: false,
          commandTimeout: const Duration(seconds: 2),
        );
        addTearDown(() {
          guest.dispose();
          host.dispose();
          guestEngine.dispose();
          hostEngine.dispose();
        });

        await _seedInGameRoom(store, hostSession);
        await host.start();
        await guest.start();

        await guest.pause();
        await _eventuallyAsync(
          () async =>
              await _persistedPresence(store, 'guest_green') ==
              OnlineParticipantPresence.reconnecting,
        );
        expect(host.canHostDriveParticipant('guest_green'), isFalse);
        expect(host.revision, 1);

        store.advance(const Duration(milliseconds: 41));
        await _eventually(() => host.canHostDriveParticipant('guest_green'));
        await _eventuallyAsync(
          () async =>
              await _persistedPresence(store, 'guest_green') ==
              OnlineParticipantPresence.cpuControlled,
        );
        expect(host.revision, 2);

        const lateActionId = 'late_human_after_takeover_001';
        final lateCommand = OnlineGameCommandRecord(
          kind: OnlineGameCommandKind.roll,
          matchId: hostSession.matchId,
          participantId: 'guest_green',
          submittedById: 'guest_green',
          actionId: lateActionId,
          expectedRevision: 2,
          submittedAtMs: store.nowMs,
        );
        await store.set(
          '$onlineTransportRoot/rooms/room_sync_001/commands/'
          'guest_green/$lateActionId',
          lateCommand.toJson(),
        );
        await _eventuallyAsync(() async {
          final raw = await store.read(
            '$onlineTransportRoot/rooms/room_sync_001/match/results/'
            'guest_green/$lateActionId',
          );
          return raw != null;
        });
        final lateResult = OnlineGameCommandResultRecord.fromJson(
          await store.read(
            '$onlineTransportRoot/rooms/room_sync_001/match/results/'
            'guest_green/$lateActionId',
          ),
        );
        expect(
          lateResult.rejection,
          OnlineCommandRejection.participantUnavailable,
        );
        expect(host.revision, 2);

        final cpuRoll = await host.submitRollFor(
          'guest_green',
          actionId: 'host_takeover_roll_001',
        );
        expect(cpuRoll.status, OnlineCommandStatus.accepted);
        expect(host.engine.dice, const <int>[5, 1]);
        expect(host.revision, 3);

        await guest.reconnect();
        expect(guest.localParticipantAwaitingNextTurn, isTrue);
        await _eventually(() => host.canHostDriveParticipant('guest_green'));
        await _eventuallyAsync(
          () async =>
              await _persistedPresence(store, 'guest_green') ==
              OnlineParticipantPresence.connected,
        );
        await _eventually(() => guest.revision == 4);
        expect(guest.engine.dice, const <int>[5, 1]);
        final blockedMove = await guest.submitMove(
          tokenId: 0,
          die: 5,
          actionId: 'human_reclaimed_move_too_soon_001',
        );
        expect(
          blockedMove.rejection,
          OnlineCommandRejection.participantUnavailable,
        );

        expect(host.canHostDriveParticipant('guest_green'), isTrue);
        // Finish the CPU-controlled dice turn. The returning guest is now
        // connected but must wait for its next turn around the table.
        host.engine.endTurn();
        await _eventually(() => !host.canHostDriveParticipant('guest_green'));
        await _eventually(() => !guest.localParticipantAwaitingNextTurn);
        final stillWaitingForSeat = await guest.submitRoll(
          actionId: 'human_reclaimed_roll_before_next_turn_001',
        );
        expect(
          stillWaitingForSeat.rejection,
          OnlineCommandRejection.notPlayersTurn,
        );
        expect(_checkpoint(guest.engine), _checkpoint(host.engine));
      },
    );

    test(
      'pause reconnects inside grace without a takeover or forfeit',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 9000);
        final hostSession = _sessionFor(PlayerColor.red);
        final hostEngine = _engine(
          localColor: PlayerColor.red,
          random: _SequenceRandom(const <int>[4, 0]),
        );
        final authority = OnlineMatchAuthority(
          session: hostSession,
          engine: hostEngine,
          disconnectPolicy: const OnlineDisconnectPolicy(
            gracePeriod: Duration(milliseconds: 50),
            afterGrace: DisconnectExpiryAction.forfeit,
          ),
        );
        final guestEngine = _engine(
          localColor: PlayerColor.green,
          random: Random(91),
        );
        final host = OnlineGameSyncClient(
          transport: _transport(store, uid: 'host_red'),
          roomId: 'room_sync_001',
          session: hostSession,
          engine: hostEngine,
          authority: authority,
          isHost: true,
        );
        final guest = OnlineGameSyncClient(
          transport: _transport(store, uid: 'guest_green'),
          roomId: 'room_sync_001',
          session: _sessionFor(PlayerColor.green),
          engine: guestEngine,
          isHost: false,
        );
        addTearDown(() {
          guest.dispose();
          host.dispose();
          guestEngine.dispose();
          hostEngine.dispose();
        });

        await _seedInGameRoom(store, hostSession);
        await host.start();
        await guest.start();
        await guest.pause();
        await _eventuallyAsync(
          () async =>
              await _persistedPresence(store, 'guest_green') ==
              OnlineParticipantPresence.reconnecting,
        );

        store.advance(const Duration(milliseconds: 20));
        await guest.reconnect();
        await _eventuallyAsync(
          () async =>
              await _persistedPresence(store, 'guest_green') ==
              OnlineParticipantPresence.connected,
        );
        store.advance(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 70));
        expect(
          await _persistedPresence(store, 'guest_green'),
          OnlineParticipantPresence.connected,
        );
        expect(host.canHostDriveParticipant('guest_green'), isFalse);

        // The reconnect happened at a clean dice boundary, so there is no
        // interrupted roll for the host to finish. The returning guest can
        // safely roll immediately instead of being stranded behind a stale
        // "wait for next turn" marker.
        expect(guest.localParticipantAwaitingNextTurn, isFalse);
        final rollAfterPause = await guest.submitRoll(
          actionId: 'roll_after_pause_at_clean_boundary_001',
        );
        expect(rollAfterPause.status, OnlineCommandStatus.accepted);
        host.engine.endTurn();
      },
    );

    test(
      'Quick Pop sync start installs a real onDisconnect presence lease',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 10000);
        final hostSession = _sessionFor(PlayerColor.red);
        final hostEngine = _engine(
          localColor: PlayerColor.red,
          random: Random(101),
          matchFormat: MatchFormat.quickPop,
        );
        final guestEngine = _engine(
          localColor: PlayerColor.green,
          random: Random(102),
          matchFormat: MatchFormat.quickPop,
        );
        final host = OnlineGameSyncClient(
          transport: _transport(store, uid: 'host_red'),
          roomId: 'room_sync_001',
          session: hostSession,
          engine: hostEngine,
          isHost: true,
        );
        final guest = OnlineGameSyncClient(
          transport: _transport(store, uid: 'guest_green'),
          roomId: 'room_sync_001',
          session: _sessionFor(PlayerColor.green),
          engine: guestEngine,
          isHost: false,
        );
        addTearDown(() {
          guest.dispose();
          host.dispose();
          guestEngine.dispose();
          hostEngine.dispose();
        });

        await _seedInGameRoom(
          store,
          hostSession,
          matchFormat: MatchFormat.quickPop,
        );
        await host.start();
        await guest.start();
        const guestPresencePath =
            '$onlineTransportRoot/rooms/room_sync_001/presence/guest_green';
        expect(
          store.operations.any(
            (operation) =>
                operation.kind == InMemoryStoreOperationKind.onDisconnect &&
                operation.path == guestPresencePath,
          ),
          isTrue,
        );

        await store.simulateDisconnect(path: guestPresencePath);
        await _eventuallyAsync(
          () async =>
              await _persistedPresence(store, 'guest_green') ==
              OnlineParticipantPresence.reconnecting,
        );
        expect(
          onlineMap(await store.read(guestPresencePath))['state'],
          LobbyPresence.disconnected.name,
        );

        await guest.reconnect();
        await _eventuallyAsync(
          () async =>
              await _persistedPresence(store, 'guest_green') ==
              OnlineParticipantPresence.connected,
        );
        guest.dispose();
        await _eventuallyAsync(
          () async =>
              onlineMap(await store.read(guestPresencePath))['state'] ==
              LobbyPresence.disconnected.name,
        );
      },
    );

    test(
      'an active match restores its one-shot presence lease after a transient '
      'disconnect',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 10500);
        final hostSession = _sessionFor(PlayerColor.red);
        final hostEngine = _engine(
          localColor: PlayerColor.red,
          random: Random(106),
          matchFormat: MatchFormat.quickPop,
        );
        final guestEngine = _engine(
          localColor: PlayerColor.green,
          random: Random(107),
          matchFormat: MatchFormat.quickPop,
        );
        final host = OnlineGameSyncClient(
          transport: _transport(store, uid: 'host_red'),
          roomId: 'room_sync_001',
          session: hostSession,
          engine: hostEngine,
          isHost: true,
          presenceRecoveryInterval: const Duration(milliseconds: 20),
        );
        final guest = OnlineGameSyncClient(
          transport: _transport(store, uid: 'guest_green'),
          roomId: 'room_sync_001',
          session: _sessionFor(PlayerColor.green),
          engine: guestEngine,
          isHost: false,
          presenceRecoveryInterval: const Duration(milliseconds: 20),
        );
        addTearDown(() {
          guest.dispose();
          host.dispose();
          guestEngine.dispose();
          hostEngine.dispose();
        });

        await _seedInGameRoom(
          store,
          hostSession,
          matchFormat: MatchFormat.quickPop,
        );
        await host.start();
        await guest.start();
        const guestPresencePath =
            '$onlineTransportRoot/rooms/room_sync_001/presence/guest_green';

        store.clearOperations();
        await store.simulateDisconnect(path: guestPresencePath);
        expect(
          onlineMap(await store.read(guestPresencePath))['state'],
          LobbyPresence.disconnected.name,
        );

        await _eventuallyAsync(
          () async =>
              onlineMap(await store.read(guestPresencePath))['state'] ==
              LobbyPresence.connected.name,
        );
        expect(
          store.operations.where(
            (operation) =>
                operation.kind == InMemoryStoreOperationKind.onDisconnect &&
                operation.path == guestPresencePath,
          ),
          isNotEmpty,
        );

        // Recovery re-arms the server hook; a second socket loss is detected
        // instead of leaving a stale connected participant forever.
        await store.simulateDisconnect(path: guestPresencePath);
        expect(
          onlineMap(await store.read(guestPresencePath))['state'],
          LobbyPresence.disconnected.name,
        );
      },
    );

    test(
      'host loss becomes explicit and the same host can recover the match',
      () async {
        final store = InMemoryOnlineRealtimeStore(initialNowMs: 11000);
        final hostSession = _sessionFor(PlayerColor.red);
        final firstHostEngine = _engine(
          localColor: PlayerColor.red,
          random: Random(111),
        );
        final guestEngine = _engine(
          localColor: PlayerColor.green,
          random: Random(112),
        );
        final firstHost = OnlineGameSyncClient(
          transport: _transport(store, uid: 'host_red'),
          roomId: 'room_sync_001',
          session: hostSession,
          engine: firstHostEngine,
          isHost: true,
        );
        final guest = OnlineGameSyncClient(
          transport: _transport(store, uid: 'guest_green'),
          roomId: 'room_sync_001',
          session: _sessionFor(PlayerColor.green),
          engine: guestEngine,
          isHost: false,
          hostReconnectGrace: const Duration(milliseconds: 40),
        );
        var guestNotifications = 0;
        void countGuestNotifications() => guestNotifications++;
        guest.addListener(countGuestNotifications);

        await _seedInGameRoom(store, hostSession);
        await firstHost.start();
        await guest.start();
        firstHost.dispose();

        await _eventually(
          () => guest.hostAvailability == OnlineHostAvailability.reconnecting,
        );
        expect(guest.connectionState, OnlineGameConnectionState.reconnecting);
        expect(guest.hostReconnectDeadline, isNotNull);
        await expectLater(
          guest.submitRoll(actionId: 'roll_without_host_001'),
          throwsA(isA<OnlineGameSyncException>()),
        );

        await _eventually(
          () => guest.hostAvailability == OnlineHostAvailability.unavailable,
        );
        expect(guest.requiresHostRecovery, isTrue);
        expect(guest.connectionState, OnlineGameConnectionState.failed);
        expect(guest.lastError, isA<OnlineHostUnavailableException>());
        expect(await guest.retryHostRecovery(), isFalse);

        final replacementEngine = _engine(
          localColor: PlayerColor.red,
          random: Random(113),
        );
        final replacementHost = OnlineGameSyncClient(
          transport: _transport(store, uid: 'host_red'),
          roomId: 'room_sync_001',
          session: hostSession,
          engine: replacementEngine,
          isHost: true,
        );
        addTearDown(() {
          guest.removeListener(countGuestNotifications);
          guest.dispose();
          replacementHost.dispose();
          replacementEngine.dispose();
          guestEngine.dispose();
          firstHostEngine.dispose();
        });

        await replacementHost.start();
        await _eventually(
          () => guest.hostAvailability == OnlineHostAvailability.available,
        );
        expect(guest.requiresHostRecovery, isFalse);
        expect(guest.connectionState, OnlineGameConnectionState.connected);
        expect(guest.lastError, isNull);
        expect(guestNotifications, greaterThanOrEqualTo(3));
        expect(await guest.retryHostRecovery(), isTrue);

        final roll = await guest.submitRoll(
          actionId: 'roll_after_host_recovery_001',
        );
        expect(roll.status, OnlineCommandStatus.accepted);
        await _eventually(() => guest.revision == 1);
        expect(_checkpoint(guest.engine), _checkpoint(replacementHost.engine));
      },
    );

    test('a guest cannot promote itself into activeHostV1 authority', () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 12000);
      final hostSession = _sessionFor(PlayerColor.red);
      final hostEngine = _engine(
        localColor: PlayerColor.red,
        random: Random(121),
      );
      final host = OnlineGameSyncClient(
        transport: _transport(store, uid: 'host_red'),
        roomId: 'room_sync_001',
        session: hostSession,
        engine: hostEngine,
        isHost: true,
      );
      final promotedEngine = _engine(
        localColor: PlayerColor.green,
        random: Random(122),
      );
      final attemptedPromotion = OnlineGameSyncClient(
        transport: _transport(store, uid: 'guest_green'),
        roomId: 'room_sync_001',
        session: _sessionFor(PlayerColor.green),
        engine: promotedEngine,
        isHost: true,
      );
      addTearDown(() {
        attemptedPromotion.dispose();
        host.dispose();
        promotedEngine.dispose();
        hostEngine.dispose();
      });

      await _seedInGameRoom(store, hostSession);
      await host.start();
      await expectLater(
        attemptedPromotion.start(),
        throwsA(
          isA<OnlineGameSyncException>().having(
            (error) => error.message,
            'message',
            contains('recorded room host'),
          ),
        ),
      );
      expect(
        attemptedPromotion.connectionState,
        OnlineGameConnectionState.failed,
      );
    });
  });
}
