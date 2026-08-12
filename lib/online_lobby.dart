import 'dart:collection';
import 'dart:math';

/// Visibility of a lobby while it is accepting players.
enum RoomVisibility { public, private }

/// Server-owned lifecycle for a two-to-four-player room.
enum RoomStatus { waiting, openingRoll, starting, inGame, closed }

/// Stable clockwise seats used by the lobby and opening-roll order.
enum LobbySeatColor { red, green, yellow, blue }

/// Whether a participant currently has a live connection to the room.
enum LobbyPresence { connected, disconnected }

/// Quick Table always has four board colors, but a room may start with only
/// two or three humans. The remaining seats are represented by deterministic
/// CPU participants once the host starts the opening roll.
const int minimumOnlinePlayers = 2;

String cpuParticipantIdForSeat(RoomCode roomCode, LobbySeatColor seat) =>
    'cpu_${roomCode.value}_${seat.name}';

String cpuDisplayNameForSeat(LobbySeatColor seat) => switch (seat) {
  LobbySeatColor.red => 'CPU Rojo',
  LobbySeatColor.green => 'CPU Verde',
  LobbySeatColor.yellow => 'CPU Amarillo',
  LobbySeatColor.blue => 'CPU Azul',
};

enum LobbyErrorCode {
  invalidRoomCode,
  invalidParticipant,
  duplicateParticipant,
  roomFull,
  roomNotJoinable,
  seatOccupied,
  unknownParticipant,
  notHost,
  hostCannotBeKicked,
  invalidStatus,
  notEnoughPlayers,
  participantsNotReady,
  participantsDisconnected,
  openingRollUnavailable,
  participantNotEligible,
  participantAlreadyRolled,
}

class LobbyException implements Exception {
  const LobbyException(this.code, this.message);

  final LobbyErrorCode code;
  final String message;

  @override
  String toString() => 'LobbyException(${code.name}): $message';
}

class LobbyJsonException implements FormatException {
  const LobbyJsonException(this.message, [this.source, this.offset]);

  @override
  final String message;

  @override
  final dynamic source;

  @override
  final int? offset;

  @override
  String toString() => 'LobbyJsonException: $message';
}

/// Six-character room code that avoids visually ambiguous characters.
final class RoomCode {
  RoomCode._(this.value);

  static const int length = 6;
  static const String alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  final String value;

  factory RoomCode.parse(String raw) {
    final normalized = normalize(raw);
    if (!isValid(normalized)) {
      throw LobbyException(
        LobbyErrorCode.invalidRoomCode,
        'Room codes must contain six unambiguous letters or numbers.',
      );
    }
    return RoomCode._(normalized);
  }

  factory RoomCode.generate(Random random) {
    final buffer = StringBuffer();
    for (var index = 0; index < length; index++) {
      buffer.write(alphabet[random.nextInt(alphabet.length)]);
    }
    return RoomCode._(buffer.toString());
  }

  /// Makes pasted codes forgiving without accepting ambiguous characters.
  static String normalize(String raw) =>
      raw.trim().toUpperCase().replaceAll(RegExp(r'[\s-]'), '');

  static bool isValid(String raw) {
    final normalized = normalize(raw);
    if (normalized.length != length) return false;
    return normalized.codeUnits.every(
      (codeUnit) => alphabet.contains(String.fromCharCode(codeUnit)),
    );
  }

  @override
  bool operator ==(Object other) => other is RoomCode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

class LobbyParticipant {
  const LobbyParticipant({
    required this.participantId,
    required this.displayName,
    required this.seat,
    this.ready = false,
    this.presence = LobbyPresence.connected,
  });

  final String participantId;
  final String displayName;
  final LobbySeatColor seat;
  final bool ready;
  final LobbyPresence presence;

  bool get connected => presence == LobbyPresence.connected;

  LobbyParticipant copyWith({
    String? participantId,
    String? displayName,
    LobbySeatColor? seat,
    bool? ready,
    LobbyPresence? presence,
  }) => LobbyParticipant(
    participantId: participantId ?? this.participantId,
    displayName: displayName ?? this.displayName,
    seat: seat ?? this.seat,
    ready: ready ?? this.ready,
    presence: presence ?? this.presence,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'participantId': participantId,
    'displayName': displayName,
    'seat': seat.name,
    'ready': ready,
    'presence': presence.name,
  };

  factory LobbyParticipant.fromJson(Map<String, Object?> json) {
    final participantId = _requiredCleanString(
      json,
      'participantId',
      'participant.participantId',
    );
    final displayName = _requiredCleanString(
      json,
      'displayName',
      'participant.displayName',
    );
    return LobbyParticipant(
      participantId: participantId,
      displayName: displayName,
      seat: _requiredEnum(
        json,
        'seat',
        LobbySeatColor.values,
        'participant.seat',
      ),
      ready: _requiredBool(json, 'ready', 'participant.ready'),
      presence: _requiredEnum(
        json,
        'presence',
        LobbyPresence.values,
        'participant.presence',
      ),
    );
  }
}

class OpeningRollRound {
  OpeningRollRound({
    required this.round,
    required Iterable<String> eligibleParticipantIds,
    required Map<String, int> rolls,
  }) : eligibleParticipantIds = UnmodifiableListView(
         List<String>.of(eligibleParticipantIds),
       ),
       rolls = UnmodifiableMapView(Map<String, int>.of(rolls));

  final int round;
  final List<String> eligibleParticipantIds;
  final Map<String, int> rolls;

  Map<String, Object?> toJson() => <String, Object?>{
    'round': round,
    'eligibleParticipantIds': List<String>.of(eligibleParticipantIds),
    'rolls': Map<String, int>.of(rolls),
  };

  factory OpeningRollRound.fromJson(Map<String, Object?> json) {
    final round = _requiredPositiveInt(
      json,
      'round',
      'openingRoll.history.round',
    );
    final eligible = _requiredStringList(
      json,
      'eligibleParticipantIds',
      'openingRoll.history.eligibleParticipantIds',
    );
    _requireUniqueStrings(
      eligible,
      'openingRoll.history.eligibleParticipantIds',
    );
    final rolls = _requiredRollMap(json, 'rolls', 'openingRoll.history.rolls');
    if (!_sameStringSet(eligible, rolls.keys)) {
      throw const LobbyJsonException(
        'Every eligible opening-roll participant must have exactly one roll.',
      );
    }
    return OpeningRollRound(
      round: round,
      eligibleParticipantIds: eligible,
      rolls: rolls,
    );
  }
}

/// Server-side opening roll. Clients ask to roll but never provide a value.
///
/// Only participants tied for the highest value enter the next round. Once a
/// winner exists, normal play continues clockwise from that participant's
/// fixed seat rather than being sorted by the remaining die values.
class OpeningRollState {
  OpeningRollState._({required Map<String, LobbySeatColor> seatByParticipantId})
    : _seatByParticipantId = Map<String, LobbySeatColor>.of(
        seatByParticipantId,
      ),
      _eligibleParticipantIds = _sortBySeat(
        seatByParticipantId.keys,
        seatByParticipantId,
      );

  factory OpeningRollState.start(Iterable<LobbyParticipant> participants) {
    final playerList = List<LobbyParticipant>.of(participants);
    final seats = <LobbySeatColor>{};
    final seatByParticipantId = <String, LobbySeatColor>{};
    for (final participant in playerList) {
      if (!seats.add(participant.seat) ||
          seatByParticipantId.containsKey(participant.participantId)) {
        throw const LobbyException(
          LobbyErrorCode.invalidParticipant,
          'Opening-roll participants must have unique IDs and seats.',
        );
      }
      seatByParticipantId[participant.participantId] = participant.seat;
    }
    if (seatByParticipantId.length < minimumOnlinePlayers ||
        seatByParticipantId.length > LobbySeatColor.values.length) {
      throw const LobbyException(
        LobbyErrorCode.notEnoughPlayers,
        'The opening roll requires at least two participants.',
      );
    }
    return OpeningRollState._(seatByParticipantId: seatByParticipantId);
  }

  factory OpeningRollState.fromJson(
    Map<String, Object?> json, {
    required Iterable<LobbyParticipant> participants,
  }) {
    final playerList = List<LobbyParticipant>.of(participants);
    final expectedSeats = <String, LobbySeatColor>{
      for (final participant in playerList)
        participant.participantId: participant.seat,
    };
    if (expectedSeats.length < minimumOnlinePlayers ||
        expectedSeats.length > LobbySeatColor.values.length) {
      throw const LobbyJsonException(
        'An opening roll requires between two and four unique participants.',
      );
    }

    final serializedSeats = _requiredStringMap(
      json,
      'seatByParticipantId',
      'openingRoll.seatByParticipantId',
    );
    if (!_sameStringSet(serializedSeats.keys, expectedSeats.keys)) {
      throw const LobbyJsonException(
        'Opening-roll seats must match the room participants.',
      );
    }
    for (final entry in serializedSeats.entries) {
      final serializedSeat = _enumFromName(
        entry.value,
        LobbySeatColor.values,
        'openingRoll.seatByParticipantId.${entry.key}',
      );
      if (expectedSeats[entry.key] != serializedSeat) {
        throw LobbyJsonException(
          'Opening-roll seat for ${entry.key} does not match the lobby.',
        );
      }
    }

    final round = _requiredPositiveInt(json, 'round', 'openingRoll.round');
    final eligible = _requiredStringList(
      json,
      'eligibleParticipantIds',
      'openingRoll.eligibleParticipantIds',
    );
    _requireUniqueStrings(eligible, 'openingRoll.eligibleParticipantIds');
    final currentRolls = _requiredRollMap(
      json,
      'currentRolls',
      'openingRoll.currentRolls',
    );
    final rawHistory = _requiredList(json, 'history', 'openingRoll.history');
    final history = <OpeningRollRound>[
      for (var index = 0; index < rawHistory.length; index++)
        OpeningRollRound.fromJson(
          _asStringMap(rawHistory[index], 'openingRoll.history[$index]'),
        ),
    ];
    final winner = _requiredNullableCleanString(
      json,
      'winnerParticipantId',
      'openingRoll.winnerParticipantId',
    );
    final clockwise = _requiredStringList(
      json,
      'clockwiseParticipantIds',
      'openingRoll.clockwiseParticipantIds',
    );
    _requireUniqueStrings(clockwise, 'openingRoll.clockwiseParticipantIds');

    final restored = OpeningRollState._(seatByParticipantId: expectedSeats);
    restored
      .._round = round
      .._eligibleParticipantIds = List<String>.of(eligible)
      .._currentRolls = Map<String, int>.of(currentRolls)
      .._winnerParticipantId = winner
      .._clockwiseParticipantIds = List<String>.of(clockwise)
      .._history.addAll(history);
    restored._validateRestoredState();
    return restored;
  }

  final Map<String, LobbySeatColor> _seatByParticipantId;
  final List<OpeningRollRound> _history = [];
  Map<String, int> _currentRolls = {};
  late List<String> _eligibleParticipantIds;
  List<String> _clockwiseParticipantIds = const [];
  String? _winnerParticipantId;
  int _round = 1;

  int get round => _round;
  bool get completed => _winnerParticipantId != null;
  String? get winnerParticipantId => _winnerParticipantId;
  List<String> get eligibleParticipantIds =>
      UnmodifiableListView(_eligibleParticipantIds);
  Map<String, int> get currentRolls => UnmodifiableMapView(_currentRolls);
  List<OpeningRollRound> get history => UnmodifiableListView(_history);
  List<String> get clockwiseParticipantIds =>
      UnmodifiableListView(_clockwiseParticipantIds);

  Map<String, Object?> toJson() => <String, Object?>{
    'round': _round,
    'seatByParticipantId': <String, String>{
      for (final entry in _seatByParticipantId.entries)
        entry.key: entry.value.name,
    },
    'eligibleParticipantIds': List<String>.of(_eligibleParticipantIds),
    'currentRolls': Map<String, int>.of(_currentRolls),
    'history': [for (final completedRound in _history) completedRound.toJson()],
    'winnerParticipantId': _winnerParticipantId,
    'clockwiseParticipantIds': List<String>.of(_clockwiseParticipantIds),
  };

  int roll(String participantId, Random random) {
    if (completed) {
      throw const LobbyException(
        LobbyErrorCode.invalidStatus,
        'The opening roll is already complete.',
      );
    }
    if (!_eligibleParticipantIds.contains(participantId)) {
      throw LobbyException(
        LobbyErrorCode.participantNotEligible,
        '$participantId is not eligible in opening-roll round $_round.',
      );
    }
    if (_currentRolls.containsKey(participantId)) {
      throw LobbyException(
        LobbyErrorCode.participantAlreadyRolled,
        '$participantId already rolled in opening-roll round $_round.',
      );
    }

    final value = random.nextInt(6) + 1;
    _currentRolls[participantId] = value;
    if (_currentRolls.length == _eligibleParticipantIds.length) {
      _resolveRound();
    }
    return value;
  }

  void _resolveRound() {
    final completedRound = OpeningRollRound(
      round: _round,
      eligibleParticipantIds: _eligibleParticipantIds,
      rolls: _currentRolls,
    );
    _history.add(completedRound);

    final highest = _currentRolls.values.reduce(max);
    final highestParticipants = _sortBySeat(
      _currentRolls.entries
          .where((entry) => entry.value == highest)
          .map((entry) => entry.key),
      _seatByParticipantId,
    );

    if (highestParticipants.length == 1) {
      _winnerParticipantId = highestParticipants.single;
      _clockwiseParticipantIds = _clockwiseOrderFrom(_winnerParticipantId!);
      return;
    }

    _round++;
    _eligibleParticipantIds = highestParticipants;
    _currentRolls = {};
  }

  List<String> _clockwiseOrderFrom(String winnerParticipantId) {
    final winnerSeat = _seatByParticipantId[winnerParticipantId]!;
    final winnerIndex = LobbySeatColor.values.indexOf(winnerSeat);
    final participantBySeat = <LobbySeatColor, String>{
      for (final entry in _seatByParticipantId.entries) entry.value: entry.key,
    };
    final order = <String>[];
    for (
      var offset = 0;
      offset < LobbySeatColor.values.length &&
          order.length < _seatByParticipantId.length;
      offset++
    ) {
      final seat = LobbySeatColor
          .values[(winnerIndex + offset) % LobbySeatColor.values.length];
      final participant = participantBySeat[seat];
      if (participant != null) order.add(participant);
    }
    return order;
  }

  static List<String> _sortBySeat(
    Iterable<String> participantIds,
    Map<String, LobbySeatColor> seatByParticipantId,
  ) => List<String>.of(participantIds)
    ..sort(
      (left, right) => seatByParticipantId[left]!.index.compareTo(
        seatByParticipantId[right]!.index,
      ),
    );

  void _validateRestoredState() {
    final allParticipants = _sortBySeat(
      _seatByParticipantId.keys,
      _seatByParticipantId,
    );
    if (_eligibleParticipantIds.isEmpty) {
      throw const LobbyJsonException(
        'Opening-roll eligibility cannot be empty.',
      );
    }
    if (!_eligibleParticipantIds.every(_seatByParticipantId.containsKey)) {
      throw const LobbyJsonException(
        'Opening-roll eligibility contains an unknown participant.',
      );
    }
    if (!_isCanonicalSeatOrder(_eligibleParticipantIds)) {
      throw const LobbyJsonException(
        'Opening-roll eligibility must be unique and ordered by seat.',
      );
    }
    if (!_currentRolls.keys.every(_eligibleParticipantIds.contains)) {
      throw const LobbyJsonException(
        'Current opening rolls contain an ineligible participant.',
      );
    }

    var expectedEligible = allParticipants;
    String? resolvedWinner;
    for (var index = 0; index < _history.length; index++) {
      final completedRound = _history[index];
      if (completedRound.round != index + 1 ||
          !_sameStringList(
            completedRound.eligibleParticipantIds,
            expectedEligible,
          )) {
        throw const LobbyJsonException(
          'Opening-roll history does not follow its previous tie.',
        );
      }
      final highest = completedRound.rolls.values.reduce(max);
      final highestParticipants = _sortBySeat(
        completedRound.rolls.entries
            .where((entry) => entry.value == highest)
            .map((entry) => entry.key),
        _seatByParticipantId,
      );
      if (highestParticipants.length == 1) {
        if (index != _history.length - 1) {
          throw const LobbyJsonException(
            'Opening-roll history continues after a winner was decided.',
          );
        }
        resolvedWinner = highestParticipants.single;
      } else {
        expectedEligible = highestParticipants;
      }
    }

    if (_winnerParticipantId == null) {
      if (resolvedWinner != null || _clockwiseParticipantIds.isNotEmpty) {
        throw const LobbyJsonException(
          'An incomplete opening roll cannot contain a winner or play order.',
        );
      }
      if (_round != _history.length + 1 ||
          !_sameStringList(_eligibleParticipantIds, expectedEligible) ||
          _currentRolls.length >= _eligibleParticipantIds.length) {
        throw const LobbyJsonException(
          'Incomplete opening-roll state is inconsistent with its history.',
        );
      }
      return;
    }

    if (resolvedWinner == null || resolvedWinner != _winnerParticipantId) {
      throw const LobbyJsonException(
        'Opening-roll winner does not match the final completed round.',
      );
    }
    final finalRound = _history.last;
    final expectedClockwise = _clockwiseOrderFrom(_winnerParticipantId!);
    if (_round != finalRound.round ||
        !_sameStringList(
          _eligibleParticipantIds,
          finalRound.eligibleParticipantIds,
        ) ||
        !_sameIntMap(_currentRolls, finalRound.rolls) ||
        !_sameStringList(_clockwiseParticipantIds, expectedClockwise)) {
      throw const LobbyJsonException(
        'Completed opening-roll state does not match its final round.',
      );
    }
  }

  bool _isCanonicalSeatOrder(List<String> participantIds) =>
      _sameStringList(
        participantIds,
        _sortBySeat(participantIds, _seatByParticipantId),
      ) &&
      participantIds.toSet().length == participantIds.length;
}

/// Pure-Dart aggregate for a two-to-four-player online lobby.
///
/// Authentication and transport are deliberately outside this type. A trusted
/// backend must derive [actorParticipantId] from the authenticated connection
/// before invoking host- or participant-owned commands.
class OnlineLobby {
  static const int jsonSchemaVersion = 1;

  OnlineLobby._({
    required this.roomId,
    required this.roomCode,
    required this.hostParticipantId,
    required this.visibility,
    required this.roomName,
    required LobbyParticipant host,
  }) : _participantsById = {host.participantId: host};

  OnlineLobby._restored({
    required this.roomId,
    required this.roomCode,
    required this.hostParticipantId,
    required this.visibility,
    required this.roomName,
    required this.status,
    required this.revision,
    required Map<String, LobbyParticipant> participantsById,
    required OpeningRollState? openingRoll,
  }) : _participantsById = Map<String, LobbyParticipant>.of(participantsById),
       _openingRoll = openingRoll;

  factory OnlineLobby.create({
    required String roomId,
    required RoomCode roomCode,
    required String hostParticipantId,
    required String hostDisplayName,
    RoomVisibility visibility = RoomVisibility.private,
    String? roomName,
  }) {
    _validateIdentity(hostParticipantId, hostDisplayName);
    if (roomId.trim().isEmpty) {
      throw const LobbyException(
        LobbyErrorCode.invalidParticipant,
        'A room ID is required.',
      );
    }
    return OnlineLobby._(
      roomId: roomId.trim(),
      roomCode: roomCode,
      hostParticipantId: hostParticipantId.trim(),
      visibility: visibility,
      roomName: _optionalCleanRoomName(roomName),
      host: LobbyParticipant(
        participantId: hostParticipantId.trim(),
        displayName: hostDisplayName.trim(),
        seat: LobbySeatColor.red,
      ),
    );
  }

  factory OnlineLobby.fromJson(Map<String, Object?> json) {
    final schemaVersion = _requiredPositiveInt(
      json,
      'schemaVersion',
      'lobby.schemaVersion',
    );
    if (schemaVersion != jsonSchemaVersion) {
      throw LobbyJsonException(
        'Unsupported lobby JSON schema version $schemaVersion.',
      );
    }
    final roomId = _requiredCleanString(json, 'roomId', 'lobby.roomId');
    final rawRoomCode = _requiredCleanString(
      json,
      'roomCode',
      'lobby.roomCode',
    );
    if (!RoomCode.isValid(rawRoomCode)) {
      throw const LobbyJsonException('lobby.roomCode is invalid.');
    }
    final roomCode = RoomCode.parse(rawRoomCode);
    final hostParticipantId = _requiredCleanString(
      json,
      'hostParticipantId',
      'lobby.hostParticipantId',
    );
    final visibility = _requiredEnum(
      json,
      'visibility',
      RoomVisibility.values,
      'lobby.visibility',
    );
    final roomName = _optionalCleanRoomName(json['roomName']);
    final status = _requiredEnum(
      json,
      'status',
      RoomStatus.values,
      'lobby.status',
    );
    final revision = _requiredNonNegativeInt(
      json,
      'revision',
      'lobby.revision',
    );
    final rawParticipants = _requiredList(
      json,
      'participants',
      'lobby.participants',
    );
    if (rawParticipants.isEmpty ||
        rawParticipants.length > fixedClockwiseSeats.length) {
      throw const LobbyJsonException(
        'A lobby must contain between one and four participants.',
      );
    }

    final participantsById = <String, LobbyParticipant>{};
    final occupiedSeats = <LobbySeatColor>{};
    for (var index = 0; index < rawParticipants.length; index++) {
      final participant = LobbyParticipant.fromJson(
        _asStringMap(rawParticipants[index], 'lobby.participants[$index]'),
      );
      if (participantsById.containsKey(participant.participantId)) {
        throw LobbyJsonException(
          'Duplicate lobby participant ${participant.participantId}.',
        );
      }
      if (!occupiedSeats.add(participant.seat)) {
        throw LobbyJsonException(
          'Duplicate lobby seat ${participant.seat.name}.',
        );
      }
      if (!participant.connected && participant.ready) {
        throw LobbyJsonException(
          'Disconnected participant ${participant.participantId} cannot be ready.',
        );
      }
      participantsById[participant.participantId] = participant;
    }

    final host = participantsById[hostParticipantId];
    if (host == null) {
      throw const LobbyJsonException(
        'The lobby host must be one of its participants.',
      );
    }
    if (host.seat != LobbySeatColor.red) {
      throw const LobbyJsonException(
        'The lobby host must occupy the fixed red seat.',
      );
    }

    // Realtime Database removes keys whose value is null. A waiting lobby is
    // serialized with `openingRoll: null`, so a real Firebase round-trip
    // legitimately restores the document without that child.
    final rawOpeningRoll = json['openingRoll'];
    final openingRoll = rawOpeningRoll == null
        ? null
        : OpeningRollState.fromJson(
            _asStringMap(rawOpeningRoll, 'lobby.openingRoll'),
            participants: participantsById.values,
          );
    _validateStatusSnapshot(status, openingRoll);

    // Construct only after every nested value and cross-field invariant has
    // been validated, so a malformed snapshot cannot produce a partial lobby.
    return OnlineLobby._restored(
      roomId: roomId,
      roomCode: roomCode,
      hostParticipantId: hostParticipantId,
      visibility: visibility,
      roomName: roomName,
      status: status,
      revision: revision,
      participantsById: participantsById,
      openingRoll: openingRoll,
    );
  }

  static const List<LobbySeatColor> fixedClockwiseSeats = LobbySeatColor.values;

  final String roomId;
  final RoomCode roomCode;
  final String hostParticipantId;
  final String? roomName;
  final Map<String, LobbyParticipant> _participantsById;
  RoomVisibility visibility;
  RoomStatus status = RoomStatus.waiting;
  int revision = 0;
  OpeningRollState? _openingRoll;

  List<LobbyParticipant> get participants {
    final sorted = List<LobbyParticipant>.of(_participantsById.values)
      ..sort((left, right) => left.seat.index.compareTo(right.seat.index));
    return UnmodifiableListView(sorted);
  }

  OpeningRollState? get openingRoll => _openingRoll;
  int get occupiedSeatCount => _participantsById.length;
  bool get isFull => occupiedSeatCount == fixedClockwiseSeats.length;
  bool get hasMinimumPlayers => occupiedSeatCount >= minimumOnlinePlayers;
  bool get allReady =>
      hasMinimumPlayers &&
      _participantsById.values.every((participant) => participant.ready);
  bool get allConnected =>
      hasMinimumPlayers &&
      _participantsById.values.every((participant) => participant.connected);
  bool get canStart => status == RoomStatus.waiting && allReady && allConnected;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': jsonSchemaVersion,
    'roomId': roomId,
    'roomCode': roomCode.value,
    'hostParticipantId': hostParticipantId,
    'visibility': visibility.name,
    if (roomName != null) 'roomName': roomName,
    'status': status.name,
    'revision': revision,
    'participants': [
      for (final participant in participants) participant.toJson(),
    ],
    'openingRoll': _openingRoll?.toJson(),
  };

  LobbyParticipant? participantForSeat(LobbySeatColor seat) {
    for (final participant in _participantsById.values) {
      if (participant.seat == seat) return participant;
    }
    return null;
  }

  LobbyParticipant participantById(String participantId) {
    final participant = _participantsById[participantId];
    if (participant == null) {
      throw LobbyException(
        LobbyErrorCode.unknownParticipant,
        '$participantId is not a member of room $roomId.',
      );
    }
    return participant;
  }

  LobbyParticipant join({
    required String participantId,
    required String displayName,
    LobbySeatColor? preferredSeat,
  }) {
    _requireWaiting();
    _validateIdentity(participantId, displayName);
    final cleanId = participantId.trim();
    if (_participantsById.containsKey(cleanId)) {
      throw LobbyException(
        LobbyErrorCode.duplicateParticipant,
        '$cleanId already belongs to this room.',
      );
    }
    if (isFull) {
      throw const LobbyException(
        LobbyErrorCode.roomFull,
        'All four seats are occupied.',
      );
    }

    final occupiedSeats = _participantsById.values
        .map((participant) => participant.seat)
        .toSet();
    if (preferredSeat != null && occupiedSeats.contains(preferredSeat)) {
      throw LobbyException(
        LobbyErrorCode.seatOccupied,
        'The ${preferredSeat.name} seat is already occupied.',
      );
    }
    final seat =
        preferredSeat ??
        fixedClockwiseSeats.firstWhere(
          (candidate) => !occupiedSeats.contains(candidate),
        );
    final participant = LobbyParticipant(
      participantId: cleanId,
      displayName: displayName.trim(),
      seat: seat,
    );
    _participantsById[cleanId] = participant;
    revision++;
    return participant;
  }

  void setReady({required String actorParticipantId, required bool ready}) {
    _requireWaiting();
    final participant = participantById(actorParticipantId);
    if (!participant.connected && ready) {
      throw const LobbyException(
        LobbyErrorCode.participantsDisconnected,
        'A disconnected participant cannot become ready.',
      );
    }
    if (participant.ready == ready) return;
    _participantsById[actorParticipantId] = participant.copyWith(ready: ready);
    revision++;
  }

  /// Presence is server-observed, not a client-authorized lobby command.
  void setPresence({
    required String participantId,
    required LobbyPresence presence,
  }) {
    final participant = participantById(participantId);
    if (participant.presence == presence) return;
    _participantsById[participantId] = participant.copyWith(
      presence: presence,
      ready: presence == LobbyPresence.disconnected ? false : participant.ready,
    );
    revision++;
  }

  void changeVisibility({
    required String actorParticipantId,
    required RoomVisibility visibility,
  }) {
    _requireHost(actorParticipantId);
    _requireWaiting();
    if (this.visibility == visibility) return;
    this.visibility = visibility;
    revision++;
  }

  LobbyParticipant kick({
    required String actorParticipantId,
    required String targetParticipantId,
  }) {
    _requireHost(actorParticipantId);
    _requireWaiting();
    if (targetParticipantId == hostParticipantId) {
      throw const LobbyException(
        LobbyErrorCode.hostCannotBeKicked,
        'The host must close the room instead of kicking itself.',
      );
    }
    final target = participantById(targetParticipantId);
    _participantsById.remove(targetParticipantId);
    revision++;
    return target;
  }

  OpeningRollState startOpeningRoll({required String actorParticipantId}) {
    _requireHost(actorParticipantId);
    _requireWaiting();
    if (!hasMinimumPlayers) {
      throw const LobbyException(
        LobbyErrorCode.notEnoughPlayers,
        'At least two seats must be occupied before the opening roll.',
      );
    }
    // A Quick Table always uses the four board colors. If the room has only
    // two or three humans, fill the remaining colors with deterministic CPU
    // seats before selecting the opening-roll order.
    fillMissingSeatsWithCpu();
    if (!allConnected) {
      throw const LobbyException(
        LobbyErrorCode.participantsDisconnected,
        'All participants must be connected before the opening roll.',
      );
    }
    if (!allReady) {
      throw const LobbyException(
        LobbyErrorCode.participantsNotReady,
        'All participants must be ready before the opening roll.',
      );
    }
    _openingRoll = OpeningRollState.start(participants);
    status = RoomStatus.openingRoll;
    revision++;
    return _openingRoll!;
  }

  /// Adds ready CPU participants for any unoccupied board colors.
  ///
  /// This is intentionally host-side lobby state. Guests still see the room
  /// as 2/4 or 3/4 while waiting; the CPU seats appear when the host starts.
  void fillMissingSeatsWithCpu() {
    _requireWaiting();
    final occupiedSeats = _participantsById.values
        .map((participant) => participant.seat)
        .toSet();
    for (final seat in fixedClockwiseSeats) {
      if (occupiedSeats.contains(seat)) continue;
      final participantId = cpuParticipantIdForSeat(roomCode, seat);
      _participantsById[participantId] = LobbyParticipant(
        participantId: participantId,
        displayName: cpuDisplayNameForSeat(seat),
        seat: seat,
        ready: true,
        presence: LobbyPresence.connected,
      );
      occupiedSeats.add(seat);
    }
    revision++;
  }

  int rollOpeningDie({
    required String actorParticipantId,
    required Random random,
  }) {
    if (status != RoomStatus.openingRoll || _openingRoll == null) {
      throw const LobbyException(
        LobbyErrorCode.openingRollUnavailable,
        'This room is not accepting opening rolls.',
      );
    }
    participantById(actorParticipantId);
    final value = _openingRoll!.roll(actorParticipantId, random);
    if (_openingRoll!.completed) status = RoomStatus.starting;
    revision++;
    return value;
  }

  void markGameStarted({required String actorParticipantId}) {
    _requireHost(actorParticipantId);
    if (status != RoomStatus.starting ||
        _openingRoll?.winnerParticipantId == null) {
      throw const LobbyException(
        LobbyErrorCode.invalidStatus,
        'The game can start only after the opening roll has a winner.',
      );
    }
    status = RoomStatus.inGame;
    revision++;
  }

  void close({required String actorParticipantId}) {
    _requireHost(actorParticipantId);
    if (status == RoomStatus.inGame) {
      throw const LobbyException(
        LobbyErrorCode.invalidStatus,
        'An active match must finish or be forfeited through match rules.',
      );
    }
    if (status == RoomStatus.closed) return;
    status = RoomStatus.closed;
    revision++;
  }

  void _requireHost(String actorParticipantId) {
    participantById(actorParticipantId);
    if (actorParticipantId != hostParticipantId) {
      throw const LobbyException(
        LobbyErrorCode.notHost,
        'Only the room host can perform this action.',
      );
    }
  }

  void _requireWaiting() {
    if (status == RoomStatus.closed) {
      throw const LobbyException(
        LobbyErrorCode.roomNotJoinable,
        'The room is closed.',
      );
    }
    if (status != RoomStatus.waiting) {
      throw LobbyException(
        LobbyErrorCode.invalidStatus,
        'This action requires a waiting room, not ${status.name}.',
      );
    }
  }

  static void _validateIdentity(String participantId, String displayName) {
    if (participantId.trim().isEmpty || displayName.trim().isEmpty) {
      throw const LobbyException(
        LobbyErrorCode.invalidParticipant,
        'Participant ID and display name are required.',
      );
    }
  }

  static void _validateStatusSnapshot(
    RoomStatus status,
    OpeningRollState? openingRoll,
  ) {
    switch (status) {
      case RoomStatus.waiting:
        if (openingRoll != null) {
          throw const LobbyJsonException(
            'A waiting lobby cannot contain an opening roll.',
          );
        }
      case RoomStatus.openingRoll:
        if (openingRoll == null || openingRoll.completed) {
          throw const LobbyJsonException(
            'An opening-roll lobby requires an unresolved opening roll.',
          );
        }
      case RoomStatus.starting:
      case RoomStatus.inGame:
        if (openingRoll == null || !openingRoll.completed) {
          throw const LobbyJsonException(
            'A starting or active lobby requires a resolved opening roll.',
          );
        }
      case RoomStatus.closed:
        break;
    }
  }
}

Map<String, Object?> _asStringMap(Object? value, String path) {
  if (value is! Map) {
    throw LobbyJsonException('$path must be a JSON object.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw LobbyJsonException('$path contains a non-string key.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

List<Object?> _requiredList(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final value = json[key];
  if (value is! List) throw LobbyJsonException('$path must be a JSON array.');
  return List<Object?>.of(value);
}

String _requiredCleanString(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final value = json[key];
  if (value is! String || value.isEmpty || value.trim() != value) {
    throw LobbyJsonException('$path must be a non-empty trimmed string.');
  }
  return value;
}

String? _requiredNullableCleanString(
  Map<String, Object?> json,
  String key,
  String path,
) {
  if (!json.containsKey(key)) {
    throw LobbyJsonException('$path is required.');
  }
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.isEmpty || value.trim() != value) {
    throw LobbyJsonException(
      '$path must be null or a non-empty trimmed string.',
    );
  }
  return value;
}

String? _optionalCleanRoomName(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw const LobbyJsonException('lobby.roomName must be a string.');
  }
  final clean = value.trim();
  if (clean.isEmpty || clean.length > 28) {
    throw const LobbyJsonException(
      'lobby.roomName must contain between 1 and 28 characters.',
    );
  }
  return clean;
}

bool _requiredBool(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! bool) throw LobbyJsonException('$path must be a boolean.');
  return value;
}

int _requiredPositiveInt(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int || value <= 0) {
    throw LobbyJsonException('$path must be a positive integer.');
  }
  return value;
}

int _requiredNonNegativeInt(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final value = json[key];
  if (value is! int || value < 0) {
    throw LobbyJsonException('$path must be a non-negative integer.');
  }
  return value;
}

T _requiredEnum<T extends Enum>(
  Map<String, Object?> json,
  String key,
  Iterable<T> values,
  String path,
) => _enumFromName(json[key], values, path);

T _enumFromName<T extends Enum>(
  Object? value,
  Iterable<T> values,
  String path,
) {
  if (value is! String) throw LobbyJsonException('$path must be a string.');
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  throw LobbyJsonException('$path has unsupported value "$value".');
}

List<String> _requiredStringList(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final raw = _requiredList(json, key, path);
  final result = <String>[];
  for (var index = 0; index < raw.length; index++) {
    final value = raw[index];
    if (value is! String || value.isEmpty || value.trim() != value) {
      throw LobbyJsonException('$path[$index] must be a trimmed string.');
    }
    result.add(value);
  }
  return result;
}

Map<String, String> _requiredStringMap(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final raw = _asStringMap(json[key], path);
  final result = <String, String>{};
  for (final entry in raw.entries) {
    if (entry.key.isEmpty || entry.key.trim() != entry.key) {
      throw LobbyJsonException('$path contains an invalid participant ID.');
    }
    final value = entry.value;
    if (value is! String || value.isEmpty) {
      throw LobbyJsonException('$path.${entry.key} must be a string.');
    }
    result[entry.key] = value;
  }
  return result;
}

Map<String, int> _requiredRollMap(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final raw = _asStringMap(json[key], path);
  final result = <String, int>{};
  for (final entry in raw.entries) {
    if (entry.key.isEmpty || entry.key.trim() != entry.key) {
      throw LobbyJsonException('$path contains an invalid participant ID.');
    }
    final value = entry.value;
    if (value is! int || value < 1 || value > 6) {
      throw LobbyJsonException('$path.${entry.key} must be a die value 1–6.');
    }
    result[entry.key] = value;
  }
  return result;
}

void _requireUniqueStrings(Iterable<String> values, String path) {
  final list = List<String>.of(values);
  if (list.toSet().length != list.length) {
    throw LobbyJsonException('$path contains duplicate participant IDs.');
  }
}

bool _sameStringList(Iterable<String> left, Iterable<String> right) {
  final leftList = List<String>.of(left);
  final rightList = List<String>.of(right);
  if (leftList.length != rightList.length) return false;
  for (var index = 0; index < leftList.length; index++) {
    if (leftList[index] != rightList[index]) return false;
  }
  return true;
}

bool _sameStringSet(Iterable<String> left, Iterable<String> right) {
  final leftSet = Set<String>.of(left);
  final rightSet = Set<String>.of(right);
  return leftSet.length == rightSet.length && leftSet.containsAll(rightSet);
}

bool _sameIntMap(Map<String, int> left, Map<String, int> right) {
  if (!_sameStringSet(left.keys, right.keys)) return false;
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) return false;
  }
  return true;
}
