import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/online_spectator.dart';

void main() {
  test('continue watching appears only online with remaining players', () {
    final standings = OnlineStandingsTracker<PlayerColor>(
      competitors: PlayerColor.values,
    );

    expect(standings.availableActions(isOnline: true), [
      OnlinePostGameAction.playAgain,
      OnlinePostGameAction.home,
    ]);

    expect(standings.recordFinish(PlayerColor.red), isTrue);
    expect(standings.recordFinish(PlayerColor.red), isFalse);
    expect(standings.placementFor(PlayerColor.red), 1);
    expect(standings.availableActions(isOnline: true), [
      OnlinePostGameAction.continueWatching,
      OnlinePostGameAction.playAgain,
      OnlinePostGameAction.home,
    ]);
    expect(standings.availableActions(isOnline: false), [
      OnlinePostGameAction.playAgain,
      OnlinePostGameAction.home,
    ]);
  });

  test('standings preserve order and remove continue after fourth place', () {
    final standings = OnlineStandingsTracker<PlayerColor>(
      competitors: PlayerColor.values,
    );
    for (final color in [
      PlayerColor.yellow,
      PlayerColor.red,
      PlayerColor.blue,
      PlayerColor.green,
    ]) {
      standings.recordFinish(color);
    }

    expect(standings.finishOrder, [
      PlayerColor.yellow,
      PlayerColor.red,
      PlayerColor.blue,
      PlayerColor.green,
    ]);
    expect(standings.placementFor(PlayerColor.blue), 3);
    expect(standings.pointsFor(PlayerColor.yellow), 100);
    expect(standings.pointsFor(PlayerColor.red), 60);
    expect(standings.pointsFor(PlayerColor.blue), 30);
    expect(standings.pointsFor(PlayerColor.green), 10);
    expect(
      standings.standings
          .map(
            (standing) =>
                (standing.competitor, standing.placement, standing.points),
          )
          .toList(),
      [
        (PlayerColor.yellow, 1, 100),
        (PlayerColor.red, 2, 60),
        (PlayerColor.blue, 3, 30),
        (PlayerColor.green, 4, 10),
      ],
    );
    expect(standings.isComplete, isTrue);
    expect(standings.remainingPlayers, isEmpty);
    expect(standings.availableActions(isOnline: true), [
      OnlinePostGameAction.playAgain,
      OnlinePostGameAction.home,
    ]);
  });

  test('the sole remaining competitor is assigned the final place', () {
    final standings = OnlineStandingsTracker<PlayerColor>(
      competitors: PlayerColor.values,
    );

    standings.recordFinish(PlayerColor.red);
    expect(standings.assignLastPlaceIfDecided(), isFalse);
    standings.recordFinish(PlayerColor.green);
    expect(standings.assignLastPlaceIfDecided(), isFalse);
    standings.recordFinish(PlayerColor.yellow);

    expect(standings.assignLastPlaceIfDecided(), isTrue);
    expect(standings.finishOrder, PlayerColor.values);
    expect(standings.placementFor(PlayerColor.blue), 4);
    expect(standings.pointsFor(PlayerColor.blue), 10);
    expect(standings.isComplete, isTrue);
  });

  test('scoring can be changed centrally without changing arrival order', () {
    final standings = OnlineStandingsTracker<String>(
      competitors: const ['A', 'B'],
      pointsByPlacement: const {1: 9, 2: 4},
    );

    standings.recordFinish('B');
    standings.recordFinish('A');

    expect(standings.finishOrder, ['B', 'A']);
    expect(standings.pointsFor('B'), 9);
    expect(standings.pointsFor('A'), 4);
  });

  test('rejects a finisher that does not belong to the match', () {
    final standings = OnlineStandingsTracker<String>(
      competitors: const ['A', 'B'],
      pointsByPlacement: const {1: 9, 2: 4},
    );

    expect(() => standings.recordFinish('C'), throwsArgumentError);
    expect(standings.finishOrder, isEmpty);
  });
}
