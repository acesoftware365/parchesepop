import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/online_v3_game_adapter.dart';
import 'package:parchesepop/online_v3_models.dart';

void main() {
  test('creates the existing Quick Pop board from hostless V3 state', () {
    final state = OnlineV3MatchState.fromJson({
      'roomId': 'qp3_0123456789abcdef01234567',
      'mode': 'traditional',
      'status': 'inGame',
      'revision': 7,
      'currentTurnUid': 'player-b',
      'phase': 'awaitingMove',
      'dice': [3, 4],
      'remainingDice': [4],
      'hasRolled': true,
      'turn': 5,
      'consecutiveDoubles': 0,
      'seats': {
        'player-a': {
          'uid': 'player-a',
          'color': 'red',
          'control': 'human',
          'displayName': 'Ana',
        },
        'player-b': {
          'uid': 'player-b',
          'color': 'green',
          'control': 'human',
          'displayName': 'Beto',
        },
        'cpu-yellow': {
          'uid': 'cpu-yellow',
          'color': 'yellow',
          'control': 'cpu',
          'displayName': 'CPU',
        },
        'cpu-blue': {
          'uid': 'cpu-blue',
          'color': 'blue',
          'control': 'cpu',
          'displayName': 'CPU',
        },
      },
      'pieces': {
        'red': [-1, 12],
        'green': [8, -1],
        'yellow': [-1, -1],
        'blue': [-1, -1],
      },
      'updatedAt': 1,
    });

    final board = OnlineV3GameAdapter.createBoard(
      state: state,
      localUid: 'player-a',
      displayNames: const {'player-a': 'Ana', 'player-b': 'Beto'},
    );

    expect(board.currentPlayer.color.name, 'green');
    expect(board.players[0].name, 'Ana');
    expect(board.players[1].name, 'Beto');
    expect(board.players[0].tokens.map((token) => token.progress), [-1, 12]);
    expect(board.remainingDice, [4]);
  });

  test('maps the server winner to the existing victory board state', () {
    final state = OnlineV3MatchState.fromJson({
      'roomId': 'qp3_0123456789abcdef01234567',
      'mode': 'traditional',
      'status': 'closed',
      'revision': 12,
      'currentTurnUid': 'player-a',
      'phase': 'finished',
      'dice': <int>[],
      'remainingDice': <int>[],
      'hasRolled': false,
      'turn': 9,
      'consecutiveDoubles': 0,
      'winnerUid': 'player-a',
      'seats': {
        'player-a': {'uid': 'player-a', 'color': 'red', 'control': 'human'},
        'cpu-green': {'uid': 'cpu-green', 'color': 'green', 'control': 'cpu'},
        'cpu-yellow': {'uid': 'cpu-yellow', 'color': 'yellow', 'control': 'cpu'},
        'cpu-blue': {'uid': 'cpu-blue', 'color': 'blue', 'control': 'cpu'},
      },
      'pieces': {
        'red': [71, 71], 'green': [-1, -1], 'yellow': [-1, -1], 'blue': [-1, -1],
      },
      'updatedAt': 1,
    });

    final checkpoint = OnlineV3GameAdapter.checkpointFor(
      state: state,
      localUid: 'player-a',
    );
    expect(checkpoint['gameOver'], isTrue);
    expect(checkpoint['winner'], 'red');
    expect(checkpoint['finishOrder'], ['red']);

    final board = OnlineV3GameAdapter.createBoard(
      state: state,
      localUid: 'player-a',
    );
    expect(board.gameOver, isTrue);
    expect(board.winner?.color.name, 'red');
  });
}
