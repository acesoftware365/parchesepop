import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';
import 'package:parchesepop/online_match.dart';
import 'package:parchesepop/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _usePhoneViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
}

OnlineMatchSession _onlineSession() => OnlineMatchSession(
  matchId: 'owned-cosmetics-widget-test',
  seed: 20260802,
  mode: GameMode.chaos,
  participants: const [
    OnlineParticipant(
      id: 'local',
      displayName: 'JuanPop',
      flag: '🇩🇴',
      avatarId: 'avatar_default',
      level: 4,
      color: PlayerColor.red,
      kind: ParticipantKind.local,
      loadout: CosmeticLoadout(themeId: 'theme_default'),
    ),
    OnlineParticipant(
      id: 'green',
      displayName: 'Luna',
      flag: '🇲🇽',
      avatarId: 'avatar_default',
      level: 7,
      color: PlayerColor.green,
      kind: ParticipantKind.virtual,
      loadout: CosmeticLoadout(themeId: 'theme_golden_night'),
    ),
    OnlineParticipant(
      id: 'yellow',
      displayName: 'Priya',
      flag: '🇮🇳',
      avatarId: 'avatar_default',
      level: 9,
      color: PlayerColor.yellow,
      kind: ParticipantKind.virtual,
      loadout: CosmeticLoadout(themeId: 'theme_tropical_splash'),
    ),
    OnlineParticipant(
      id: 'blue',
      displayName: 'Noah',
      flag: '🇺🇸',
      avatarId: 'avatar_default',
      level: 11,
      color: PlayerColor.blue,
      kind: ParticipantKind.virtual,
      loadout: CosmeticLoadout(themeId: 'theme_celestial_carnival'),
    ),
  ],
);

void main() {
  testWidgets('owned cosmetics button keeps a 44 pixel touch target', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    _usePhoneViewport(tester);
    final wallet = await WalletController.create();
    final engine = GameEngine(mode: GameMode.chaos);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'Online match',
          mode: GameMode.chaos,
          gameEngine: engine,
          wallet: wallet,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    final button = find.byKey(const ValueKey('game-owned-cosmetics-button'));
    expect(button, findsOneWidget);
    expect(tester.getSize(button), const Size.square(44));
    await tester.ensureVisible(button);
    await tester.pump();
    expect(button.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    engine.dispose();
    wallet.dispose();
  });

  testWidgets(
    'picker lists only owned items and equips only the local player side',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      _usePhoneViewport(tester);
      final wallet = await WalletController.create(initialBalance: 2000);
      expect(
        await wallet.purchase('theme_neon_rush'),
        PurchaseResult.purchased,
      );
      final engine = GameEngine(mode: GameMode.chaos);

      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            opponent: 'Online match',
            mode: GameMode.chaos,
            gameEngine: engine,
            wallet: wallet,
            onlineSession: _onlineSession(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));

      final button = find.byKey(const ValueKey('game-owned-cosmetics-button'));
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(
        find.byKey(const ValueKey('owned-cosmetics-picker')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('owned-cosmetic-theme_default')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('owned-cosmetic-theme_neon_rush')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('owned-cosmetic-theme_golden_night')),
        findsNothing,
        reason: 'A rival loadout must not become owned by the local player.',
      );

      await tester.tap(
        find.byKey(const ValueKey('owned-cosmetic-theme_neon_rush')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        wallet.equippedProductId(CosmeticCategory.theme),
        'theme_neon_rush',
      );
      final board = tester.widget<GameBoardMockup>(
        find.byType(GameBoardMockup),
      );
      expect(
        board.resolvedPlayerThemeIds,
        containsPair(PlayerColor.red, 'theme_neon_rush'),
      );
      expect(
        board.resolvedPlayerThemeIds,
        containsPair(PlayerColor.green, 'theme_golden_night'),
      );
      expect(
        board.resolvedPlayerThemeIds,
        containsPair(PlayerColor.yellow, 'theme_tropical_splash'),
      );
      expect(
        board.resolvedPlayerThemeIds,
        containsPair(PlayerColor.blue, 'theme_celestial_carnival'),
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      engine.dispose();
      wallet.dispose();
    },
  );
}
