import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';

GameEngine _engineWithBarrierAt(int globalIndex) {
  final engine = GameEngine();
  for (final player in engine.players) {
    for (final token in player.tokens) {
      token.progress = -1;
    }
  }

  for (final color in PlayerColor.values) {
    final start = GameEngine.startOffset[color]!;
    final progress =
        (globalIndex - start + GameEngine.loopLength) % GameEngine.loopLength;
    if (progress >= GameEngine.commonPathLength) continue;
    final player = engine.players.firstWhere((entry) => entry.color == color);
    player.tokens[0].progress = progress;
    player.tokens[1].progress = progress;
    return engine;
  }
  throw StateError('No player can reach loop index $globalIndex');
}

void main() {
  test('barriers on every outside edge keep both pieces fully inside', () {
    // The user-facing numbers are 12–14, 29–31, 46–48 and 63–65. The engine
    // stores them as zero-based loop indices.
    const edgeIndices = [11, 12, 13, 28, 29, 30, 45, 46, 47, 62, 63, 64];

    for (final compactPhone in [false, true]) {
      final safeEdge = .64 - (compactPhone ? .08 : .26);
      for (final globalIndex in edgeIndices) {
        final engine = _engineWithBarrierAt(globalIndex);
        final cells = displayTokenCellsForTesting(
          engine,
          compactPhone: compactPhone,
        );
        final player = engine.players.firstWhere(
          (entry) => entry.tokens[0].progress >= 0,
        );
        final barrierPositions = [
          cells[player.tokens[0]]!,
          cells[player.tokens[1]]!,
        ];

        expect(
          barrierPositions,
          hasLength(2),
          reason: 'Expected two pieces at edge number ${globalIndex + 1}',
        );
        for (final position in barrierPositions) {
          expect(
            position.dx,
            inInclusiveRange(safeEdge, 20 - safeEdge),
            reason:
                'x clipped at edge number ${globalIndex + 1} '
                '(compact=$compactPhone)',
          );
          expect(
            position.dy,
            inInclusiveRange(safeEdge, 20 - safeEdge),
            reason:
                'y clipped at edge number ${globalIndex + 1} '
                '(compact=$compactPhone)',
          );
        }
        engine.dispose();
      }
    }
  });
}
