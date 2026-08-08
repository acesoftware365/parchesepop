import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart'
    show GameScreen, ParchesePopApp, ShopScreen;
import 'package:parchesepop/mobile_ads.dart';
import 'package:parchesepop/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('supportsMobileAds', () {
    test('supports only native Android and iOS', () {
      expect(supportsMobileAds(TargetPlatform.android), isTrue);
      expect(supportsMobileAds(TargetPlatform.iOS), isTrue);

      expect(supportsMobileAds(TargetPlatform.macOS), isFalse);
      expect(supportsMobileAds(TargetPlatform.windows), isFalse);
      expect(supportsMobileAds(TargetPlatform.linux), isFalse);
      expect(supportsMobileAds(TargetPlatform.fuchsia), isFalse);
    });

    test('never supports web, even with a mobile target platform', () {
      expect(supportsMobileAds(TargetPlatform.android, isWeb: true), isFalse);
      expect(supportsMobileAds(TargetPlatform.iOS, isWeb: true), isFalse);
    });
  });

  test('mobile ad requests allow only general-audience content', () {
    final configuration = familySafeAdRequestConfiguration();

    expect(configuration.maxAdContentRating, 'G');
    expect(configuration.tagForChildDirectedTreatment, isNull);
    expect(configuration.tagForUnderAgeOfConsent, isNull);
  });

  group('MobileAdShell', () {
    testWidgets('shows exactly one bottom banner when mobile ads are ready', (
      tester,
    ) async {
      final controller = _FakeAdsController(supported: true, adsReady: true);

      await tester.pumpWidget(_testApp(controller));

      expect(find.byKey(const ValueKey('screen-content')), findsOneWidget);
      expect(find.byKey(const ValueKey('fake-mobile-banner')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });

    testWidgets('waits until the mobile controller reports ads ready', (
      tester,
    ) async {
      final controller = _FakeAdsController(supported: true, adsReady: false);

      await tester.pumpWidget(_testApp(controller));
      expect(find.byKey(const ValueKey('fake-mobile-banner')), findsNothing);

      controller.setAdsReady(true);
      await tester.pump();

      expect(find.byKey(const ValueKey('fake-mobile-banner')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });

    testWidgets(
      'does not reserve banner space on macOS or another no-op host',
      (tester) async {
        final controller = _FakeAdsController(supported: false, adsReady: true);

        await tester.pumpWidget(_testApp(controller));

        expect(find.byKey(const ValueKey('screen-content')), findsOneWidget);
        expect(find.byKey(const ValueKey('fake-mobile-banner')), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );

    testWidgets('NoopAppAdsController never renders a banner', (tester) async {
      final controller = NoopAppAdsController();

      await tester.pumpWidget(_testApp(controller));

      expect(controller.supported, isFalse);
      expect(controller.adsReady, isFalse);
      expect(find.byKey(const ValueKey('fake-mobile-banner')), findsNothing);
      expect(find.byType(AdaptiveMobileBanner), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });

    testWidgets(
      'removes the iPhone bottom inset from content when the banner owns it',
      (tester) async {
        _configureIPhone14View(tester);
        final controller = _FakeAdsController(supported: true, adsReady: true);

        await tester.pumpWidget(_insetTestApp(controller));

        final probeContext = tester.element(
          find.byKey(const ValueKey('content-padding-probe')),
        );
        final content = tester.getRect(
          find.byKey(const ValueKey('safe-screen-content')),
        );
        final banner = tester.getRect(
          find.byKey(const ValueKey('fake-mobile-banner')),
        );

        expect(MediaQuery.paddingOf(probeContext).bottom, 0);
        expect(
          find.byKey(const ValueKey('version-above-ad-banner')),
          findsOneWidget,
        );
        expect(banner.top - content.bottom, closeTo(21, .01));

        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );

    testWidgets(
      'preserves the iPhone bottom inset while no banner is displayed',
      (tester) async {
        _configureIPhone14View(tester);
        final controller = _FakeAdsController(supported: true, adsReady: false);

        await tester.pumpWidget(_insetTestApp(controller));

        final probeContext = tester.element(
          find.byKey(const ValueKey('content-padding-probe')),
        );
        final content = tester.getRect(
          find.byKey(const ValueKey('safe-screen-content')),
        );

        expect(MediaQuery.paddingOf(probeContext).bottom, 34);
        expect(content.bottom, closeTo(810, .01));
        expect(find.byKey(const ValueKey('fake-mobile-banner')), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );

    testWidgets('iPhone home controls remain above the ready bottom banner', (
      tester,
    ) async {
      _configureIPhone14View(tester);
      SharedPreferences.setMockInitialValues({
        'profile_name': 'JuanPop',
        'profile_email': 'juan@example.com',
        'profile_flag': '🇩🇴',
      });
      final controller = _FakeAdsController(supported: true, adsReady: true);

      await tester.pumpWidget(ParchesePopApp(adsController: controller));
      for (var attempt = 0; attempt < 30; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find
            .byKey(const ValueKey('home-menu-dock'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }

      final banner = tester.getRect(
        find.byKey(const ValueKey('fake-mobile-banner')),
      );
      final dock = tester.getRect(find.byKey(const ValueKey('home-menu-dock')));
      expect(dock.bottom, lessThanOrEqualTo(banner.top));

      for (final label in const [
        'PARTIDA ONLINE',
        'CONTRA CPU',
        'Tienda',
        'Mi perfil',
        'Cómo jugar',
        'Trampas',
      ]) {
        final text = find.text(label);
        expect(text, findsOneWidget);
        final tappable = find
            .ancestor(of: text, matching: find.byType(InkWell))
            .first;
        expect(tappable, findsOneWidget);
        final rect = tester.getRect(tappable);
        expect(rect.top, greaterThanOrEqualTo(47));
        expect(rect.bottom, lessThanOrEqualTo(banner.top));
        expect(tappable.hitTestable(), findsOneWidget);
      }

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('rewarded result contract', () {
    test(
      'returns earned only when the fake reward callback earned it',
      () async {
        final earnedController = _FakeAdsController(
          supported: true,
          adsReady: true,
          rewardedReady: true,
          rewardedResult: true,
        );
        final dismissedController = _FakeAdsController(
          supported: true,
          adsReady: true,
          rewardedReady: true,
          rewardedResult: false,
        );

        expect(await earnedController.showRewarded(), isTrue);
        expect(await dismissedController.showRewarded(), isFalse);
        expect(earnedController.rewardedShowCount, 1);
        expect(dismissedController.rewardedShowCount, 1);

        earnedController.dispose();
        dismissedController.dispose();
      },
    );

    test('NoopAppAdsController never grants a reward', () async {
      final controller = NoopAppAdsController();

      controller.preloadRewarded();
      expect(controller.rewardedReady, isFalse);
      expect(await controller.showRewarded(), isFalse);

      controller.dispose();
    });
  });

  group('victory navigation rewarded ads', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets(
      'Play Again waits for one rewarded ad and still continues when dismissed',
      (tester) async {
        final engine = _finishedVictoryEngine();
        final rewarded = Completer<bool>();
        final ads = _FakeAdsController(
          supported: true,
          adsReady: true,
          rewardedReady: true,
          onShowRewarded: () => rewarded.future,
        );
        addTearDown(engine.dispose);
        addTearDown(ads.dispose);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.binding.setSurfaceSize(const Size(390, 844));
        await tester.pumpWidget(
          MobileAdsScope(
            controller: ads,
            child: MaterialApp(
              home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 1400));

        expect(ads.rewardedPreloadCount, greaterThanOrEqualTo(1));

        final playAgain = find.byKey(const ValueKey('victory-play-again'));
        await tester.tap(playAgain);
        await tester.pump();

        expect(ads.rewardedShowCount, 1);
        expect(find.byKey(const ValueKey('victory-celebration')), findsOne);
        expect(tester.widget<FilledButton>(playAgain).onPressed, isNull);

        rewarded.complete(false);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(ads.rewardedShowCount, 1);
        expect(find.byKey(const ValueKey('victory-celebration')), findsNothing);
        expect(find.byKey(const ValueKey('game-board')), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('Back to Home waits for its rewarded ad before navigating', (
      tester,
    ) async {
      final engine = _finishedVictoryEngine();
      final rewarded = Completer<bool>();
      final ads = _FakeAdsController(
        supported: true,
        adsReady: true,
        rewardedReady: true,
        onShowRewarded: () => rewarded.future,
      );
      addTearDown(engine.dispose);
      addTearDown(ads.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        MobileAdsScope(
          controller: ads,
          child: MaterialApp(
            home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
            routes: {
              '/home': (_) => const Scaffold(
                body: SizedBox(key: ValueKey('home-route-marker')),
              ),
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1400));

      final home = find.byKey(const ValueKey('victory-home'));
      await tester.tap(home);
      await tester.pump();

      expect(ads.rewardedShowCount, 1);
      expect(find.byKey(const ValueKey('home-route-marker')), findsNothing);
      expect(tester.widget<OutlinedButton>(home).onPressed, isNull);

      rewarded.complete(true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(ads.rewardedShowCount, 1);
      expect(find.byKey(const ValueKey('home-route-marker')), findsOneWidget);
      expect(find.byType(GameScreen), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('desktop/no-op hosts navigate without requesting a reward', (
      tester,
    ) async {
      final engine = _finishedVictoryEngine();
      final ads = _FakeAdsController(supported: false, adsReady: false);
      addTearDown(engine.dispose);
      addTearDown(ads.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        MobileAdsScope(
          controller: ads,
          child: MaterialApp(
            home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1400));
      await tester.tap(find.byKey(const ValueKey('victory-play-again')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(ads.rewardedShowCount, 0);
      expect(find.byKey(const ValueKey('victory-celebration')), findsNothing);
      expect(find.byKey(const ValueKey('game-board')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('rewarded ads are warmed when a match opens and app resumes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final engine = GameEngine();
    final ads = _FakeAdsController(
      supported: true,
      adsReady: true,
      rewardedReady: false,
    );
    addTearDown(engine.dispose);
    addTearDown(ads.dispose);

    await tester.pumpWidget(
      MobileAdsScope(
        controller: ads,
        child: MaterialApp(
          home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
        ),
      ),
    );
    await tester.pump();

    expect(ads.rewardedPreloadCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(ads.rewardedPreloadCount, 2);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'app shell warms rewarded ads again after returning to foreground',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final ads = _FakeAdsController(supported: true, adsReady: true);

      await tester.pumpWidget(ParchesePopApp(adsController: ads));
      await tester.pump(const Duration(milliseconds: 200));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(ads.rewardedPreloadCount, 1);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  group('ShopScreen rewarded coins integration', () {
    testWidgets('adds exactly 100 coins after an earned mobile reward', (
      tester,
    ) async {
      final harness = await _pumpRewardedShop(tester, rewardedResult: true);
      final startingBalance = harness.wallet.balance;

      await tester.ensureVisible(
        find.byKey(const ValueKey('shop-rewarded-coins')),
      );
      await tester.tap(find.byKey(const ValueKey('shop-rewarded-coins')));
      await tester.pumpAndSettle();

      expect(harness.ads.rewardedShowCount, 1);
      expect(harness.wallet.balance, startingBalance + 100);

      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });

    testWidgets('does not add coins when the mobile reward was not earned', (
      tester,
    ) async {
      final harness = await _pumpRewardedShop(tester, rewardedResult: false);
      final startingBalance = harness.wallet.balance;

      await tester.ensureVisible(
        find.byKey(const ValueKey('shop-rewarded-coins')),
      );
      await tester.tap(find.byKey(const ValueKey('shop-rewarded-coins')));
      await tester.pumpAndSettle();

      expect(harness.ads.rewardedShowCount, 1);
      expect(harness.wallet.balance, startingBalance);

      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });
  });
}

Widget _testApp(AppAdsController controller) {
  return MaterialApp(
    home: MobileAdShell(
      controller: controller,
      child: const ColoredBox(
        key: ValueKey('screen-content'),
        color: Colors.white,
      ),
    ),
  );
}

void _configureIPhone14View(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
  tester.binding.platformDispatcher.localeTestValue = const Locale('es');
  addTearDown(tester.view.reset);
  addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
}

Widget _insetTestApp(AppAdsController controller) {
  return MaterialApp(
    home: MobileAdShell(
      controller: controller,
      child: Builder(
        key: const ValueKey('content-padding-probe'),
        builder: (context) => const SafeArea(
          child: ColoredBox(
            key: ValueKey('safe-screen-content'),
            color: Colors.white,
          ),
        ),
      ),
    ),
  );
}

Future<_RewardedShopHarness> _pumpRewardedShop(
  WidgetTester tester, {
  required bool rewardedResult,
}) async {
  SharedPreferences.setMockInitialValues({
    'parchesepop.wallet.balance.v1': 250,
  });
  final preferences = await SharedPreferences.getInstance();
  final wallet = await WalletController.create(preferences: preferences);
  final ads = _FakeAdsController(
    supported: true,
    adsReady: true,
    rewardedReady: true,
    rewardedResult: rewardedResult,
  );

  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: MobileAdsScope(
        controller: ads,
        child: ShopScreen(wallet: wallet, showTestCoinControls: false),
      ),
    ),
  );
  await tester.pump();

  expect(find.byKey(const ValueKey('shop-rewarded-coins')), findsOneWidget);
  return _RewardedShopHarness(wallet: wallet, ads: ads);
}

class _RewardedShopHarness {
  const _RewardedShopHarness({required this.wallet, required this.ads});

  final WalletController wallet;
  final _FakeAdsController ads;

  void dispose() {
    wallet.dispose();
    ads.dispose();
  }
}

class _FakeAdsController extends AppAdsController {
  _FakeAdsController({
    required this.supported,
    required bool adsReady,
    this.rewardedReady = false,
    this.rewardedResult = false,
    this.onShowRewarded,
  }) : _adsReady = adsReady;

  @override
  final bool supported;

  bool _adsReady;

  @override
  bool get adsReady => _adsReady;

  @override
  final bool rewardedReady;

  @override
  bool get privacyOptionsRequired => false;

  final bool rewardedResult;
  final Future<bool> Function()? onShowRewarded;
  int rewardedShowCount = 0;
  int rewardedPreloadCount = 0;

  void setAdsReady(bool value) {
    if (_adsReady == value) return;
    _adsReady = value;
    notifyListeners();
  }

  @override
  Widget buildBanner(BuildContext context) {
    return const SizedBox(
      key: ValueKey('fake-mobile-banner'),
      height: 50,
      child: Text('TEST AD'),
    );
  }

  @override
  Future<void> initialize() async {}

  @override
  void preloadRewarded() {
    rewardedPreloadCount += 1;
  }

  @override
  Future<bool> showRewarded() async {
    rewardedShowCount += 1;
    if (onShowRewarded != null) return onShowRewarded!();
    return rewardedResult;
  }

  @override
  Future<void> showPrivacyOptions() async {}
}

GameEngine _finishedVictoryEngine() {
  final engine = GameEngine();
  for (final token in engine.currentPlayer.tokens) {
    token.progress = GameEngine.finishProgress;
  }
  engine
    ..winner = engine.currentPlayer
    ..gameOver = true
    ..hasRolled = false
    ..remainingDice.clear();
  return engine;
}
