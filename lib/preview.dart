import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_language.dart';
import 'cosmetic_visuals.dart';
import 'game_engine.dart';
import 'game_guide.dart';
import 'main.dart' as app;
import 'online_match.dart';
import 'orientation_policy.dart';

const preview = String.fromEnvironment(
  'PARCHESPOP_PREVIEW',
  defaultValue: 'home',
);

const previewLanguage = String.fromEnvironment(
  'PARCHESPOP_PREVIEW_LANGUAGE',
  defaultValue: '',
);

// Lets visual regression captures exercise a specific board theme.
const previewTheme = String.fromEnvironment(
  'PARCHESPOP_PREVIEW_THEME',
  defaultValue: 'theme_neon_rush',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final languagePreference = _previewLanguagePreference(previewLanguage);
  if (languagePreference != null) {
    final store = await SharedPreferences.getInstance();
    await store.setString(
      AppLanguageController.preferenceKey,
      languagePreference.storedValue,
    );
  }
  await enableFlexibleOrientation();
  if (preview == 'home') {
    runApp(const app.ParchesePopApp());
    return;
  }
  final language = AppLanguageController();
  await language.initialize();
  final previewLocalPlayer = OnlineParticipant(
    id: 'preview-local',
    displayName: 'JuanPop',
    flag: '🇩🇴',
    avatarId: 'avatar_ninja',
    level: 18,
    color: PlayerColor.red,
    kind: ParticipantKind.local,
    loadout: CosmeticLoadout(
      themeId: previewTheme,
      diceId: 'dice_galaxy',
      tokensId: matchingTokenStyleIdForTheme(previewTheme),
    ),
  );
  final previewOnlineSession = const VirtualProfileFactory(seed: 2026)
      .createSession(
        matchId: 'preview-online-match',
        mode: GameMode.chaos,
        localPlayer: previewLocalPlayer,
      );
  final previewOnlineEngine =
      preview == 'online_game' || preview == 'portrait_online_game'
      ? (GameEngine(
            mode: GameMode.chaos,
            humanName: previewOnlineSession
                .participantForColor(PlayerColor.red)
                .displayName,
            cpuNames: [
              previewOnlineSession
                  .participantForColor(PlayerColor.green)
                  .displayName,
              previewOnlineSession
                  .participantForColor(PlayerColor.yellow)
                  .displayName,
              previewOnlineSession
                  .participantForColor(PlayerColor.blue)
                  .displayName,
            ],
          )
          ..currentPlayerIndex = 1
          ..message = 'Turno del rival.')
      : null;
  final previewControlsEngine = preview == 'controls'
      ? GameEngine(mode: GameMode.chaos)
      : null;
  final previewVictoryEngine = preview == 'victory'
      ? _buildVictoryPreviewEngine()
      : null;
  final screen = switch (preview) {
    'shop' => const app.ShopScreen(),
    'settings' => const app.SettingsScreen(),
    'guide' => const GameGuideScreen(initialMode: GameGuideMode.chaos),
    'matchmaking' => const app.MatchmakingScreen(
      profile: app.PlayerProfile(
        name: 'JuanPop',
        email: 'juan@example.com',
        flag: '🇩🇴',
        level: 18,
      ),
      mode: GameMode.chaos,
    ),
    'online_game' => app.GameScreen(
      opponent: 'Mesa rápida • Normal',
      onlineSession: previewOnlineSession,
      gameEngine: previewOnlineEngine,
    ),
    'portrait_online_game' => app.GameScreen(
      opponent: 'Mesa rápida • Normal',
      onlineSession: previewOnlineSession,
      gameEngine: previewOnlineEngine,
    ),
    'game' => const app.GameScreen(
      opponent: 'CPU • Normal',
      mode: GameMode.chaos,
    ),
    'portrait_game' => const app.GameScreen(
      opponent: 'CPU • Normal',
      mode: GameMode.chaos,
    ),
    'victory' => app.GameScreen(
      opponent: 'Mesa rápida • Normal',
      gameEngine: previewVictoryEngine,
    ),
    'controls' => Scaffold(
      body: app.PopBackground(
        child: SafeArea(
          child: Column(
            children: [
              const Expanded(
                child: Center(
                  child: Text(
                    'CONTROL DE TURNO',
                    style: TextStyle(
                      color: app.PopColors.navy,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: app.GameControlPanel(engine: previewControlsEngine!),
              ),
            ],
          ),
        ),
      ),
    ),
    _ => const app.ShopScreen(),
  };
  runApp(
    AppLanguageScope(
      controller: language,
      child: AnimatedBuilder(
        animation: language,
        builder: (context, child) => MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: language.localeOverride,
          supportedLocales: const [Locale('es'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          localeResolutionCallback: (locale, supportedLocales) {
            if (locale?.languageCode == 'en') return const Locale('en');
            return const Locale('es');
          },
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: app.PopColors.blue,
              primary: app.PopColors.blue,
              secondary: app.PopColors.yellow,
            ),
          ),
          home: child,
        ),
        child: screen,
      ),
    ),
  );
}

AppLanguagePreference? _previewLanguagePreference(String code) =>
    switch (code) {
      '' => null,
      'system' => AppLanguagePreference.system,
      'es' => AppLanguagePreference.spanish,
      'en' => AppLanguagePreference.english,
      _ => throw ArgumentError.value(
        code,
        'PARCHESPOP_PREVIEW_LANGUAGE',
        'Use system, es or en.',
      ),
    };

GameEngine _buildVictoryPreviewEngine() {
  final engine = GameEngine(mode: GameMode.chaos);
  final player = engine.currentPlayer;
  for (var tokenId = 0; tokenId < player.tokens.length - 1; tokenId++) {
    player.tokens[tokenId].progress = GameEngine.finishProgress;
  }
  player.tokens.last.progress = GameEngine.finishProgress - 1;
  engine.hasRolled = true;
  engine.dice = const [1, 4];
  engine.remainingDice.addAll(const [1, 4]);
  engine.moveToken(player.tokens.last, die: 1);
  return engine;
}
