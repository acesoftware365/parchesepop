# Parchese Pop

Juego de parchés multiplataforma desarrollado con Flutter para iOS, Android,
macOS y Windows.

## Estado actual

- Modos Tradicional y Caos.
- Partidas contra CPU y Partida Rápida local con rivales automáticos.
- Tablero completo con salidas, seguros, barreras, capturas y carriles de meta.
- Cubos animados, poderes automáticos, trampas, escudo y efectos visuales.
- Selección de un dado o de la suma de ambos, con vista previa del destino.
- Clasificación final de cuatro posiciones y puntuación por lugar.
- Tienda de temas, fichas, dados y avatares, con vista previa.
- Paquetes consumibles de monedas mediante App Store y Google Play; las
  monedas solo desbloquean contenido cosmético.
- Interfaz en español, inglés o idioma del sistema.
- Contrato de telemetría preparado para diferenciar Partida Rápida y partidas
  contra CPU. La compilación actual usa una implementación local `no-op`: no
  incluye Firebase ni envía eventos de Analytics.
- AdMob banner y rewarded ads en iOS y Android; macOS no muestra anuncios.
- Diseño adaptable para teléfono, tableta y escritorio. En iOS y Android, la
  experiencia de juego está optimizada y fijada en orientación vertical.

## Soporte y privacidad

- Soporte: [sales@liisgo.com](mailto:sales@liisgo.com)
- Política de privacidad:
  [https://liisgo.com/#/apps/ParchesePop/privacy](https://liisgo.com/#/apps/ParchesePop/privacy)

## Recursos de publicación

Los recursos finales de las tiendas están versionados en:

- Google Play: [`store_assets/google_play/`](store_assets/google_play/)
- iPhone/iPad: [`store_assets/ios/`](store_assets/ios/)
- macOS: [`store_assets/macos/`](store_assets/macos/)
- Iconos fuente: [`assets/branding/`](assets/branding/)

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
