import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';
import 'package:parchesepop/online_match.dart';

List<int> _tokenPositions(GameEngine engine) => [
  for (final player in engine.players)
    for (final token in player.tokens) token.progress,
];

void _prepareFirstWinner(GameEngine engine) {
  engine
    ..currentPlayerIndex = PlayerColor.red.index
    ..turnNumber = 23
    ..hasRolled = true
    ..dice = const [1, 4];
  engine.remainingDice
    ..clear()
    ..addAll(const [1, 4]);

  final red = engine.players[PlayerColor.red.index];
  for (var tokenId = 0; tokenId < 3; tokenId++) {
    red.tokens[tokenId].progress = GameEngine.finishProgress;
  }
  red.tokens.last.progress = GameEngine.finishProgress - 1;

  const unfinishedPositions = <PlayerColor, List<int>>{
    PlayerColor.green: [7, 18, -1, 33],
    PlayerColor.yellow: [2, -1, 28, 44],
    PlayerColor.blue: [-1, 12, 25, 60],
  };
  for (final entry in unfinishedPositions.entries) {
    final player = engine.players[entry.key.index];
    for (var tokenId = 0; tokenId < player.tokens.length; tokenId++) {
      player.tokens[tokenId].progress = entry.value[tokenId];
    }
  }
}

void _finishCurrentPlayer(GameEngine engine) {
  final player = engine.currentPlayer;
  for (var tokenId = 0; tokenId < 3; tokenId++) {
    player.tokens[tokenId].progress = GameEngine.finishProgress;
  }
  player.tokens.last.progress = GameEngine.finishProgress - 1;
  engine
    ..hasRolled = true
    ..dice = const [1, 2];
  engine.remainingDice
    ..clear()
    ..addAll(const [1, 2]);
  expect(engine.moveToken(player.tokens.last, die: 1), isTrue);
}

OnlineMatchSession _rankedSession() => OnlineMatchSession(
  matchId: 'spectator-ranking-test',
  seed: 901,
  mode: GameMode.traditional,
  participants: const [
    OnlineParticipant(
      id: 'local',
      displayName: 'JuanPop',
      flag: '🇩🇴',
      avatarId: 'avatar_default',
      level: 4,
      color: PlayerColor.red,
      kind: ParticipantKind.local,
      loadout: CosmeticLoadout(),
    ),
    OnlineParticipant(
      id: 'green',
      displayName: 'AminaStar',
      flag: '🇲🇦',
      avatarId: 'avatar_explorer',
      level: 5,
      color: PlayerColor.green,
      kind: ParticipantKind.virtual,
      loadout: CosmeticLoadout(),
    ),
    OnlineParticipant(
      id: 'yellow',
      displayName: 'PriyaPop',
      flag: '🇮🇳',
      avatarId: 'avatar_comet',
      level: 6,
      color: PlayerColor.yellow,
      kind: ParticipantKind.virtual,
      loadout: CosmeticLoadout(),
    ),
    OnlineParticipant(
      id: 'blue',
      displayName: 'JoaoTurbo',
      flag: '🇧🇷',
      avatarId: 'avatar_robot',
      level: 3,
      color: PlayerColor.blue,
      kind: ParticipantKind.virtual,
      loadout: CosmeticLoadout(),
    ),
  ],
);

String _visibleTextInside(WidgetTester tester, Finder parent) {
  return tester
      .widgetList<Text>(
        find.descendant(of: parent, matching: find.byType(Text)),
      )
      .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
      .join(' ');
}

void main() {
  test('continue watching preserves every position and advances one turn', () {
    final engine = GameEngine();
    _prepareFirstWinner(engine);
    final firstWinner = engine.currentPlayer;

    expect(engine.moveToken(firstWinner.tokens.last, die: 1), isTrue);
    final positionsAtVictory = _tokenPositions(engine);
    final victoryTurn = engine.turnNumber;

    expect(engine.continueAfterWinner(), isTrue);

    expect(_tokenPositions(engine), positionsAtVictory);
    expect(engine.turnNumber, victoryTurn + 1);
    expect(engine.currentPlayer.color, PlayerColor.green);
    expect(engine.winner, same(firstWinner));
    expect(engine.finishOrder, [PlayerColor.red]);
    expect(engine.gameOver, isFalse);
    expect(engine.spectatorContinuationActive, isTrue);
    engine.dispose();
  });

  test('the winner is skipped and the final player is assigned fourth', () {
    final engine = GameEngine();
    _prepareFirstWinner(engine);
    final firstWinner = engine.currentPlayer;
    expect(engine.moveToken(firstWinner.tokens.last, die: 1), isTrue);
    expect(engine.continueAfterWinner(), isTrue);

    for (final expected in const [
      PlayerColor.yellow,
      PlayerColor.blue,
      PlayerColor.green,
    ]) {
      engine
        ..dice = const [1, 2]
        ..hasRolled = true;
      engine.endTurn();
      expect(engine.currentPlayer.color, expected);
      expect(engine.currentPlayer.color, isNot(PlayerColor.red));
    }

    _finishCurrentPlayer(engine);
    expect(engine.currentPlayer.color, PlayerColor.yellow);
    expect(engine.currentPlayer.color, isNot(PlayerColor.red));
    expect(engine.winner, same(firstWinner));
    _finishCurrentPlayer(engine);

    expect(engine.gameOver, isTrue);
    expect(engine.winner, same(firstWinner));
    expect(engine.finishOrder, const [
      PlayerColor.red,
      PlayerColor.green,
      PlayerColor.yellow,
      PlayerColor.blue,
    ]);
    expect(
      engine.players[PlayerColor.blue.index].tokens.every(
        (token) => token.finished,
      ),
      isFalse,
    );
    engine.dispose();
  });

  test('checkpoint preserves spectator continuation and finish order', () {
    final engine = GameEngine();
    _prepareFirstWinner(engine);
    expect(engine.moveToken(engine.currentPlayer.tokens.last, die: 1), isTrue);
    expect(engine.continueAfterWinner(), isTrue);
    _finishCurrentPlayer(engine);

    expect(engine.finishOrder, const [PlayerColor.red, PlayerColor.green]);
    expect(engine.currentPlayer.color, PlayerColor.yellow);
    expect(engine.gameOver, isFalse);

    final checkpoint = <String, dynamic>{
      ...engine.checkpointRuleMetadata,
      'mode': engine.mode.name,
      'cpuLevel': engine.cpuLevel,
      'turn': engine.turnNumber,
      'currentPlayer': engine.currentPlayer.color.name,
      'dice': engine.dice,
      'remainingDice': engine.remainingDice,
      'hasRolled': engine.hasRolled,
      'players': <Map<String, dynamic>>[
        for (final player in engine.players)
          <String, dynamic>{
            'color': player.color.name,
            'name': player.name,
            'tokens': <int>[for (final token in player.tokens) token.progress],
            'inventory': player.inventory?.name,
            'shielded': player.shielded,
            'skippedTurns': player.skippedTurns,
          },
      ],
    };

    final restored = GameEngine.fromCheckpoint(checkpoint);
    expect(restored.finishOrder, const [PlayerColor.red, PlayerColor.green]);
    expect(restored.winner?.color, PlayerColor.red);
    expect(restored.currentPlayer.color, PlayerColor.yellow);
    expect(restored.spectatorContinuationActive, isTrue);
    expect(restored.gameOver, isFalse);

    _finishCurrentPlayer(restored);
    expect(restored.gameOver, isTrue);
    expect(restored.finishOrder, PlayerColor.values);

    restored.dispose();
    engine.dispose();
  });

  testWidgets('final spectator results show places 1 to 4 and their points', (
    tester,
  ) async {
    final engine = GameEngine();
    _prepareFirstWinner(engine);
    final finalRedToken = engine.currentPlayer.tokens.last;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'Online',
          gameEngine: engine,
          onlineSession: _rankedSession(),
          cpuThinkDelayProvider: () => const Duration(milliseconds: 100),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(engine.moveToken(finalRedToken, die: 1), isTrue);
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(find.byKey(const ValueKey('victory-continue-watching')));
    await tester.pump(const Duration(milliseconds: 50));

    for (final expectedColor in const [PlayerColor.green, PlayerColor.yellow]) {
      expect(engine.currentPlayer.color, expectedColor);
      _finishCurrentPlayer(engine);
    }
    await tester.pump(const Duration(milliseconds: 1800));

    expect(engine.finishOrder, PlayerColor.values);
    expect(find.byKey(const ValueKey('final-ranking')), findsOneWidget);
    const expectedNames = ['JuanPop', 'AminaStar', 'PriyaPop', 'JoaoTurbo'];
    const expectedPoints = [100, 60, 30, 10];
    for (var index = 0; index < 4; index++) {
      final place = index + 1;
      final row = find.byKey(ValueKey('final-ranking-$place'));
      expect(row, findsOneWidget);
      expect(
        find.byKey(ValueKey('final-ranking-points-$place')),
        findsOneWidget,
      );
      final rowText = _visibleTextInside(tester, row);
      expect(rowText, contains(expectedNames[index]));
      expect(rowText, contains('$place'));
      expect(rowText, contains('${expectedPoints[index]}'));
    }
    expect(
      find.byKey(const ValueKey('victory-continue-watching')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    engine.dispose();
  });
}
