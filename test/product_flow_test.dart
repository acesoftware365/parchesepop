import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/cosmetic_visuals.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/game_guide.dart';
import 'package:parchesepop/main.dart';
import 'package:parchesepop/online_match.dart';
import 'package:parchesepop/wallet.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void useViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    binding.platformDispatcher.localeTestValue = const Locale('es');
    PackageInfo.setMockInitialValues(
      appName: 'Parchese Pop',
      packageName: 'com.example.parchesepop',
      version: '1.2.3',
      buildNumber: '45',
      buildSignature: '',
    );
  });
  tearDown(binding.platformDispatcher.clearLocaleTestValue);

  testWidgets('main menu keeps the complete how-to-play guide', (tester) async {
    SharedPreferences.setMockInitialValues({});
    useViewport(tester, const Size(390, 844));

    await tester.pumpWidget(const ParchesePopApp());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-how-to-play')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-traps')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('home-how-to-play')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-how-to-play')));
    await tester.pumpAndSettle();

    expect(find.byType(GameGuideScreen), findsOneWidget);
    expect(find.byType(TrapPowerLabScreen), findsNothing);
    expect(find.text('CÓMO JUGAR'), findsOneWidget);
    expect(find.byKey(const ValueKey('show-power-lab')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Trampas opens only the four trap animations', (tester) async {
    SharedPreferences.setMockInitialValues({});
    useViewport(tester, const Size(390, 844));

    await tester.pumpWidget(const ParchesePopApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('home-traps')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-traps')));
    await tester.pumpAndSettle();

    expect(find.byType(TrapPowerLabScreen), findsOneWidget);
    expect(find.byType(GameGuideScreen), findsNothing);
    expect(find.byKey(const ValueKey('trap-power-lab-screen')), findsOneWidget);
    expect(find.text('TRAMPAS Y ANIMACIONES'), findsOneWidget);
    expect(find.text('Laboratorio de trampas'), findsOneWidget);
    expect(find.byKey(const ValueKey('trap-lab-back')), findsOneWidget);
    for (final trap in const ['glue', 'setback', 'prison', 'bomb']) {
      expect(find.byKey(ValueKey('guide-effect-$trap')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('guide-effect-shield')), findsNothing);
    expect(find.byKey(const ValueKey('guide-effect-turbo')), findsNothing);
    expect(find.text('CÓMO JUGAR'), findsNothing);
    expect(find.byKey(const ValueKey('guide-mode-traditional')), findsNothing);
    expect(find.byKey(const ValueKey('guide-mode-chaos')), findsNothing);
    expect(find.text('Salir con un 5'), findsNothing);
    expect(find.text('CHULETA RÁPIDA'), findsNothing);

    final bomb = find.byKey(const ValueKey('guide-effect-bomb'));
    await tester.ensureVisible(bomb);
    await tester.pumpAndSettle();
    await tester.tap(bomb);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('¡BUM! A LA CÁRCEL'), findsOneWidget);
    expect(find.text('Demostración: Bomba'), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(find.byType(TrapPowerLabScreen), findsNothing);
    expect(find.byKey(const ValueKey('home-traps')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CPU setup is a two-step game dialog', (tester) async {
    SharedPreferences.setMockInitialValues({});
    useViewport(tester, const Size(390, 844));

    await tester.pumpWidget(const ParchesePopApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONTRA CPU'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cpu-mode-step')), findsOneWidget);
    expect(find.text('Tradicional'), findsOneWidget);
    expect(find.text('Caos'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cpu-mode-chaos')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cpu-level-step')), findsOneWidget);
    expect(find.text('Fácil'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('Experto'), findsOneWidget);

    await tester.ensureVisible(find.text('Fácil'));
    await tester.pump();
    final easyCard = find
        .ancestor(of: find.text('Fácil'), matching: find.byType(InkWell))
        .first;
    await tester.tap(easyCard);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.textContaining('Caos'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('online setup clearly offers traditional and chaos modes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'profile_name': 'JuanPop',
      'profile_email': 'juan@example.com',
      'profile_flag': '🇩🇴',
      'player_auth_email': 'juan@example.com',
      'player_auth_digest': 'fixture-digest',
      'player_auth_signed_in': true,
    });
    useViewport(tester, const Size(390, 844));

    await tester.pumpWidget(const ParchesePopApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('PARTIDA RÁPIDA'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.byKey(const ValueKey('online-mode-step')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('online-mode-traditional')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('online-mode-chaos')), findsOneWidget);
    expect(find.text('Tradicional'), findsOneWidget);
    expect(find.text('Caos'), findsOneWidget);
    expect(
      find.text('Reglas clásicas, sin cubos, objetos ni trampas.'),
      findsOneWidget,
    );
    expect(
      find.text('Cubos sorpresa, poderes, trampas y efectos especiales.'),
      findsOneWidget,
    );
    expect(find.text('CLÁSICO'), findsOneWidget);
    expect(find.text('MÁS ACCIÓN'), findsOneWidget);
    expect(find.byType(MatchmakingScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a legacy profile can start a quick match without an account', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'profile_name': 'JuanPop',
      'profile_email': 'juan@example.com',
      'profile_flag': '🇩🇴',
    });
    useViewport(tester, const Size(390, 844));

    await tester.pumpWidget(const ParchesePopApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('PARTIDA RÁPIDA'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.byKey(const ValueKey('online-mode-step')), findsOneWidget);
    expect(find.text('Tradicional'), findsOneWidget);
    expect(find.text('Caos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final mode in GameMode.values) {
    testWidgets(
      'online ${mode.name} choice is preserved through matchmaking and game',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'profile_name': 'JuanPop',
          'profile_email': 'juan@example.com',
          'profile_flag': '🇩🇴',
          'player_auth_email': 'juan@example.com',
          'player_auth_digest': 'fixture-digest',
          'player_auth_signed_in': true,
        });
        useViewport(tester, const Size(390, 844));

        await tester.pumpWidget(const ParchesePopApp());
        await tester.pumpAndSettle();
        await tester.tap(find.text('PARTIDA RÁPIDA'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 450));
        await tester.tap(
          find.byKey(
            ValueKey(
              mode == GameMode.chaos
                  ? 'online-mode-chaos'
                  : 'online-mode-traditional',
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 450));

        expect(find.byType(MatchmakingScreen), findsOneWidget);
        final matchmaking = tester.widget<MatchmakingScreen>(
          find.byType(MatchmakingScreen),
        );
        expect((matchmaking as dynamic).mode, mode);

        await tester.pump(const Duration(seconds: 12));
        await tester.pump(const Duration(milliseconds: 450));

        final game = tester.widget<GameScreen>(find.byType(GameScreen));
        expect(game.mode, mode);
        expect(game.onlineSession, isNotNull);
        expect(game.onlineSession!.mode, mode);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('coin button, purchase and equip are functional', (tester) async {
    SharedPreferences.setMockInitialValues({});
    useViewport(tester, const Size(390, 844));
    final wallet = await WalletController.create();

    await tester.pumpWidget(
      MaterialApp(home: ShopScreen(wallet: wallet, showTestCoinControls: true)),
    );
    await tester.pumpAndSettle();
    expect(wallet.balance, 250);

    await tester.tap(find.byKey(const ValueKey('shop-add-test-balance')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('test-balance-dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('add-test-coins-10000')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-test-coins-500')));
    await tester.pumpAndSettle();
    expect(wallet.balance, 750);

    await tester.drag(
      find.byKey(const ValueKey('shop-filters')),
      const Offset(-260, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('shop-filters')),
        matching: find.text('Dados'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shop-action-dice_galaxy')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shop-confirm-purchase')));
    await tester.pumpAndSettle();

    expect(wallet.balance, 400);
    expect(wallet.isOwned('dice_galaxy'), isTrue);
    expect(wallet.isEquipped('dice_galaxy'), isTrue);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('shop-action-dice_galaxy')),
        matching: find.text('EN USO'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    wallet.dispose();
  });

  testWidgets('basic dice are shown before premium dice in the store', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    useViewport(tester, const Size(390, 844));
    final wallet = await WalletController.create();

    await tester.pumpWidget(
      MaterialApp(home: ShopScreen(wallet: wallet, showTestCoinControls: true)),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('shop-filters')),
      const Offset(-260, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('shop-filters')),
        matching: find.text('Dados'),
      ),
    );
    await tester.pumpAndSettle();

    final basic = find.byKey(const ValueKey('shop-preview-dice_default'));
    final firstPremium = find.byKey(const ValueKey('shop-preview-dice_galaxy'));
    expect(basic, findsOneWidget);
    expect(firstPremium, findsOneWidget);

    final basicPosition = tester.getTopLeft(basic);
    final premiumPosition = tester.getTopLeft(firstPremium);
    expect(
      basicPosition.dy,
      lessThanOrEqualTo(premiumPosition.dy),
      reason: 'The basic dice must be in the first store row.',
    );
    if ((basicPosition.dy - premiumPosition.dy).abs() < 1) {
      expect(
        basicPosition.dx,
        lessThan(premiumPosition.dx),
        reason: 'The basic dice must be the first item in the row.',
      );
    }
    expect(
      find.descendant(
        of: find.ancestor(of: basic, matching: find.byType(Card)),
        matching: find.text('GRATIS'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    wallet.dispose();
  });

  testWidgets('production-style store hides every test coin control', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    useViewport(tester, const Size(390, 844));
    final wallet = await WalletController.create();

    await tester.pumpWidget(
      MaterialApp(
        home: ShopScreen(wallet: wallet, showTestCoinControls: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('shop-add-test-balance')), findsNothing);
    expect(find.byKey(const ValueKey('add-coins')), findsNothing);
    expect(find.text('SALDO PARA PROBAR'), findsNothing);
    expect(find.byKey(const ValueKey('test-balance-dialog')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('shop-action-theme_neon_rush')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('test-balance-dialog')),
      findsNothing,
      reason:
          'Insufficient funds must not expose the local test wallet in '
          'production.',
    );
    expect(wallet.balance, 250);
    expect(tester.takeException(), isNull);
    wallet.dispose();
  });

  testWidgets('equipped store items change the live game', (tester) async {
    SharedPreferences.setMockInitialValues({});
    useViewport(tester, const Size(844, 390));
    final wallet = await WalletController.create(initialBalance: 4000);

    for (final productId in const [
      'theme_neon_rush',
      'dice_ice_crystal',
      'tokens_robot',
    ]) {
      expect(await wallet.purchase(productId), PurchaseResult.purchased);
      expect(await wallet.equip(productId), EquipResult.equipped);
    }

    final engine = GameEngine(mode: GameMode.chaos);
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'CPU • Fácil',
          mode: GameMode.chaos,
          gameEngine: engine,
          wallet: wallet,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final board = tester.widget<GameBoardMockup>(find.byType(GameBoardMockup));
    final controls = tester.widget<GameControlPanel>(
      find.byType(GameControlPanel),
    );
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(board.themeId, 'theme_neon_rush');
    expect(board.robotTokens, isTrue);
    expect(controls.diceId, 'dice_ice_crystal');
    expect(controls.galaxyDice, isFalse);
    expect(
      scaffold.backgroundColor,
      themeVisualSpecFor('theme_neon_rush').gameBackgroundColor,
    );
    expect(tester.takeException(), isNull);

    engine.dispose();
    wallet.dispose();
  });

  testWidgets('online fallback keeps complete profiles inside the match', (
    tester,
  ) async {
    useViewport(tester, const Size(844, 390));
    final local = OnlineParticipant(
      id: 'local-juan',
      displayName: 'JuanPop',
      flag: '🇩🇴',
      avatarId: 'avatar_ninja',
      level: 18,
      color: PlayerColor.red,
      kind: ParticipantKind.local,
      loadout: const CosmeticLoadout(
        themeId: 'theme_neon_rush',
        diceId: 'dice_galaxy',
        tokensId: 'tokens_robot',
      ),
    );
    final session = const VirtualProfileFactory(seed: 2026).createSession(
      matchId: 'widget-online-match',
      mode: GameMode.chaos,
      localPlayer: local,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'Mesa rápida • Normal',
          onlineSession: session,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('game-rail-players')));
    await tester.pump(const Duration(milliseconds: 320));

    for (final participant in session.participants) {
      expect(
        find.textContaining(participant.displayName),
        findsAtLeastNWidgets(1),
      );
      final completeName = find.text(participant.displayName);
      expect(completeName, findsAtLeastNWidgets(1));
      final fittedNames = find.ancestor(
        of: completeName,
        matching: find.byType(FittedBox),
      );
      expect(fittedNames.evaluate().length, completeName.evaluate().length);
      for (final text in tester.widgetList<Text>(completeName)) {
        expect(text.overflow, isNot(TextOverflow.ellipsis));
      }
      expect(
        find.byKey(ValueKey('online-profile-${participant.color.name}')),
        findsOneWidget,
      );
    }
    expect(find.textContaining('Rival'), findsNWidgets(3));
    expect(
      find.textContaining(RegExp('virtual', caseSensitive: false)),
      findsNothing,
    );

    final board = tester.widget<GameBoardMockup>(find.byType(GameBoardMockup));
    expect(board.playerLabels[PlayerColor.green], isNot(startsWith('CPU')));
    expect(board.robotTokenColors, {
      for (final participant in session.participants)
        if (participant.loadout.tokensId == 'tokens_robot') participant.color,
    });
    expect(board.tokenStyleIds, {
      for (final participant in session.participants)
        participant.color: participant.loadout.tokensId,
    });
    expect(board.robotTokenColors.length, lessThan(PlayerColor.values.length));

    await tester.tap(find.byTooltip('Poderes y trampas'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      find.textContaining(RegExp('virtual', caseSensitive: false)),
      findsNothing,
    );
    for (final participant in session.participants) {
      final completeNameAndFlag = find.text(
        '${participant.displayName} ${participant.flag}',
      );
      expect(completeNameAndFlag, findsOneWidget);
      expect(
        find.ancestor(
          of: completeNameAndFlag,
          matching: find.byType(FittedBox),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data?.startsWith('Nivel ') ?? false) &&
            (widget.data?.endsWith(' · Rival automático') ?? false),
      ),
      findsNWidgets(3),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('matchmaking uses neutral labels and passes fallback profiles', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    useViewport(tester, const Size(390, 844));
    final wallet = await WalletController.create();

    await tester.pumpWidget(
      MaterialApp(
        home: MatchmakingScreen(
          profile: const PlayerProfile(
            name: 'JugadorCompleto',
            email: 'juan@example.com',
            flag: '🇩🇴',
            level: 12,
          ),
          mode: GameMode.traditional,
          wallet: wallet,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.textContaining(RegExp('virtual', caseSensitive: false)),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('matchmaking-seats')), findsOneWidget);
    expect(find.text('Preparando rivales automáticos…'), findsOneWidget);
    final localName = find.text('JugadorCompleto 🇩🇴');
    expect(localName, findsOneWidget);
    expect(
      find.ancestor(of: localName, matching: find.byType(FittedBox)),
      findsOneWidget,
    );
    expect(find.text('Preparando…'), findsNWidgets(3));
    expect(find.text('RIVAL AUTOMÁTICO'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(MatchmakingScreen), findsOneWidget);
    expect(find.text('Rivales listos · 1/3'), findsOneWidget);
    expect(find.text('RIVAL AUTOMÁTICO'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Rivales listos · 2/3'), findsOneWidget);
    expect(find.text('RIVAL AUTOMÁTICO'), findsNWidgets(2));

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Rivales listos · 3/3'), findsOneWidget);
    expect(find.text('RIVAL AUTOMÁTICO'), findsNWidgets(3));
    expect(
      find.textContaining(RegExp('virtual', caseSensitive: false)),
      findsNothing,
    );
    expect(find.byType(MatchmakingScreen), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 400));

    final game = tester.widget<GameScreen>(find.byType(GameScreen));
    expect(game.onlineSession, isNotNull);
    expect(game.onlineSession!.participants, hasLength(4));
    expect(
      game.onlineSession!.participants.where(
        (participant) => participant.kind == ParticipantKind.virtual,
      ),
      hasLength(3),
    );
    expect(tester.takeException(), isNull);
    wallet.dispose();
  });

  testWidgets('settings toggles persist', (tester) async {
    SharedPreferences.setMockInitialValues({'settings_sound': false});
    useViewport(tester, const Size(390, 844));

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
    var sound = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('settings-sound')),
    );
    expect(sound.value, isFalse);

    await tester.tap(find.byKey(const ValueKey('settings-sound')));
    await tester.pumpAndSettle();
    sound = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('settings-sound')),
    );
    expect(sound.value, isTrue);
    expect(
      (await SharedPreferences.getInstance()).getBool('settings_sound'),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings defaults to system and offers system Spanish English', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'settings_language': 'fr'});
    useViewport(tester, const Size(390, 844));
    tester.binding.platformDispatcher.localeTestValue = const Locale(
      'de',
      'DE',
    );
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-language')), findsOneWidget);
    expect(find.text('Sistema · Español'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getString('settings_language'),
      'system',
    );

    await tester.tap(find.byKey(const ValueKey('settings-language')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-language-selector')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-language-system')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('settings-language-es')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-language-en')), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Français'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('settings-language-en')));
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getString('settings_language'),
      'en',
    );
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-language-es')));
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getString('settings_language'),
      'es',
    );
    expect(find.text('Ajustes'), findsOneWidget);
    expect(find.text('Español'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('system language and explicit choice update the complete app', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'settings_language': 'system'});
    useViewport(tester, const Size(390, 844));
    tester.binding.platformDispatcher.localeTestValue = const Locale(
      'en',
      'US',
    );
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);

    await tester.pumpWidget(const ParchesePopApp());
    await tester.pumpAndSettle();
    expect(find.text('QUICK MATCH'), findsOneWidget);
    expect(find.text('PLAY CPU'), findsOneWidget);
    expect(
      Localizations.localeOf(tester.element(find.byType(HomeScreen))),
      const Locale('en'),
    );

    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('System · English'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-language-es')));
    await tester.pumpAndSettle();
    expect(find.text('Ajustes'), findsOneWidget);
    expect(find.text('Sonido'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getString('settings_language'),
      'es',
    );

    await tester.tap(find.byKey(const ValueKey('settings-back')));
    await tester.pumpAndSettle();
    expect(find.text('PARTIDA RÁPIDA'), findsOneWidget);
    expect(find.text('CONTRA CPU'), findsOneWidget);
    expect(
      Localizations.localeOf(tester.element(find.byType(HomeScreen))),
      const Locale('es'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('English covers home shop game and how to play', (tester) async {
    SharedPreferences.setMockInitialValues({'settings_language': 'en'});
    useViewport(tester, const Size(390, 844));

    await tester.pumpWidget(const ParchesePopApp());
    await tester.pumpAndSettle();
    expect(find.text('QUICK MATCH'), findsOneWidget);
    expect(find.text('PLAY CPU'), findsOneWidget);

    await tester.ensureVisible(find.text('Shop'));
    await tester.tap(find.text('Shop'));
    await tester.pumpAndSettle();
    expect(find.byType(ShopScreen), findsOneWidget);
    expect(find.text('Customize your game'), findsOneWidget);
    expect(
      find.text('Customize your game without competitive advantages.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('shop-back')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('PLAY CPU'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Traditional'));
    await tester.pumpAndSettle();
    expect(find.text('Easy'), findsOneWidget);
    final easy = find.byKey(const ValueKey('cpu-level-Fácil'));
    await tester.ensureVisible(easy);
    await tester.pumpAndSettle();
    await tester.tap(easy);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('Roll'), findsOneWidget);
    expect(find.text('Traditional mode'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to home'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('How to play'));
    await tester.tap(find.text('How to play'));
    await tester.pumpAndSettle();
    expect(find.text('HOW TO PLAY'), findsOneWidget);
    expect(find.text('Leave base with a 5'), findsOneWidget);
    expect(find.text('Captures and +20 bonus'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('iPhone 14 landscape uses a board and contextual side rail', (
    tester,
  ) async {
    useViewport(tester, const Size(844, 390));
    final engine = GameEngine(mode: GameMode.chaos);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'CPU • Fácil',
          mode: GameMode.chaos,
          gameEngine: engine,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final board = tester.getRect(find.byKey(const ValueKey('game-board')));
    final rail = tester.getRect(find.byKey(const ValueKey('game-side-rail')));
    expect((board.width - board.height).abs(), lessThanOrEqualTo(.5));
    expect(board.left, closeTo(0, .5));
    expect(board.top, closeTo(0, .5));
    expect(board.height, closeTo(390, .5));
    expect(board.right, lessThan(rail.left));
    expect(find.byKey(const ValueKey('game-quick-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('match-elapsed-timer')), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.byKey(const ValueKey('game-version-label')), findsOneWidget);
    expect(find.text('v1.2.3+45'), findsOneWidget);
    final version = tester.getRect(
      find.byKey(const ValueKey('game-version-label')),
    );
    expect(version.left, greaterThanOrEqualTo(rail.left));
    expect(version.right, lessThanOrEqualTo(rail.right));
    expect(version.top, greaterThanOrEqualTo(rail.top));
    expect(version.bottom, lessThanOrEqualTo(rail.bottom));

    await tester.tap(find.byKey(const ValueKey('game-rail-players')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('game-rail-roster')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('game-rail-powers')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('game-rail-power-panel')), findsOneWidget);
    expect(tester.takeException(), isNull);
    engine.dispose();
  });

  testWidgets('small macOS window also keeps the board beside the rail', (
    tester,
  ) async {
    useViewport(tester, const Size(760, 620));

    await tester.pumpWidget(
      const MaterialApp(home: GameScreen(opponent: 'CPU • Fácil')),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final board = tester.getRect(find.byKey(const ValueKey('game-board')));
    expect((board.width - board.height).abs(), lessThanOrEqualTo(.5));
    expect(board.left, closeTo(0, .5));
    expect(board.top, closeTo(0, .5));
    expect(board.height, closeTo(551, 1));
    expect(find.byKey(const ValueKey('game-side-rail')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait game board fills the complete safe width', (
    tester,
  ) async {
    useViewport(tester, const Size(390, 844));

    await tester.pumpWidget(
      const MaterialApp(home: GameScreen(opponent: 'CPU • Fácil')),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final board = tester.getRect(find.byKey(const ValueKey('game-board')));
    final quickBar = tester.getRect(
      find.byKey(const ValueKey('game-quick-bar')),
    );
    final controls = tester.getRect(
      find.byKey(const ValueKey('portrait-game-hud')),
    );
    expect((board.width - board.height).abs(), lessThanOrEqualTo(.5));
    expect(board.left, closeTo(0, .5));
    expect(board.width, closeTo(390, .5));
    expect(quickBar.left, closeTo(0, .5));
    expect(quickBar.right, closeTo(390, .5));
    expect(quickBar.top, closeTo(0, .5));
    expect(board.top, greaterThanOrEqualTo(quickBar.bottom));
    expect(controls.top, greaterThanOrEqualTo(board.bottom));
    expect(controls.bottom, lessThanOrEqualTo(844));
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait game controls become one compact playable HUD', (
    tester,
  ) async {
    useViewport(tester, const Size(320, 568));
    final engine = GameEngine(mode: GameMode.chaos);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: GameControlPanel(engine: engine),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final hud = tester.getRect(find.byKey(const ValueKey('portrait-game-hud')));
    final dice = tester.getRect(find.byKey(const ValueKey('dice-group')));
    final actions = tester.getRect(
      find.byKey(const ValueKey('portrait-control-actions')),
    );
    final roll = tester.getRect(find.byKey(const ValueKey('roll-action')));
    final item = tester.getRect(find.byKey(const ValueKey('item-action')));
    final message = tester.getRect(
      find.byKey(const ValueKey('portrait-message')),
    );

    expect(hud.width, closeTo(312, .5));
    expect(hud.height, lessThanOrEqualTo(215));
    expect(dice.right, lessThan(actions.left));
    expect(roll.top, lessThan(item.top));
    expect(roll.height, greaterThanOrEqualTo(44));
    expect(item.height, greaterThanOrEqualTo(40));
    expect(message.top, greaterThan(actions.bottom));
    expect(find.text('Tú'), findsOneWidget);
    expect(find.text('Sin poder ni trampa'), findsOneWidget);
    expect(find.text('⚡ CAOS'), findsOneWidget);
    expect(find.text('Lanzar'), findsOneWidget);
    expect(find.text('Sin objeto'), findsOneWidget);
    expect(find.text(engine.message), findsOneWidget);
    expect(find.byKey(const ValueKey('game-version-label')), findsOneWidget);
    expect(find.text('v1.2.3+45'), findsOneWidget);
    final version = tester.getRect(
      find.byKey(const ValueKey('game-version-label')),
    );
    expect(version.left, greaterThanOrEqualTo(message.left));
    expect(version.right, lessThanOrEqualTo(message.right));
    expect(find.byKey(const ValueKey('roll-action')).hitTestable(), findsOne);
    expect(find.byKey(const ValueKey('item-action')).hitTestable(), findsOne);
    final emptyStatus = tester.widget<Container>(
      find.byKey(const ValueKey('empty-red')),
    );
    final emptyDecoration = emptyStatus.decoration! as BoxDecoration;
    final statusLuminance = emptyDecoration.color!.computeLuminance();
    final labelLuminance = PopColors.navy.computeLuminance();
    final contrastRatio = (statusLuminance + .05) / (labelLuminance + .05);
    expect(emptyDecoration.color!.a, 1);
    expect(contrastRatio, greaterThanOrEqualTo(4.5));

    final initialRollSerial = engine.rollSerial;
    await tester.tap(find.text('Lanzar'));
    await tester.pump();
    expect(engine.rollSerial, initialRollSerial + 1);
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
    engine.dispose();
  });

  testWidgets('large macOS window no longer caps the board at 760 pixels', (
    tester,
  ) async {
    useViewport(tester, const Size(1512, 982));

    await tester.pumpWidget(
      const MaterialApp(home: GameScreen(opponent: 'CPU • Fácil')),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final board = tester.getRect(find.byKey(const ValueKey('game-board')));
    final railSlot = tester.getRect(
      find.byKey(const ValueKey('game-rail-slot')),
    );
    expect((board.width - board.height).abs(), lessThanOrEqualTo(.5));
    expect(board.width, closeTo(982, .5));
    expect(board.right, lessThan(railSlot.left));
    expect(tester.takeException(), isNull);
  });
}
