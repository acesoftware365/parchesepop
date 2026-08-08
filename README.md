# Parchís Pop

Juego de parchés multiplataforma desarrollado con Flutter para iOS, Android,
macOS y Windows.

## Estado actual · versión 2.1

- Modos Tradicional y Caos.
- Quick Pop local de dos fichas por jugador para partidas más cortas.
- Partidas contra CPU y mesa rápida local con rivales identificados como CPU.
- Tablero completo con salidas, seguros, barreras, capturas y carriles de meta.
- Cubos animados, poderes automáticos, trampas, escudo y efectos visuales.
- Selección de un dado o de la suma de ambos, con vista previa del destino.
- Clasificación final de cuatro posiciones y puntuación por lugar.
- Tutorial contextual de seis pasos sobre el tablero, sin reducirlo.
- Monedas por terminar partidas, posición, primera partida diaria y misiones.
- Anuncio opcional después de la partida para duplicar el premio base.
- Tienda de temas, fichas, dados y avatares, con vista previa.
- Interfaz en español, inglés o idioma del sistema.
- Analítica anónima opcional —apagada por defecto y activable en Ajustes— de
  inicio, primera tirada, finalización, abandono, reanudación, revancha,
  tutorial, misiones, anuncios voluntarios y tienda.
- Banners AdMob solo fuera de partida/guía/búsqueda y rewarded ads voluntarios
  en iOS y Android; macOS no muestra anuncios.
- Diseño adaptable para teléfono, tableta, escritorio y ambas orientaciones.

El juego online competitivo todavía no se anuncia como disponible. El proyecto
incluye el contrato de autoridad, reconexión, idempotencia y validación que debe
ejecutarse en un servidor real antes de activar Quick Pop online, rangos o
eventos con recompensas.

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
flutter build apk --release --dart-define=QA_TEST_ADS=true
```

`QA_TEST_ADS` utiliza exclusivamente las unidades de prueba oficiales de
Google. Las compilaciones de producción omiten este parámetro y conservan las
unidades reales configuradas para la aplicación.

## Verificación

```bash
flutter analyze
flutter test
```

La información funcional y las decisiones del producto están documentadas en
[`INFORMACIÓN PARA CODEX DEL JUEGO DE PARCHÉ.md`](INFORMACI%C3%93N%20PARA%20CODEX%20DEL%20JUEGO%20DE%20PARCH%C3%89.md).
El inventario de audio solicitado se encuentra en
[`BRIEF_DE_AUDIO_PARCHESE_POP.md`](BRIEF_DE_AUDIO_PARCHESE_POP.md).
