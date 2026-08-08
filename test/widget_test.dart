import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';
import 'package:parchesepop/online_match.dart';
import 'package:parchesepop/safe_chat.dart';
import 'package:parchesepop/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> tapBoardCell(WidgetTester tester, Offset cell) async {
  final board = find.byKey(const ValueKey('game-board'));
  final rect = tester.getRect(board);
  final boardWidget = tester.widget<GameBoardMockup>(
    find.byType(GameBoardMockup),
  );
  final frameGutterCells = boardWidget.compactPhone ? .08 : .26;
  final boardCell = rect.width / (20 + frameGutterCells * 2);
  final inset = boardCell * frameGutterCells;
  await tester.tapAt(
    Offset(
      rect.left + inset + boardCell * cell.dx,
      rect.top + inset + boardCell * cell.dy,
    ),
  );
  await tester.pump();
}

class _WidgetSequenceRandom implements Random {
  _WidgetSequenceRandom(this.values);

  final List<int> values;
  int position = 0;

  int _next() => position < values.length ? values[position++] : 0;

  @override
  bool nextBool() => _next().isOdd;

  @override
  double nextDouble() => (_next() % 1000) / 1000;

  @override
  int nextInt(int max) => _next() % max;
}

GameEngine oneMoveFromVictory({int playerIndex = 0}) {
  final engine = GameEngine();
  engine.currentPlayerIndex = playerIndex;
  final player = engine.currentPlayer;
  for (var tokenId = 0; tokenId < 3; tokenId++) {
    player.tokens[tokenId].progress = GameEngine.finishProgress;
  }
  player.tokens.last.progress = GameEngine.finishProgress - 1;
  engine.hasRolled = true;
  engine.dice = [1, 6];
  engine.remainingDice.addAll([1, 6]);
  return engine;
}

OnlineMatchSession onlineTestSession() => OnlineMatchSession(
  matchId: 'widget-online-match',
  seed: 42,
  mode: GameMode.traditional,
  participants: const [
    OnlineParticipant(
      id: 'local',
      displayName: 'JuanPop',
      flag: '🇩🇴',
      avatarId: 'avatar_default',
      level: 4,
      color: PlayerColor.red,
      kind: ParticipantKind.local,
      loadout: CosmeticLoadout(),
    ),
    OnlineParticipant(
      id: 'green',
      displayName: 'AminaStar',
      flag: '🇲🇦',
      avatarId: 'avatar_explorer',
      level: 5,
      color: PlayerColor.green,
      kind: ParticipantKind.virtual,
      loadout: CosmeticLoadout(),
    ),
    OnlineParticipant(
      id: 'yellow',
      displayName: 'PriyaPop',
      flag: '🇮🇳',
      avatarId: 'avatar_comet',
      level: 6,
      color: PlayerColor.yellow,
      kind: ParticipantKind.virtual,
      loadout: CosmeticLoadout(),
    ),
    OnlineParticipant(
      id: 'blue',
      displayName: 'JoaoTurbo',
      flag: '🇧🇷',
      avatarId: 'avatar_robot',
      level: 3,
      color: PlayerColor.blue,
      kind: ParticipantKind.virtual,
      loadout: CosmeticLoadout(),
    ),
  ],
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    binding.platformDispatcher.localeTestValue = const Locale('es');
  });
  tearDown(binding.platformDispatcher.clearLocaleTestValue);

  testWidgets('allows a new player to continue as guest', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ParchesePopApp());
    await tester.pumpAndSettle();

    expect(find.text('¡Listo para jugar!'), findsOneWidget);
    expect(find.text('Registrarme'), findsOneWidget);
  });

  testWidgets('game history button opens the visible event timeline', (
    tester,
  ) async {
    final engine = GameEngine(random: _WidgetSequenceRandom([2, 5]));
    engine.currentPlayer.tokens.first.progress = 1;
    engine.roll();
    final rollDescription = engine.eventHistory
        .lastWhere((event) => event.type == GameEventType.roll)
        .description;

    await tester.binding.setSurfaceSize(const Size(844, 390));
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
      ),
    );
    await tester.pump();

    final historyButton = find.byKey(const ValueKey('game-history-button'));
    expect(historyButton, findsOneWidget);
    await tester.tap(historyButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.text('Historial de la partida'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('game-event-history-sheet')),
        matching: find.text(rollDescription),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    engine.dispose();
  });

  testWidgets('portrait game toolbar keeps 44 point touch targets', (
    tester,
  ) async {
    final engine = GameEngine();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
      ),
    );
    await tester.pump();

    for (final key in const <String>[
      'game-back-button',
      'game-history-button',
      'game-settings-button',
    ]) {
      final target = find.byKey(ValueKey(key));
      expect(target, findsOneWidget);
      final size = tester.getSize(target);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
    expect(
      tester.getSize(find.byKey(const ValueKey('game-quick-bar'))).height,
      greaterThanOrEqualTo(44),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    engine.dispose();
  });

  testWidgets('match timer counts play time and pauses when the game ends', (
    tester,
  ) async {
    final engine = GameEngine();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('match-elapsed-timer')), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('00:03'), findsOneWidget);

    engine.gameOver = true;
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('00:03'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    engine.dispose();
  });

  for (final size in <String, Size>{
    'small phone': const Size(390, 844),
    'regular modern phone': const Size(402, 874),
    'large phone': const Size(440, 956),
    '7 inch tablet': const Size(600, 960),
    '10 inch tablet': const Size(800, 1280),
    '11 inch tablet': const Size(834, 1194),
    'desktop window': const Size(1180, 820),
  }.entries) {
    testWidgets('home adapts to ${size.key}', (tester) async {
      SharedPreferences.setMockInitialValues({
        'profile_name': 'JuanPop',
        'profile_email': 'juan@example.com',
        'profile_flag': '🇩🇴',
      });
      await tester.binding.setSurfaceSize(size.value);

      await tester.pumpWidget(const ParchesePopApp());
      await tester.pumpAndSettle();

      expect(find.textContaining('JuanPop'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.binding.setSurfaceSize(null);
    });
  }

  testWidgets('store stays compact and game-like on an iPhone 14', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(const MaterialApp(home: ShopScreen()));
    await tester.pumpAndSettle();

    final title = find.text('Tienda');
    final subtitle = find.text(
      'Personaliza tu juego sin ventajas competitivas.',
    );
    final featuredProducts = shopCatalog
        .where((product) => product.featured)
        .toList(growable: false);
    final firstCard = find
        .ancestor(
          of: find.text('Cosmic Realms Red'),
          matching: find.byType(Card),
        )
        .first;
    final secondCard = find
        .ancestor(
          of: find.text('Cosmic Realms Yellow'),
          matching: find.byType(Card),
        )
        .first;

    expect(title, findsOneWidget);
    expect(subtitle, findsOneWidget);
    expect(find.byKey(const ValueKey('shop-back')), findsOneWidget);
    expect(find.byKey(const ValueKey('shop-balance-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('shop-add-test-balance')), findsOneWidget);
    expect(find.byKey(const ValueKey('shop-filters')), findsOneWidget);
    expect(find.byType(Card), findsNWidgets(featuredProducts.length));
    for (final product in featuredProducts) {
      expect(
        find.byKey(ValueKey('shop-preview-${product.id}')),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);

    final inherited = DefaultTextStyle.of(tester.element(subtitle)).style;
    expect(inherited.fontSize ?? 14, lessThanOrEqualTo(20));
    expect(inherited.decoration ?? TextDecoration.none, TextDecoration.none);
    expect(tester.getRect(title).height, lessThanOrEqualTo(40));
    expect(tester.getRect(subtitle).height, lessThanOrEqualTo(40));
    expect(
      tester.getSize(find.byKey(const ValueKey('shop-header'))).height,
      lessThanOrEqualTo(72),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('shop-filters'))).height,
      lessThanOrEqualTo(48),
    );

    final firstRect = tester.getRect(firstCard);
    final secondRect = tester.getRect(secondCard);
    expect(firstRect.top, lessThanOrEqualTo(390));
    expect(firstRect.left, greaterThanOrEqualTo(16));
    expect(secondRect.right, lessThanOrEqualTo(374));
    expect((firstRect.top - secondRect.top).abs(), lessThan(1));

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
    expect(find.text('Dados Clásicos'), findsOneWidget);
    expect(find.text('Dados Galaxia'), findsOneWidget);
    expect(find.text('Dados Caramelo'), findsOneWidget);
    expect(find.text('Dados Volcán'), findsOneWidget);
    expect(find.text('Dados Hielo'), findsOneWidget);
    expect(find.text('Dados Arcade'), findsOneWidget);
    expect(find.text('Dados Perla'), findsOneWidget);
    expect(find.text('Dados Prisma'), findsOneWidget);
    expect(find.text('Dados Medianoche'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('shop-die-dice_default-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('shop-die-dice_galaxy-0')),
      findsOneWidget,
    );
    expect(find.text('Ciudad Futurista'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('CPU setup offers traditional and chaos modes', (tester) async {
    SharedPreferences.setMockInitialValues({
      'profile_name': 'JuanPop',
      'profile_email': 'juan@example.com',
      'profile_flag': '🇩🇴',
    });
    await tester.binding.setSurfaceSize(const Size(1180, 820));
    await tester.pumpWidget(const ParchesePopApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('CONTRA CPU'));
    await tester.pumpAndSettle();

    expect(find.text('Tradicional'), findsOneWidget);
    expect(find.text('Caos'), findsOneWidget);
    expect(find.textContaining('Reglas clásicas'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('chaos game fits an iPhone 14 viewport', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', mode: GameMode.chaos),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Caos'), findsOneWidget);
    expect(find.text('Lanzar'), findsNothing);
    expect(
      find.byKey(const ValueKey('dice-roll-target')).hitTestable(),
      findsOne,
    );
    expect(find.text('Sin objeto'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('game fits the current macOS window without clipping', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(998, 761));
    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', mode: GameMode.traditional),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('game-board')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('chaos game explains automatic powers and accumulating traps', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', mode: GameMode.chaos),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('Poderes y trampas'));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Poderes y trampas'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'escudo.+activa solo', caseSensitive: false)),
      findsOneWidget,
    );
    expect(find.textContaining('puedes mantener varias'), findsOneWidget);
    expect(find.text('Tú'), findsWidgets);
    expect(find.text('CPU 1'), findsOneWidget);
    expect(find.text('CPU 2'), findsOneWidget);
    expect(find.text('CPU 3'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('a stored shield is labeled as automatic in the controls', (
    tester,
  ) async {
    final engine = GameEngine(mode: GameMode.chaos);
    engine.currentPlayer.inventory = PowerUp.shield;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: GameControlPanel(engine: engine, compact: true),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Escudo listo · automático'), findsOneWidget);
    expect(find.textContaining('Usar: Escudo'), findsNothing);
    expect(
      find.byTooltip(
        'Escudo: Se activa automáticamente al caer en una trampa rival y se consume al bloquearla.',
      ),
      findsWidgets,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    engine.dispose();
  });

  testWidgets('local shield appears directly below the current player name', (
    tester,
  ) async {
    final engine = GameEngine(mode: GameMode.chaos);
    engine.currentPlayer.inventory = PowerUp.shield;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: GameControlPanel(engine: engine, compact: true),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final name = find.text('Tú');
    final badge = find.byKey(const ValueKey('held-shield'));
    expect(badge, findsOneWidget);
    expect(find.text('PODER · Escudo listo · AUTO'), findsOneWidget);
    expect(find.byIcon(Icons.shield_rounded), findsWidgets);
    expect(tester.getRect(badge).top, greaterThan(tester.getRect(name).bottom));

    await tester.pumpWidget(const SizedBox.shrink());
    engine.dispose();
  });

  testWidgets(
    'owner sees a stored shield and several placed traps simultaneously',
    (tester) async {
      final engine = GameEngine(mode: GameMode.chaos);
      engine.currentPlayer.inventory = PowerUp.shield;
      engine.traps.addAll(const [
        BoardTrap(owner: PlayerColor.red, type: PowerUp.bomb, loopIndex: 26),
        BoardTrap(
          owner: PlayerColor.red,
          type: PowerUp.setbackTrap,
          loopIndex: 31,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 340, child: PlayerRoster(engine: engine)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final name = find.text('Tú');
      expect(find.textContaining('Escudo'), findsWidgets);
      expect(
        find.textContaining(
          RegExp(r'(2.+trampas|trampas.+2)', caseSensitive: false),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('traps-red-2')), findsOneWidget);
      final shield = find.byIcon(Icons.shield_rounded);
      expect(shield, findsWidgets);
      expect(
        tester.getRect(shield.first).top,
        greaterThan(tester.getRect(name).top),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      engine.dispose();
    },
  );

  testWidgets('power details list every trap owned by the local player', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final engine = GameEngine(mode: GameMode.chaos);
    engine.currentPlayer.inventory = PowerUp.shield;
    engine.traps.addAll(const [
      BoardTrap(owner: PlayerColor.red, type: PowerUp.bomb, loopIndex: 26),
      BoardTrap(
        owner: PlayerColor.red,
        type: PowerUp.setbackTrap,
        loopIndex: 31,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'CPU • Fácil',
          gameEngine: engine,
          showAllTestTraps: false,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Poderes y trampas'));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.textContaining('Escudo listo'), findsWidgets);
    expect(find.textContaining('Bomba · casilla 27'), findsOneWidget);
    expect(
      find.textContaining('Trampa de retroceso · casilla 32'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    engine.dispose();
  });

  testWidgets('right roster hides a CPU held power-up', (tester) async {
    final engine = GameEngine(mode: GameMode.chaos);
    engine.players[1].inventory = PowerUp.shield;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 290, child: PlayerRoster(engine: engine)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Poder automático oculto'), findsOneWidget);
    expect(find.textContaining('Escudo'), findsNothing);
    expect(find.byKey(const ValueKey('hidden-held-green')), findsOneWidget);
    expect(find.text('UN PODER POR JUGADOR'), findsNothing);

    engine.dispose();
  });

  testWidgets(
    'right roster shows rival trap count but hides types and squares',
    (tester) async {
      final engine = GameEngine(mode: GameMode.chaos);
      engine.traps.addAll(const [
        BoardTrap(
          owner: PlayerColor.green,
          type: PowerUp.setbackTrap,
          loopIndex: 26,
        ),
        BoardTrap(owner: PlayerColor.green, type: PowerUp.bomb, loopIndex: 31),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 290, child: PlayerRoster(engine: engine)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining(
          RegExp(
            r'(2.+trampas.+ocultas|trampas.+ocultas.+2)',
            caseSensitive: false,
          ),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Trampa de retroceso'), findsNothing);
      expect(find.textContaining('Bomba'), findsNothing);
      expect(find.textContaining('#27'), findsNothing);
      expect(find.textContaining('#32'), findsNothing);

      engine.dispose();
    },
  );

  testWidgets('trap inventory never exposes a manual placement action', (
    tester,
  ) async {
    final engine = GameEngine(mode: GameMode.chaos);
    engine.currentPlayer.inventory = PowerUp.bomb;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: GameControlPanel(engine: engine, compact: true),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Colocar'), findsNothing);
    expect(find.text('Cancelar trampa'), findsNothing);
    expect(find.text('Elige una casilla blanca'), findsNothing);
    final button = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('item-action')),
    );
    expect(button.onPressed, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    engine.dispose();
  });

  testWidgets('Turbo remains a manual power action', (tester) async {
    final engine = GameEngine(mode: GameMode.chaos);
    engine.currentPlayer.inventory = PowerUp.boost;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: GameControlPanel(engine: engine, compact: true),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Usar'), findsOneWidget);
    expect(find.textContaining('Turbo'), findsWidgets);
    final button = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('item-action')),
    );
    expect(button.onPressed, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    engine.dispose();
  });

  for (final power in const [PowerUp.bomb, PowerUp.setbackTrap]) {
    testWidgets('${power.name} starts a visible board effect when triggered', (
      tester,
    ) async {
      final engine = GameEngine(mode: GameMode.chaos);
      final trapIndex = const [
        26,
        27,
        28,
      ].firstWhere((index) => !engine.itemLoopIndices.contains(index));
      engine.traps.add(
        BoardTrap(owner: PlayerColor.red, type: power, loopIndex: trapIndex),
      );

      engine.currentPlayerIndex = 1;
      final green = engine.currentPlayer.tokens.first
        ..progress =
            (trapIndex - 1 - GameEngine.startOffset[PlayerColor.green]!) %
            GameEngine.loopLength;
      engine.hasRolled = true;
      engine.dice = [1, 5];
      engine.remainingDice.addAll([1, 5]);

      Widget board() => MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 400,
            child: GameBoardMockup(engine: engine),
          ),
        ),
      );

      await tester.pumpWidget(board());
      final effectSerialBeforeTrigger = engine.effectSerial;
      expect(engine.moveToken(green, die: 1), isTrue);
      await tester.pumpWidget(board());
      await tester.pump(const Duration(milliseconds: 100));

      final boardPaint = find.descendant(
        of: find.byType(GameBoardMockup),
        matching: find.byType(CustomPaint),
      );
      final customPaint = boardPaint.evaluate().single.widget as CustomPaint;
      final dynamic painter = customPaint.painter;
      final effectProgress = painter.effectProgress as double;

      expect(engine.effectSerial, effectSerialBeforeTrigger + 1);
      expect(engine.effectLoopIndex, trapIndex);
      expect(engine.effectPowerUp, power);
      expect(engine.effectKind, PowerEffectKind.triggered);
      expect(engine.effectToken, same(green));
      expect(effectProgress, greaterThan(0));
      expect(effectProgress, lessThan(1));
      expect(engine.traps, isEmpty);
      if (power == PowerUp.bomb) {
        expect(green.inNest, isTrue);
        expect(engine.message, contains('¡BOMBA!'));
      } else {
        expect(green.inNest, isFalse);
        expect(
          engine.loopIndex(PlayerColor.green, green.progress),
          trapIndex - 6,
        );
        expect(engine.message, contains('¡RETROCESO!'));
      }

      await tester.pump(const Duration(milliseconds: 330));
      final routedPaint = boardPaint.evaluate().single.widget as CustomPaint;
      final dynamic routedPainter = routedPaint.painter;
      final routedCells = Map<GameToken, Offset>.from(
        routedPainter.animatedCells as Map<GameToken, Offset>,
      );
      expect(
        (routedCells[green]! - GameEngine.loop[trapIndex]).distance,
        lessThan(.75),
        reason: 'the piece must visibly arrive on the trap before reacting',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      engine.dispose();
    });
  }

  testWidgets('leaving jail starts the visible SALIDA effect', (tester) async {
    final engine = GameEngine();
    final token = engine.currentPlayer.tokens.first;
    engine.hasRolled = true;
    engine.dice = [5, 2];
    engine.remainingDice.addAll([5, 2]);

    Widget board() => MaterialApp(
      home: Center(
        child: SizedBox.square(
          dimension: 400,
          child: GameBoardMockup(engine: engine),
        ),
      ),
    );

    await tester.pumpWidget(board());
    expect(engine.moveToken(token, die: 5), isTrue);
    await tester.pumpWidget(board());
    await tester.pump(const Duration(milliseconds: 100));

    final customPaint =
        find
                .descendant(
                  of: find.byType(GameBoardMockup),
                  matching: find.byType(CustomPaint),
                )
                .evaluate()
                .single
                .widget
            as CustomPaint;
    final dynamic painter = customPaint.painter;
    expect(engine.effectKind, PowerEffectKind.departure);
    expect(
      engine.effectBoardCell,
      GameEngine.loop[GameEngine.startOffset[PlayerColor.red]!],
    );
    expect(painter.effectProgress as double, greaterThan(0));
    expect(painter.effectProgress as double, lessThan(1));

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox.shrink());
    engine.dispose();
  });

  testWidgets('capturing a rival starts the visible impact effect', (
    tester,
  ) async {
    final engine = GameEngine();
    final red = engine.players[0].tokens.first..progress = 1;
    final green = engine.players[1].tokens.first
      ..progress =
          (4 - GameEngine.startOffset[PlayerColor.green]!) %
          GameEngine.loopLength;
    engine.hasRolled = true;
    engine.dice = [3, 6];
    engine.remainingDice.addAll([3, 6]);

    Widget board() => MaterialApp(
      home: Center(
        child: SizedBox.square(
          dimension: 400,
          child: GameBoardMockup(engine: engine),
        ),
      ),
    );

    await tester.pumpWidget(board());
    expect(engine.moveToken(red, die: 3), isTrue);
    await tester.pumpWidget(board());
    await tester.pump(const Duration(milliseconds: 100));

    final customPaint =
        find
                .descendant(
                  of: find.byType(GameBoardMockup),
                  matching: find.byType(CustomPaint),
                )
                .evaluate()
                .single
                .widget
            as CustomPaint;
    final dynamic painter = customPaint.painter;
    expect(green.inNest, isTrue);
    expect(engine.effectKind, PowerEffectKind.capture);
    expect(engine.effectBoardCell, GameEngine.loop[4]);
    expect(painter.effectProgress as double, greaterThan(0));
    expect(painter.effectProgress as double, lessThan(1));

    await tester.pumpWidget(const SizedBox.shrink());
    engine.dispose();
  });

  testWidgets('reaching the center starts the visible META effect', (
    tester,
  ) async {
    final engine = GameEngine();
    final token = engine.currentPlayer.tokens.first
      ..progress = GameEngine.finishProgress - 1;
    engine.currentPlayer.tokens[1].progress = 0;
    engine.hasRolled = true;
    engine.dice = [1, 6];
    engine.remainingDice.addAll([1, 6]);

    Widget board() => MaterialApp(
      home: Center(
        child: SizedBox.square(
          dimension: 400,
          child: GameBoardMockup(engine: engine),
        ),
      ),
    );

    await tester.pumpWidget(board());
    expect(engine.moveToken(token, die: 1), isTrue);
    await tester.pumpWidget(board());
    await tester.pump(const Duration(milliseconds: 100));

    final customPaint =
        find
                .descendant(
                  of: find.byType(GameBoardMockup),
                  matching: find.byType(CustomPaint),
                )
                .evaluate()
                .single
                .widget
            as CustomPaint;
    final dynamic painter = customPaint.painter;
    expect(token.finished, isTrue);
    expect(engine.effectKind, PowerEffectKind.goal);
    expect(engine.effectBoardCell, GameEngine.goalCells[PlayerColor.red]);
    expect(engine.effectLoopIndex, isNull);
    expect(painter.effectProgress as double, greaterThan(0));
    expect(painter.effectProgress as double, lessThan(1));

    await tester.pumpWidget(const SizedBox.shrink());
    engine.dispose();
  });

  testWidgets(
    'a stored shield starts the protected board effect automatically',
    (tester) async {
      final engine = GameEngine(mode: GameMode.chaos);
      engine.traps.add(
        const BoardTrap(
          owner: PlayerColor.red,
          type: PowerUp.bomb,
          loopIndex: 26,
        ),
      );
      engine.currentPlayerIndex = 1;
      final green = engine.currentPlayer.tokens.first
        ..progress =
            (25 - GameEngine.startOffset[PlayerColor.green]!) %
            GameEngine.loopLength;
      final landingProgress = green.progress + 1;
      engine.currentPlayer.inventory = PowerUp.shield;
      engine.hasRolled = true;
      engine.dice = [1, 5];
      engine.remainingDice.addAll([1, 5]);

      Widget board() => MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 400,
            child: GameBoardMockup(engine: engine),
          ),
        ),
      );

      await tester.pumpWidget(board());
      expect(engine.moveToken(green, die: 1), isTrue);
      await tester.pumpWidget(board());
      await tester.pump(const Duration(milliseconds: 180));

      final boardPaint = find.descendant(
        of: find.byType(GameBoardMockup),
        matching: find.byType(CustomPaint),
      );
      final customPaint = boardPaint.evaluate().single.widget as CustomPaint;
      final dynamic painter = customPaint.painter;

      expect(engine.effectKind, PowerEffectKind.blocked);
      expect(engine.effectPowerUp, PowerUp.shield);
      expect(engine.effectToken, same(green));
      expect(engine.currentPlayer.inventory, isNull);
      expect(green.progress, landingProgress);
      expect(green.inNest, isFalse);
      expect(engine.traps, isEmpty);
      expect(painter.effectProgress as double, greaterThan(0));
      expect(engine.message, contains('¡PROTEGIDO!'));

      await tester.pumpWidget(const SizedBox.shrink());
      engine.dispose();
    },
  );

  testWidgets('a new move does not replay older token animations', (
    tester,
  ) async {
    final engine = GameEngine(mode: GameMode.traditional);
    final first = engine.currentPlayer.tokens[0]..progress = 0;
    final second = engine.currentPlayer.tokens[1]..progress = 10;
    engine.hasRolled = true;
    engine.dice = [2, 3];
    engine.remainingDice.addAll([2, 3, 6]);

    Widget board() => MaterialApp(
      home: Center(
        child: SizedBox.square(
          dimension: 400,
          child: GameBoardMockup(engine: engine),
        ),
      ),
    );

    await tester.pumpWidget(board());
    expect(engine.moveToken(first, die: 2), isTrue);
    await tester.pumpWidget(board());
    await tester.pump(const Duration(milliseconds: 500));

    expect(engine.moveToken(second, die: 3), isTrue);
    await tester.pumpWidget(board());

    final boardPaint = find.descendant(
      of: find.byType(GameBoardMockup),
      matching: find.byType(CustomPaint),
    );
    final customPaint = boardPaint.evaluate().single.widget as CustomPaint;
    final dynamic painter = customPaint.painter;
    final cells = Map<GameToken, Offset>.from(
      painter.animatedCells as Map<GameToken, Offset>,
    );

    expect(cells[first], GameEngine.loop[2]);
    expect(cells[second], GameEngine.loop[10]);

    await tester.pumpWidget(const SizedBox.shrink());
    engine.dispose();
  });

  testWidgets('two barrier tokens are shown separately on the same cell', (
    tester,
  ) async {
    final engine = GameEngine(mode: GameMode.traditional);
    final first = engine.currentPlayer.tokens[0]..progress = 0;
    final second = engine.currentPlayer.tokens[1]..progress = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 400,
            child: GameBoardMockup(engine: engine),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final boardPaint = find.descendant(
      of: find.byType(GameBoardMockup),
      matching: find.byType(CustomPaint),
    );
    var customPaint = boardPaint.evaluate().single.widget as CustomPaint;
    dynamic painter = customPaint.painter;
    var cells = Map<GameToken, Offset>.from(
      painter.animatedCells as Map<GameToken, Offset>,
    );
    var firstCell = cells[first]!;
    var secondCell = cells[second]!;
    var midpoint = (firstCell + secondCell) / 2;

    expect((firstCell - secondCell).distance, closeTo(.94, .001));
    expect(firstCell.dx, closeTo(secondCell.dx, .001));
    expect(firstCell.dy, isNot(closeTo(secondCell.dy, .001)));
    expect(midpoint.dx, closeTo(GameEngine.loop.first.dx, .001));
    expect(midpoint.dy, closeTo(GameEngine.loop.first.dy, .001));

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 400,
            child: GameBoardMockup(engine: engine, compactPhone: true),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    customPaint = boardPaint.evaluate().single.widget as CustomPaint;
    painter = customPaint.painter;
    cells = Map<GameToken, Offset>.from(
      painter.animatedCells as Map<GameToken, Offset>,
    );
    firstCell = cells[first]!;
    secondCell = cells[second]!;
    midpoint = (firstCell + secondCell) / 2;

    expect((firstCell - secondCell).distance, closeTo(1.0, .001));
    expect(midpoint.dx, closeTo(GameEngine.loop.first.dx, .001));
    expect(midpoint.dy, closeTo(GameEngine.loop.first.dy, .001));

    await tester.pumpWidget(const SizedBox.shrink());
    engine.dispose();
  });

  testWidgets('move previews show the colored destinations for 4 and 20', (
    tester,
  ) async {
    final engine = GameEngine(mode: GameMode.traditional);
    final selected = engine.currentPlayer.tokens[0]..progress = 0;
    engine.currentPlayer.tokens[1].progress = 10;
    engine.currentPlayer.tokens[2].progress = 20;
    engine.currentPlayer.tokens[3].progress = 30;
    engine.hasRolled = true;
    engine.dice = [4, 6];
    engine.remainingDice.addAll([4, 20]);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 400,
            child: GameBoardMockup(engine: engine, selectedToken: selected),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final boardPaint = find.descendant(
      of: find.byType(GameBoardMockup),
      matching: find.byType(CustomPaint),
    );
    final customPaint = boardPaint.evaluate().single.widget as CustomPaint;
    final dynamic painter = customPaint.painter;
    final previews = List<MoveDestinationPreview>.from(
      painter.movePreviews as List<MoveDestinationPreview>,
    );

    expect(previews.map((preview) => preview.value), [4, 20]);
    expect(previews[0].cell, GameEngine.loop[4]);
    expect(previews[0].color, PopColors.blue);
    expect(previews[1].cell, GameEngine.loop[20]);
    expect(previews[1].color, const Color(0xFF7C4DFF));
    expect(previews[1].token, same(selected));
    expect(previews[1].overview, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    engine.dispose();
  });

  testWidgets(
    'a capture bonus shows distinct 20-step destinations for every legal token',
    (tester) async {
      final engine = GameEngine(mode: GameMode.traditional);
      final first = engine.currentPlayer.tokens[0]..progress = 0;
      final second = engine.currentPlayer.tokens[1]..progress = 8;
      engine.currentPlayer.tokens[2].progress = 18;
      engine.currentPlayer.tokens[3].progress = 70;
      final victim = engine.players[1].tokens.first;
      victim.progress =
          (3 - GameEngine.startOffset[victim.owner]!) % GameEngine.loopLength;
      engine.hasRolled = true;
      engine.dice = [3, 6];
      engine.remainingDice.add(3);

      expect(engine.moveToken(first, die: 3), isTrue);
      expect(victim.inNest, isTrue);
      expect(engine.remainingDice, [20]);
      expect(engine.message, contains('Bono +20'));

      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('capture-bonus-20')), findsOneWidget);
      expect(find.text('BONO +20 · Elige una ficha por color'), findsOneWidget);

      CustomPaint boardPaint() =>
          find
                  .descendant(
                    of: find.byType(GameBoardMockup),
                    matching: find.byType(CustomPaint),
                  )
                  .evaluate()
                  .single
                  .widget
              as CustomPaint;

      final dynamic overviewPainter = boardPaint().painter;
      final overview = List<MoveDestinationPreview>.from(
        overviewPainter.movePreviews as List<MoveDestinationPreview>,
      );
      expect(overview.map((preview) => preview.token.id), [0, 1, 2]);
      expect(overview.map((preview) => preview.value), everyElement(20));
      expect(overview.map((preview) => preview.overview), everyElement(isTrue));
      expect(overview.map((preview) => preview.cell), [
        GameEngine.loop[23],
        GameEngine.loop[28],
        GameEngine.loop[38],
      ]);
      expect(overview.map((preview) => preview.color).toSet(), hasLength(3));

      final secondGuideColor = overview
          .singleWhere((preview) => identical(preview.token, second))
          .color;
      await tapBoardCell(tester, GameEngine.loop[8]);

      expect(find.byKey(const ValueKey('token-move-popup')), findsOneWidget);
      expect(find.text('FICHA 2 · BONO +20'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Mover ficha 2 con el bono de 20 pasos'),
        findsOneWidget,
      );
      final dynamic focusedPainter = boardPaint().painter;
      final focused = List<MoveDestinationPreview>.from(
        focusedPainter.movePreviews as List<MoveDestinationPreview>,
      );
      expect(focused, hasLength(1));
      expect(focused.single.token, same(second));
      expect(focused.single.cell, GameEngine.loop[28]);
      expect(focused.single.color, secondGuideColor);
      expect(focused.single.overview, isFalse);

      await tester.tap(find.byKey(const ValueKey('move-choice-20')));
      await tester.pump();

      expect(second.progress, 28);
      expect(engine.remainingDice, isEmpty);
      expect(engine.message, 'Avanzaste 20.');
      expect(find.byKey(const ValueKey('token-move-popup')), findsNothing);

      engine.gameOver = true;
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
      engine.dispose();
    },
  );

  testWidgets('a piece animates through the turn into its red home lane', (
    tester,
  ) async {
    final engine = GameEngine(mode: GameMode.traditional);
    final token = engine.currentPlayer.tokens[0]
      ..progress = GameEngine.commonPathLength - 2;
    engine.hasRolled = true;
    engine.dice = [3, 6];
    engine.remainingDice.addAll([3, 6]);

    Widget board() => MaterialApp(
      home: Center(
        child: SizedBox.square(
          dimension: 400,
          child: GameBoardMockup(engine: engine),
        ),
      ),
    );

    await tester.pumpWidget(board());
    expect(engine.moveToken(token, die: 3), isTrue);
    await tester.pumpWidget(board());
    await tester.pump(const Duration(milliseconds: 227));

    final boardPaint = find.descendant(
      of: find.byType(GameBoardMockup),
      matching: find.byType(CustomPaint),
    );
    var customPaint = boardPaint.evaluate().single.widget as CustomPaint;
    dynamic painter = customPaint.painter;
    var cells = Map<GameToken, Offset>.from(
      painter.animatedCells as Map<GameToken, Offset>,
    );
    expect(
      (cells[token]! - GameEngine.homeLanes[PlayerColor.red]!.first).distance,
      lessThan(.50),
    );

    await tester.pump(const Duration(milliseconds: 300));
    customPaint = boardPaint.evaluate().single.widget as CustomPaint;
    painter = customPaint.painter;
    cells = Map<GameToken, Offset>.from(
      painter.animatedCells as Map<GameToken, Offset>,
    );
    expect(cells[token], GameEngine.homeLanes[PlayerColor.red]![1]);

    await tester.pumpWidget(const SizedBox.shrink());
    engine.dispose();
  });

  testWidgets('a second red piece enters the home lane instead of the loop', (
    tester,
  ) async {
    final engine = GameEngine(mode: GameMode.traditional);
    final first = engine.currentPlayer.tokens[0]
      ..progress = GameEngine.commonPathLength + 1;
    final second = engine.currentPlayer.tokens[1]
      ..progress = GameEngine.commonPathLength - 1;
    engine.currentPlayer.tokens[2].progress = 10;
    engine.currentPlayer.tokens[3].progress = 20;
    engine.hasRolled = true;
    engine.dice = [1, 6];
    engine.remainingDice.addAll([1, 6]);

    Widget board() => MaterialApp(
      home: Center(
        child: SizedBox.square(
          dimension: 400,
          child: GameBoardMockup(engine: engine),
        ),
      ),
    );

    await tester.pumpWidget(board());
    expect(engine.moveToken(second, die: 1), isTrue);
    await tester.pumpWidget(board());
    await tester.pump(const Duration(milliseconds: 500));

    final boardPaint = find.descendant(
      of: find.byType(GameBoardMockup),
      matching: find.byType(CustomPaint),
    );
    final customPaint = boardPaint.evaluate().single.widget as CustomPaint;
    final dynamic painter = customPaint.painter;
    final cells = Map<GameToken, Offset>.from(
      painter.animatedCells as Map<GameToken, Offset>,
    );
    expect(cells[first], GameEngine.homeLanes[PlayerColor.red]![1]);
    expect(cells[second], GameEngine.homeLanes[PlayerColor.red]!.first);
    expect(GameEngine.loop, isNot(contains(cells[second])));

    await tester.pumpWidget(const SizedBox.shrink());
    engine.dispose();
  });

  testWidgets('a five says SALIDA when the selected token is in jail', (
    tester,
  ) async {
    final engine = GameEngine(mode: GameMode.traditional);
    final token = engine.currentPlayer.tokens.first;
    engine.hasRolled = true;
    engine.dice = [5, 5];
    engine.remainingDice.addAll([5, 5]);
    engine.message = 'Sacaste doble cinco.';

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tapBoardCell(
      tester,
      displayTokenCellsForTesting(engine, compactPhone: true)[token]!,
    );

    expect(find.byKey(const ValueKey('move-choice-5')), findsOneWidget);
    expect(find.text('FICHA 1 · SALIDA'), findsOneWidget);
    expect(find.text('SALIDA'), findsOneWidget);
    expect(find.text('Pulsa SALIDA'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('move-choice-5')));
    await tester.pump();

    expect(token.progress, 0);
    expect(engine.remainingDice, [5]);
    expect(engine.message, 'Sacaste una ficha.');

    engine.gameOver = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    engine.dispose();
  });

  testWidgets('a five says five steps after every token is outside', (
    tester,
  ) async {
    final engine = GameEngine(mode: GameMode.traditional);
    for (var index = 0; index < engine.currentPlayer.tokens.length; index++) {
      engine.currentPlayer.tokens[index].progress = index * 3;
    }
    engine.hasRolled = true;
    engine.dice = [5, 2];
    engine.remainingDice.addAll([5, 2]);
    engine.message = 'Sacaste 5 y 2.';

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tapBoardCell(tester, GameEngine.loop[0]);

    expect(find.text('FICHA 1 · PASOS'), findsOneWidget);
    expect(find.text('SALIDA'), findsNothing);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('pasos'), findsWidgets);

    engine.gameOver = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    engine.dispose();
  });

  testWidgets(
    'an occupied home entry shows CAPTURAR and both preview positions',
    (tester) async {
      final engine = GameEngine(mode: GameMode.traditional);
      final mover = engine.currentPlayer.tokens.first
        ..progress = GameEngine.commonPathLength - 2;
      engine.currentPlayer.tokens[1].progress = 10;
      engine.currentPlayer.tokens[2].progress = 20;
      engine.currentPlayer.tokens[3].progress = 30;
      final gate = GameEngine.homeEntryOffset[PlayerColor.red]!;
      final blocker = engine.players[1].tokens.first
        ..progress =
            (gate - GameEngine.startOffset[PlayerColor.green]!) %
            GameEngine.loopLength;
      engine.hasRolled = true;
      engine.dice = [5, 5];
      engine.remainingDice.addAll([5, 5]);
      engine.message = 'Sacaste doble cinco.';

      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tapBoardCell(tester, engine.tokenCell(mover)!);

      expect(find.text('FICHA 1 · CAPTURA'), findsOneWidget);
      expect(find.text('CAPTURAR'), findsOneWidget);
      expect(engine.captureTargetFor(mover, 5), same(blocker));
      expect(
        find.bySemanticsLabel(
          'Capturar la ficha verde que bloquea la entrada con 5',
        ),
        findsOneWidget,
      );

      final boardPaint = find.descendant(
        of: find.byType(GameBoardMockup),
        matching: find.byType(CustomPaint),
      );
      final customPaint = boardPaint.evaluate().single.widget as CustomPaint;
      final dynamic painter = customPaint.painter;
      final previews = List<MoveDestinationPreview>.from(
        painter.movePreviews as List<MoveDestinationPreview>,
      );
      expect(previews, hasLength(1));
      expect(previews.single.value, 5);
      expect(previews.single.isHomeEntryCapture, isTrue);
      expect(previews.single.captureCell, GameEngine.loop[gate]);
      expect(previews.single.cell, GameEngine.homeLanes[PlayerColor.red]![3]);

      await tester.tap(find.byKey(const ValueKey('move-choice-5')));
      await tester.pump();

      expect(mover.progress, GameEngine.commonPathLength + 3);
      expect(blocker.inNest, isTrue);
      expect(engine.remainingDice, [5, 20]);
      expect(engine.message, contains('entrada'));

      engine.gameOver = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
      engine.dispose();
    },
  );

  testWidgets('tapping a highlighted destination consumes its matching die', (
    tester,
  ) async {
    final engine = GameEngine(mode: GameMode.traditional);
    final first = engine.currentPlayer.tokens[0]..progress = 0;
    final second = engine.currentPlayer.tokens[1]..progress = 10;
    engine.hasRolled = true;
    engine.dice = [2, 3];
    engine.remainingDice.addAll([2, 3]);
    engine.message = 'Sacaste 2 y 3.';

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tapBoardCell(tester, GameEngine.loop[0]);
    expect(find.byKey(const ValueKey('move-choice-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('move-choice-3')), findsOneWidget);

    await tapBoardCell(tester, GameEngine.loop[3]);

    expect(first.progress, 3);
    expect(engine.remainingDice, [2]);
    expect(engine.message, 'Avanzaste 3.');
    expect(find.byKey(const ValueKey('token-move-popup')), findsNothing);

    await tapBoardCell(tester, GameEngine.loop[10]);
    expect(find.byKey(const ValueKey('move-choice-2')), findsOneWidget);

    await tapBoardCell(tester, GameEngine.loop[12]);

    expect(second.progress, 12);
    expect(engine.remainingDice, isEmpty);
    expect(engine.message, 'Avanzaste 2.');

    engine.gameOver = true;
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    engine.dispose();
  });

  testWidgets('a highlighted SALIDA square can be tapped directly', (
    tester,
  ) async {
    final engine = GameEngine(mode: GameMode.traditional);
    final token = engine.currentPlayer.tokens.first;
    engine.hasRolled = true;
    engine.dice = [5, 5];
    engine.remainingDice.addAll([5, 5]);
    engine.message = 'Sacaste doble cinco.';

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tapBoardCell(
      tester,
      displayTokenCellsForTesting(engine, compactPhone: true)[token]!,
    );
    expect(find.text('SALIDA'), findsOneWidget);

    await tapBoardCell(tester, GameEngine.loop[0]);

    expect(token.progress, 0);
    expect(engine.remainingDice, [5]);
    expect(engine.message, 'Sacaste una ficha.');
    expect(find.byKey(const ValueKey('token-move-popup')), findsNothing);

    engine.gameOver = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    engine.dispose();
  });

  testWidgets('a selected capture bonus destination can be tapped directly', (
    tester,
  ) async {
    final engine = GameEngine(mode: GameMode.traditional);
    final token = engine.currentPlayer.tokens.first..progress = 8;
    engine.hasRolled = true;
    engine.dice = [3, 6];
    engine.remainingDice.add(20);
    engine.message = 'Bono +20: elige una ficha.';

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tapBoardCell(tester, GameEngine.loop[8]);
    expect(find.byKey(const ValueKey('move-choice-20')), findsOneWidget);

    await tapBoardCell(tester, GameEngine.loop[28]);

    expect(token.progress, 28);
    expect(engine.remainingDice, isEmpty);
    expect(engine.message, 'Avanzaste 20.');
    expect(find.byKey(const ValueKey('token-move-popup')), findsNothing);

    engine.gameOver = true;
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    engine.dispose();
  });

  testWidgets(
    'a token center changes selection while the free destination still moves',
    (tester) async {
      final engine = GameEngine(mode: GameMode.traditional);
      final moving = engine.currentPlayer.tokens[0]..progress = 0;
      final occupying = engine.currentPlayer.tokens[1]..progress = 2;
      engine.hasRolled = true;
      engine.dice = [2, 3];
      engine.remainingDice.addAll([2, 3]);

      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tapBoardCell(tester, GameEngine.loop[0]);
      await tapBoardCell(tester, GameEngine.loop[2]);

      expect(moving.progress, 0);
      expect(occupying.progress, 2);
      expect(engine.remainingDice, [2, 3]);
      expect(find.text('FICHA 2 · PASOS'), findsOneWidget);

      await tapBoardCell(tester, GameEngine.loop[0]);
      expect(find.text('FICHA 1 · PASOS'), findsOneWidget);

      await tapBoardCell(tester, GameEngine.loop[2] + const Offset(0, .82));

      expect(moving.progress, 2);
      expect(occupying.progress, 2);
      expect(engine.remainingDice, [3]);
      expect(find.byKey(const ValueKey('token-move-popup')), findsNothing);

      engine.gameOver = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
      engine.dispose();
    },
  );

  testWidgets('tapping another jailed token replaces the popup selection', (
    tester,
  ) async {
    final engine = GameEngine(mode: GameMode.traditional);
    final first = engine.currentPlayer.tokens[0];
    final second = engine.currentPlayer.tokens[1];
    engine.hasRolled = true;
    engine.dice = [5, 5];
    engine.remainingDice.addAll([5, 5]);
    engine.message = 'Sacaste doble cinco.';

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tapBoardCell(
      tester,
      displayTokenCellsForTesting(engine, compactPhone: true)[first]!,
    );
    expect(find.text('FICHA 1 · SALIDA'), findsOneWidget);

    await tapBoardCell(
      tester,
      displayTokenCellsForTesting(engine, compactPhone: true)[second]!,
    );

    expect(first.inNest, isTrue);
    expect(second.inNest, isTrue);
    expect(engine.remainingDice, [5, 5]);
    expect(find.byKey(const ValueKey('token-move-popup')), findsOneWidget);
    expect(find.text('FICHA 1 · SALIDA'), findsNothing);
    expect(find.text('FICHA 2 · SALIDA'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('move-choice-5')));
    await tester.pump();

    expect(first.inNest, isTrue);
    expect(second.progress, 0);
    expect(engine.remainingDice, [5]);

    engine.gameOver = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    engine.dispose();
  });

  testWidgets('player chooses 2 and saves 3 for another token', (tester) async {
    final engine = GameEngine(mode: GameMode.traditional);
    final first = engine.currentPlayer.tokens[0]..progress = 0;
    final second = engine.currentPlayer.tokens[1]..progress = 10;
    engine.hasRolled = true;
    engine.dice = [2, 3];
    engine.remainingDice.addAll([2, 3]);
    engine.message = 'Sacaste 2 y 3.';

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tapBoardCell(tester, GameEngine.loop[0]);

    final board = find.byKey(const ValueKey('game-board'));
    final popup = find.byKey(const ValueKey('token-move-popup'));
    final controls = find.byType(GameControlPanel);
    expect(popup, findsOneWidget);
    expect(find.descendant(of: board, matching: popup), findsNothing);
    expect(find.descendant(of: controls, matching: popup), findsNothing);
    expect(find.byKey(const ValueKey('move-choice-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('move-choice-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('move-choice-all')), findsOneWidget);
    expect(find.text('Elige un dado o TODOS (5)'), findsOneWidget);
    final boardRect = tester.getRect(board);
    final controlsRect = tester.getRect(controls);
    final popupRect = tester.getRect(popup);
    expect(popupRect.top, greaterThanOrEqualTo(boardRect.bottom));
    expect(popupRect.bottom, lessThanOrEqualTo(controlsRect.top));
    expect(
      find.descendant(
        of: controls,
        matching: find.byKey(const ValueKey('move-choice-2')),
      ),
      findsNothing,
    );
    final boardPaint = find.descendant(
      of: find.byType(GameBoardMockup),
      matching: find.byType(CustomPaint),
    );
    var customPaint = boardPaint.evaluate().single.widget as CustomPaint;
    dynamic painter = customPaint.painter;
    var previews = List<MoveDestinationPreview>.from(
      painter.movePreviews as List<MoveDestinationPreview>,
    );
    expect(previews.map((preview) => preview.value), [2, 3, 5]);
    expect(previews[0].cell, GameEngine.loop[2]);
    expect(previews[0].color, PopColors.blue);
    expect(previews[1].cell, GameEngine.loop[3]);
    expect(previews[1].color, PopColors.red);
    expect(previews[2].cell, GameEngine.loop[5]);
    expect(previews[2].color, const Color(0xFF7057FF));
    expect(previews[2].usesAllDice, isTrue);

    await tester.tap(find.byKey(const ValueKey('move-choice-2')));
    await tester.pump();

    expect(first.progress, 2);
    expect(engine.remainingDice, [3]);
    expect(engine.message, 'Avanzaste 2.');
    expect(popup, findsNothing);
    customPaint = boardPaint.evaluate().single.widget as CustomPaint;
    painter = customPaint.painter;
    previews = List<MoveDestinationPreview>.from(
      painter.movePreviews as List<MoveDestinationPreview>,
    );
    expect(previews, isEmpty);

    await tapBoardCell(tester, GameEngine.loop[10]);

    expect(find.byKey(const ValueKey('move-choice-2')), findsNothing);
    expect(find.byKey(const ValueKey('move-choice-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('move-choice-all')), findsNothing);
    final secondPopupRect = tester.getRect(popup);
    expect(secondPopupRect.top, greaterThanOrEqualTo(boardRect.bottom));
    expect(secondPopupRect.bottom, lessThanOrEqualTo(controlsRect.top));

    await tester.tap(find.byKey(const ValueKey('move-choice-3')));
    await tester.pump();

    expect(second.progress, 13);
    expect(engine.remainingDice, isEmpty);

    engine.gameOver = true;
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    engine.dispose();
  });

  testWidgets('TODOS moves one token by both physical dice', (tester) async {
    final engine = GameEngine(mode: GameMode.traditional);
    final token = engine.currentPlayer.tokens.first..progress = 0;
    engine.hasRolled = true;
    engine.dice = [2, 3];
    engine.remainingDice.addAll([2, 3]);
    engine.message = 'Sacaste 2 y 3.';

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tapBoardCell(tester, GameEngine.loop[0]);

    expect(find.byKey(const ValueKey('move-choice-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('move-choice-3')), findsOneWidget);
    final allDiceButton = find.byKey(const ValueKey('move-choice-all'));
    expect(allDiceButton, findsOneWidget);

    await tester.tap(allDiceButton);
    await tester.pump();

    expect(token.progress, 5);
    expect(engine.remainingDice, isEmpty);
    expect(
      engine.message.toLowerCase(),
      anyOf(contains('todos'), contains('ambos dados')),
    );
    expect(find.byKey(const ValueKey('token-move-popup')), findsNothing);

    engine.gameOver = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    engine.dispose();
  });

  testWidgets('tapping the violet sum destination uses both dice', (
    tester,
  ) async {
    final engine = GameEngine(mode: GameMode.traditional);
    final token = engine.currentPlayer.tokens.first..progress = 0;
    engine.hasRolled = true;
    engine.dice = [2, 3];
    engine.remainingDice.addAll([2, 3]);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tapBoardCell(tester, GameEngine.loop[0]);

    final boardPaint = find.descendant(
      of: find.byType(GameBoardMockup),
      matching: find.byType(CustomPaint),
    );
    final customPaint = boardPaint.evaluate().single.widget as CustomPaint;
    dynamic painter = customPaint.painter;
    final previews = List<MoveDestinationPreview>.from(
      painter.movePreviews as List<MoveDestinationPreview>,
    );
    final sumPreview = previews.singleWhere((preview) => preview.usesAllDice);
    expect(sumPreview.value, 5);
    expect(sumPreview.cell, GameEngine.loop[5]);
    expect(sumPreview.color, const Color(0xFF7057FF));
    expect(find.byKey(const ValueKey('move-choice-all')), findsOneWidget);

    await tapBoardCell(tester, sumPreview.cell);

    expect(token.progress, 5);
    expect(engine.remainingDice, isEmpty);
    expect(find.byKey(const ValueKey('token-move-popup')), findsNothing);

    engine.gameOver = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    engine.dispose();
  });

  testWidgets('both dice animate again when a roll repeats both values', (
    tester,
  ) async {
    final engine = GameEngine(random: _WidgetSequenceRandom([2, 3, 2, 3]));
    engine.currentPlayer.tokens.first.progress = 0;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    engine.roll();
    await tester.pump();
    final firstBlueState = tester.state(
      find.byKey(const ValueKey('die-face-0')),
    );
    final firstRedState = tester.state(
      find.byKey(const ValueKey('die-face-1')),
    );
    dynamic blueState = firstBlueState;
    dynamic redState = firstRedState;
    expect(engine.dice, [3, 4]);
    expect(blueState.controller.isAnimating, isTrue);
    expect(redState.controller.isAnimating, isTrue);

    await tester.pump(const Duration(milliseconds: 850));
    expect(blueState.controller.isAnimating, isFalse);
    expect(redState.controller.isAnimating, isFalse);

    engine.hasRolled = false;
    engine.remainingDice.clear();
    engine.roll();
    await tester.pump();
    blueState = tester.state(find.byKey(const ValueKey('die-face-0')));
    redState = tester.state(find.byKey(const ValueKey('die-face-1')));

    expect(engine.dice, [3, 4], reason: 'both values intentionally repeated');
    expect(engine.rollSerial, 2);
    expect(identical(blueState, firstBlueState), isTrue);
    expect(identical(redState, firstRedState), isTrue);
    expect(blueState.controller.isAnimating, isTrue);
    expect(redState.controller.isAnimating, isTrue);

    engine.gameOver = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    engine.dispose();
  });

  testWidgets('a human victory shows one responsive celebration and rematch', (
    tester,
  ) async {
    final engine = oneMoveFromVictory();
    final finalToken = engine.currentPlayer.tokens.last;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(engine.moveToken(finalToken, die: 1), isTrue);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('victory-celebration')), findsNothing);
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byKey(const ValueKey('victory-celebration')), findsNothing);
    expect(engine.effectKind, PowerEffectKind.goal);
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('victory-celebration')), findsOneWidget);
    expect(find.text('¡GANASTE!'), findsOneWidget);
    expect(find.text('TÚ ERES EL CAMPEÓN'), findsOneWidget);
    expect(find.text('4 / 4 EN META'), findsOneWidget);
    expect(find.text('JUGAR OTRA VEZ'), findsOneWidget);
    expect(find.text('VOLVER AL INICIO'), findsOneWidget);
    final cardRect = tester.getRect(find.byKey(const ValueKey('victory-card')));
    expect(cardRect.left, greaterThanOrEqualTo(0));
    expect(cardRect.top, greaterThanOrEqualTo(0));
    expect(cardRect.right, lessThanOrEqualTo(390));
    expect(cardRect.bottom, lessThanOrEqualTo(844));

    engine
      ..notifyListeners()
      ..notifyListeners();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('victory-celebration')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700));
    expect(
      find.byKey(const ValueKey('victory-play-again')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('victory-play-again')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byKey(const ValueKey('game-board')), findsOneWidget);
    expect(find.textContaining('¡Tu turno!'), findsWidgets);
    expect(find.byKey(const ValueKey('victory-celebration')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    engine.dispose();
  });

  testWidgets('a CPU victory names the winner instead of congratulating you', (
    tester,
  ) async {
    final engine = oneMoveFromVictory(playerIndex: 1);
    final finalToken = engine.currentPlayer.tokens.last;
    await tester.binding.setSurfaceSize(const Size(1180, 820));
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(opponent: 'CPU • Normal', gameEngine: engine),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(engine.moveToken(finalToken, die: 1), isTrue);
    await tester.pump(const Duration(milliseconds: 1700));

    expect(find.text('¡BUENA PARTIDA!'), findsOneWidget);
    expect(find.text('CPU 1 GANA'), findsOneWidget);
    expect(find.text('¡GANASTE!'), findsNothing);
    expect(find.byKey(const ValueKey('victory-celebration')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    engine.dispose();
  });

  testWidgets(
    'winner can keep watching when the table uses fallback opponents',
    (tester) async {
      final engine = oneMoveFromVictory();
      final finalToken = engine.currentPlayer.tokens.last;
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            opponent: 'Mesa rápida • Normal',
            gameEngine: engine,
            cpuThinkDelayProvider: () => const Duration(milliseconds: 100),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(engine.moveToken(finalToken, die: 1), isTrue);
      await tester.pump(const Duration(milliseconds: 1800));

      final continueButton = find.byKey(
        const ValueKey('victory-continue-watching'),
      );
      expect(continueButton, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(continueButton);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const ValueKey('victory-celebration')), findsNothing);
      expect(engine.spectatorContinuationActive, isTrue);
      expect(engine.gameOver, isFalse);
      expect(engine.currentPlayer.color, PlayerColor.green);

      engine.gameOver = true;
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
      engine.dispose();
    },
  );

  testWidgets('online winner can keep watching the remaining players', (
    tester,
  ) async {
    final engine = oneMoveFromVictory();
    final finalToken = engine.currentPlayer.tokens.last;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'Online',
          gameEngine: engine,
          onlineSession: onlineTestSession(),
          cpuThinkDelayProvider: () => const Duration(seconds: 10),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(engine.moveToken(finalToken, die: 1), isTrue);
    await tester.pump(const Duration(milliseconds: 1800));

    final continueButton = find.byKey(
      const ValueKey('victory-continue-watching'),
    );
    expect(continueButton, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(continueButton);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('victory-celebration')), findsNothing);
    expect(engine.spectatorContinuationActive, isTrue);
    expect(engine.gameOver, isFalse);
    expect(engine.currentPlayer.color, PlayerColor.green);

    for (final expectedColor in const [PlayerColor.green, PlayerColor.yellow]) {
      expect(engine.currentPlayer.color, expectedColor);
      final player = engine.currentPlayer;
      for (var tokenId = 0; tokenId < 3; tokenId++) {
        player.tokens[tokenId].progress = GameEngine.finishProgress;
      }
      player.tokens.last.progress = GameEngine.finishProgress - 1;
      engine.hasRolled = true;
      engine.dice = const [1, 2];
      engine.remainingDice
        ..clear()
        ..addAll(const [1, 2]);
      expect(engine.moveToken(player.tokens.last, die: 1), isTrue);
    }

    await tester.pump(const Duration(milliseconds: 1800));
    expect(engine.gameOver, isTrue);
    expect(engine.finishOrder, PlayerColor.values);
    expect(find.byKey(const ValueKey('victory-celebration')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('victory-continue-watching')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
    await tester.binding.setSurfaceSize(null);
    engine.dispose();
  });

  testWidgets('online chat offers only safe preselected messages', (
    tester,
  ) async {
    final engine = GameEngine(mode: GameMode.chaos);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          opponent: 'Online',
          gameEngine: engine,
          onlineSession: onlineTestSession(),
        ),
      ),
    );
    await tester.pump();

    final chatButton = find.byKey(const ValueKey('game-safe-chat-button'));
    final playerStatus = find.byKey(const ValueKey('portrait-player-status'));
    expect(
      find.descendant(of: playerStatus, matching: chatButton),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('game-quick-bar')),
        matching: chatButton,
      ),
      findsNothing,
    );
    expect(find.text('⚡ CAOS'), findsNothing);
    expect(find.byKey(const ValueKey('game-mode-indicator')), findsOneWidget);
    expect(
      tester.getRect(chatButton).right,
      lessThanOrEqualTo(tester.getRect(playerStatus).right),
    );
    expect(tester.getSize(chatButton), const Size.square(44));

    await tester.tap(chatButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final sheet = find.byKey(const ValueKey('safe-chat-sheet'));
    final sheetRect = tester.getRect(sheet);
    final closeButton = find.byKey(const ValueKey('safe-chat-close'));
    expect(sheet, findsOneWidget);
    expect(find.text('PARCHÍS POP!'), findsOneWidget);
    expect(find.text('MENSAJES RÁPIDOS'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(tester.getSize(closeButton), const Size.square(44));
    expect(closeButton.hitTestable(), findsOneWidget);
    for (final phrase in SafeChatCatalog.phrases) {
      final action = find.byKey(ValueKey('safe-chat-${phrase.id.name}'));
      expect(action, findsOneWidget);
      expect(action.hitTestable(), findsOneWidget);
      final size = tester.getSize(action);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      final rect = tester.getRect(action);
      expect(rect.left, greaterThanOrEqualTo(sheetRect.left));
      expect(rect.top, greaterThanOrEqualTo(sheetRect.top));
      expect(rect.right, lessThanOrEqualTo(sheetRect.right));
      expect(rect.bottom, lessThanOrEqualTo(sheetRect.bottom));
    }
    final sheetScrollables = find.descendant(
      of: sheet,
      matching: find.byType(Scrollable),
    );
    for (var index = 0; index < sheetScrollables.evaluate().length; index++) {
      final scrollable = tester.state<ScrollableState>(
        sheetScrollables.at(index),
      );
      expect(scrollable.position.pixels, 0);
      expect(scrollable.position.maxScrollExtent, 0);
    }
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('safe-chat-hello')));
    await tester.pump(const Duration(milliseconds: 400));
    final banner = find.byKey(const ValueKey('safe-chat-banner'));
    expect(banner, findsOneWidget);
    expect(
      find.descendant(of: banner, matching: find.text('¡Hola!')),
      findsOneWidget,
    );

    await tester.binding.setSurfaceSize(const Size(844, 390));
    await tester.pump(const Duration(milliseconds: 400));
    expect(chatButton, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('game-rail-control')),
        matching: chatButton,
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('game-quick-bar')),
        matching: chatButton,
      ),
      findsNothing,
    );
    expect(tester.getSize(chatButton), const Size.square(44));
    expect(tester.takeException(), isNull);

    engine.gameOver = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    engine.dispose();
  });

  testWidgets('the victory home button returns to the first route', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final engine = oneMoveFromVictory();
    for (final token in engine.currentPlayer.tokens) {
      token.progress = GameEngine.finishProgress;
    }
    engine
      ..winner = engine.currentPlayer
      ..gameOver = true
      ..hasRolled = false
      ..remainingDice.clear();

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(
          body: SizedBox(key: ValueKey('home-route-marker')),
        ),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 720));

    expect(find.byKey(const ValueKey('victory-celebration')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(find.byKey(const ValueKey('victory-home')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.byKey(const ValueKey('home-route-marker')), findsOneWidget);
    expect(find.byType(GameScreen), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    engine.dispose();
  });
}
