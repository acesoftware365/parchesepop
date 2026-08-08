import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/app_language.dart';
import 'package:parchesepop/player_progression.dart';
import 'package:parchesepop/progress_hub.dart';
import 'package:parchesepop/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Version 2 static and dynamic copy has complete English coverage', () {
    const staticCopy = <String, String>{
      'MESA RÁPIDA': 'QUICK TABLE',
      'Partida local con rivales CPU': 'Local match with CPU opponents',
      'Misiones': 'Missions',
      'TUTORIAL JUGABLE': 'PLAYABLE TUTORIAL',
      '¿CÓMO QUIERES APRENDER?': 'HOW DO YOU WANT TO LEARN?',
      'Empieza una partida guiada o consulta todas las reglas.':
          'Start a guided match or review all the rules.',
      'GUÍA COMPLETA': 'COMPLETE GUIDE',
      'Aprende dentro de tu primera partida': 'Learn during your first match',
      '1 · TIRA LOS DADOS': '1 · ROLL THE DICE',
      'Toca los dados en el panel inferior.':
          'Tap the dice in the bottom panel.',
      'YA SÉ JUGAR': 'I KNOW HOW TO PLAY',
      'Tu progreso': 'Your progress',
      'MISIONES DE HOY': "TODAY'S MISSIONS",
      'Mueve 20 casillas': 'Move 20 spaces',
      'Saca una ficha': 'Release a piece',
      'OBJETIVO SEMANAL': 'WEEKLY GOAL',
      'Termina 7 partidas': 'Finish 7 matches',
      'MONEDAS DISPONIBLES': 'AVAILABLE COINS',
      'LISTO': 'DONE',
      'Premios por jugar, no por pagar': 'Rewards for playing, not paying',
      'Esta partida local está en curso. Si sales ahora, se cerrará.':
          'This local match is in progress. If you leave now, it will end.',
      '2 / 2 EN META': '2 / 2 HOME',
      'CARGANDO ANUNCIO…': 'LOADING AD…',
    };

    for (final entry in staticCopy.entries) {
      expect(
        translateForLanguage(entry.key, 'en'),
        entry.value,
        reason: entry.key,
      );
    }

    const dynamicCopy = <String, String>{
      'Preparando partida local · 4s': 'Preparing local match · 4s',
      'Añadiendo CPU · 2/3': 'Adding CPU players · 2/3',
      'Parchís Pop · Caos': 'Parchís Pop · Chaos',
      'Tutorial • CPU Fácil': 'Tutorial • CPU Easy',
      'Nivel 3 · CPU temporal': 'Level 3 · Temporary CPU',
      '🇩🇴 Nv. 3 · CPU temporal': '🇩🇴 Lv. 3 · Temporary CPU',
      '¡Duplicaste tu premio: +70 monedas!':
          'You doubled your reward: +70 coins!',
      '+70 MONEDAS POR JUGAR': '+70 COINS FOR PLAYING',
      'VER ANUNCIO · DUPLICAR\n+70 MONEDAS': 'WATCH AD · DOUBLE\n+70 COINS',
      '+70 MONEDAS DUPLICADAS': '+70 DOUBLED COINS',
      'Tus dos fichas llegaron a la meta.': 'Your two pieces reached home.',
      'CPU Azul llevó sus dos fichas a la meta. ¡La revancha está lista!':
          'CPU Azul brought both pieces home. The rematch is ready!',
    };

    for (final entry in dynamicCopy.entries) {
      expect(
        translateForLanguage(entry.key, 'en'),
        entry.value,
        reason: entry.key,
      );
    }
  });

  testWidgets('Progress Hub follows the English AppLanguageScope', (
    tester,
  ) async {
    final language = AppLanguageController();
    final wallet = await WalletController.create();
    final progression = await PlayerProgressionController.create();
    addTearDown(language.dispose);
    addTearDown(wallet.dispose);
    addTearDown(progression.dispose);

    await language.select(AppLanguagePreference.english);
    await progression.recordCellsMoved(eventId: 'i18n_move', cells: 20);
    await progression.recordTokenReleased(eventId: 'i18n_release');

    await tester.pumpWidget(
      AppLanguageScope(
        controller: language,
        child: MaterialApp(
          home: ProgressHubScreen(progression: progression, wallet: wallet),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Your progress'), findsOneWidget);
    expect(find.text("TODAY'S MISSIONS"), findsOneWidget);
    expect(find.text('Move 20 spaces'), findsOneWidget);
    expect(find.text('Release a piece'), findsOneWidget);
    expect(find.text('Finish one match'), findsOneWidget);
    expect(find.text('DONE'), findsNWidgets(2));
    await tester.scrollUntilVisible(
      find.text('Finish 7 matches'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('WEEKLY GOAL'), findsOneWidget);
    expect(find.text('Finish 7 matches'), findsOneWidget);
    expect(find.text('Tu progreso'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
