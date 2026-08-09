import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_analytics.dart';
import 'package:parchesepop/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ConsentAwareAnalytics
    implements TypedGameAnalytics, AnalyticsPrivacyControl {
  bool enabled = true;

  @override
  bool get analyticsCollectionEnabled => enabled;

  @override
  Future<void> setAnalyticsCollectionEnabled(bool enabled) async {
    this.enabled = enabled;
  }

  @override
  Future<void> logEvent(GameAnalyticsEvent event) async {}

  @override
  Future<void> logMatchStarted(MatchStartEvent event) async {}
}

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
  testWidgets(
    'compact-board checkpoint is discarded during 68-cell migration',
    (tester) async {
      _useViewport(tester, const Size(390, 844));
      SharedPreferences.setMockInitialValues({
        'active_match_board_layout_version': 2,
        'active_match_checkpoint': '{"players":[]}',
      });

      await _pumpLoadedHome(tester);

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('active_match_checkpoint'), isNull);
      expect(
        preferences.getInt('active_match_board_layout_version'),
        activeMatchBoardLayoutVersion,
      );
    },
  );

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
          'QUICK POP',
          'MESA RÁPIDA',
          'CONTRA CPU',
          'Tienda',
          'Misiones',
          'Cómo jugar',
          'Trampas',
        ]) {
          await _expectReachableControl(tester, label, viewport.value);
        }

        expect(
          find.byKey(const ValueKey('home-profile-button')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('top bar keeps one compact profile access', (tester) async {
    _useSpanish();
    _useViewport(tester, const Size(1180, 820));
    SharedPreferences.setMockInitialValues({
      'profile_name': 'JuanPop',
      'profile_email': 'juan@example.com',
      'profile_flag': '🇩🇴',
    });

    await _pumpLoadedHome(tester);

    final profileButton = find.byKey(const ValueKey('home-profile-button'));
    expect(profileButton, findsOneWidget);
    expect(find.byKey(const ValueKey('home-game-hero')), findsNothing);
    expect(
      find.descendant(
        of: profileButton,
        matching: find.byIcon(Icons.play_circle_fill_rounded),
      ),
      findsNothing,
    );
    final profileSize = tester.getSize(profileButton);
    expect(profileSize.width, inInclusiveRange(44, 48));
    expect(profileSize.height, inInclusiveRange(44, 48));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Mi perfil',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone home removes duplicate actions and uses one utility row', (
    tester,
  ) async {
    _useSpanish();
    const viewport = Size(390, 844);
    _useViewport(tester, viewport);
    SharedPreferences.setMockInitialValues({});

    await _pumpLoadedHome(tester);

    expect(find.text('¡Listo para jugar!'), findsNothing);
    expect(find.text('Registrarme'), findsNothing);
    expect(find.byKey(const ValueKey('home-game-hero')), findsNothing);
    final profile = find.byKey(const ValueKey('home-profile-button'));
    expect(profile, findsOneWidget);
    expect(tester.getSize(profile).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(profile).height, greaterThanOrEqualTo(44));
    expect(profile.hitTestable(), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Registrarme',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-profile-sign-up-badge')),
      findsOneWidget,
    );

    final dock = find.byKey(const ValueKey('home-menu-dock'));
    expect(dock, findsOneWidget);
    expect(tester.getSize(dock).height, lessThanOrEqualTo(68));
    final centers = <double>[];
    for (final label in const ['Tienda', 'Misiones', 'Cómo jugar', 'Trampas']) {
      final button = find
          .ancestor(of: find.text(label), matching: find.byType(InkWell))
          .first;
      expect(button, findsOneWidget);
      final rect = tester.getRect(button);
      expect(rect.width, greaterThanOrEqualTo(70));
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(viewport.width));
      expect(button.hitTestable(), findsOneWidget);
      centers.add(rect.center.dy);
    }
    for (final center in centers.skip(1)) {
      expect(center, closeTo(centers.first, .1));
    }
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
        'QUICK POP',
        'MESA RÁPIDA',
        'CONTRA CPU',
        'Tienda',
        'Misiones',
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
          find.bySemanticsLabel(RegExp('QUICK POP')),
          findsAtLeastNWidgets(1),
        );
        expect(
          find.bySemanticsLabel(RegExp('MESA RÁPIDA')),
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

  testWidgets('home gives each primary mode clear copy and a stable identity', (
    tester,
  ) async {
    _useSpanish();
    _useViewport(tester, const Size(390, 844));
    SharedPreferences.setMockInitialValues({});

    await _pumpLoadedHome(tester);

    expect(find.byKey(const ValueKey('home-mode-quick-pop')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-mode-quick-table')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-mode-cpu')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-quick-pop')), findsNothing);
    expect(find.text('QUICK POP'), findsOneWidget);
    expect(find.text('ONLINE · PRÓXIMAMENTE'), findsOneWidget);
    expect(find.text('2 fichas · partida rápida'), findsOneWidget);
    expect(find.text('MESA RÁPIDA'), findsOneWidget);
    expect(find.text('Partida local'), findsOneWidget);
    expect(find.text('CONTRA CPU'), findsOneWidget);
    expect(find.text('Juega contra el CPU'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact profile uses the avatar equipped in the shop', (
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
        of: find.byKey(const ValueKey('home-profile-button')),
        matching: find.byKey(const ValueKey('home-avatar-avatar_ninja')),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact profile button opens the profile dialog', (
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

    await tester.tap(find.byKey(const ValueKey('home-profile-button')));
    await _expectProfileDialog(tester);
    await tester.tap(find.byKey(const ValueKey('home-profile-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byKey(const ValueKey('home-profile-dialog')), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('MESA RÁPIDA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'account deletion clears every local record and mounted player state',
    (tester) async {
      _useSpanish();
      _useViewport(tester, const Size(390, 844));
      final analytics = _ConsentAwareAnalytics();
      SharedPreferences.setMockInitialValues({
        'profile_name': 'JuanPop',
        'profile_email': 'juan@example.com',
        'profile_flag': '🇩🇴',
        'profile_level': 8,
        'player_auth_email': 'juan@example.com',
        'player_auth_salt': 'local-salt',
        'player_auth_digest': 'local-digest',
        'player_auth_signed_in': false,
        'active_match_board_layout_version': activeMatchBoardLayoutVersion,
        'active_match_checkpoint': '{"players":[]}',
        'parchesepop.wallet.balance.v1': 1800,
        'parchesepop.wallet.owned.v1': ['avatar_ninja'],
        'parchesepop.wallet.equipped.v1.avatar': 'avatar_ninja',
        'parchesepop.tutorial.progress.v1':
            '{"schemaVersion":1,"lifecycle":"completed",'
            '"completedSteps":["firstRoll","releaseToken","chooseMove",'
            '"safeSquare","capture","reachHome"],'
            '"recordedAnalytics":[],"startedAtMilliseconds":1}',
        'settings_sound': false,
        'settings_language': 'es',
        analyticsCollectionPreferenceKey: true,
        'private-test-marker': 'must be removed',
      });

      await tester.pumpWidget(ParchesePopApp(analytics: analytics));
      for (var attempt = 0; attempt < 30; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byType(HomeScreen).evaluate().isNotEmpty) break;
      }

      expect(find.byKey(const ValueKey('resume-saved-match-button')), findsOne);
      expect(find.byKey(const ValueKey('home-profile-button')), findsOneWidget);
      expect(find.text('1,800'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('start-contextual-tutorial')),
        findsNothing,
      );
      expect(analytics.analyticsCollectionEnabled, isTrue);

      await tester.tap(find.byKey(const ValueKey('home-profile-button')));
      await _expectProfileDialog(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('home-profile-delete')),
      );
      await tester.tap(find.byKey(const ValueKey('home-profile-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Eliminar definitivamente'), findsOneWidget);

      await tester.tap(find.text('Eliminar definitivamente'));
      await tester.pumpAndSettle();

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getKeys(), isEmpty);
      expect(analytics.analyticsCollectionEnabled, isFalse);
      expect(
        find.byKey(const ValueKey('resume-saved-match-button')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('home-profile-button')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-avatar-avatar_default')),
        findsOne,
      );
      expect(
        find.byKey(const ValueKey('home-profile-sign-up-badge')),
        findsOneWidget,
      );
      expect(find.text('250'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('start-contextual-tutorial')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('home-profile-dialog')), findsNothing);
    },
  );

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
    await tester.tap(find.byKey(const ValueKey('home-profile-button')));
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
    expect(find.text('MESA RÁPIDA').hitTestable(), findsOneWidget);
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
    await tester.tap(find.byKey(const ValueKey('home-profile-button')));
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
    expect(find.text('MESA RÁPIDA').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
