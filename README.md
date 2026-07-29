# Parchese Pop

Juego de parchés multiplataforma desarrollado con Flutter para iOS, Android,
macOS y Windows.

## Estado actual

- Modos Tradicional y Caos.
- Partidas contra CPU y experiencia online con continuidad automática.
- Tablero completo con salidas, seguros, barreras, capturas y carriles de meta.
- Cubos animados, poderes automáticos, trampas, escudo y efectos visuales.
- Selección de un dado o de la suma de ambos, con vista previa del destino.
- Clasificación final de cuatro posiciones y puntuación por lugar.
- Tienda de temas, fichas, dados y avatares, con vista previa.
- Interfaz en español, inglés o idioma del sistema.
- Google Analytics para diferenciar partidas online y contra CPU.
- AdMob banner y rewarded ads en iOS y Android; macOS no muestra anuncios.
- Diseño adaptable para teléfono, tableta, escritorio y ambas orientaciones.

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

## Verificación

```bash
flutter analyze
flutter test
```

La información funcional y las decisiones del producto están documentadas en
[`INFORMACIÓN PARA CODEX DEL JUEGO DE PARCHÉ.md`](INFORMACI%C3%93N%20PARA%20CODEX%20DEL%20JUEGO%20DE%20PARCH%C3%89.md).
El inventario de audio solicitado se encuentra en
[`BRIEF_DE_AUDIO_PARCHESE_POP.md`](BRIEF_DE_AUDIO_PARCHESE_POP.md).
