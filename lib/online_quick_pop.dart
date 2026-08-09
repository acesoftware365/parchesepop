import 'dart:async';

import 'package:crypto/crypto.dart';

import 'game_engine.dart';
import 'online_game_sync.dart';
import 'online_lobby.dart';
import 'online_match.dart';
import 'online_transport.dart';
import 'online_transport_models.dart';

/// A live two-human Quick Pop match. The two remaining clockwise seats are
/// filled by CPU players and are driven only by the active room host.
final class OnlineQuickPopPreparedMatch {
  const OnlineQuickPopPreparedMatch({
    required this.room,
    required this.session,
    required this.engine,
    required this.sync,
  });

  final OnlineRoomRecord room;
  final OnlineMatchSession session;
  final GameEngine engine;
  final OnlineGameSyncClient sync;
}

/// Turns a successful Quick Pop claim into the shared room consumed by the
/// live game synchronizer.
///
/// Both devices derive the same host, colors, room code, CPU identities and
/// seed. Only the deterministic host creates the room; the other device waits
/// for that exact room instead of creating a competing authority.
final class OnlineQuickPopBootstrap {
  const OnlineQuickPopBootstrap._();

  static Future<OnlineQuickPopPreparedMatch> prepare({
    required OnlineTransportClient transport,
    required QuickPopResolution resolution,
    GameMode mode = GameMode.traditional,
    Duration hostTimeout = const Duration(seconds: 12),
    Duration pollInterval = const Duration(milliseconds: 150),
  }) async {
    if (resolution.kind != QuickPopResolutionKind.human ||
        resolution.opponentUid == null) {
      throw const OnlineGameSyncException(
        'Quick Pop online requires a human matchmaking result.',
      );
    }
    final localUid = transport.identity.uid;
    final opponentUid = resolution.opponentUid!;
    if (opponentUid == localUid) {
      throw const OnlineGameSyncException(
        'A Quick Pop opponent must be another player.',
      );
    }
    final humanUids = <String>[localUid, opponentUid]..sort();
    final hostUid = humanUids.first;
    final guestUid = humanUids.last;
    final now = await transport.store.serverNowMs();
    final roomCode = _roomCodeFor(resolution.roomId);

    if (localUid == hostUid) {
      final hostName = await _displayNameFor(transport, hostUid);
      final guestName = await _displayNameFor(transport, guestUid);
      final room = OnlineRoomRecord(
        id: resolution.roomId,
        code: roomCode,
        hostUid: hostUid,
        visibility: RoomVisibility.private,
        status: RoomStatus.inGame,
        mode: mode.name,
        matchFormat: MatchFormat.quickPop.name,
        members: <String, OnlineRoomMemberRecord>{
          hostUid: OnlineRoomMemberRecord(
            uid: hostUid,
            displayName: hostName,
            seat: LobbySeatColor.red,
            joinedAtMs: now,
            ready: true,
          ),
          guestUid: OnlineRoomMemberRecord(
            uid: guestUid,
            displayName: guestName,
            seat: LobbySeatColor.green,
            joinedAtMs: now,
            ready: true,
          ),
          _cpuUid(
            resolution.roomId,
            LobbySeatColor.yellow,
          ): OnlineRoomMemberRecord(
            uid: _cpuUid(resolution.roomId, LobbySeatColor.yellow),
            displayName: 'CPU Rayo',
            seat: LobbySeatColor.yellow,
            joinedAtMs: now,
            ready: true,
          ),
          _cpuUid(
            resolution.roomId,
            LobbySeatColor.blue,
          ): OnlineRoomMemberRecord(
            uid: _cpuUid(resolution.roomId, LobbySeatColor.blue),
            displayName: 'CPU Pop',
            seat: LobbySeatColor.blue,
            joinedAtMs: now,
            ready: true,
          ),
        },
        presence: <String, OnlinePresenceRecord>{
          for (final uid in <String>[
            hostUid,
            guestUid,
            _cpuUid(resolution.roomId, LobbySeatColor.yellow),
            _cpuUid(resolution.roomId, LobbySeatColor.blue),
          ])
            uid: OnlinePresenceRecord(
              uid: uid,
              presence: uid.startsWith('cpu_')
                  ? LobbyPresence.connected
                  : LobbyPresence.disconnected,
              changedAtMs: now,
              connectionId: uid.startsWith('cpu_')
                  ? 'virtual_${resolution.roomId}'
                  : 'quick_${resolution.roomId}_$uid',
            ),
        },
        revision: 0,
        createdAtMs: now,
        updatedAtMs: now,
      );
      final creation = await transport.store.transaction(
        '$onlineTransportRoot/rooms/${resolution.roomId}',
        (raw) => raw == null
            ? OnlineStoreTransactionDecision.commit(room.toJson())
            : const OnlineStoreTransactionDecision.abort(),
      );
      if (!creation.committed) {
        final existing = OnlineRoomRecord.fromJson(creation.value);
        _validateExistingRoom(existing, hostUid, humanUids);
      }
    }

    final room = await _waitForRoom(
      transport,
      roomId: resolution.roomId,
      hostUid: hostUid,
      humanUids: humanUids,
      timeout: hostTimeout,
      pollInterval: pollInterval,
    );
    final localMember = room.members[localUid]!;
    final participants = <OnlineParticipant>[
      for (final member in room.members.values)
        OnlineParticipant(
          id: member.uid,
          displayName: member.displayName,
          flag: member.uid.startsWith('cpu_') ? '🤖' : '🎮',
          avatarId: member.uid.startsWith('cpu_')
              ? 'avatar_robot'
              : 'avatar_default',
          level: 1,
          color: _playerColor(member.seat),
          kind: member.uid == localUid
              ? ParticipantKind.local
              : member.uid.startsWith('cpu_')
              ? ParticipantKind.virtual
              : ParticipantKind.remoteHuman,
          loadout: const CosmeticLoadout(),
        ),
    ];
    final session = OnlineMatchSession(
      matchId: room.id,
      seed: _seedFor(room.id),
      mode: mode,
      participants: participants,
    );
    final playerNames = <PlayerColor, String>{
      for (final participant in session.participants)
        participant.color: participant.displayName,
    };
    final engine = GameEngine(
      mode: mode,
      matchFormat: MatchFormat.quickPop,
      localViewerColor: _playerColor(localMember.seat),
      initialPlayerColor: PlayerColor.red,
      humanName: localMember.displayName,
      playerNames: playerNames,
    );
    final sync = OnlineGameSyncClient(
      transport: transport,
      roomId: room.id,
      session: session,
      engine: engine,
      isHost: localUid == hostUid,
    );
    return OnlineQuickPopPreparedMatch(
      room: room,
      session: session,
      engine: engine,
      sync: sync,
    );
  }

  static Future<String> _displayNameFor(
    OnlineTransportClient transport,
    String uid,
  ) async {
    if (uid == transport.identity.uid) return transport.identity.displayName;
    final raw = await transport.store.read(
      '$onlineTransportRoot/profiles/$uid',
    );
    if (raw != null) {
      try {
        return SyncedOnlineProfile.fromJson(raw, uid: uid).displayName;
      } on FormatException {
        // Fall through to the friendly non-identifying label.
      }
    }
    return 'Jugador online';
  }

  static Future<OnlineRoomRecord> _waitForRoom(
    OnlineTransportClient transport, {
    required String roomId,
    required String hostUid,
    required List<String> humanUids,
    required Duration timeout,
    required Duration pollInterval,
  }) async {
    final startedAt = await transport.store.serverNowMs();
    final expiresAt = startedAt + timeout.inMilliseconds;
    while (true) {
      final room = await transport.readRoom(roomId);
      if (room != null) {
        _validateExistingRoom(room, hostUid, humanUids);
        return room;
      }
      final now = await transport.store.serverNowMs();
      if (now >= expiresAt) {
        throw const OnlineGameSyncException(
          'El anfitrión no pudo preparar la partida Quick Pop.',
        );
      }
      await Future<void>.delayed(
        Duration(
          milliseconds: (expiresAt - now).clamp(1, pollInterval.inMilliseconds),
        ),
      );
    }
  }

  static void _validateExistingRoom(
    OnlineRoomRecord room,
    String hostUid,
    List<String> humanUids,
  ) {
    if (room.hostUid != hostUid ||
        room.status != RoomStatus.inGame ||
        room.matchFormat != MatchFormat.quickPop.name ||
        !humanUids.every(room.members.containsKey) ||
        room.members.length != PlayerColor.values.length) {
      throw const OnlineGameSyncException(
        'La sala Quick Pop compartida no coincide con el emparejamiento.',
      );
    }
  }

  static String _cpuUid(String roomId, LobbySeatColor seat) =>
      'cpu_${seat.name}_${sha256.convert(roomId.codeUnits).toString().substring(0, 12)}';

  static RoomCode _roomCodeFor(String roomId) {
    final digest = sha256.convert(roomId.codeUnits).bytes;
    final code = String.fromCharCodes(
      List<int>.generate(RoomCode.length, (index) {
        final char =
            RoomCode.alphabet[digest[index] % RoomCode.alphabet.length];
        return char.codeUnitAt(0);
      }),
    );
    return RoomCode.parse(code);
  }

  static int _seedFor(String roomId) {
    final hex = sha256.convert(roomId.codeUnits).toString().substring(0, 8);
    return int.parse(hex, radix: 16) & 0x7fffffff;
  }

  static PlayerColor _playerColor(LobbySeatColor seat) => switch (seat) {
    LobbySeatColor.red => PlayerColor.red,
    LobbySeatColor.green => PlayerColor.green,
    LobbySeatColor.yellow => PlayerColor.yellow,
    LobbySeatColor.blue => PlayerColor.blue,
  };
}
