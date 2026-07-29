import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _useViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
}

void _useSpanish() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  binding.platformDispatcher.localeTestValue = const Locale('es');
  addTearDown(binding.platformDispatcher.clearLocaleTestValue);
}

Future<void> _pumpLoadedHome(WidgetTester tester) async {
  await tester.pumpWidget(const ParchesePopApp());
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(HomeScreen).evaluate().isNotEmpty) return;
  }
  fail('The home screen did not finish loading.');
}

Future<void> _expectReachableControl(
  WidgetTester tester,
  String label,
  Size viewport,
) async {
  final text = find.text(label);
  expect(text, findsOneWidget);
  await tester.ensureVisible(text);
  await tester.pump(const Duration(milliseconds: 100));

  final tappable = find
      .ancestor(of: text, matching: find.byType(InkWell))
      .first;
  expect(tappable, findsOneWidget);
  expect(tappable.hitTestable(), findsOneWidget);

  final rect = tester.getRect(tappable);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(viewport.width));
  expect(rect.width, greaterThanOrEqualTo(48));
  expect(rect.height, greaterThanOrEqualTo(48));
}

void _expectInitiallyVisibleControl(
  WidgetTester tester,
  String label,
  Size viewport,
) {
  final text = find.text(label);
  expect(text, findsOneWidget);
  final tappable = find
      .ancestor(of: text, matching: find.byType(InkWell))
      .first;
  expect(tappable, findsOneWidget);
  expect(tappable.hitTestable(), findsOneWidget);
  final rect = tester.getRect(tappable);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(viewport.width));
  expect(
    rect.bottom,
    lessThanOrEqualTo(viewport.height),
    reason: '$label must be completely visible before scrolling.',
  );
  expect(rect.width, greaterThanOrEqualTo(44));
  expect(rect.height, greaterThanOrEqualTo(44));
}

Future<void> _expectProfileDialog(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
  expect(find.byKey(const ValueKey('home-profile-dialog')), findsOneWidget);
  expect(find.byKey(const ValueKey('home-profile-close')), findsOneWidget);
  expect(find.byKey(const ValueKey('home-profile-edit')), findsOneWidget);
  expect(find.byType(ProfileView), findsNothing);
  expect(find.byType(HomeScreen), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  for (final viewport in <String, Size>{
    'iPhone 14 portrait': const Size(390, 844),
    'macOS game window': const Size(1180, 820),
  }.entries) {
    testWidgets(
      'game home keeps every primary action reachable on ${viewport.key}',
      (tester) async {
        _useSpanish();
        _useViewport(tester, viewport.value);
        SharedPreferences.setMockInitialValues({
          'profile_name': 'JuanPop',
          'profile_email': 'juan@example.com',
          'profile_flag': '🇩🇴',
        });

        await _pumpLoadedHome(tester);

        for (final label in const [
          'JUGAR ONLINE',
          'CONTRA CPU',
          'Tienda',
          'Mi perfil',
          'Cómo jugar',
          'Trampas',
        ]) {
          await _expectReachableControl(tester, label, viewport.value);
        }

        expect(find.byKey(const ValueKey('home-game-hero')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('welcome card has no redundant trailing play control', (
    tester,
  ) async {
    _useSpanish();
    _useViewport(tester, const Size(1180, 820));
    SharedPreferences.setMockInitialValues({
      'profile_name': 'JuanPop',
      'profile_email': 'juan@example.com',
      'profile_flag': '🇩🇴',
    });

    await _pumpLoadedHome(tester);

    final welcomeCard = find.byKey(const ValueKey('home-game-hero'));
    expect(welcomeCard, findsOneWidget);
    expect(
      find.descendant(
        of: welcomeCard,
        matching: find.byIcon(Icons.play_circle_fill_rounded),
      ),
      findsNothing,
    );
    expect(find.textContaining('JuanPop'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'banner-constrained landscape shows the complete home without scrolling',
    (tester) async {
      _useSpanish();
      const viewport = Size(750, 307);
      _useViewport(tester, viewport);
      SharedPreferences.setMockInitialValues({
        'profile_name': 'JuanPop',
        'profile_email': 'juan@example.com',
        'profile_flag': '🇩🇴',
      });

      await _pumpLoadedHome(tester);
      for (final label in const [
        'JUGAR ONLINE',
        'CONTRA CPU',
        'Tienda',
        'Mi perfil',
        'Cómo jugar',
        'Trampas',
      ]) {
        _expectInitiallyVisibleControl(tester, label, viewport);
      }
      final dock = tester.getRect(find.byKey(const ValueKey('home-menu-dock')));
      expect(dock.bottom, lessThanOrEqualTo(viewport.height));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'animated decoration is ignored by semantics and honors reduced motion',
    (tester) async {
      _useSpanish();
      _useViewport(tester, const Size(390, 844));
      tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      SharedPreferences.setMockInitialValues({});
      final semantics = tester.ensureSemantics();

      try {
        await _pumpLoadedHome(tester);
        await tester.pump(const Duration(seconds: 2));

        final decoration = find.byKey(
          const ValueKey('home-animated-decoration'),
        );
        expect(decoration, findsOneWidget);

        var isExcludedFromSemantics =
            tester.widget(decoration) is ExcludeSemantics;
        tester.element(decoration).visitAncestorElements((element) {
          if (element.widget is ExcludeSemantics) {
            isExcludedFromSemantics = true;
            return false;
          }
          return true;
        });
        expect(isExcludedFromSemantics, isTrue);
        expect(
          find.bySemanticsLabel(RegExp('JUGAR ONLINE')),
          findsAtLeastNWidgets(1),
        );
        expect(
          find.bySemanticsLabel(RegExp('CONTRA CPU')),
          findsAtLeastNWidgets(1),
        );
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('player card uses the avatar equipped in the shop', (
    tester,
  ) async {
    _useSpanish();
    _useViewport(tester, const Size(390, 844));
    SharedPreferences.setMockInitialValues({
      'profile_name': 'JuanPop',
      'profile_email': 'juan@example.com',
      'profile_flag': '🇩🇴',
      'parchesepop.wallet.owned.v1': ['avatar_ninja'],
      'parchesepop.wallet.equipped.v1.avatar': 'avatar_ninja',
    });

    await _pumpLoadedHome(tester);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-game-hero')),
        matching: find.byKey(const ValueKey('home-avatar-avatar_ninja')),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('player card and Mi perfil open the same compact dialog', (
    tester,
  ) async {
    _useSpanish();
    _useViewport(tester, const Size(390, 844));
    SharedPreferences.setMockInitialValues({
      'profile_name': 'JuanPop',
      'profile_email': 'juan@example.com',
      'profile_flag': '🇩🇴',
    });

    await _pumpLoadedHome(tester);

    await tester.tap(find.byKey(const ValueKey('home-game-hero')));
    await _expectProfileDialog(tester);
    await tester.tap(find.byKey(const ValueKey('home-profile-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byKey(const ValueKey('home-profile-dialog')), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);

    final menuProfile = find.text('Mi perfil');
    await tester.ensureVisible(menuProfile);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(menuProfile);
    await _expectProfileDialog(tester);
    await tester.tap(find.byKey(const ValueKey('home-profile-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.byKey(const ValueKey('home-profile-dialog')), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('JUGAR ONLINE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile editing can be cancelled back to the game home', (
    tester,
  ) async {
    _useSpanish();
    _useViewport(tester, const Size(390, 844));
    SharedPreferences.setMockInitialValues({
      'profile_name': 'JuanPop',
      'profile_email': 'juan@example.com',
      'profile_flag': '🇩🇴',
    });

    await _pumpLoadedHome(tester);
    await tester.tap(find.byKey(const ValueKey('home-game-hero')));
    await _expectProfileDialog(tester);

    await tester.tap(find.byKey(const ValueKey('home-profile-edit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byKey(const ValueKey('profile-edit-cancel')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('profile-edit-cancel')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('profile-edit-cancel')).hitTestable(),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('home-profile-dialog')), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('JUGAR ONLINE').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('system back exits profile editing without trapping the player', (
    tester,
  ) async {
    _useSpanish();
    _useViewport(tester, const Size(390, 844));
    SharedPreferences.setMockInitialValues({
      'profile_name': 'JuanPop',
      'profile_email': 'juan@example.com',
      'profile_flag': '🇩🇴',
    });

    await _pumpLoadedHome(tester);
    await tester.tap(find.byKey(const ValueKey('home-game-hero')));
    await _expectProfileDialog(tester);
    await tester.tap(find.byKey(const ValueKey('home-profile-edit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byKey(const ValueKey('profile-edit-cancel')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('profile-edit-cancel')).hitTestable(),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('home-profile-dialog')), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('JUGAR ONLINE').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
