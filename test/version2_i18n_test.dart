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
      'Partida rápida online': 'Quick casual online play',
      'Amigos online · crea una sala':
          'Play online with friends · create a room',
      'Hasta 4 en una tablet': 'Up to 4 on one tablet',
      'Mesa compartida': 'Shared table',
      'Turnos y asientos': 'Turns and seats',
      'Misiones y victoria': 'Missions and victory',
      'JUEGA CON AMIGOS': 'PLAY WITH FRIENDS',
      'CREAR SALA': 'CREATE ROOM',
      'ENTRAR CON CÓDIGO': 'JOIN WITH CODE',
      'SALAS PÚBLICAS': 'PUBLIC ROOMS',
      'PARTIDA LOCAL': 'LOCAL MATCH',
      'QUIÉN PUEDE ENTRAR': 'WHO CAN JOIN',
      'PRIVADA': 'PRIVATE',
      'PÚBLICA': 'PUBLIC',
      'ESCRIBE EL CÓDIGO DE LA SALA': 'ENTER THE ROOM CODE',
      'ENTRAR A LA SALA': 'JOIN ROOM',
      'SALA ONLINE': 'ONLINE ROOM',
      'Ya no estás en la sala.': 'You are no longer in the room.',
      'La operación tardó demasiado. Revisa tu conexión e inténtalo otra vez.':
          'The operation took too long. Check your connection and try again.',
      'La operación fue cancelada.': 'The operation was canceled.',
      'MARCAR LISTO': 'MARK READY',
      'INICIAR TIRADA': 'START OPENING ROLL',
      'TIRADA PARA COMENZAR': 'ROLL TO START',
      'Partida local con rivales CPU': 'Local match with CPU opponents',
      'ONLINE · PRÓXIMAMENTE': 'ONLINE · COMING SOON',
      '2 fichas · partida rápida': '2 pieces · quick match',
      'Partida local': 'Local match',
      'Juega contra el CPU': 'Play against CPU',
      'QUICK POP ONLINE': 'QUICK POP ONLINE',
      'JUGAR CON AMIGOS ONLINE': 'PLAY WITH FRIENDS ONLINE',
      'Buscando un jugador online…': 'Searching for an online player…',
      'Luego jugarás contra CPU automáticamente':
          'Then you will automatically play against the CPU',
      'JUGAR ONLINE · BUSCAR 10 S': 'PLAY ONLINE · SEARCH 10 S',
      'JUGAR AHORA CONTRA CPU': 'PLAY NOW AGAINST CPU',
      'El modo online necesita conexión con un servidor seguro. Mientras lo terminamos, puedes probar Quick Pop contra el CPU.':
          'Online play requires a secure server connection. While we finish it, you can try Quick Pop against the CPU.',
      'PROBAR QUICK POP': 'TRY QUICK POP',
      'AHORA NO': 'NOT NOW',
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
      'CARGANDO…': 'LOADING…',
      'POR JUGAR': 'FOR PLAYING',
      'VER ANUNCIO': 'WATCH AD',
      'EXTRA RECIBIDAS': 'EXTRA RECEIVED',
      'Borrando cuenta de forma segura…': 'Deleting account securely…',
      'No se completó el borrado': 'Deletion was not completed',
      'Intentar de nuevo': 'Try again',
      'Mide sesiones, retención y pasos online de Quick Pop y Quick Table, sin enviar nombre, correo ni códigos de sala':
          'Measures sessions, retention, and Quick Pop and Quick Table online steps without sending names, email, or room codes',
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
      'Entrando a la sala ABC234…': 'Joining room ABC234…',
      'Maria saldrá de la sala.': 'Maria will be removed from the room.',
      'Maria · TÚ': 'Maria · YOU',
      'Expulsar Maria': 'Remove Maria',
      '2/4 jugadores': '2/4 players',
      'CLÁSICO · 2/4 · ABC234': 'CLASSIC · 2/4 · ABC234',
      'DESEMPATE · RONDA 2': 'TIEBREAK · ROUND 2',
      'COMENZAR · Maria': 'START · Maria',
      'Maria comienza. Esperando al anfitrión…':
          'Maria starts. Waiting for the host…',
      'Parchís Pop · Caos': 'Parchís Pop · Chaos',
      'Tutorial • CPU Fácil': 'Tutorial • CPU Easy',
      'Nivel 3 · CPU temporal': 'Level 3 · Temporary CPU',
      '🇩🇴 Nv. 3 · CPU temporal': '🇩🇴 Lv. 3 · Temporary CPU',
      '¡Duplicaste tu premio: +70 monedas!':
          'You doubled your reward: +70 coins!',
      '+70 MONEDAS POR JUGAR': '+70 COINS FOR PLAYING',
      '+70 MONEDAS': '+70 COINS',
      'VER ANUNCIO\n+70 MONEDAS EXTRA': 'WATCH AD\n+70 EXTRA COINS',
      '+70 MONEDAS EXTRA RECIBIDAS': '+70 EXTRA COINS RECEIVED',
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

  test('Version 2 advertising copy describes the persistent safe banner', () {
    const detailedSpanish =
        'En Android y iOS puede permanecer visible una banda publicitaria adaptable en una franja reservada en la parte inferior, incluso durante la partida, la guía y la búsqueda de jugadores. Esta banda no cubre los controles ni interrumpe una jugada. Los anuncios recompensados son siempre voluntarios: pueden ofrecerse en la tienda por la bonificación indicada y al finalizar la mesa para duplicar una recompensa elegible. Solo se abren cuando los eliges y la recompensa se entrega únicamente al completar el anuncio. Las acciones normales del juego, como tirar los dados, mover una ficha, Jugar otra vez, Volver al inicio y Reanudar, nunca abren anuncios a pantalla completa o recompensados. La aplicación solicita consentimiento cuando corresponde y ofrece opciones para administrar la privacidad publicitaria. macOS no muestra banners ni anuncios recompensados.';
    const detailedEnglish =
        'On Android and iOS, an adaptive ad banner may remain visible in a reserved strip at the bottom, including during gameplay, the guide, and matchmaking. This banner does not cover controls or interrupt a move. Rewarded ads are always voluntary: they may be offered in the Shop for the stated bonus and after the table finishes to double an eligible reward. They open only when you choose them, and the reward is granted only after the ad is completed. Normal game actions, such as rolling the dice, moving a piece, Play Again, Back to Home, and Resume, never open full-screen or rewarded ads. The app requests consent when required and provides options to manage ad privacy. macOS does not show banners or rewarded ads.';
    const summarySpanish =
        'Android y iOS pueden mantener una banda publicitaria adaptable en una franja inferior reservada, incluso durante la partida, la guía y la búsqueda de jugadores. Los anuncios recompensados son siempre voluntarios en la tienda y al finalizar la mesa; las acciones normales del juego nunca los abren. Puedes administrar el consentimiento y las preferencias disponibles desde esta pantalla. La versión de macOS no muestra estos anuncios.';
    const summaryEnglish =
        'Android and iOS may keep an adaptive ad banner in a reserved bottom strip, including during gameplay, the guide, and matchmaking. Rewarded ads are always voluntary in the Shop and after the table finishes; normal game actions never open them. You can manage consent and available preferences from this screen. The macOS version does not show these ads.';

    expect(translateForLanguage(detailedSpanish, 'en'), detailedEnglish);
    expect(translateForLanguage(summarySpanish, 'en'), summaryEnglish);
  });

  test('Quick Pop search phases are translated completely', () {
    expect(
      translateForLanguage('Preparando la búsqueda online…', 'en'),
      'Preparing the online search…',
    );
    expect(
      translateForLanguage('Sincronizando la mesa con el otro jugador…', 'en'),
      'Syncing the table with the other player…',
    );
    expect(
      translateForLanguage('Confirmando la partida con el otro jugador…', 'en'),
      'Confirming the match with the other player…',
    );
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
