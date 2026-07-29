# Parchese Pop — publicación de tiendas

## Datos comunes

- **Nombre:** Parchese Pop
- **Categoría:** Juegos > Mesa / Board
- **Jugadores:** 4 por partida
- **Modelo en Android/iOS:** Gratis con banners, anuncios recompensados
  opcionales y compras consumibles dentro de la app.
- **Modelo en macOS:** Sin banners ni anuncios recompensados. Su monetización
  se administra por separado de la versión móvil.
- **Soporte:** sales@liisgo.com
- **Sitio web:** https://liisgo.com
- **Política de privacidad:** https://liisgo.com/#/apps/ParchesePop/privacy
- **Idiomas:** Español e inglés

## Descripción (español)

Parchese Pop transforma el parchís clásico en una experiencia colorida, moderna y llena de acción. Lanza los dados, saca tus fichas con un 5, recorre el tablero y llévalas al centro para ganar. Partida Rápida prepara una mesa en tu dispositivo y completa automáticamente los asientos con rivales del juego, sin exigir una cuenta; también puedes practicar contra CPU y elegir su dificultad. Juega en modo Tradicional, con las reglas clásicas, o en modo Caos, donde aparecen poderes, escudos y trampas estratégicas.

### Características

- Partida Rápida local de cuatro puestos con rivales automáticos del juego.
- Partidas contra CPU con tres niveles de dificultad.
- Perfil opcional; no hace falta iniciar sesión para jugar.
- Modo Tradicional y Modo Caos.
- Dados, fichas, tableros y avatares personalizables.
- Poderes automáticos, escudos y trampas visuales.
- Mensajes rápidos preseleccionados y seguros.
- Español e inglés.

## English description

Parchese Pop brings the classic board game to life in a colorful, modern experience full of action. Roll the dice, bring your pieces out with a 5, race around the board, and get them to the center to win. Quick Match prepares a table on your device and automatically completes its seats with game rivals, with no account required; you can also practice against the CPU at three difficulty levels. Choose Traditional mode for classic rules or Chaos mode for strategic powers, shields, and traps.

## Promotional text

Dados, estrategia y poderes: lleva tus cuatro fichas al centro en Parchese Pop.

## Google Play short description

Parchís clásico con CPU, poderes, trampas y partidas rápidas.

## Google Play short description (English)

Classic Parchese with CPU rivals, powers, traps, and fast local matches.

## Apple subtitle

- **Español:** Parchís clásico con poderes
- **English:** Classic dice, traps & powers

## Apple keywords

- **Español:** parchís,parqués,dados,tablero,estrategia,trampas,poderes,familiar,casual
- **English:** parcheesi,parchis,dice,board,strategy,traps,powers,family,casual

## Consumables — same IDs for Apple and Google

| Product ID | Coins | Reference price |
| --- | ---: | ---: |
| com.liisgo.parchesepop.coins.500 | 500 | USD 0.99 |
| com.liisgo.parchesepop.coins.1200 | 1,200 | USD 1.99 |
| com.liisgo.parchesepop.coins.3000 | 3,000 | USD 4.99 |
| com.liisgo.parchesepop.coins.7000 | 7,000 | USD 9.99 |
| com.liisgo.parchesepop.coins.16000 | 16,000 | USD 19.99 |

The IDs and coin quantities above are the source-of-truth values in
`lib/coin_store.dart`. Prices are fallback references; App Store and Google
Play provide the localized price shown to each customer. Coins only unlock
cosmetic content and do not provide a competitive advantage.

## Assets

- Google Play feature graphic:
  `store_assets/google_play/feature-graphic-1024x500.png`
- Google Play icon: `store_assets/google_play/icon-512-rgba.png`
- iOS screenshots:
  - `store_assets/ios/01-home-1290x2796.png`
  - `store_assets/ios/02-gameplay-1290x2796.png`
  - `store_assets/ios/03-shop-1290x2796.png`
- iPad 13-inch screenshots:
  - `store_assets/ipad/01-home-2064x2752.png`
  - `store_assets/ipad/02-gameplay-2064x2752.png`
  - `store_assets/ipad/03-shop-2064x2752.png`
- macOS screenshots:
  - `store_assets/macos/01-home-1440x900.png`
  - `store_assets/macos/02-gameplay-1440x900.png`
  - `store_assets/macos/03-traps-1440x900.png`
  - `store_assets/macos/04-bomb-trap-1440x900.png`
  - `store_assets/macos/01-settings-1440x900.png`
- Source branding icons: `assets/branding/`

Store captures use generic profiles and final clean builds. Files named
`*-source.png` under `store_assets/ios/` are working sources, not final
upload assets.

## Estado de publicación — 29 de julio de 2026

- Apple: ficha creada para iOS y macOS, metadatos y recursos preparados. El
  archivo iOS `1.0.0 (4)` se genera correctamente, pero la entrega a App Store
  Connect continúa bloqueada hasta iniciar sesión en Xcode y disponer del
  certificado y perfil de distribución de Apple. No se ha verificado una
  subida de esta compilación a Apple.
- Google Play: la versión `1.0.0 (4) - Quick Match` está publicada en el canal
  de pruebas internas. El grupo de correo `Tester` (1 usuario) está
  seleccionado y guardado. Play Console todavía muestra el canal como
  **Inactive** hasta completar la configuración pendiente; esto no equivale a
  un lanzamiento público.
- Ficha de Google Play: las fichas en inglés y español latino quedaron
  guardadas. La ficha predeterminada incluye el icono final y cuatro capturas
  en cada grupo de dispositivos: teléfono, tableta de 7 pulgadas y tableta de
  10 pulgadas. La ficha española hereda los recursos visuales predeterminados.
- Revisión de Google Play: el único bloqueo restante para **Send app for
  review** es completar la clasificación de contenido IARC y aceptar sus
  términos. El correo y la categoría `Game` están preparados, pero los
  términos no se han aceptado en nombre del propietario.
- Recursos: las capturas finales de iPhone, iPad, Google Play y macOS están en
  `store_assets/`. Todos los PNG de entrega tienen dimensiones válidas, color
  RGB y no contienen transparencia, anuncios ni datos personales.
- Analytics: la compilación actual usa `NoopGameAnalytics`; no incluye Firebase
  ni transmite eventos de Analytics.
- AdMob: IDs de banner y rewarded configurados solo para Android/iOS. macOS no
  muestra anuncios.
- Compras: `CoinStore` consulta y compra los cinco productos consumibles
  anteriores mediante StoreKit o Google Play Billing. Los cinco productos
  están activos en Google Play; todavía deben crearse o verificarse en App
  Store Connect antes de enviar la versión de Apple a revisión.
