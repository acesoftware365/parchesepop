import 'dart:collection';

import 'online_lobby.dart';

const String onlineTransportRoot = 'onlineV2';
const Duration quickPopSearchWindow = Duration(seconds: 5);

Map<String, Object?> onlineMap(Object? value) {
  if (value is! Map) return <String, Object?>{};
  return <String, Object?>{
    for (final entry in value.entries)
      entry.key.toString(): onlineValue(entry.value),
  };
}

Object? onlineValue(Object? value) {
  if (value is Map) return onlineMap(value);
  if (value is List) return value.map(onlineValue).toList(growable: false);
  return value;
}

String _requiredString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  throw FormatException('Missing or invalid $key.');
}

String? _optionalString(Map<String, Object?> map, String key) {
  final value = map[key];
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

int _requiredInt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is num) return value.toInt();
  throw FormatException('Missing or invalid $key.');
}

int? _optionalInt(Map<String, Object?> map, String key) {
  final value = map[key];
  return value is num ? value.toInt() : null;
}

bool _bool(Map<String, Object?> map, String key, {bool fallback = false}) {
  final value = map[key];
  return value is bool ? value : fallback;
}

T _enumValue<T extends Enum>(Iterable<T> values, Object? raw, T fallback) {
  if (raw is! String) return fallback;
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return fallback;
}

final class SyncedOnlineProfile {
  const SyncedOnlineProfile({
    required this.uid,
    required this.displayName,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.avatarId,
  });

  final String uid;
  final String displayName;
  final String? avatarId;
  final int createdAtMs;
  final int updatedAtMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'uid': uid,
    'displayName': displayName,
    if (avatarId != null) 'avatarId': avatarId,
    'createdAt': createdAtMs,
    'updatedAt': updatedAtMs,
  };

  factory SyncedOnlineProfile.fromJson(Object? raw, {String? uid}) {
    final map = onlineMap(raw);
    return SyncedOnlineProfile(
      uid: uid ?? _requiredString(map, 'uid'),
      displayName: _requiredString(map, 'displayName'),
      avatarId: _optionalString(map, 'avatarId'),
      createdAtMs:
          _optionalInt(map, 'createdAt') ?? _requiredInt(map, 'updatedAt'),
      updatedAtMs: _requiredInt(map, 'updatedAt'),
    );
  }
}

final class OnlineRoomMemberRecord {
  const OnlineRoomMemberRecord({
    required this.uid,
    required this.displayName,
    required this.seat,
    required this.joinedAtMs,
    this.ready = false,
  });

  final String uid;
  final String displayName;
  final LobbySeatColor seat;
  final int joinedAtMs;
  final bool ready;

  LobbyParticipant toLobbyParticipant({
    LobbyPresence presence = LobbyPresence.connected,
  }) => LobbyParticipant(
    participantId: uid,
    displayName: displayName,
    seat: seat,
    ready: ready,
    presence: presence,
  );

  OnlineRoomMemberRecord copyWith({bool? ready}) => OnlineRoomMemberRecord(
    uid: uid,
    displayName: displayName,
    seat: seat,
    joinedAtMs: joinedAtMs,
    ready: ready ?? this.ready,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'uid': uid,
    'displayName': displayName,
    'seat': seat.name,
    'ready': ready,
    'joinedAt': joinedAtMs,
  };

  factory OnlineRoomMemberRecord.fromJson(Object? raw, {String? uid}) {
    final map = onlineMap(raw);
    return OnlineRoomMemberRecord(
      uid: uid ?? _requiredString(map, 'uid'),
      displayName: _requiredString(map, 'displayName'),
      seat: _enumValue(LobbySeatColor.values, map['seat'], LobbySeatColor.red),
      ready: _bool(map, 'ready'),
      joinedAtMs: _requiredInt(map, 'joinedAt'),
    );
  }
}

final class OnlinePresenceRecord {
  const OnlinePresenceRecord({
    required this.uid,
    required this.presence,
    required this.changedAtMs,
    required this.connectionId,
  });

  final String uid;
  final LobbyPresence presence;
  final int changedAtMs;
  final String connectionId;

  Map<String, Object?> toJson() => <String, Object?>{
    'uid': uid,
    'state': presence.name,
    'changedAt': changedAtMs,
    'connectionId': connectionId,
  };

  factory OnlinePresenceRecord.fromJson(Object? raw, {String? uid}) {
    final map = onlineMap(raw);
    return OnlinePresenceRecord(
      uid: uid ?? _requiredString(map, 'uid'),
      presence: _enumValue(
        LobbyPresence.values,
        map['state'],
        LobbyPresence.disconnected,
      ),
      changedAtMs: _requiredInt(map, 'changedAt'),
      connectionId: _requiredString(map, 'connectionId'),
    );
  }
}

final class OnlineRoomRecord {
  OnlineRoomRecord({
    required this.id,
    required this.code,
    required this.hostUid,
    required this.visibility,
    required this.status,
    required this.mode,
    required this.matchFormat,
    required Map<String, OnlineRoomMemberRecord> members,
    required Map<String, OnlinePresenceRecord> presence,
    required this.revision,
    required this.createdAtMs,
    required this.updatedAtMs,
  }) : members = UnmodifiableMapView(Map.of(members)),
       presence = UnmodifiableMapView(Map.of(presence));

  final String id;
  final RoomCode code;
  final String hostUid;
  final RoomVisibility visibility;
  final RoomStatus status;
  final String mode;
  final String matchFormat;
  final Map<String, OnlineRoomMemberRecord> members;
  final Map<String, OnlinePresenceRecord> presence;
  final int revision;
  final int createdAtMs;
  final int updatedAtMs;

  int get occupiedSeatCount => members.length;
  bool get isJoinable => status == RoomStatus.waiting && members.length < 4;
  bool get isPublic => visibility == RoomVisibility.public;

  LobbyPresence presenceFor(String uid) =>
      presence[uid]?.presence ?? LobbyPresence.disconnected;

  List<LobbyParticipant> get lobbyParticipants {
    final participants = members.values
        .map(
          (member) =>
              member.toLobbyParticipant(presence: presenceFor(member.uid)),
        )
        .toList(growable: false);
    participants.sort(
      (left, right) => left.seat.index.compareTo(right.seat.index),
    );
    return participants;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code.value,
    'hostUid': hostUid,
    'visibility': visibility.name,
    'status': status.name,
    'mode': mode,
    'matchFormat': matchFormat,
    'members': <String, Object?>{
      for (final entry in members.entries) entry.key: entry.value.toJson(),
    },
    'presence': <String, Object?>{
      for (final entry in presence.entries) entry.key: entry.value.toJson(),
    },
    'revision': revision,
    'createdAt': createdAtMs,
    'updatedAt': updatedAtMs,
  };

  factory OnlineRoomRecord.fromJson(Object? raw) {
    final map = onlineMap(raw);
    final membersRaw = onlineMap(map['members']);
    final presenceRaw = onlineMap(map['presence']);
    return OnlineRoomRecord(
      id: _requiredString(map, 'id'),
      code: RoomCode.parse(_requiredString(map, 'code')),
      hostUid: _requiredString(map, 'hostUid'),
      visibility: _enumValue(
        RoomVisibility.values,
        map['visibility'],
        RoomVisibility.private,
      ),
      status: _enumValue(RoomStatus.values, map['status'], RoomStatus.waiting),
      mode: _requiredString(map, 'mode'),
      matchFormat: _requiredString(map, 'matchFormat'),
      members: <String, OnlineRoomMemberRecord>{
        for (final entry in membersRaw.entries)
          entry.key: OnlineRoomMemberRecord.fromJson(
            entry.value,
            uid: entry.key,
          ),
      },
      presence: <String, OnlinePresenceRecord>{
        for (final entry in presenceRaw.entries)
          entry.key: OnlinePresenceRecord.fromJson(entry.value, uid: entry.key),
      },
      revision: _requiredInt(map, 'revision'),
      createdAtMs: _requiredInt(map, 'createdAt'),
      updatedAtMs: _requiredInt(map, 'updatedAt'),
    );
  }
}

final class PublicOnlineRoomRecord {
  const PublicOnlineRoomRecord({
    required this.roomId,
    required this.code,
    required this.hostUid,
    required this.hostDisplayName,
    required this.mode,
    required this.matchFormat,
    required this.occupiedSeatCount,
    required this.updatedAtMs,
  });

  final String roomId;
  final RoomCode code;
  final String hostUid;
  final String hostDisplayName;
  final String mode;
  final String matchFormat;
  final int occupiedSeatCount;
  final int updatedAtMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'roomId': roomId,
    'code': code.value,
    'hostUid': hostUid,
    'hostDisplayName': hostDisplayName,
    'mode': mode,
    'matchFormat': matchFormat,
    'occupiedSeats': occupiedSeatCount,
    'updatedAt': updatedAtMs,
  };

  factory PublicOnlineRoomRecord.fromJson(Object? raw) {
    final map = onlineMap(raw);
    return PublicOnlineRoomRecord(
      roomId: _requiredString(map, 'roomId'),
      code: RoomCode.parse(_requiredString(map, 'code')),
      hostUid: _requiredString(map, 'hostUid'),
      hostDisplayName: _requiredString(map, 'hostDisplayName'),
      mode: _requiredString(map, 'mode'),
      matchFormat: _requiredString(map, 'matchFormat'),
      occupiedSeatCount: _requiredInt(map, 'occupiedSeats'),
      updatedAtMs: _requiredInt(map, 'updatedAt'),
    );
  }

  factory PublicOnlineRoomRecord.fromRoom(OnlineRoomRecord room) {
    final host = room.members[room.hostUid];
    if (host == null) throw const FormatException('Room host is not a member.');
    return PublicOnlineRoomRecord(
      roomId: room.id,
      code: room.code,
      hostUid: room.hostUid,
      hostDisplayName: host.displayName,
      mode: room.mode,
      matchFormat: room.matchFormat,
      occupiedSeatCount: room.occupiedSeatCount,
      updatedAtMs: room.updatedAtMs,
    );
  }
}

final class OnlineRoomJoinRequestRecord {
  const OnlineRoomJoinRequestRecord({
    required this.roomId,
    required this.roomCode,
    required this.uid,
    required this.displayName,
    required this.requestedAtMs,
  });

  final String roomId;
  final RoomCode roomCode;
  final String uid;
  final String displayName;
  final int requestedAtMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'roomId': roomId,
    'roomCode': roomCode.value,
    'uid': uid,
    'displayName': displayName,
    'requestedAt': requestedAtMs,
  };

  factory OnlineRoomJoinRequestRecord.fromJson(Object? raw, {String? uid}) {
    final map = onlineMap(raw);
    return OnlineRoomJoinRequestRecord(
      roomId: _requiredString(map, 'roomId'),
      roomCode: RoomCode.parse(_requiredString(map, 'roomCode')),
      uid: uid ?? _requiredString(map, 'uid'),
      displayName: _requiredString(map, 'displayName'),
      requestedAtMs: _requiredInt(map, 'requestedAt'),
    );
  }
}

enum QuickPopTicketState { waiting, matched, cpuFallback, cancelled }

enum QuickPopResolutionKind { human, cpu }

final class QuickPopQueueTicket {
  const QuickPopQueueTicket({
    required this.ticketId,
    required this.uid,
    required this.displayName,
    required this.queueKey,
    required this.joinedAtMs,
    required this.deadlineAtMs,
    this.state = QuickPopTicketState.waiting,
    this.claimId,
    this.roomId,
    this.opponentUid,
  });

  final String ticketId;
  final String uid;
  final String displayName;
  final String queueKey;
  final int joinedAtMs;
  final int deadlineAtMs;
  final QuickPopTicketState state;
  final String? claimId;
  final String? roomId;
  final String? opponentUid;

  bool get resolved =>
      state == QuickPopTicketState.matched ||
      state == QuickPopTicketState.cpuFallback;

  Map<String, Object?> toJson() => <String, Object?>{
    'ticketId': ticketId,
    'uid': uid,
    'displayName': displayName,
    'queueKey': queueKey,
    'joinedAt': joinedAtMs,
    'deadlineAt': deadlineAtMs,
    'state': state.name,
    if (claimId != null) 'claimId': claimId,
    if (roomId != null) 'roomId': roomId,
    if (opponentUid != null) 'opponentUid': opponentUid,
  };

  factory QuickPopQueueTicket.fromJson(Object? raw, {String? uid}) {
    final map = onlineMap(raw);
    return QuickPopQueueTicket(
      ticketId: _requiredString(map, 'ticketId'),
      uid: uid ?? _requiredString(map, 'uid'),
      displayName: _requiredString(map, 'displayName'),
      queueKey: _requiredString(map, 'queueKey'),
      joinedAtMs: _requiredInt(map, 'joinedAt'),
      deadlineAtMs: _requiredInt(map, 'deadlineAt'),
      state: _enumValue(
        QuickPopTicketState.values,
        map['state'],
        QuickPopTicketState.waiting,
      ),
      claimId: _optionalString(map, 'claimId'),
      roomId: _optionalString(map, 'roomId'),
      opponentUid: _optionalString(map, 'opponentUid'),
    );
  }
}

final class QuickPopResolution {
  const QuickPopResolution({
    required this.ticketId,
    required this.roomId,
    required this.kind,
    required this.resolvedAtMs,
    this.opponentUid,
  });

  final String ticketId;
  final String roomId;
  final QuickPopResolutionKind kind;
  final int resolvedAtMs;
  final String? opponentUid;
}

final class QuickPopClaimAcceptance {
  const QuickPopClaimAcceptance({
    required this.uid,
    required this.ticketId,
    required this.opponentUid,
    required this.opponentTicketId,
    required this.acceptedAtMs,
  });

  final String uid;
  final String ticketId;
  final String opponentUid;
  final String opponentTicketId;
  final int acceptedAtMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'uid': uid,
    'ticketId': ticketId,
    'opponentUid': opponentUid,
    'opponentTicketId': opponentTicketId,
    'acceptedAt': acceptedAtMs,
  };

  factory QuickPopClaimAcceptance.fromJson(Object? raw, {String? uid}) {
    final map = onlineMap(raw);
    return QuickPopClaimAcceptance(
      uid: uid ?? _requiredString(map, 'uid'),
      ticketId: _requiredString(map, 'ticketId'),
      opponentUid: _requiredString(map, 'opponentUid'),
      opponentTicketId: _requiredString(map, 'opponentTicketId'),
      acceptedAtMs: _requiredInt(map, 'acceptedAt'),
    );
  }
}

final class QuickPopClaimResolution {
  const QuickPopClaimResolution({
    required this.kind,
    required this.roomId,
    required this.resolvedAtMs,
    this.firstUid,
    this.secondUid,
  });

  final QuickPopResolutionKind kind;
  final String roomId;
  final int resolvedAtMs;
  final String? firstUid;
  final String? secondUid;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'roomId': roomId,
    'resolvedAt': resolvedAtMs,
    if (firstUid != null) 'firstUid': firstUid,
    if (secondUid != null) 'secondUid': secondUid,
  };

  factory QuickPopClaimResolution.fromJson(Object? raw) {
    final map = onlineMap(raw);
    return QuickPopClaimResolution(
      kind: _enumValue(
        QuickPopResolutionKind.values,
        map['kind'],
        QuickPopResolutionKind.cpu,
      ),
      roomId: _requiredString(map, 'roomId'),
      resolvedAtMs: _requiredInt(map, 'resolvedAt'),
      firstUid: _optionalString(map, 'firstUid'),
      secondUid: _optionalString(map, 'secondUid'),
    );
  }
}
