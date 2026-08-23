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

import 'support/in_memory_online_realtime_store.dart';

const _participantIds = <PlayerColor, String>{
  PlayerColor.red: 'player_red',
  PlayerColor.green: 'player_green',
  PlayerColor.yellow: 'player_yellow',
  PlayerColor.blue: 'player_blue',
};

OnlineParticipant _participant({
  required PlayerColor color,
  required ParticipantKind kind,
}) => OnlineParticipant(
  id: _participantIds[color]!,
  displayName: 'Player ${color.name}',
  flag: '🇩🇴',
  avatarId: 'avatar_default',
  level: 1,
  color: color,
  kind: kind,
  loadout: const CosmeticLoadout(),
);

OnlineMatchSession _session({
  required String matchId,
  required PlayerColor localColor,
  required int humanCount,
  required GameMode mode,
}) => OnlineMatchSession(
  matchId: matchId,
  seed: 20260813,
  mode: mode,
  participants: <OnlineParticipant>[
    for (final color in PlayerColor.values)
      _participant(
        color: color,
        kind: color == localColor
            ? ParticipantKind.local
            : color.index < humanCount
            ? ParticipantKind.remoteHuman
            : ParticipantKind.virtual,
      ),
  ],
);

GameEngine _engine({
  required PlayerColor localColor,
  required PlayerColor initialPlayer,
  required MatchFormat format,
  required GameMode mode,
  required int seed,
}) => GameEngine(
  mode: mode,
  matchFormat: format,
  localViewerColor: localColor,
  initialPlayerColor: initialPlayer,
  random: Random(seed),
  humanName: 'Player ${localColor.name}',
  playerNames: <PlayerColor, String>{
    for (final color in PlayerColor.values) color: 'Player ${color.name}',
  },
);

OnlineTransportClient _transport(
  InMemoryOnlineRealtimeStore store,
  PlayerColor color,
) => OnlineTransportClient(
  store: store,
  identity: OnlineTransportIdentity(
    uid: _participantIds[color]!,
    displayName: 'Player ${color.name}',
  ),
  random: Random(100 + color.index),
);

Future<void> _seedRoom({
  required InMemoryOnlineRealtimeStore store,
  required String roomId,
  required OnlineMatchSession session,
  required MatchFormat format,
}) async {
  final now = store.nowMs;
  final room = OnlineRoomRecord(
    id: roomId,
    code: RoomCode.parse('ABC234'),
    hostUid: _participantIds[PlayerColor.red]!,
    visibility: RoomVisibility.private,
    status: RoomStatus.inGame,
    mode: session.mode.name,
    matchFormat: format.name,
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
  await store.set('$onlineTransportRoot/rooms/$roomId', room.toJson());
}

Future<void> _eventually(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition was not satisfied before $timeout.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

String _checkpoint(GameEngine engine) => jsonEncode(engine.createCheckpoint());

void main() {
  test(
    'online rooms with 1-4 humans consume the +10 goal bonus and finish in every mode',
    () async {
      for (var repetition = 1; repetition <= 2; repetition++) {
        for (final format in MatchFormat.values) {
          for (final mode in GameMode.values) {
            for (var humanCount = 1; humanCount <= 4; humanCount++) {
              final label =
                  'repeat $repetition / ${format.name} / ${mode.name} / '
                  '$humanCount human(s)';
              final store = InMemoryOnlineRealtimeStore(
                initialNowMs:
                    200000 +
                    repetition * 10000 +
                    format.index * 1000 +
                    mode.index * 100 +
                    humanCount,
              );
              final roomId =
                  'goal_${repetition}_${format.name}_${mode.name}_$humanCount';
              final matchId = '${roomId}_match';
              final activeColor = PlayerColor.values[humanCount - 1];
              final hostSession = _session(
                matchId: matchId,
                localColor: PlayerColor.red,
                humanCount: humanCount,
                mode: mode,
              );
              final hostEngine = _engine(
                localColor: PlayerColor.red,
                initialPlayer: activeColor,
                format: format,
                mode: mode,
                seed: 1000 + humanCount,
              );

              final activePlayer = hostEngine.players[activeColor.index];
              final required = hostEngine.rules.tokensRequiredToWin;
              for (var tokenId = 0; tokenId < required - 2; tokenId++) {
                activePlayer.tokens[tokenId].progress =
                    GameEngine.finishProgress;
              }
              final firstGoalToken = activePlayer.tokens[required - 2]
                ..progress = GameEngine.finishProgress - 1;
              final bonusGoalToken = activePlayer.tokens[required - 1]
                ..progress = GameEngine.finishProgress - 10;
              hostEngine
                ..currentPlayerIndex = activeColor.index
                ..hasRolled = true
                ..dice = const <int>[1, 6];
              hostEngine.remainingDice.addAll(const <int>[1, 6]);

              final clients = <OnlineGameSyncClient>[];
              final engines = <GameEngine>[hostEngine];
              try {
                final host = OnlineGameSyncClient(
                  transport: _transport(store, PlayerColor.red),
                  roomId: roomId,
                  session: hostSession,
                  engine: hostEngine,
                  isHost: true,
                  commandTimeout: const Duration(seconds: 3),
                );
                clients.add(host);

                for (
                  var colorIndex = 1;
                  colorIndex < humanCount;
                  colorIndex++
                ) {
                  final color = PlayerColor.values[colorIndex];
                  final replicaEngine = _engine(
                    localColor: color,
                    initialPlayer: activeColor,
                    format: format,
                    mode: mode,
                    seed: 2000 + colorIndex,
                  );
                  engines.add(replicaEngine);
                  clients.add(
                    OnlineGameSyncClient(
                      transport: _transport(store, color),
                      roomId: roomId,
                      session: _session(
                        matchId: matchId,
                        localColor: color,
                        humanCount: humanCount,
                        mode: mode,
                      ),
                      engine: replicaEngine,
                      isHost: false,
                      commandTimeout: const Duration(seconds: 3),
                    ),
                  );
                }

                await _seedRoom(
                  store: store,
                  roomId: roomId,
                  session: hostSession,
                  format: format,
                );
                for (final client in clients) {
                  await client.start();
                }

                final actor = clients[humanCount - 1];
                final firstGoal = await actor.submitMove(
                  tokenId: firstGoalToken.id,
                  die: 1,
                  actionId: '${roomId}_first_goal',
                );
                expect(
                  firstGoal.status,
                  OnlineCommandStatus.accepted,
                  reason: label,
                );
                await _eventually(
                  () => clients.every(
                    (client) =>
                        client.revision == firstGoal.authorityRevision &&
                        client.engine.remainingDice.contains(10),
                  ),
                );

                final winningBonus = await actor.submitMove(
                  tokenId: bonusGoalToken.id,
                  die: 10,
                  actionId: '${roomId}_winning_bonus',
                );
                expect(
                  winningBonus.status,
                  OnlineCommandStatus.accepted,
                  reason: label,
                );
                await _eventually(
                  () => clients.every(
                    (client) =>
                        client.revision == winningBonus.authorityRevision &&
                        client.engine.gameOver,
                  ),
                );

                final authoritative = _checkpoint(host.engine);
                for (final client in clients) {
                  expect(
                    client.engine.winner?.color,
                    activeColor,
                    reason: label,
                  );
                  expect(
                    client.engine.players[activeColor.index].tokens
                        .where((token) => token.finished)
                        .length,
                    required,
                    reason: label,
                  );
                  expect(
                    _checkpoint(client.engine),
                    authoritative,
                    reason: label,
                  );
                }
              } finally {
                for (final client in clients.reversed) {
                  client.dispose();
                }
                for (final engine in engines.reversed) {
                  engine.dispose();
                }
              }
            }
          }
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
