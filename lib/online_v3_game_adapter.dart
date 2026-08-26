import 'game_engine.dart';
import 'online_v3_models.dart';

/// Turns the server's V3 board state into the existing read-only Flutter board
/// checkpoint format. It does not create moves or timers; commands remain in
/// [OnlineV3QuickPopClient] and are validated by Cloud Functions.
final class OnlineV3GameAdapter {
  const OnlineV3GameAdapter._();

  static GameEngine createBoard({
    required OnlineV3MatchState state,
    required String localUid,
    Map<String, String> displayNames = const {},
  }) {
    final localSeat = state.seats[localUid];
    if (localSeat == null || localSeat.control != OnlineV3SeatControl.human) {
      throw const FormatException(
        'The local user is not a V3 human participant.',
      );
    }
    final checkpoint = checkpointFor(
      state: state,
      localUid: localUid,
      displayNames: displayNames,
    );
    final board = GameEngine.fromCheckpoint(
      checkpoint,
      localViewerColor: _color(localSeat.color),
    );
    // fromCheckpoint restores the stable board. Applying that same canonical
    // snapshot adds remote-only presentation fields such as gameOver and the
    // winner, so a player reopening an already-finished V3 room still gets
    // the existing victory screen.
    board.applyRemoteCheckpoint(checkpoint);
    return board;
  }

  static Map<String, dynamic> checkpointFor({
    required OnlineV3MatchState state,
    required String localUid,
    Map<String, String> displayNames = const {},
  }) {
    final currentSeat = state.seats[state.currentTurnUid];
    if (currentSeat == null) {
      throw const FormatException('V3 state has no current-turn seat.');
    }
    final winnerSeat = state.winnerUid == null
        ? null
        : state.seats[state.winnerUid!];
    return <String, dynamic>{
      'matchFormat': MatchFormat.quickPop.name,
      'rulesVersion': MatchRules.quickPopRulesVersion,
      'mode': state.mode,
      // V3 decides which seat may act. Keeping all board seats interactive
      // prevents the local presentation from trying to run a CPU turn for a
      // remote player; [OnlineV3QuickPopGameController] gates all input.
      'allPlayersHuman': true,
      'initialPlayer': PlayerColor.red.name,
      'currentPlayer': currentSeat.color,
      'turn': state.turn,
      'dice': state.dice.isEmpty ? <int>[1, 1] : state.dice,
      'remainingDice': state.remainingDice,
      'hasRolled': state.hasRolled,
      'consecutiveDoubles': state.consecutiveDoubles,
      'gameOver': state.status == 'closed',
      // The existing victory presentation is driven by the winning board
      // color. V3 owns the winner UID, so resolve it only from its canonical
      // seat map rather than inferring it from a local device.
      'winner': winnerSeat?.color,
      'players': <Map<String, Object?>>[
        for (final color in PlayerColor.values)
          <String, Object?>{
            'color': color.name,
            'name': _nameFor(
              state,
              color.name,
              localUid: localUid,
              displayNames: displayNames,
            ),
            'tokens': state.pieces[color.name] ?? const <int>[-1, -1],
          },
      ],
      'traps': const <Object?>[],
      'items': const <Object?>[],
      'finishOrder': winnerSeat == null
          ? const <Object?>[]
          : <Object?>[winnerSeat.color],
      'events': const <Object?>[],
    };
  }

  static String _nameFor(
    OnlineV3MatchState state,
    String color, {
    required String localUid,
    required Map<String, String> displayNames,
  }) {
    final seat = state.seats.values
        .where((candidate) => candidate.color == color)
        .firstOrNull;
    if (seat == null) return 'CPU';
    if (seat.uid == localUid) {
      return displayNames[seat.uid] ??
          (seat.displayName.isNotEmpty ? seat.displayName : 'Tú');
    }
    if (seat.control != OnlineV3SeatControl.human) return 'CPU';
    return seat.displayName.isNotEmpty
        ? seat.displayName
        : displayNames[seat.uid] ?? 'Jugador';
  }

  static PlayerColor _color(String name) => PlayerColor.values.firstWhere(
    (color) => color.name == name,
    orElse: () => throw FormatException('Unknown V3 board color: $name'),
  );
}
