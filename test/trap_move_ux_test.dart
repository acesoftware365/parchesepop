import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/main.dart';

Future<void> _tapBoardCell(WidgetTester tester, Offset cell) async {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('trap feedback', () {
    const expectedFeedback = <PowerUp, (String, String)>{
      PowerUp.glueTrap: ('¡PEGAMENTO!', 'próximo turno'),
      PowerUp.setbackTrap: ('¡RETROCESO!', '6 pasos'),
      PowerUp.prisonTrap: ('¡TRAMPA CÁRCEL!', 'volvió a la cárcel'),
      PowerUp.bomb: ('¡BOMBA!', 'volvió a la cárcel'),
    };

    for (final entry in expectedFeedback.entries) {
      testWidgets(
        '${entry.key.name} tells the player its exact trap and effect',
        (tester) async {
          final engine = GameEngine(mode: GameMode.chaos);
          const trapIndex = 26;
          engine.traps.add(
            BoardTrap(
              owner: PlayerColor.green,
              type: entry.key,
              loopIndex: trapIndex,
            ),
          );
          final token = engine.currentPlayer.tokens.first
            ..progress = trapIndex - 1;
          engine.hasRolled = true;
          engine.dice = const [1, 5];
          engine.remainingDice.addAll(const [1, 5]);

          expect(engine.moveToken(token, die: 1), isTrue);
          expect(engine.effectKind, PowerEffectKind.triggered);
          expect(engine.effectPowerUp, entry.key);
          expect(engine.message, contains(entry.value.$1));
          expect(engine.message, contains(entry.value.$2));
          expect(
            engine.eventHistory
                .lastWhere((event) => event.type == GameEventType.trap)
                .description,
            engine.message,
          );

          await tester.binding.setSurfaceSize(const Size(390, 844));
          await tester.pumpWidget(
            MaterialApp(
              home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
            ),
          );
          await tester.pump();

          expect(
            find.text(engine.message),
            findsOneWidget,
            reason:
                'The exact trap feedback must remain visible beside the '
                'game controls while the board effect runs.',
          );

          engine.gameOver = true;
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.binding.setSurfaceSize(null);
          engine.dispose();
        },
      );
    }
  });

  group('move selector placement and dismissal', () {
    testWidgets('selector is a strip between the board and JuanPop controls', (
      tester,
    ) async {
      final engine = GameEngine(mode: GameMode.traditional);
      engine.currentPlayer.tokens.first.progress = 0;
      engine.hasRolled = true;
      engine.dice = const [2, 3];
      engine.remainingDice.addAll(const [2, 3]);

      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await _tapBoardCell(tester, GameEngine.loop.first);

      final board = find.byKey(const ValueKey('game-board'));
      final selector = find.byKey(const ValueKey('token-move-popup'));
      final controls = find.byType(GameControlPanel);
      expect(selector, findsOneWidget);
      expect(find.descendant(of: board, matching: selector), findsNothing);
      expect(find.descendant(of: controls, matching: selector), findsNothing);

      final boardRect = tester.getRect(board);
      final selectorRect = tester.getRect(selector);
      final controlsRect = tester.getRect(controls);
      expect(selectorRect.top, greaterThanOrEqualTo(boardRect.bottom));
      expect(selectorRect.bottom, lessThanOrEqualTo(controlsRect.top));
      expect(tester.takeException(), isNull);

      engine.gameOver = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
      engine.dispose();
    });

    testWidgets('empty board tap dismisses selection without spending a die', (
      tester,
    ) async {
      final engine = GameEngine(mode: GameMode.traditional);
      final token = engine.currentPlayer.tokens.first..progress = 0;
      engine.hasRolled = true;
      engine.dice = const [2, 3];
      engine.remainingDice.addAll(const [2, 3]);

      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await _tapBoardCell(tester, GameEngine.loop.first);
      expect(find.byKey(const ValueKey('token-move-popup')), findsOneWidget);

      await _tapBoardCell(tester, const Offset(10, 10));

      expect(find.byKey(const ValueKey('token-move-popup')), findsNothing);
      expect(token.progress, 0);
      expect(engine.remainingDice, const [2, 3]);

      engine.gameOver = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
      engine.dispose();
    });

    testWidgets('tap outside the board and selector closes the selector', (
      tester,
    ) async {
      final engine = GameEngine(mode: GameMode.traditional);
      final token = engine.currentPlayer.tokens.first..progress = 0;
      engine.hasRolled = true;
      engine.dice = const [2, 3];
      engine.remainingDice.addAll(const [2, 3]);

      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await _tapBoardCell(tester, GameEngine.loop.first);
      expect(find.byKey(const ValueKey('token-move-popup')), findsOneWidget);

      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('game-quick-bar'))),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('token-move-popup')), findsNothing);
      expect(token.progress, 0);
      expect(engine.remainingDice, const [2, 3]);

      engine.gameOver = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
      engine.dispose();
    });

    testWidgets(
      'another token replaces selection and a destination completes it',
      (tester) async {
        final engine = GameEngine(mode: GameMode.traditional);
        final first = engine.currentPlayer.tokens[0]..progress = 0;
        final second = engine.currentPlayer.tokens[1]..progress = 10;
        engine.hasRolled = true;
        engine.dice = const [2, 3];
        engine.remainingDice.addAll(const [2, 3]);

        await tester.binding.setSurfaceSize(const Size(390, 844));
        await tester.pumpWidget(
          MaterialApp(
            home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        await _tapBoardCell(tester, GameEngine.loop[first.progress]);
        expect(find.text('FICHA 1 · PASOS'), findsOneWidget);

        await _tapBoardCell(tester, GameEngine.loop[second.progress]);
        expect(find.text('FICHA 1 · PASOS'), findsNothing);
        expect(find.text('FICHA 2 · PASOS'), findsOneWidget);

        await _tapBoardCell(tester, GameEngine.loop[second.progress + 3]);
        expect(second.progress, 13);
        expect(engine.remainingDice, const [2]);
        expect(find.byKey(const ValueKey('token-move-popup')), findsNothing);

        engine.gameOver = true;
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.binding.setSurfaceSize(null);
        engine.dispose();
      },
    );

    testWidgets(
      'tapping a different immovable token closes the current selector',
      (tester) async {
        final engine = GameEngine(mode: GameMode.traditional);
        engine.currentPlayer.tokens.first.progress = 0;
        final jailedToken = engine.currentPlayer.tokens[1];
        engine.hasRolled = true;
        engine.dice = const [2, 3];
        engine.remainingDice.addAll(const [2, 3]);

        await tester.binding.setSurfaceSize(const Size(390, 844));
        await tester.pumpWidget(
          MaterialApp(
            home: GameScreen(opponent: 'CPU • Fácil', gameEngine: engine),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        await _tapBoardCell(tester, GameEngine.loop.first);
        expect(find.text('FICHA 1 · PASOS'), findsOneWidget);

        await _tapBoardCell(
          tester,
          displayTokenCellsForTesting(engine, compactPhone: true)[jailedToken]!,
        );

        expect(jailedToken.inNest, isTrue);
        expect(find.byKey(const ValueKey('token-move-popup')), findsNothing);
        expect(engine.remainingDice, const [2, 3]);

        engine.gameOver = true;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.binding.setSurfaceSize(null);
        engine.dispose();
      },
    );
  });
}
