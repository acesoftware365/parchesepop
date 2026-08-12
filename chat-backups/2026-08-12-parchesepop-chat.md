# Parchís Pop — respaldo del chat

**Fecha:** 12 de agosto de 2026
**Proyecto:** `Parchese Pop`
**Rama:** `version-2`

## Registro de decisiones y trabajo

- Se mantuvo el nombre y la identidad visual del juego como **Parchís Pop**.
- Se organizó el tablero móvil para conservar el tablero completo, el minimapa interactivo y el HUD fijo sin reducir el tablero por culpa del banner.
- El minimapa vuelve a mostrar el tablero completo cuando no se toca y activa el zoom únicamente mientras el jugador mantiene el dedo sobre él.
- Los dados se colocan en la zona principal de acción; la animación usa la mano transparente, el dado equipado y una fase de lanzamiento/rodado/zoom sin la caja blanca.
- Se conservaron las recompensas voluntarias por anuncios: el anuncio nunca bloquea reanudar, jugar otra vez, volver al inicio ni una jugada normal.
- Quick Pop quedó definido como modo rápido online con dos fichas por jugador y fallback a CPU cuando no se encuentra un jugador dentro de la ventana configurada.
- Quick Table quedó definido para partidas locales o con amigos online mediante sala, código, acceso público/privado, invitación y control del anfitrión.
- El flujo online incluye sincronización de sala, ready, desempate de apertura, orden horario, reconexión y sustitución por CPU cuando un jugador abandona según las reglas del modo.
- Se corrigió el flujo de Quick Pop online en el que, después de capturar una ficha, el bono de **+20 pasos** podía quedar bloqueado. El checkpoint conserva el bono, la interfaz evita doble toque, espera revisiones atrasadas y reintenta rechazos transitorios.
- Se añadieron perfiles de revisión responsive para: teléfono pequeño, Fold 8, Fold 8 Ultra, Flip 8, tablet de 8 pulgadas y tablet de 13 pulgadas.
- Durante la revisión responsive se encontró y corrigió un overflow pequeño en las tarjetas compactas de inicio. El tablero y sus reglas no fueron cambiados por ese ajuste.

## Verificación realizada

- `flutter analyze --no-fatal-infos`: sin problemas.
- Pruebas de orientación, minimapa, mano/dados y banner adaptativo: **75/75** correctas.
- Pruebas de captura y burbujas de movimiento: **10/10** correctas.
- Pruebas de sincronización online de Quick Pop: **17/17** correctas.
- Pruebas de motor y reglas Quick Pop: **113/113** correctas.
- La prueba de regresión confirma que una captura seguida inmediatamente por el bono +20 funciona en las dos réplicas online.

## Nota sobre la revisión Android

Los perfiles Android fueron creados y el emulador pequeño llegó a arrancar. La compilación visual del APK quedó limitada por archivos `._*` de AppleDouble que macOS vuelve a crear dentro del build del disco externo. Es un problema del entorno de archivos, no un error de Dart ni del layout; el análisis y las pruebas de Flutter permanecen limpios.

## Estado de publicación

- No se envió APK en esta fase.
- No se envió ningún mensaje a Marianny.
- Esta copia se guarda junto al proyecto y en el respaldo del disco externo antes del push.
