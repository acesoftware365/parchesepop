/// Immutable client view of the server-owned Online V3 game state.
///
/// V3 intentionally does not expose a writable board model. Every change is
/// requested as a command and the server publishes the resulting revision.
final class OnlineV3MatchState {
  const OnlineV3MatchState({
    required this.roomId,
    required this.mode,
    required this.status,
    required this.revision,
    required this.currentTurnUid,
    required this.phase,
    required this.dice,
    required this.remainingDice,
    required this.hasRolled,
    required this.turn,
    required this.consecutiveDoubles,
    required this.seats,
    required this.pieces,
    required this.startAt,
    this.winnerUid,
    required this.updatedAt,
  });

  final String roomId;
  final String mode;
  final String status;
  final int revision;
  final String currentTurnUid;
  final String phase;
  final List<int> dice;
  final List<int> remainingDice;
  final bool hasRolled;
  final int turn;
  final int consecutiveDoubles;
  final Map<String, OnlineV3Seat> seats;
  final Map<String, List<int>> pieces;
  final int startAt;

  /// Present only after the authoritative server closes the match.
  final String? winnerUid;
  final int updatedAt;

  bool isHumanTurn(String uid) =>
      currentTurnUid == uid && seats[uid]?.control == OnlineV3SeatControl.human;

  factory OnlineV3MatchState.fromJson(Map<Object?, Object?> json) {
    final seatsJson = _map(json['seats']);
    final piecesJson = _map(json['pieces']);
    return OnlineV3MatchState(
      roomId: _string(json['roomId'], 'roomId'),
      mode: _string(json['mode'], 'mode'),
      status: _string(json['status'], 'status'),
      revision: _int(json['revision'], 'revision'),
      currentTurnUid: _string(json['currentTurnUid'], 'currentTurnUid'),
      phase: _string(json['phase'], 'phase'),
      // RTDB omits an empty array from the persisted object. At the start of
      // every turn that means "no dice rolled yet", not malformed state.
      dice: _intList(json['dice'] ?? const [], 'dice'),
      remainingDice: _intList(
        json['remainingDice'] ?? const [],
        'remainingDice',
      ),
      hasRolled: json['hasRolled'] is bool ? json['hasRolled'] as bool : false,
      turn: _intOrDefault(json['turn'], 1, 'turn'),
      consecutiveDoubles: _intOrDefault(
        json['consecutiveDoubles'],
        0,
        'consecutiveDoubles',
      ),
      seats: {
        for (final entry in seatsJson.entries)
          entry.key.toString(): OnlineV3Seat.fromJson(_map(entry.value)),
      },
      pieces: {
        for (final entry in piecesJson.entries)
          entry.key.toString(): _intList(entry.value, 'pieces.${entry.key}'),
      },
      startAt: _intOrDefault(
        json['startAt'],
        _int(json['updatedAt'], 'updatedAt'),
        'startAt',
      ),
      winnerUid: json['winnerUid'] is String
          ? json['winnerUid'] as String
          : null,
      updatedAt: _int(json['updatedAt'], 'updatedAt'),
    );
  }
}

enum OnlineV3SeatControl { human, cpu, cpuTemporary }

final class OnlineV3Seat {
  const OnlineV3Seat({
    required this.uid,
    required this.color,
    required this.control,
    required this.displayName,
  });

  final String uid;
  final String color;
  final OnlineV3SeatControl control;
  final String displayName;

  factory OnlineV3Seat.fromJson(Map<Object?, Object?> json) {
    final rawControl = _string(json['control'], 'seat.control');
    return OnlineV3Seat(
      uid: _string(json['uid'], 'seat.uid'),
      color: _string(json['color'], 'seat.color'),
      displayName: _optionalDisplayName(json['displayName']),
      control: switch (rawControl) {
        'human' => OnlineV3SeatControl.human,
        'cpu' => OnlineV3SeatControl.cpu,
        'cpuTemporary' => OnlineV3SeatControl.cpuTemporary,
        _ => throw FormatException(
          'Unknown Online V3 seat control: $rawControl',
        ),
      },
    );
  }
}

String _optionalDisplayName(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : '';

enum OnlineV3QuickPopCommandKind { roll, move, moveAll }

final class OnlineV3CommandResult {
  const OnlineV3CommandResult({required this.code, required this.revision});

  final String code;
  final int revision;

  bool get accepted => code == 'accepted' || code == 'duplicate';

  factory OnlineV3CommandResult.fromJson(Map<Object?, Object?> json) =>
      OnlineV3CommandResult(
        code: _string(json['code'], 'code'),
        revision: _int(json['revision'], 'revision'),
      );
}

final class OnlineV3QuickPopTicket {
  const OnlineV3QuickPopTicket({
    required this.ticketId,
    required this.state,
    required this.roomId,
    required this.launchAt,
    required this.expiresAt,
    required this.lobbyPlayerCount,
    required this.maxPlayers,
  });

  final String ticketId;
  final String state;
  final String? roomId;
  final int launchAt;
  final int expiresAt;
  final int? lobbyPlayerCount;
  final int maxPlayers;

  factory OnlineV3QuickPopTicket.fromJson(Map<Object?, Object?> json) =>
      OnlineV3QuickPopTicket(
        ticketId: _string(json['ticketId'], 'ticketId'),
        state: _string(json['state'], 'state'),
        roomId: json['roomId'] as String?,
        launchAt: _int(json['launchAt'], 'launchAt'),
        expiresAt: _int(json['expiresAt'], 'expiresAt'),
        lobbyPlayerCount: json['lobbyPlayerCount'] is int
            ? json['lobbyPlayerCount'] as int
            : null,
        maxPlayers: _intOrDefault(json['maxPlayers'], 4, 'maxPlayers'),
      );
}

Map<Object?, Object?> _map(Object? value) {
  if (value is Map<Object?, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<Object?, Object?>.from(value);
  }
  throw FormatException('Expected an Online V3 JSON object.');
}

String _string(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Online V3 field $field must be a non-empty string.');
}

int _int(Object? value, String field) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw FormatException('Online V3 field $field must be an integer.');
}

int _intOrDefault(Object? value, int fallback, String field) =>
    value == null ? fallback : _int(value, field);

List<int> _intList(Object? value, String field) {
  if (value is! List) {
    throw FormatException('Online V3 field $field must be a list.');
  }
  return List<int>.unmodifiable(value.map((element) => _int(element, field)));
}
