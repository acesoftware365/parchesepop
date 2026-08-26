import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';
import 'package:parchesepop/player_progression.dart';
import 'package:parchesepop/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a completed match pays normal play rewards exactly once', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final engine = _oneMoveFromFirstPlace();
    final wallet = await WalletController.create();
    final progression = await PlayerProgressionController.create();
    addTearDown(engine.dispose);
    addTearDown(wallet.dispose);
    addTearDown(progression.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'CPU • Fácil',
          gameEngine: engine,
          wallet: wallet,
          progression: progression,
        ),
      ),
    );
    await tester.pump();

    expect(engine.moveToken(engine.currentPlayer.tokens.last, die: 1), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    // 30 for completion + 40 for first place + 50 first match of the day.
    expect(wallet.balance, 370);
    expect(progression.balance, 370);
    expect(progression.weeklyMission.matchesCompleted, 1);
    expect(
      progression.transactions
          .where((transaction) => transaction.matchId != null)
          .length,
      3,
    );

    // A later rebuild/event cannot mint the same match rewards again.
    engine.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(wallet.balance, 370);
    expect(progression.balance, 370);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a CPU first place still pays participation immediately', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final engine = _oneMoveFromCpuFirstPlace();
    final wallet = await WalletController.create();
    final progression = await PlayerProgressionController.create();
    addTearDown(engine.dispose);
    addTearDown(wallet.dispose);
    addTearDown(progression.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'CPU • Fácil',
          gameEngine: engine,
          wallet: wallet,
          progression: progression,
        ),
      ),
    );
    await tester.pump();

    expect(engine.moveToken(engine.currentPlayer.tokens.last, die: 1), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1800));

    expect(engine.winner?.color, PlayerColor.green);
    expect(engine.placementFor(PlayerColor.red), isNull);
    // 30 for completing the active match + 50 for the first match of the day.
    expect(wallet.balance, 330);
    expect(progression.balance, 330);
    expect(progression.weeklyMission.matchesCompleted, 1);
    expect(
      find.byKey(const ValueKey('victory-early-earned-reward')),
      findsOneWidget,
    );
    expect(find.text('+80 MONEDAS POR JUGAR'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('victory-early-rewarded-ad')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the first Quick Pop move completes the release mission', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final engine = GameEngine(matchFormat: MatchFormat.quickPop)
      ..hasRolled = true
      ..dice = const [1, 2];
    engine.remainingDice
      ..clear()
      ..addAll(const [1, 2]);
    final wallet = await WalletController.create();
    final progression = await PlayerProgressionController.create();
    addTearDown(engine.dispose);
    addTearDown(wallet.dispose);
    addTearDown(progression.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'Quick Pop • CPU Normal',
          matchFormat: MatchFormat.quickPop,
          gameEngine: engine,
          wallet: wallet,
          progression: progression,
        ),
      ),
    );
    await tester.pump();

    expect(engine.moveToken(engine.currentPlayer.tokens.first, die: 1), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(progression.dailyMissions.tokenReleased, isTrue);
    // Quick Pop now begins in base. The first die releases the piece onto its
    // departure square; it does not also count as a travelled board cell.
    expect(progression.dailyMissions.cellsMoved, 0);
    expect(wallet.balance, 285);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('restored event sequences keep counting mission movement', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final wallet = await WalletController.create();
    final progression = await PlayerProgressionController.create();
    addTearDown(wallet.dispose);
    addTearDown(progression.dispose);

    Future<void> playOneRun(GameEngine engine) async {
      // Exercise an actual board move instead of the new base-release action.
      engine.currentPlayer.tokens.first.progress = 0;
      engine
        ..hasRolled = true
        ..dice = const [1, 2];
      engine.remainingDice
        ..clear()
        ..addAll(const [1, 2]);
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            opponent: 'Quick Pop • CPU Normal',
            matchFormat: MatchFormat.quickPop,
            gameEngine: engine,
            wallet: wallet,
            progression: progression,
            analyticsMatchRef: 'same_restored_match',
          ),
        ),
      );
      await tester.pump();
      expect(
        engine.moveToken(engine.currentPlayer.tokens.first, die: 1),
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      engine.dispose();
    }

    await playOneRun(GameEngine(matchFormat: MatchFormat.quickPop));
    await playOneRun(GameEngine(matchFormat: MatchFormat.quickPop));

    expect(progression.dailyMissions.cellsMoved, 2);
  });

  testWidgets('Pass & Play counts turns from every human seat', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final engine = GameEngine(humanPlayerColors: PlayerColor.values.toSet());
    final wallet = await WalletController.create();
    final progression = await PlayerProgressionController.create();
    addTearDown(engine.dispose);
    addTearDown(wallet.dispose);
    addTearDown(progression.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'PASS & PLAY',
          gameEngine: engine,
          passAndPlay: true,
          wallet: wallet,
          progression: progression,
        ),
      ),
    );
    await tester.pump();

    for (
      var turn = 0;
      turn < progression.policy.sharedTableTurnsTarget;
      turn++
    ) {
      engine.endTurn();
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 160));

    expect(
      progression.sharedTableMissions.turnsPlayed,
      progression.policy.sharedTableTurnsTarget,
    );
    expect(progression.sharedTableMissions.turnRewardClaimed, isTrue);
    expect(wallet.balance, 250 + progression.policy.sharedTableTurnsCoins);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

GameEngine _oneMoveFromFirstPlace() {
  final engine = GameEngine();
  final player = engine.currentPlayer;
  for (var index = 0; index < player.tokens.length - 1; index++) {
    player.tokens[index].progress = GameEngine.finishProgress;
  }
  player.tokens.last.progress = GameEngine.finishProgress - 1;
  engine
    ..hasRolled = true
    ..dice = const [1, 2];
  engine.remainingDice
    ..clear()
    ..addAll(const [1, 2]);
  return engine;
}

GameEngine _oneMoveFromCpuFirstPlace() {
  final engine = GameEngine()..currentPlayerIndex = 1;
  final player = engine.currentPlayer;
  for (var index = 0; index < player.tokens.length - 1; index++) {
    player.tokens[index].progress = GameEngine.finishProgress;
  }
  player.tokens.last.progress = GameEngine.finishProgress - 1;
  engine
    ..hasRolled = true
    ..dice = const [1, 2];
  engine.remainingDice
    ..clear()
    ..addAll(const [1, 2]);
  return engine;
}
