import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_analytics.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';
import 'package:parchesepop/online_match.dart';
import 'package:parchesepop/player_auth.dart';
import 'package:parchesepop/player_progression.dart';
import 'package:parchesepop/progress_hub.dart';
import 'package:parchesepop/tutorial_controller.dart';
import 'package:parchesepop/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _mobileViewport = Size(390, 844);

void _useMobileViewport(WidgetTester tester, {Size size = _mobileViewport}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  String? reason,
  int maxPumps = 20,
  Duration step = const Duration(milliseconds: 50),
}) async {
  for (var pump = 0; pump < maxPumps; pump++) {
    if (condition()) return;
    await tester.pump(step);
  }
  expect(condition(), isTrue, reason: reason ?? 'bounded pump condition');
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'Quick Pop renders the authentic board with two tokens per side',
    (tester) async {
      _useMobileViewport(tester);

      await tester.pumpWidget(
        const MaterialApp(
          home: GameScreen(
            opponent: 'Quick Pop • CPU Normal',
            matchFormat: MatchFormat.quickPop,
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () => find.byType(GameBoardMockup).evaluate().length == 1,
        reason: 'Quick Pop board did not render within one second.',
      );

      final board = tester.widget<GameBoardMockup>(
        find.byType(GameBoardMockup),
      );
      expect(board.engine.matchFormat, MatchFormat.quickPop);
      expect(
        board.engine.players.every((player) => player.tokens.length == 2),
        isTrue,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('game-mode-indicator')),
          matching: find.textContaining('Quick Pop'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mobile-portrait-game-layout')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await _unmount(tester);
    },
  );

  testWidgets('Quick Pop HUD reports a two-token finish target', (
    tester,
  ) async {
    _useMobileViewport(tester, size: const Size(844, 390));

    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(
          opponent: 'Quick Pop • CPU Normal',
          matchFormat: MatchFormat.quickPop,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('landscape-player-strip'))
          .evaluate()
          .isNotEmpty,
      reason: 'Quick Pop landscape HUD did not render within one second.',
    );

    expect(find.text('0/2'), findsNWidgets(4));
    expect(find.text('0/4'), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('home promotes Quick Pop honestly and opens its local preview', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final wallet = await WalletController.create();
    final progression = await PlayerProgressionController.create();
    final auth = await LocalPlayerAuthGateway.create();
    addTearDown(auth.dispose);
    addTearDown(wallet.dispose);
    addTearDown(progression.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          profile: PlayerProfile.guest,
          onProfileChanged: (_) {},
          wallet: wallet,
          progression: progression,
          authGateway: auth,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('home-mode-quick-pop'))
          .evaluate()
          .isNotEmpty,
      reason: 'The featured Quick Pop card did not render within one second.',
    );

    final quickPop = find.byKey(const ValueKey('home-mode-quick-pop'));
    final quickTable = find.byKey(const ValueKey('home-mode-quick-table'));
    final cpu = find.byKey(const ValueKey('home-mode-cpu'));
    final passAndPlay = find.byKey(const ValueKey('home-mode-pass-and-play'));
    expect(quickPop, findsOneWidget);
    expect(quickTable, findsOneWidget);
    expect(cpu, findsOneWidget);
    expect(passAndPlay, findsNothing);
    expect(
      find.byKey(const ValueKey('home-quick-pop')),
      findsNothing,
      reason: 'Quick Pop must not be duplicated in the secondary menu dock.',
    );
    expect(find.text('QUICK POP'), findsOneWidget);
    expect(find.text('Partida rápida online'), findsOneWidget);
    expect(find.text('MESA RÁPIDA'), findsOneWidget);
    expect(find.text('Amigos online · crea una sala'), findsOneWidget);
    expect(find.text('CONTRA CPU'), findsOneWidget);
    expect(find.text('Juega contra el CPU'), findsOneWidget);
    expect(find.text('PASS & PLAY'), findsNothing);

    for (final card in [quickPop, quickTable, cpu]) {
      await tester.ensureVisible(card);
      await tester.pump(const Duration(milliseconds: 50));
      expect(card.hitTestable(), findsOneWidget);
      final rect = tester.getRect(card);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(_mobileViewport.width));
      expect(rect.width, greaterThanOrEqualTo(48));
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(
        find.descendant(
          of: card,
          matching: find.byIcon(Icons.arrow_forward_rounded),
        ),
        findsNothing,
        reason:
            'Mode cards should be centered and use the whole card as the tap target.',
      );
    }
    for (final title in ['QUICK POP', 'MESA RÁPIDA', 'CONTRA CPU']) {
      final titleFinder = find.text(title);
      final titleCenter = tester.getCenter(titleFinder);
      final card = switch (title) {
        'QUICK POP' => quickPop,
        'MESA RÁPIDA' => quickTable,
        'CONTRA CPU' => cpu,
        _ => cpu,
      };
      expect(
        titleCenter.dx,
        closeTo(tester.getRect(card).center.dx, 2),
        reason: '$title should be centered inside its mode card.',
      );
    }
    final featuredTop = tester.getTopLeft(quickPop).dy;
    expect(
      tester.getTopLeft(quickTable).dy,
      closeTo(featuredTop, 1),
      reason: 'Quick Pop and Quick Table should share the first row.',
    );
    expect(tester.getTopLeft(cpu).dy, greaterThan(featuredTop));

    await tester.ensureVisible(quickPop);
    await tester.tap(quickPop);
    await tester.pump();
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('quick-pop-entry-dialog'))
          .evaluate()
          .isNotEmpty,
      reason: 'Quick Pop did not explain its online/local entry choices.',
    );
    expect(find.byType(MatchmakingScreen), findsNothing);
    expect(find.byType(GameScreen), findsNothing);

    final localPreview = find.byKey(const ValueKey('quick-pop-local-preview'));
    expect(localPreview, findsOneWidget);
    expect(localPreview.hitTestable(), findsOneWidget);
    expect(tester.getSize(localPreview).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(localPreview).height, greaterThanOrEqualTo(48));
    await tester.tap(localPreview);
    await tester.pump();
    await _pumpUntil(
      tester,
      () => find.byType(GameScreen).evaluate().length == 1,
      reason: 'The explicitly local Quick Pop preview did not open.',
    );

    final screen = tester.widget<GameScreen>(find.byType(GameScreen));
    expect(screen.matchFormat, MatchFormat.quickPop);
    expect(screen.onlineSession, isNull);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('online startup is playable locally by fifteen seconds', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final wallet = await WalletController.create(initialBalance: 10000);
    final progression = await PlayerProgressionController.create();
    final auth = await LocalPlayerAuthGateway.create();
    addTearDown(auth.dispose);
    addTearDown(wallet.dispose);
    addTearDown(progression.dispose);
    for (final productId in const [
      'theme_neon_rush',
      'dice_ice_crystal',
      'tokens_robot',
      'avatar_ninja',
    ]) {
      expect(await wallet.purchase(productId), PurchaseResult.purchased);
      expect(await wallet.equip(productId), EquipResult.equipped);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          profile: PlayerProfile.guest,
          onProfileChanged: (_) {},
          wallet: wallet,
          progression: progression,
          authGateway: auth,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('home-mode-quick-pop'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('home-mode-quick-pop')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('quick-pop-online-start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 14999));
    if (find.byType(GameScreen).evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('quick-pop-start-cpu'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('quick-pop-start-cpu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final screen = tester.widget<GameScreen>(find.byType(GameScreen));
    final local = screen.onlineSession!.localParticipant;
    expect(screen.matchFormat, MatchFormat.quickPop);
    expect(screen.onlineGameSync, isNull);
    expect(screen.wallet, same(wallet));
    expect(screen.progression, same(progression));
    expect(local.avatarId, 'avatar_ninja');
    expect(local.loadout.themeId, 'theme_neon_rush');
    expect(local.loadout.diceId, 'dice_ice_crystal');
    expect(local.loadout.tokensId, 'tokens_robot');
    expect(
      find.byKey(const ValueKey('dice-roll-target')).hitTestable(),
      findsOneWidget,
    );
    expect(find.text('INTENTAR DE NUEVO'), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('a short phone keeps the playable tutorial reachable', (
    tester,
  ) async {
    _useMobileViewport(tester, size: const Size(390, 700));
    final wallet = await WalletController.create();
    final progression = await PlayerProgressionController.create();
    final tutorial = await TutorialController.create(
      analytics: const NoopGameAnalytics(),
    );
    final auth = await LocalPlayerAuthGateway.create();
    addTearDown(auth.dispose);
    addTearDown(wallet.dispose);
    addTearDown(progression.dispose);
    addTearDown(tutorial.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          profile: PlayerProfile.guest,
          onProfileChanged: (_) {},
          wallet: wallet,
          progression: progression,
          tutorial: tutorial,
          authGateway: auth,
        ),
      ),
    );
    final action = find.byKey(const ValueKey('home-how-to-play'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pump();
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('learning-options-sheet'))
          .evaluate()
          .isNotEmpty,
      reason: 'The short-phone learning choices did not open.',
    );
    await tester.pump(const Duration(milliseconds: 400));
    final tutorialChoice = find.byKey(
      const ValueKey('learning-start-tutorial'),
    );
    expect(tutorialChoice.hitTestable(), findsOneWidget);
    await tester.tap(tutorialChoice);
    await tester.pump();
    await _pumpUntil(
      tester,
      () => find.byType(GameScreen).evaluate().isNotEmpty,
      reason: 'The playable tutorial did not open on a short phone.',
    );

    expect(tutorial.lifecycle, TutorialLifecycle.inProgress);
    expect(find.byType(GameScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('progress hub shows automatic daily and weekly progress', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final wallet = await WalletController.create();
    final progression = await PlayerProgressionController.create();
    addTearDown(wallet.dispose);
    addTearDown(progression.dispose);
    await progression.recordCellsMoved(eventId: 'move_1', cells: 20);
    await progression.recordTokenReleased(eventId: 'release_1');
    for (var index = 0; index < 3; index++) {
      await progression.recordMatchCompleted(
        matchId: 'mission_match_$index',
        placement: 2,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: ProgressHubScreen(progression: progression, wallet: wallet),
      ),
    );

    expect(find.byKey(const ValueKey('mission-move-20')), findsOneWidget);
    expect(find.byKey(const ValueKey('mission-release-token')), findsOneWidget);
    expect(find.byKey(const ValueKey('mission-finish-match')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mission-shared-table-turns')),
      findsOneWidget,
    );
    expect(find.text('LISTO'), findsNWidgets(3));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('mission-shared-table-match')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const ValueKey('mission-shared-table-match')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('mission-weekly-matches')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const ValueKey('mission-weekly-matches')),
      findsOneWidget,
    );
    expect(find.text('3 / 7'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('contextual tutorial overlays the board and can be skipped', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final tutorial = await TutorialController.create(
      analytics: const NoopGameAnalytics(),
    );
    addTearDown(tutorial.dispose);
    await tutorial.start();

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'Tutorial • CPU Fácil',
          tutorial: tutorial,
          cpuThinkDelayProvider: () => const Duration(seconds: 30),
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('contextual-tutorial-banner'))
          .evaluate()
          .isNotEmpty,
      reason: 'Tutorial banner did not render within one second.',
    );

    expect(
      find.byKey(const ValueKey('contextual-tutorial-banner')),
      findsOneWidget,
    );
    expect(find.text('1 · TIRA LOS DADOS'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tutorial-skip')));
    await tester.pump();
    await _pumpUntil(
      tester,
      () =>
          tutorial.lifecycle == TutorialLifecycle.skipped &&
          find
              .byKey(const ValueKey('contextual-tutorial-banner'))
              .evaluate()
              .isEmpty,
      reason: 'Tutorial did not leave the skipped state within one second.',
    );

    expect(tutorial.lifecycle, TutorialLifecycle.skipped);
    expect(
      find.byKey(const ValueKey('contextual-tutorial-banner')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('the local CPU table pauses and offers normal save controls', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final engine = GameEngine();
    final session = _localCpuSession();
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'Mesa local',
          gameEngine: engine,
          onlineSession: session,
          cpuThinkDelayProvider: () => Duration.zero,
        ),
      ),
    );
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 400));
    expect(engine.currentPlayer.color, PlayerColor.red);
    expect(engine.rollSerial, 0);
    expect(engine.hasRolled, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('¿GUARDAR PARTIDA?'), findsOneWidget);
    expect(find.text('GUARDAR Y SALIR'), findsOneWidget);
    expect(find.text('SALIR Y PERDER'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('CANCELAR'));
    await tester.pump();
    await _unmount(tester);
  });
}

OnlineMatchSession _localCpuSession() {
  const local = OnlineParticipant(
    id: 'local-player',
    displayName: 'Jugador',
    flag: '🎮',
    avatarId: 'avatar_default',
    level: 1,
    color: PlayerColor.red,
    kind: ParticipantKind.local,
    loadout: CosmeticLoadout(),
  );
  return const VirtualProfileFactory(seed: 44).createSession(
    matchId: 'local-table',
    mode: GameMode.traditional,
    localPlayer: local,
  );
}
