import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/online_v3_models.dart';

void main() {
  test('parses canonical V3 state without a host field', () {
    final state = OnlineV3MatchState.fromJson({
      'roomId': 'qp3_0123456789abcdef01234567',
      'mode': 'traditional',
      'status': 'inGame',
      'revision': 7,
      'currentTurnUid': 'player-a',
      'phase': 'awaitingRoll',
      'dice': <int>[],
      'seats': {
        'player-a': {'uid': 'player-a', 'color': 'red', 'control': 'human'},
        'cpu-1': {'uid': 'cpu-1', 'color': 'green', 'control': 'cpuTemporary'},
      },
      'pieces': {
        'red': [-1, -1],
        'green': [-1, -1],
        'yellow': [-1, -1],
        'blue': [-1, -1],
      },
      'updatedAt': 1,
    });

    expect(state.isHumanTurn('player-a'), isTrue);
    expect(state.seats['player-a']!.displayName, isEmpty);
    expect(state.isHumanTurn('cpu-1'), isFalse);
    expect(
      state.seats.values.map((seat) => seat.color),
      containsAll(['red', 'green']),
    );
  });

  test('rejects an unknown server-owned seat control', () {
    expect(
      () => OnlineV3Seat.fromJson({
        'uid': 'a',
        'color': 'red',
        'control': 'host',
      }),
      throwsFormatException,
    );
  });

  test('reads the canonical winner only when the server provides one', () {
    final state = OnlineV3MatchState.fromJson({
      'roomId': 'qp3_0123456789abcdef01234567',
      'mode': 'traditional',
      'status': 'closed',
      'revision': 9,
      'currentTurnUid': 'player-a',
      'phase': 'finished',
      'dice': <int>[],
      'remainingDice': <int>[],
      'hasRolled': false,
      'turn': 8,
      'consecutiveDoubles': 0,
      'winnerUid': 'player-a',
      'seats': {
        'player-a': {'uid': 'player-a', 'color': 'red', 'control': 'human'},
      },
      'pieces': {
        'red': [71, 71], 'green': [-1, -1], 'yellow': [-1, -1], 'blue': [-1, -1],
      },
      'updatedAt': 1,
    });

    expect(state.winnerUid, 'player-a');
  });
}
