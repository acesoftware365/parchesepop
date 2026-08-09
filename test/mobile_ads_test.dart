import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:parchesepop/game_analytics.dart';
import 'package:parchesepop/game_guide.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart'
    show
        GameScreen,
        MatchmakingScreen,
        ParchesePopApp,
        PlayerProfile,
        ShopScreen;
import 'package:parchesepop/mobile_ads.dart';
import 'package:parchesepop/player_progression.dart';
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

  group('anchored adaptive banner sizing', () {
    test('uses the full safe width and native optimized height', () async {
      int? requestedWidth;

      final size = await resolveAnchoredAdaptiveBannerSize(
        390,
        loadAdaptive: (width) async {
          requestedWidth = width;
          return AdSize(width: width, height: 60);
        },
      );

      expect(requestedWidth, 390);
      expect(size?.width, 390);
      expect(size?.height, 60);
    });

    test('fixed fallback never exceeds the available width', () async {
      for (final expectation in <(int, int?, int?)>[
        (280, null, null),
        (320, 320, 50),
        (390, 320, 50),
        (468, 468, 60),
        (600, 468, 60),
        (728, 468, 60),
      ]) {
        final size = await resolveAnchoredAdaptiveBannerSize(
          expectation.$1,
          loadAdaptive: (_) async => null,
        );
        expect(size?.width, expectation.$2);
        expect(size?.height, expectation.$3);
        expect(size?.width ?? 0, lessThanOrEqualTo(expectation.$1));
      }
    });

    testWidgets('reloads at the new full width after rotation', (tester) async {
      final requestedWidths = <int>[];
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(390, 844));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const Expanded(child: SizedBox.shrink()),
                AdaptiveMobileBanner(
                  adUnitId: 'test-ad-unit',
                  sizeLoader: (width) async {
                    requestedWidths.add(width);
                    return AdSize(width: width, height: width < 500 ? 60 : 90);
                  },
                  contentBuilder: (context, size) => const ColoredBox(
                    key: ValueKey('adaptive-test-creative'),
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      var slot = tester.getRect(
        find.byKey(const ValueKey('mobile-ad-banner-slot')),
      );
      var creative = tester.getRect(
        find.byKey(const ValueKey('adaptive-test-creative')),
      );
      expect(requestedWidths, [390]);
      expect(slot.size, const Size(390, 60));
      expect(creative.size, const Size(390, 60));

      await tester.binding.setSurfaceSize(const Size(844, 390));
      await tester.pump();
      await tester.pumpAndSettle();

      slot = tester.getRect(
        find.byKey(const ValueKey('mobile-ad-banner-slot')),
      );
      creative = tester.getRect(
        find.byKey(const ValueKey('adaptive-test-creative')),
      );
      expect(requestedWidths, [390, 844]);
      expect(slot.size, const Size(844, 90));
      expect(creative.size, const Size(844, 90));
      expect(tester.takeException(), isNull);
    });

    testWidgets('reloads when orientation changes at the same width', (
      tester,
    ) async {
      var requestCount = 0;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const Expanded(child: SizedBox.shrink()),
                AdaptiveMobileBanner(
                  adUnitId: 'test-ad-unit',
                  sizeLoader: (width) async {
                    requestCount += 1;
                    return AdSize(width: width, height: 50 + requestCount * 10);
                  },
                  contentBuilder: (context, size) => const ColoredBox(
                    key: ValueKey('same-width-adaptive-creative'),
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(requestCount, 1);

      tester.view.physicalSize = const Size(390, 300);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(requestCount, 2);
      expect(
        tester.getSize(find.byKey(const ValueKey('mobile-ad-banner-slot'))),
        const Size(390, 70),
      );
      expect(tester.takeException(), isNull);
    });
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
      'focused screens suppress banner space until every blocker is removed',
      (tester) async {
        final controller = _FakeAdsController(supported: true, adsReady: true);

        await tester.pumpWidget(_testApp(controller, suppressionDepth: 2));
        await tester.pump();
        expect(find.byKey(const ValueKey('fake-mobile-banner')), findsNothing);
        expect(
          find.byKey(const ValueKey('version-above-ad-banner')),
          findsNothing,
        );

        await tester.pumpWidget(_testApp(controller, suppressionDepth: 1));
        await tester.pump();
        expect(find.byKey(const ValueKey('fake-mobile-banner')), findsNothing);

        await tester.pumpWidget(_testApp(controller));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('fake-mobile-banner')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('version-above-ad-banner')),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );

    testWidgets('guide, lab and matchmaking keep one global bottom banner', (
      tester,
    ) async {
      final controller = _FakeAdsController(supported: true, adsReady: true);

      for (final screen in <Widget>[
        const GameGuideScreen(),
        const TrapPowerLabScreen(),
        const MatchmakingScreen(
          profile: PlayerProfile.guest,
          mode: GameMode.traditional,
        ),
      ]) {
        await tester.pumpWidget(_focusedScreenApp(controller, screen));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('fake-mobile-banner')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('version-above-ad-banner')),
          findsOneWidget,
        );
      }

      await tester.pumpWidget(_testApp(controller));
      await tester.pump();
      expect(find.byKey(const ValueKey('fake-mobile-banner')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });

    testWidgets(
      'iPhone game board and controls stay above the banner and usable',
      (tester) async {
        _configureIPhone14View(tester);
        SharedPreferences.setMockInitialValues({});
        final controller = _FakeAdsController(supported: true, adsReady: true);
        final engine = GameEngine();
        addTearDown(engine.dispose);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _gameScreenAdApp(controller: controller, engine: engine),
        );
        await tester.pump(const Duration(milliseconds: 200));

        final bannerFinder = find.byKey(const ValueKey('fake-mobile-banner'));
        final versionFinder = find.byKey(
          const ValueKey('version-above-ad-banner'),
        );
        final boardFinder = find.byKey(const ValueKey('game-board'));
        final backFinder = find.byKey(const ValueKey('game-back-button'));
        final diceFinder = find.byKey(const ValueKey('dice-roll-target'));

        expect(bannerFinder, findsOneWidget);
        expect(versionFinder, findsOneWidget);
        expect(boardFinder, findsOneWidget);
        expect(backFinder.hitTestable(), findsOneWidget);
        expect(diceFinder.hitTestable(), findsOneWidget);

        final banner = tester.getRect(bannerFinder);
        for (final content in <Finder>[boardFinder, backFinder, diceFinder]) {
          expect(tester.getRect(content).bottom, lessThanOrEqualTo(banner.top));
        }
        expect(
          tester.getRect(versionFinder).bottom,
          lessThanOrEqualTo(banner.top),
        );
        expect(controller.rewardedShowCount, 0);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'a taller adaptive banner shrinks only the HUD, never the board',
      (tester) async {
        _configureIPhone14View(tester);
        SharedPreferences.setMockInitialValues({});
        Rect? regularBoard;
        Rect? regularHud;

        for (final bannerHeight in <double>[50, 100]) {
          final controller = _FakeAdsController(
            supported: true,
            adsReady: true,
            bannerHeight: bannerHeight,
          );
          final engine = GameEngine();
          await tester.pumpWidget(
            _gameScreenAdApp(controller: controller, engine: engine),
          );
          await tester.pump(const Duration(milliseconds: 200));

          final board = tester.getRect(
            find.byKey(const ValueKey('game-board')),
          );
          final hud = tester.getRect(
            find.byKey(const ValueKey('portrait-game-hud')),
          );
          final banner = tester.getRect(
            find.byKey(const ValueKey('fake-mobile-banner')),
          );
          expect(board.size, const Size.square(390));
          expect(hud.bottom, lessThanOrEqualTo(banner.top));
          expect(tester.takeException(), isNull);

          if (regularBoard == null) {
            regularBoard = board;
            regularHud = hud;
          } else {
            expect(board.left, closeTo(regularBoard.left, .5));
            expect(board.top, closeTo(regularBoard.top, .5));
            expect(board.size, regularBoard.size);
            expect(hud.height, lessThan(regularHud!.height));
          }

          await tester.pumpWidget(const SizedBox.shrink());
          engine.dispose();
          controller.dispose();
        }
      },
    );

    testWidgets(
      'a short iPhone keeps the full board and essential HUD above a tall banner',
      (tester) async {
        _configureIPhoneSEView(tester);
        SharedPreferences.setMockInitialValues({});
        final controller = _FakeAdsController(
          supported: true,
          adsReady: true,
          bannerHeight: 100,
        );
        final engine = GameEngine(mode: GameMode.chaos);
        addTearDown(engine.dispose);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _gameScreenAdApp(controller: controller, engine: engine),
        );
        await tester.pump(const Duration(milliseconds: 250));

        final board = tester.getRect(find.byKey(const ValueKey('game-board')));
        final hud = tester.getRect(
          find.byKey(const ValueKey('portrait-game-hud')),
        );
        final banner = tester.getRect(
          find.byKey(const ValueKey('fake-mobile-banner')),
        );
        final dice = find.byKey(const ValueKey('dice-roll-target'));
        final minimap = find.byKey(const ValueKey('mobile-board-navigator'));

        expect(board.size, const Size.square(375));
        expect(hud.bottom, lessThanOrEqualTo(banner.top));
        expect(dice.hitTestable(), findsOneWidget);
        expect(minimap.hitTestable(), findsOneWidget);
        expect(tester.getRect(dice).bottom, lessThanOrEqualTo(hud.bottom));
        expect(tester.getRect(minimap).bottom, lessThanOrEqualTo(hud.bottom));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

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
      'landscape banner respects both notch sides and its adaptive height',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(844, 390);
        tester.view.padding = const FakeViewPadding(
          left: 47,
          right: 47,
          bottom: 21,
        );
        tester.view.viewPadding = const FakeViewPadding(
          left: 47,
          right: 47,
          bottom: 21,
        );
        addTearDown(tester.view.reset);
        final controller = _FakeAdsController(
          supported: true,
          adsReady: true,
          bannerHeight: 60,
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(_insetTestApp(controller));

        final banner = tester.getRect(
          find.byKey(const ValueKey('fake-mobile-banner')),
        );
        final version = tester.getRect(
          find.byKey(const ValueKey('version-above-ad-banner')),
        );
        expect(banner.left, 47);
        expect(banner.right, 797);
        expect(banner.height, 60);
        expect(banner.bottom, lessThanOrEqualTo(369));
        expect(version.bottom, lessThanOrEqualTo(banner.top));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
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

    testWidgets(
      'iPhone home controls remain reachable above the bottom banner',
      (tester) async {
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

        for (final label in const [
          'QUICK POP',
          'MESA RÁPIDA',
          'CONTRA CPU',
          'Tienda',
          'Mi perfil',
          'Cómo jugar',
          'Trampas',
        ]) {
          final text = find.text(label);
          expect(text, findsOneWidget);
          await tester.ensureVisible(text);
          await tester.pumpAndSettle();
          final tappable = find
              .ancestor(of: text, matching: find.byType(InkWell))
              .first;
          expect(tappable, findsOneWidget);
          final rect = tester.getRect(tappable);
          final banner = tester.getRect(
            find.byKey(const ValueKey('fake-mobile-banner')),
          );
          expect(rect.top, greaterThanOrEqualTo(47));
          expect(rect.bottom, lessThanOrEqualTo(banner.top));
          expect(tappable.hitTestable(), findsOneWidget);
        }

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });

  group('rewarded result contract', () {
    for (final result in RewardedAdResult.values) {
      test(
        '${result.name} remains distinct and maps to the legacy bool',
        () async {
          final typedController = _FakeAdsController(
            supported: true,
            adsReady: true,
            rewardedReady: true,
            rewardedResult: result,
          );
          final compatibilityController = _FakeAdsController(
            supported: true,
            adsReady: true,
            rewardedReady: true,
            rewardedResult: result,
          );

          expect(await typedController.showRewardedWithResult(), result);
          expect(
            await compatibilityController.showRewarded(),
            result == RewardedAdResult.earned,
          );
          expect(typedController.rewardedShowCount, 1);
          expect(compatibilityController.rewardedShowCount, 1);

          typedController.dispose();
          compatibilityController.dispose();
        },
      );
    }

    test('NoopAppAdsController reports unavailable and never grants', () async {
      final controller = NoopAppAdsController();

      controller.preloadRewarded();
      expect(controller.rewardedReady, isFalse);
      expect(
        await controller.showRewardedWithResult(),
        RewardedAdResult.unavailable,
      );
      expect(await controller.showRewarded(), isFalse);

      controller.dispose();
    });
  });

  group('victory navigation is never gated by ads', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('Play Again starts immediately without showing a rewarded ad', (
      tester,
    ) async {
      final engine = _finishedVictoryEngine();
      final ads = _FakeAdsController(
        supported: true,
        adsReady: true,
        rewardedReady: true,
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
      await tester.pump(const Duration(seconds: 1));

      expect(ads.rewardedShowCount, 0);
      expect(find.byKey(const ValueKey('victory-celebration')), findsNothing);
      expect(find.byKey(const ValueKey('game-board')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Back to Home navigates immediately without showing an ad', (
      tester,
    ) async {
      final engine = _finishedVictoryEngine();
      final ads = _FakeAdsController(
        supported: true,
        adsReady: true,
        rewardedReady: true,
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
      await tester.pump(const Duration(seconds: 1));

      expect(ads.rewardedShowCount, 0);
      expect(find.byKey(const ValueKey('home-route-marker')), findsOneWidget);
      expect(find.byType(GameScreen), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'iPhone final results keep Back to Home visible above the banner',
      (tester) async {
        _configureIPhone14View(tester);
        final engine = _completedMatch();
        final ads = _FakeAdsController(
          supported: true,
          adsReady: true,
          rewardedReady: true,
        );
        addTearDown(engine.dispose);
        addTearDown(ads.dispose);

        await tester.pumpWidget(
          MobileAdsScope(
            controller: ads,
            child: MaterialApp(
              builder: (context, child) => MobileAdShell(
                controller: ads,
                child: child ?? const SizedBox.shrink(),
              ),
              home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
              routes: {
                '/home': (_) => const Scaffold(
                  body: SizedBox(key: ValueKey('home-route-marker')),
                ),
              },
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 1900));

        final celebration = find.byKey(const ValueKey('victory-celebration'));
        final home = find.byKey(const ValueKey('victory-home'));
        final version = find.byKey(const ValueKey('version-above-ad-banner'));
        expect(celebration, findsOneWidget);
        expect(find.byKey(const ValueKey('final-ranking')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('fake-mobile-banner')),
          findsOneWidget,
        );
        expect(home.hitTestable(), findsOneWidget);
        expect(tester.getRect(home).height, greaterThanOrEqualTo(44));
        expect(
          tester.getRect(home).bottom,
          lessThanOrEqualTo(tester.getRect(version).top),
        );

        final scrollable = find.descendant(
          of: celebration,
          matching: find.byType(Scrollable),
        );
        expect(scrollable, findsOneWidget);
        final scrollState = tester.state<ScrollableState>(scrollable);
        expect(scrollState.position.pixels, 0);
        expect(scrollState.position.maxScrollExtent, 0);

        await tester.tap(home);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(ads.rewardedShowCount, 0);
        expect(find.byKey(const ValueKey('home-route-marker')), findsOneWidget);
        expect(find.byType(GameScreen), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'iPhone first-place result keeps every action visible without scrolling',
      (tester) async {
        _configureIPhone14View(tester);
        final engine = _firstWinnerMatch();
        final ads = _FakeAdsController(
          supported: true,
          adsReady: true,
          rewardedReady: true,
        );
        addTearDown(engine.dispose);
        addTearDown(ads.dispose);

        await tester.pumpWidget(
          MobileAdsScope(
            controller: ads,
            child: MaterialApp(
              builder: (context, child) => MobileAdShell(
                controller: ads,
                child: child ?? const SizedBox.shrink(),
              ),
              home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 1900));

        final celebration = find.byKey(const ValueKey('victory-celebration'));
        final version = find.byKey(const ValueKey('version-above-ad-banner'));
        expect(
          find.byKey(const ValueKey('victory-action-dock')),
          findsOneWidget,
        );
        for (final key in const [
          ValueKey('victory-continue-watching'),
          ValueKey('victory-play-again'),
          ValueKey('victory-home'),
        ]) {
          final action = find.byKey(key);
          expect(action.hitTestable(), findsOneWidget);
          expect(tester.getRect(action).height, greaterThanOrEqualTo(44));
          expect(
            tester.getRect(action).bottom,
            lessThanOrEqualTo(tester.getRect(version).top),
          );
        }

        final scrollable = find.descendant(
          of: celebration,
          matching: find.byType(Scrollable),
        );
        expect(scrollable, findsOneWidget);
        final scrollState = tester.state<ScrollableState>(scrollable);
        expect(scrollState.position.pixels, 0);
        expect(scrollState.position.maxScrollExtent, 0);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'iPhone first place pins earned coins and optional ad above every action',
      (tester) async {
        _configureIPhone14View(tester);
        SharedPreferences.setMockInitialValues({});
        final engine = _firstWinnerMatch();
        final wallet = await WalletController.create();
        final progression = await PlayerProgressionController.create();
        final ads = _FakeAdsController(
          supported: true,
          adsReady: true,
          rewardedReady: true,
          rewardedResult: RewardedAdResult.earned,
        );
        addTearDown(engine.dispose);
        addTearDown(wallet.dispose);
        addTearDown(progression.dispose);
        addTearDown(ads.dispose);

        await tester.pumpWidget(
          MobileAdsScope(
            controller: ads,
            child: MaterialApp(
              builder: (context, child) => MobileAdShell(
                controller: ads,
                child: child ?? const SizedBox.shrink(),
              ),
              home: GameScreen(
                opponent: 'CPU • Fácil',
                gameEngine: engine,
                wallet: wallet,
                progression: progression,
                analyticsMatchRef: 'pinned_reward_match',
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 1900));

        expect(wallet.balance, 370);
        expect(find.text('+120 MONEDAS'), findsOneWidget);
        expect(find.text('POR JUGAR'), findsOneWidget);
        expect(find.text('+70 EXTRA'), findsOneWidget);
        expect(find.text('VER ANUNCIO'), findsOneWidget);
        expect(ads.rewardedShowCount, 0);

        final version = find.byKey(const ValueKey('version-above-ad-banner'));
        for (final key in const [
          ValueKey('victory-early-rewarded-ad'),
          ValueKey('victory-continue-watching'),
          ValueKey('victory-play-again'),
          ValueKey('victory-home'),
        ]) {
          final action = find.byKey(key);
          expect(action, findsOneWidget);
          expect(action.hitTestable(), findsOneWidget);
          expect(tester.getRect(action).height, greaterThanOrEqualTo(44));
          expect(
            tester.getRect(action).bottom,
            lessThanOrEqualTo(tester.getRect(version).top),
          );
        }

        final scrollable = find.descendant(
          of: find.byKey(const ValueKey('victory-celebration')),
          matching: find.byType(Scrollable),
        );
        expect(scrollable, findsOneWidget);
        final scrollState = tester.state<ScrollableState>(scrollable);
        expect(scrollState.position.pixels, 0);
        expect(scrollState.position.maxScrollExtent, 0);
        expect(
          tester.getRect(find.byKey(const ValueKey('victory-card'))).bottom,
          lessThanOrEqualTo(
            tester
                .getRect(find.byKey(const ValueKey('victory-action-dock')))
                .top,
          ),
        );

        await tester.tap(
          find.byKey(const ValueKey('victory-early-rewarded-ad')),
        );
        await tester.pump(const Duration(milliseconds: 120));

        expect(ads.rewardedShowCount, 1);
        expect(wallet.balance, 440);
        expect(find.text('+70 MONEDAS'), findsOneWidget);
        expect(find.text('EXTRA RECIBIDAS'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('victory-early-rewarded-ad')),
          findsNothing,
        );
        expect(scrollState.position.maxScrollExtent, 0);
        for (final key in const [
          ValueKey('victory-continue-watching'),
          ValueKey('victory-play-again'),
          ValueKey('victory-home'),
        ]) {
          expect(find.byKey(key).hitTestable(), findsOneWidget);
        }

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'restored completed match never reoffers an already claimed reward',
      (tester) async {
        _configureIPhone14View(tester);
        SharedPreferences.setMockInitialValues({});
        final firstEngine = _firstWinnerMatch();
        final restoredEngine = _firstWinnerMatch();
        final wallet = await WalletController.create();
        final progression = await PlayerProgressionController.create();
        final ads = _FakeAdsController(
          supported: true,
          adsReady: true,
          rewardedReady: true,
          rewardedResult: RewardedAdResult.earned,
        );
        addTearDown(firstEngine.dispose);
        addTearDown(restoredEngine.dispose);
        addTearDown(wallet.dispose);
        addTearDown(progression.dispose);
        addTearDown(ads.dispose);

        Widget resultScreen(GameEngine engine) => MobileAdsScope(
          controller: ads,
          child: MaterialApp(
            builder: (context, child) => MobileAdShell(
              controller: ads,
              child: child ?? const SizedBox.shrink(),
            ),
            home: GameScreen(
              opponent: 'CPU • Fácil',
              gameEngine: engine,
              wallet: wallet,
              progression: progression,
              analyticsMatchRef: 'restored_claimed_reward_match',
            ),
          ),
        );

        await tester.pumpWidget(resultScreen(firstEngine));
        await tester.pump(const Duration(milliseconds: 1900));
        await tester.tap(
          find.byKey(const ValueKey('victory-early-rewarded-ad')),
        );
        await tester.pump(const Duration(milliseconds: 120));

        expect(wallet.balance, 440);
        expect(ads.rewardedShowCount, 1);
        expect(
          progression.rewardedDoubleClaimed('restored_claimed_reward_match'),
          isTrue,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pumpWidget(resultScreen(restoredEngine));
        await tester.pump(const Duration(milliseconds: 1900));

        expect(wallet.balance, 440);
        expect(ads.rewardedShowCount, 1);
        expect(find.text('+120 MONEDAS'), findsOneWidget);
        expect(find.text('+70 MONEDAS'), findsOneWidget);
        expect(find.text('EXTRA RECIBIDAS'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('victory-early-rewarded-ad')),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'iPhone final standings pin earned coins and optional ad without overlap',
      (tester) async {
        _configureIPhone14View(tester);
        SharedPreferences.setMockInitialValues({});
        final engine = _completedMatch();
        final wallet = await WalletController.create();
        final progression = await PlayerProgressionController.create();
        final ads = _FakeAdsController(
          supported: true,
          adsReady: true,
          rewardedReady: true,
        );
        addTearDown(engine.dispose);
        addTearDown(wallet.dispose);
        addTearDown(progression.dispose);
        addTearDown(ads.dispose);

        await tester.pumpWidget(
          MobileAdsScope(
            controller: ads,
            child: MaterialApp(
              builder: (context, child) => MobileAdShell(
                controller: ads,
                child: child ?? const SizedBox.shrink(),
              ),
              home: GameScreen(
                opponent: 'CPU • Fácil',
                gameEngine: engine,
                wallet: wallet,
                progression: progression,
                analyticsMatchRef: 'final_pinned_reward_match',
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 1900));

        expect(wallet.balance, 370);
        expect(
          find.byKey(const ValueKey('victory-earned-reward')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('victory-rewarded-ad')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('final-ranking')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('victory-continue-watching')),
          findsNothing,
        );

        final celebration = find.byKey(const ValueKey('victory-celebration'));
        final scrollable = find.descendant(
          of: celebration,
          matching: find.byType(Scrollable),
        );
        final scrollState = tester.state<ScrollableState>(scrollable);
        expect(scrollState.position.maxScrollExtent, 0);
        expect(
          tester.getRect(find.byKey(const ValueKey('victory-card'))).bottom,
          lessThanOrEqualTo(
            tester
                .getRect(find.byKey(const ValueKey('victory-action-dock')))
                .top,
          ),
        );
        for (final key in const [
          ValueKey('victory-rewarded-ad'),
          ValueKey('victory-play-again'),
          ValueKey('victory-home'),
        ]) {
          expect(find.byKey(key).hitTestable(), findsOneWidget);
        }

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('never offers a rewarded result without a wallet', (
      tester,
    ) async {
      _configureIPhone14View(tester);
      final engine = _completedMatch();
      final ads = _FakeAdsController(
        supported: true,
        adsReady: true,
        rewardedReady: true,
      );
      final analytics = _RecordingTypedAnalytics();
      addTearDown(engine.dispose);
      addTearDown(ads.dispose);

      await tester.pumpWidget(
        MobileAdsScope(
          controller: ads,
          child: MaterialApp(
            home: GameScreen(
              opponent: 'CPU • Fácil',
              gameEngine: engine,
              analytics: analytics,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1900));

      expect(find.byKey(const ValueKey('victory-rewarded-ad')), findsNothing);
      expect(ads.rewardedShowCount, 0);
      expect(analytics.events.whereType<RewardedAdEvent>(), isEmpty);

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

  testWidgets('post-match reward is voluntary and credits coins once', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'parchesepop.wallet.balance.v1': 250,
    });
    final engine = _completedMatch();
    final wallet = await WalletController.create();
    final analytics = _RecordingTypedAnalytics();
    final ads = _FakeAdsController(
      supported: true,
      adsReady: true,
      rewardedReady: true,
      rewardedResult: RewardedAdResult.earned,
    );
    addTearDown(engine.dispose);
    addTearDown(wallet.dispose);
    addTearDown(ads.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MobileAdsScope(
        controller: ads,
        child: MaterialApp(
          home: GameScreen(
            opponent: 'CPU • Fácil',
            gameEngine: engine,
            wallet: wallet,
            analytics: analytics,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1900));

    expect(wallet.balance, 250);
    expect(ads.rewardedShowCount, 0);
    await tester.tap(find.byKey(const ValueKey('victory-rewarded-ad')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(ads.rewardedShowCount, 1);
    expect(wallet.balance, 350);
    expect(
      analytics.events.whereType<RewardedAdEvent>().map((event) => event.stage),
      containsAllInOrder(<RewardedAdStage>[
        RewardedAdStage.offered,
        RewardedAdStage.started,
        RewardedAdStage.completed,
      ]),
    );
    expect(analytics.events.whereType<CurrencyEvent>(), hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
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

  testWidgets(
    'double-tapping resume opens one saved match with banner and no forced ad',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'active_match_board_layout_version': 4,
        'active_match_checkpoint':
            '{"savedAt":"2026-08-08T01:00:00Z",'
            '"analyticsMatchRef":"resume_test_match",'
            '"mode":"traditional","cpuLevel":"Normal",'
            '"opponent":"CPU • Normal","elapsedSeconds":12,'
            '"turn":1,"currentPlayer":"red","dice":[1,1],'
            '"remainingDice":[],"hasRolled":false,"players":[]}',
      });
      final ads = _FakeAdsController(supported: true, adsReady: true);

      await tester.pumpWidget(ParchesePopApp(adsController: ads));
      for (var attempt = 0; attempt < 30; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find
            .byKey(const ValueKey('resume-saved-match-button'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }

      final resumeButton = tester.widget<InkWell>(
        find.byKey(const ValueKey('resume-saved-match-button')),
      );
      resumeButton.onTap!();
      resumeButton.onTap!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(GameScreen), findsOneWidget);
      expect(ads.rewardedShowCount, 0);
      expect(find.byKey(const ValueKey('fake-mobile-banner')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('version-above-ad-banner')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  group('ShopScreen rewarded coins integration', () {
    for (final result in RewardedAdResult.values) {
      testWidgets('${result.name} maps to exact metrics and coin balance', (
        tester,
      ) async {
        final harness = await _pumpRewardedShop(tester, rewardedResult: result);
        final startingBalance = harness.wallet.balance;

        await tester.ensureVisible(
          find.byKey(const ValueKey('shop-rewarded-coins')),
        );
        await tester.tap(find.byKey(const ValueKey('shop-rewarded-coins')));
        await tester.pumpAndSettle();

        expect(harness.ads.rewardedShowCount, 1);
        expect(
          harness.wallet.balance,
          startingBalance + (result == RewardedAdResult.earned ? 100 : 0),
        );
        final expectedStage = switch (result) {
          RewardedAdResult.earned => RewardedAdStage.completed,
          RewardedAdResult.dismissed => RewardedAdStage.declined,
          RewardedAdResult.unavailable => RewardedAdStage.unavailable,
          RewardedAdResult.failed => RewardedAdStage.failed,
        };
        expect(
          harness.analytics.events.whereType<RewardedAdEvent>().map(
            (event) => event.stage,
          ),
          containsAllInOrder(<RewardedAdStage>[
            RewardedAdStage.offered,
            RewardedAdStage.started,
            expectedStage,
          ]),
        );
        expect(
          harness.analytics.events.whereType<CurrencyEvent>(),
          result == RewardedAdResult.earned ? hasLength(1) : isEmpty,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        harness.dispose();
      });
    }
  });
}

Widget _testApp(AppAdsController controller, {int suppressionDepth = 0}) {
  Widget content = const ColoredBox(
    key: ValueKey('screen-content'),
    color: Colors.white,
  );
  for (var index = 0; index < suppressionDepth; index++) {
    content = SuppressMobileAdBanner(
      key: ValueKey('banner-suppressor-$index'),
      child: content,
    );
  }
  return MobileAdsScope(
    controller: controller,
    child: MaterialApp(
      home: MobileAdShell(controller: controller, child: content),
    ),
  );
}

Widget _focusedScreenApp(AppAdsController controller, Widget screen) {
  return MobileAdsScope(
    controller: controller,
    child: MaterialApp(
      home: MobileAdShell(controller: controller, child: screen),
    ),
  );
}

Widget _gameScreenAdApp({
  required AppAdsController controller,
  required GameEngine engine,
}) {
  return MobileAdsScope(
    controller: controller,
    child: MaterialApp(
      home: MobileAdShell(
        controller: controller,
        child: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
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

void _configureIPhoneSEView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(375, 667);
  tester.view.padding = const FakeViewPadding(top: 20);
  tester.view.viewPadding = const FakeViewPadding(top: 20);
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
  required RewardedAdResult rewardedResult,
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
  final analytics = _RecordingTypedAnalytics();

  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: MobileAdsScope(
        controller: ads,
        child: ShopScreen(
          wallet: wallet,
          showTestCoinControls: false,
          analytics: analytics,
        ),
      ),
    ),
  );
  await tester.pump();

  expect(find.byKey(const ValueKey('shop-rewarded-coins')), findsOneWidget);
  return _RewardedShopHarness(wallet: wallet, ads: ads, analytics: analytics);
}

class _RewardedShopHarness {
  const _RewardedShopHarness({
    required this.wallet,
    required this.ads,
    required this.analytics,
  });

  final WalletController wallet;
  final _FakeAdsController ads;
  final _RecordingTypedAnalytics analytics;

  void dispose() {
    wallet.dispose();
    ads.dispose();
  }
}

class _RecordingTypedAnalytics implements TypedGameAnalytics {
  final events = <GameAnalyticsEvent>[];

  @override
  Future<void> logEvent(GameAnalyticsEvent event) async {
    events.add(event);
  }

  @override
  Future<void> logMatchStarted(MatchStartEvent event) => logEvent(event);
}

class _FakeAdsController extends AppAdsController {
  _FakeAdsController({
    required this.supported,
    required bool adsReady,
    this.rewardedReady = false,
    this.rewardedResult = RewardedAdResult.dismissed,
    this.bannerHeight = 50,
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

  final RewardedAdResult rewardedResult;
  final double bannerHeight;
  int rewardedShowCount = 0;
  int rewardedPreloadCount = 0;

  void setAdsReady(bool value) {
    if (_adsReady == value) return;
    _adsReady = value;
    notifyListeners();
  }

  @override
  Widget buildBanner(BuildContext context) {
    return SizedBox(
      key: const ValueKey('fake-mobile-banner'),
      width: double.infinity,
      height: bannerHeight,
      child: const Text('TEST AD'),
    );
  }

  @override
  Future<void> initialize() async {}

  @override
  void preloadRewarded() {
    rewardedPreloadCount += 1;
  }

  @override
  Future<RewardedAdResult> showRewardedWithResult() async {
    rewardedShowCount += 1;
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

GameEngine _firstWinnerMatch() {
  final engine = GameEngine();
  _putCurrentPlayerOneMoveFromFinishing(engine);
  expect(engine.moveToken(engine.currentPlayer.tokens.last, die: 1), isTrue);
  expect(engine.canContinueAfterWinner, isTrue);
  return engine;
}

void _putCurrentPlayerOneMoveFromFinishing(GameEngine engine) {
  final player = engine.currentPlayer;
  for (var tokenId = 0; tokenId < player.tokens.length - 1; tokenId++) {
    player.tokens[tokenId].progress = GameEngine.finishProgress;
  }
  player.tokens.last.progress = GameEngine.finishProgress - 1;
  engine
    ..hasRolled = true
    ..dice = const [1, 2];
  engine.remainingDice
    ..clear()
    ..addAll(const [1, 2]);
}

GameEngine _completedMatch() {
  final engine = GameEngine();
  _putCurrentPlayerOneMoveFromFinishing(engine);
  expect(engine.moveToken(engine.currentPlayer.tokens.last, die: 1), isTrue);
  expect(engine.continueAfterWinner(), isTrue);

  for (final expectedColor in const [PlayerColor.green, PlayerColor.yellow]) {
    expect(engine.currentPlayer.color, expectedColor);
    _putCurrentPlayerOneMoveFromFinishing(engine);
    expect(engine.moveToken(engine.currentPlayer.tokens.last, die: 1), isTrue);
  }

  expect(engine.standingsComplete, isTrue);
  return engine;
}
