# Parchís Pop

Juego de parchés multiplataforma desarrollado con Flutter para iOS, Android,
macOS y Windows.

## Estado actual · versión 2.2

- Modos Tradicional y Caos.
- Quick Pop de dos fichas por jugador para partidas más cortas: busca a otro
  jugador online durante cinco segundos. Si al llegar al límite no existe un
  compromiso humano compartido, abre la partida local contra CPU; si una
  partida humana ya fue comprometida pero la conexión no permite confirmar el
  mismo resultado en ambos dispositivos, muestra una opción honesta para
  revisar la conexión y volver, sin separar a los jugadores.
- Quick Table local y online con salas públicas o privadas, código de seis
  caracteres, invitación compartible, hasta cuatro jugadores y tirada inicial
  para decidir quién comienza; los turnos continúan hacia la derecha.
- Partidas contra CPU y mesa rápida local con rivales identificados como CPU.
- Tablero completo con salidas, seguros, barreras, capturas y carriles de meta.
- Cubos animados, poderes automáticos, trampas, escudo y efectos visuales.
- Selección de un dado o de la suma de ambos, con vista previa del destino.
- Clasificación final de cuatro posiciones y puntuación por lugar.
- Tutorial contextual de seis pasos sobre el tablero, sin reducirlo.
- Monedas por terminar partidas, posición, primera partida diaria y misiones.
- Botón voluntario y permanente después de la partida para obtener el bonus
  recompensado en todos los modos móviles; nunca bloquea las demás acciones y,
  tras reclamarlo, muestra el estado recibido sin permitir pagos duplicados.
- Tienda de temas, fichas, dados y avatares, con vista previa.
- Interfaz en español, inglés o idioma del sistema.
- Analítica anónima opcional —apagada por defecto y activable en Ajustes— de
  sesión y retención, primera tirada, finalización, abandono, reanudación,
  revancha, tutorial, misiones, anuncios voluntarios, tienda y embudos de
  conexión de Quick Pop y Quick Table. No registra nombres, códigos de sala,
  identificadores de cuenta ni errores sin filtrar.
- Banners AdMob adaptables pueden aparecer como una banda inferior reservada en
  iOS y Android, incluso durante una partida, la guía o la búsqueda, sin cubrir
  controles, pausar ni interrumpir una jugada. Los rewarded ads se abren solo
  cuando el jugador los elige voluntariamente; macOS no muestra anuncios.
- Diseño adaptable para teléfono, tableta, escritorio y ambas orientaciones.

Quick Pop online y las salas casuales de Quick Table están disponibles para
pruebas controladas sobre Firebase. El modo clasificado, premios competitivos y
una publicación social a gran escala todavía requieren autoridad confiable del
servidor, App Check, moderación y endurecimiento operativo; por eso no se
anuncian como funciones de producción.

## Ejecutar

```bash
flutter pub get
flutter run
```

Para iniciar en un dispositivo concreto:

```bash
flutter devices
flutter run -d <device-id>
```

Para generar un APK optimizado de prueba sin servir anuncios reales:

```bash
PARCHES_POP_ALLOW_DEBUG_RELEASE_APK=true flutter build apk --release --dart-define=QA_TEST_ADS=true
```

`QA_TEST_ADS` utiliza exclusivamente las unidades de prueba oficiales de
Google. `PARCHES_POP_ALLOW_DEBUG_RELEASE_APK` permite únicamente el APK QA
firmado con el certificado de depuración cuando todavía no existe un keystore
privado de distribución. Nunca se debe publicar ese APK en una tienda. Las
compilaciones de producción omiten `QA_TEST_ADS` y requieren su propio keystore
seguro, sin esta excepción de QA.

## Verificación

```bash
flutter analyze
flutter test
```

La información funcional y las decisiones del producto están documentadas en
[`INFORMACIÓN PARA CODEX DEL JUEGO DE PARCHÉ.md`](INFORMACI%C3%93N%20PARA%20CODEX%20DEL%20JUEGO%20DE%20PARCH%C3%89.md).
El inventario de audio solicitado se encuentra en
[`BRIEF_DE_AUDIO_PARCHESE_POP.md`](BRIEF_DE_AUDIO_PARCHESE_POP.md).
