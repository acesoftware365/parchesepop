import 'dart:math';

import 'game_engine.dart';
import 'online_game_sync.dart';
import 'online_lobby.dart';
import 'online_mode_services.dart';
import 'online_match.dart';
import 'online_room_ui.dart';
import 'online_transport.dart';
import 'online_transport_models.dart';
import 'realtime_online_room_controller.dart';

class OnlineQuickTablePreparationException implements Exception {
  const OnlineQuickTablePreparationException(this.message);

  final String message;

  @override
  String toString() => 'OnlineQuickTablePreparationException: $message';
}

/// Fully validated, unstarted live-match objects for one Quick Table client.
class PreparedOnlineQuickTableMatch {
  const PreparedOnlineQuickTableMatch({
    required this.room,
    required this.lobby,
    required this.session,
    required this.engine,
    required this.sync,
    required this.isHost,
    required this.initialPlayerColor,
  });

  final OnlineRoomRecord room;
  final OnlineLobby lobby;
  final OnlineMatchSession session;
  final GameEngine engine;
  final OnlineGameSyncClient sync;
  final bool isHost;
  final PlayerColor initialPlayerColor;

  PlayerColor get localColor => session.localColor;
}

/// Converts the current completed Quick Table lobby into a synchronized match.
///
/// The returned [OnlineGameSyncClient] has not been started. The caller can
/// attach its screen/listeners first, then await `result.sync.start()`.
PreparedOnlineQuickTableMatch prepareOnlineQuickTableMatch(
  RealtimeOnlineRoomController controller, {
  Random? engineRandom,
}) {
  final lobby = controller.lobby;
  final room = controller.roomRecord;
  final roomMode = controller.roomMode;
  if (lobby == null || room == null || roomMode == null) {
    throw const OnlineQuickTablePreparationException(
      'The realtime room has not produced a complete lobby snapshot.',
    );
  }
  return prepareOnlineQuickTableMatchFromSnapshot(
    transport: controller.transport,
    localParticipantId: controller.localParticipantId,
    lobby: lobby,
    room: room,
    roomMode: roomMode,
    engineRandom: engineRandom,
  );
}

/// Pure snapshot form used by deterministic tests and reconnect adapters.
PreparedOnlineQuickTableMatch prepareOnlineQuickTableMatchFromSnapshot({
  required OnlineTransportClient transport,
  required String localParticipantId,
  required OnlineLobby lobby,
  required OnlineRoomRecord room,
  required OnlineRoomGameMode roomMode,
  Random? engineRandom,
}) {
  _validateQuickTableSnapshot(
    transport: transport,
    localParticipantId: localParticipantId,
    lobby: lobby,
    room: room,
    roomMode: roomMode,
  );
  OnlineQuickTableService(transport).assertRoom(room);

  final opening = lobby.openingRoll!;
  final winnerId = opening.winnerParticipantId!;
  final winner = lobby.participantById(winnerId);
  final initialPlayerColor = playerColorForLobbySeat(winner.seat);
  final local = lobby.participantById(localParticipantId);
  final localColor = playerColorForLobbySeat(local.seat);
  final mode = roomMode == OnlineRoomGameMode.chaos
      ? GameMode.chaos
      : GameMode.traditional;
  final matchId = 'qt_${room.id}';
  final seed = _stableMatchSeed(
    '$matchId|$winnerId|${opening.clockwiseParticipantIds.join('|')}',
  );
  final participants = <OnlineParticipant>[
    for (final participant in lobby.participants)
      OnlineParticipant(
        id: participant.participantId,
        displayName: participant.displayName,
        flag: '🌎',
        avatarId: 'avatar_default',
        level: 1,
        color: playerColorForLobbySeat(participant.seat),
        kind: participant.participantId == localParticipantId
            ? ParticipantKind.local
            : participant.participantId.startsWith('cpu_')
            ? ParticipantKind.virtual
            : ParticipantKind.remoteHuman,
        loadout: const CosmeticLoadout(),
      ),
  ];
  final session = OnlineMatchSession(
    matchId: matchId,
    seed: seed,
    mode: mode,
    participants: participants,
  );
  final names = <PlayerColor, String>{
    for (final participant in participants)
      participant.color: participant.displayName,
  };
  final engine = GameEngine(
    mode: mode,
    matchFormat: MatchFormat.classic,
    localViewerColor: localColor,
    initialPlayerColor: initialPlayerColor,
    random: engineRandom ?? Random.secure(),
    humanName: local.displayName,
    playerNames: names,
  );
  final isHost = localParticipantId == lobby.hostParticipantId;
  final sync = OnlineGameSyncClient(
    transport: transport,
    roomId: room.id,
    session: session,
    engine: engine,
    isHost: isHost,
  );
  return PreparedOnlineQuickTableMatch(
    room: room,
    lobby: lobby,
    session: session,
    engine: engine,
    sync: sync,
    isHost: isHost,
    initialPlayerColor: initialPlayerColor,
  );
}

PlayerColor playerColorForLobbySeat(LobbySeatColor seat) => switch (seat) {
  LobbySeatColor.red => PlayerColor.red,
  LobbySeatColor.green => PlayerColor.green,
  LobbySeatColor.yellow => PlayerColor.yellow,
  LobbySeatColor.blue => PlayerColor.blue,
};

void _validateQuickTableSnapshot({
  required OnlineTransportClient transport,
  required String localParticipantId,
  required OnlineLobby lobby,
  required OnlineRoomRecord room,
  required OnlineRoomGameMode roomMode,
}) {
  if (transport.identity.uid != localParticipantId) {
    throw const OnlineQuickTablePreparationException(
      'The local lobby identity does not match the authenticated transport.',
    );
  }
  if (lobby.status != RoomStatus.inGame || room.status != RoomStatus.inGame) {
    throw const OnlineQuickTablePreparationException(
      'Quick Table can be prepared only after the lobby enters the game.',
    );
  }
  if (lobby.roomId != room.id ||
      lobby.roomCode != room.code ||
      lobby.hostParticipantId != room.hostUid ||
      lobby.visibility != room.visibility) {
    throw const OnlineQuickTablePreparationException(
      'Room and lobby identity fields are inconsistent.',
    );
  }
  if (room.matchFormat != 'quickTable' || room.mode != roomMode.name) {
    throw const OnlineQuickTablePreparationException(
      'The room is not a matching Quick Table mode.',
    );
  }
  if (lobby.participants.length != PlayerColor.values.length ||
      room.members.length != PlayerColor.values.length) {
    throw const OnlineQuickTablePreparationException(
      'Quick Table must contain four board seats after CPU fill.',
    );
  }

  final lobbyIds = lobby.participants
      .map((participant) => participant.participantId)
      .toSet();
  if (!lobbyIds.contains(localParticipantId) ||
      !lobbyIds.contains(room.hostUid) ||
      lobbyIds.length != PlayerColor.values.length ||
      !lobbyIds.containsAll(room.members.keys) ||
      !room.members.keys.toSet().containsAll(lobbyIds)) {
    throw const OnlineQuickTablePreparationException(
      'Room and lobby participants do not match.',
    );
  }
  for (final participant in lobby.participants) {
    final member = room.members[participant.participantId]!;
    if (member.displayName != participant.displayName ||
        member.seat != participant.seat ||
        member.ready != participant.ready ||
        room.presenceFor(member.uid) != participant.presence) {
      throw OnlineQuickTablePreparationException(
        'Room and lobby disagree about ${participant.participantId}.',
      );
    }
  }

  final opening = lobby.openingRoll;
  if (opening == null ||
      !opening.completed ||
      opening.winnerParticipantId == null ||
      opening.clockwiseParticipantIds.length != PlayerColor.values.length ||
      opening.clockwiseParticipantIds.first != opening.winnerParticipantId ||
      opening.clockwiseParticipantIds.toSet().length !=
          PlayerColor.values.length ||
      !opening.clockwiseParticipantIds.toSet().containsAll(lobbyIds)) {
    throw const OnlineQuickTablePreparationException(
      'The opening roll has no complete winner and play order.',
    );
  }
  final winner = lobby.participantById(opening.winnerParticipantId!);
  final expectedClockwise = <String>[
    for (var offset = 0; offset < LobbySeatColor.values.length; offset++)
      lobby
          .participantForSeat(
            LobbySeatColor.values[(winner.seat.index + offset) %
                LobbySeatColor.values.length],
          )!
          .participantId,
  ];
  for (var index = 0; index < expectedClockwise.length; index++) {
    if (opening.clockwiseParticipantIds[index] != expectedClockwise[index]) {
      throw const OnlineQuickTablePreparationException(
        'The opening-roll play order is not clockwise from its winner.',
      );
    }
  }
}

int _stableMatchSeed(String value) {
  var hash = 0x811c9dc5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}
