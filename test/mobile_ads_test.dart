import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/main.dart' show ParchesePopApp, ShopScreen;
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
        expect(banner.top - content.bottom, closeTo(2, .01));

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
        'JUGAR ONLINE',
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

      expect(controller.rewardedReady, isFalse);
      expect(await controller.showRewarded(), isFalse);

      controller.dispose();
    });
  });

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
  int rewardedShowCount = 0;

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
  Future<bool> showRewarded() async {
    rewardedShowCount += 1;
    return rewardedResult;
  }

  @override
  Future<void> showPrivacyOptions() async {}
}
