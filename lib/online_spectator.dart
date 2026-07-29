import 'dart:collection';

enum OnlinePostGameAction { continueWatching, playAgain, home }

/// Provisional placement-only scoring.
///
/// The product did not yet define a different formula, so all score values
/// live here and can be changed without touching the game engine or the UI.
const Map<int, int> defaultPlacementPoints = <int, int>{
  1: 100,
  2: 60,
  3: 30,
  4: 10,
};

/// Immutable result for one participant that has reached the goal.
class MatchStanding<T> {
  const MatchStanding({
    required this.competitor,
    required this.placement,
    required this.points,
  });

  final T competitor;
  final int placement;
  final int points;
}

/// Owns the authoritative arrival order and placement score for a match.
///
/// Keeping this state outside the presentation layer lets a match pause after
/// the first winner, resume with the exact board state, and keep recording
/// second through fourth place without rebuilding the ranking in each screen.
class OnlineStandingsTracker<T> {
  OnlineStandingsTracker({
    required Iterable<T> competitors,
    Map<int, int> pointsByPlacement = defaultPlacementPoints,
  }) : _competitors = List<T>.unmodifiable(competitors),
       _pointsByPlacement = Map<int, int>.unmodifiable(pointsByPlacement) {
    if (_competitors.isEmpty) {
      throw ArgumentError.value(
        competitors,
        'competitors',
        'At least one competitor is required.',
      );
    }
    if (_competitors.toSet().length != _competitors.length) {
      throw ArgumentError.value(
        competitors,
        'competitors',
        'Competitors must be unique.',
      );
    }
    for (var placement = 1; placement <= _competitors.length; placement++) {
      if (!_pointsByPlacement.containsKey(placement)) {
        throw ArgumentError.value(
          pointsByPlacement,
          'pointsByPlacement',
          'A score is required for every placement.',
        );
      }
    }
  }

  final List<T> _competitors;
  final Map<int, int> _pointsByPlacement;
  final List<T> _finishOrder = <T>[];

  UnmodifiableListView<T> get competitors =>
      UnmodifiableListView<T>(_competitors);

  UnmodifiableListView<T> get finishOrder =>
      UnmodifiableListView<T>(_finishOrder);

  UnmodifiableListView<MatchStanding<T>> get standings =>
      UnmodifiableListView<MatchStanding<T>>(<MatchStanding<T>>[
        for (var index = 0; index < _finishOrder.length; index++)
          MatchStanding<T>(
            competitor: _finishOrder[index],
            placement: index + 1,
            points: _pointsByPlacement[index + 1]!,
          ),
      ]);

  bool recordFinish(T competitor) {
    if (!_competitors.contains(competitor)) {
      throw ArgumentError.value(
        competitor,
        'competitor',
        'The competitor is not part of this match.',
      );
    }
    if (_finishOrder.contains(competitor)) return false;
    _finishOrder.add(competitor);
    return true;
  }

  /// Assigns the final remaining competitor to last place once every higher
  /// position has already been decided.
  bool assignLastPlaceIfDecided() {
    final remaining = remainingPlayers;
    if (remaining.length != 1 || _finishOrder.isEmpty) return false;
    return recordFinish(remaining.single);
  }

  bool hasFinished(T competitor) => _finishOrder.contains(competitor);

  int? placementFor(T competitor) {
    final index = _finishOrder.indexOf(competitor);
    return index < 0 ? null : index + 1;
  }

  int? pointsFor(T competitor) {
    final placement = placementFor(competitor);
    return placement == null ? null : _pointsByPlacement[placement];
  }

  bool get isComplete => _finishOrder.length == _competitors.length;

  bool get hasRemainingPlayers => !isComplete;

  UnmodifiableListView<T> get remainingPlayers => UnmodifiableListView<T>(
    _competitors
        .where((competitor) => !_finishOrder.contains(competitor))
        .toList(growable: false),
  );

  List<OnlinePostGameAction> availableActions({required bool isOnline}) {
    return <OnlinePostGameAction>[
      if (isOnline && _finishOrder.isNotEmpty && hasRemainingPlayers)
        OnlinePostGameAction.continueWatching,
      OnlinePostGameAction.playAgain,
      OnlinePostGameAction.home,
    ];
  }
}
