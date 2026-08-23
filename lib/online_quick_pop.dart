import 'dart:async';

import 'package:crypto/crypto.dart';

import 'game_engine.dart';
import 'online_game_sync.dart';
import 'online_lobby.dart';
import 'online_match.dart';
import 'online_transport.dart';
import 'online_transport_models.dart';

/// A live Quick Pop match. Between two and four humans are admitted during
/// the shared search window; any seats still empty at the deadline are filled
/// by CPU players driven only by the active room host.
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
    required QuickPopQueueTicket ticket,
    required QuickPopResolution resolution,
    GameMode mode = GameMode.traditional,
    Duration hostTimeout = const Duration(seconds: 25),
    Duration pollInterval = const Duration(milliseconds: 150),
  }) async {
    if (resolution.kind != QuickPopResolutionKind.human) {
      throw const OnlineGameSyncException(
        'Quick Pop online requires a human matchmaking result.',
      );
    }
    final localUid = transport.identity.uid;
    final humanUids = <String>{
      if (resolution.participantUids.isNotEmpty)
        ...resolution.participantUids
      else ...<String>[
        localUid,
        if (resolution.opponentUid != null) resolution.opponentUid!,
      ],
    };
    final isGroup = resolution.groupId != null;
    if (humanUids.length < 2 ||
        humanUids.length > LobbySeatColor.values.length ||
        !humanUids.contains(localUid) ||
        ticket.uid != localUid ||
        ticket.ticketId != resolution.ticketId ||
        resolution.queueKey != ticket.queueKey ||
        (isGroup
            ? resolution.groupId == null
            : resolution.claimId == null || resolution.opponentUid == null)) {
      throw const OnlineGameSyncException(
        'A Quick Pop opponent must come from this verified search ticket.',
      );
    }
    if (await transport.isQuickPopLaunchAbandoned(
      ticket: ticket,
      resolution: resolution,
    )) {
      throw const OnlineGameSyncException(
        'The Quick Pop launch was abandoned before room preparation.',
      );
    }
    final orderedHumanUids = humanUids.toList()..sort();
    final hostUid = orderedHumanUids.first;
    final launchMetadata = await transport.quickPopLaunchMetadata(
      ticket: ticket,
      resolution: resolution,
    );
    final now = await transport.store.serverNowMs();
    final roomCode = _roomCodeFor(resolution.roomId);

    if (localUid == hostUid) {
      final names = <String, String>{
        for (final uid in orderedHumanUids)
          uid: uid == localUid
              ? transport.identity.displayName
              : await _verifiedParticipantDisplayName(
                  transport,
                  uid: uid,
                  queueKey: ticket.queueKey,
                  resolution: resolution,
                  launchMetadata: launchMetadata,
                ),
      };
      if (await transport.isQuickPopLaunchAbandoned(
        ticket: ticket,
        resolution: resolution,
      )) {
        throw const OnlineGameSyncException(
          'The Quick Pop launch was abandoned before room creation.',
        );
      }
      final members = <String, OnlineRoomMemberRecord>{};
      final presence = <String, OnlinePresenceRecord>{};
      for (var index = 0; index < LobbySeatColor.values.length; index++) {
        final seat = LobbySeatColor.values[index];
        final humanUid = index < orderedHumanUids.length
            ? orderedHumanUids[index]
            : null;
        final uid = humanUid ?? _cpuUid(resolution.roomId, seat);
        final isCpu = humanUid == null;
        members[uid] = OnlineRoomMemberRecord(
          uid: uid,
          displayName: isCpu
              ? _cpuDisplayName(seat)
              : names[uid] ?? transport.identity.displayName,
          seat: seat,
          joinedAtMs: now,
          ready: true,
        );
        presence[uid] = OnlinePresenceRecord(
          uid: uid,
          presence: isCpu
              ? LobbyPresence.connected
              : LobbyPresence.disconnected,
          changedAtMs: now,
          connectionId: isCpu
              ? 'virtual_${resolution.roomId}'
              : 'quick_${resolution.roomId}_$uid',
        );
      }
      final room = OnlineRoomRecord(
        id: resolution.roomId,
        code: roomCode,
        hostUid: hostUid,
        visibility: RoomVisibility.private,
        status: RoomStatus.starting,
        mode: mode.name,
        matchFormat: MatchFormat.quickPop.name,
        members: members,
        presence: presence,
        revision: 0,
        createdAtMs: now,
        updatedAtMs: now,
      );
      final roomJson = room.toJson()..['quickPopLaunch'] = launchMetadata;
      final creation = await transport.store.transaction(
        '$onlineTransportRoot/rooms/${resolution.roomId}',
        (raw) => raw == null
            ? OnlineStoreTransactionDecision.commit(roomJson)
            : const OnlineStoreTransactionDecision.abort(),
      );
      if (!creation.committed) {
        final existing = OnlineRoomRecord.fromJson(creation.value);
        _validateExistingRoom(existing, hostUid, orderedHumanUids);
      }
    }

    final room = await _waitForRoom(
      transport,
      roomId: resolution.roomId,
      hostUid: hostUid,
      humanUids: orderedHumanUids,
      timeout: hostTimeout,
      pollInterval: pollInterval,
      isAbandoned: () => transport.isQuickPopLaunchAbandoned(
        ticket: ticket,
        resolution: resolution,
      ),
    );
    await _validateLaunchMetadata(
      transport,
      roomId: room.id,
      expected: launchMetadata,
    );
    if (await transport.isQuickPopLaunchAbandoned(
      ticket: ticket,
      resolution: resolution,
    )) {
      throw const OnlineGameSyncException(
        'The Quick Pop launch was abandoned during room preparation.',
      );
    }
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

  static Future<String> _verifiedParticipantDisplayName(
    OnlineTransportClient transport, {
    required String uid,
    required String queueKey,
    required QuickPopResolution resolution,
    required Map<String, Object?> launchMetadata,
  }) async {
    final members = onlineMap(launchMetadata['members']);
    final member = onlineMap(members[uid]);
    final expectedTicketId = member['ticketId'] is String
        ? member['ticketId'] as String
        : launchMetadata['firstUid'] == uid
        ? launchMetadata['firstTicketId']
        : launchMetadata['secondUid'] == uid
        ? launchMetadata['secondTicketId']
        : null;
    if (expectedTicketId is! String || expectedTicketId.isEmpty) {
      throw const OnlineGameSyncException(
        'A Quick Pop player is missing from the verified launch group.',
      );
    }
    if (resolution.groupId != null) {
      // The group protocol admits between two and `LobbySeatColor.values.length`
      // humans (currently four, but this scales to any future seat count
      // without changes here). Unlike the legacy pair claim, there is no
      // exact-record read grant for a group peer's own queue ticket, so an
      // extra cross read would always be denied by the security rules.
      // Instead trust this member snapshot: the security rules require the
      // group writer to prove ownership of a 'waiting' ticket with a matching
      // ticketId *and* displayName at write time, so the group record is
      // already an authoritative mirror of that player's ticket.
      final memberUid = member['uid'];
      final memberTicketId = member['ticketId'];
      final displayName = member['displayName'];
      if (memberUid == uid &&
          memberTicketId == expectedTicketId &&
          displayName is String &&
          displayName.isNotEmpty) {
        return displayName;
      }
      throw const OnlineGameSyncException(
        'The Quick Pop player ticket does not match the verified launch.',
      );
    }
    final raw = await transport.store.read(
      '$onlineTransportRoot/quickQueues/$queueKey/$uid',
    );
    try {
      final player = QuickPopQueueTicket.fromJson(raw, uid: uid);
      final ticketMatches =
          player.ticketId == expectedTicketId &&
          player.queueKey == queueKey &&
          player.claimId == resolution.claimId;
      final expectedDisplayName = member['displayName'];
      if (ticketMatches &&
          (expectedDisplayName is! String ||
              player.displayName == expectedDisplayName)) {
        return player.displayName;
      }
    } on FormatException {
      // Fall through to the generic verification error below.
    }
    throw const OnlineGameSyncException(
      'The Quick Pop player ticket does not match the verified launch.',
    );
  }

  static Future<OnlineRoomRecord> _waitForRoom(
    OnlineTransportClient transport, {
    required String roomId,
    required String hostUid,
    required List<String> humanUids,
    required Duration timeout,
    required Duration pollInterval,
    required Future<bool> Function() isAbandoned,
  }) async {
    final startedAt = await transport.store.serverNowMs();
    final expiresAt = startedAt + timeout.inMilliseconds;
    while (true) {
      final room = await transport.readRoom(roomId);
      if (room != null) {
        _validateExistingRoom(room, hostUid, humanUids);
        return room;
      }
      if (await isAbandoned()) {
        throw const OnlineGameSyncException(
          'The Quick Pop launch was cancelled before the room was ready.',
        );
      }
      final now = await transport.store.serverNowMs();
      if (now >= expiresAt) {
        throw OnlineGameSyncException(
          'El anfitrión no pudo preparar la partida Quick Pop ($roomId).',
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
        (room.status != RoomStatus.starting &&
            room.status != RoomStatus.inGame) ||
        room.matchFormat != MatchFormat.quickPop.name ||
        !humanUids.every(room.members.containsKey) ||
        room.members.length != PlayerColor.values.length) {
      throw const OnlineGameSyncException(
        'La sala Quick Pop compartida no coincide con el emparejamiento.',
      );
    }
  }

  static Future<void> _validateLaunchMetadata(
    OnlineTransportClient transport, {
    required String roomId,
    required Map<String, Object?> expected,
  }) async {
    final raw = onlineMap(
      await transport.store.read('$onlineTransportRoot/rooms/$roomId'),
    );
    final launch = onlineMap(raw['quickPopLaunch']);
    if (expected.entries.any(
      (entry) => !_wireValueEqual(launch[entry.key], entry.value),
    )) {
      throw const OnlineGameSyncException(
        'La sala Quick Pop no contiene el acuerdo de inicio esperado.',
      );
    }
  }

  static bool _wireValueEqual(Object? left, Object? right) {
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final key in left.keys) {
        if (!right.containsKey(key) ||
            !_wireValueEqual(left[key], right[key])) {
          return false;
        }
      }
      return true;
    }
    if (left is List && right is List) {
      return left.length == right.length &&
          List<bool>.generate(
            left.length,
            (index) => _wireValueEqual(left[index], right[index]),
          ).every((value) => value);
    }
    return left == right;
  }

  static String _cpuUid(String roomId, LobbySeatColor seat) =>
      'cpu_${seat.name}_${sha256.convert(roomId.codeUnits).toString().substring(0, 12)}';

  static String _cpuDisplayName(LobbySeatColor seat) => switch (seat) {
    LobbySeatColor.red => 'CPU Rojo',
    LobbySeatColor.green => 'CPU Verde',
    LobbySeatColor.yellow => 'CPU Rayo',
    LobbySeatColor.blue => 'CPU Pop',
  };

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
