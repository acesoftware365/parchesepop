# Información para Codex del juego de Parché

## Propósito del archivo

Este es el documento permanente de contexto del proyecto. Debe actualizarse cuando se apruebe una nueva regla, función, sistema visual, decisión comercial o cambio técnico. Su función es evitar que se pierdan las decisiones del juego entre sesiones.

## Concepto general

Parchese es una adaptación digital de parchís para cuatro colores. Mantiene el recorrido clásico de fichas, dados, cárcel, seguros, barreras y meta, pero añade cubos sorpresa, objetos, trampas, personalización completa, tienda, partidas contra CPU y una Partida Rápida local con rivales automáticos.

## Identidad y ubicación del proyecto

- Nombre de trabajo y marca principal: **Parchese Pop**.
- Repositorio oficial: `https://github.com/acesoftware365/parchesepop`.
- Tecnología actual: Flutter.
- Plataformas incluidas: iOS, Android, Windows y macOS.
- Tema visual principal: **Arcade Pop**, una estética colorida, moderna y familiar inspirada en la energía de los juegos arcade, sin copiar personajes, mundos, sonidos ni elementos protegidos de otras franquicias.
- Paleta base sugerida: azul `#2474E5`, rojo coral `#F04452`, amarillo `#FFC83D`, verde `#32B875`, azul oscuro `#17284D`, fondo claro `#F4F7FC` y texto `#243047`.
- Paquetes visuales considerados: Neon Rush, Golden Night, Royal Quest, Galaxy Run, Wild Jungle y Casino Luxe.

## Primera arquitectura de pantallas

1. Bienvenida y creación de perfil.
2. Inicio con Partida rápida y Contra CPU.
3. Selección Tradicional/Caos para Partida Rápida o Contra CPU.
4. Selección de dificultad cuando se juega contra CPU.
5. Preparación local de rivales con temporizador de 8 segundos.
6. Partida y tablero adaptable.
7. Tienda de temas, fichas, dados y efectos.
8. Perfil y edición de nombre, correo y bandera.
9. Ajustes de sonido, música, vibración e idioma.
10. Privacidad, términos, conducta, publicidad y eliminación de cuenta.
11. Resultados, recompensas y siguiente partida.

## Estado actual de implementación

La primera versión funcional en Flutter incluye:

- Entrada como invitado sin registro obligatorio.
- Registro opcional con nombre, correo y bandera.
- Partida Rápida disponible para invitados, sin cuenta ni inicio de sesión.
- Menú principal rediseñado como lobby Arcade Pop: fondo azul/violeta con
  motivos de parchés, entrada animada, ficha de jugador con avatar equipado,
  nivel y bandera, botones Partida Rápida/CPU con profundidad 3D y reacción al toque,
  y dock inferior para Tienda, Perfil, Cómo jugar y Trampas.
- Tablero dibujado como parchís con bases circulares, fichas, recorrido, pasillos de meta, seguros, centro y cubos.
- Motor local de turnos para un jugador y tres CPU.
- Dos dados, salida de cárcel con 5, movimientos legales y llegada exacta.
- Capturas, casillas seguras, barreras básicas y victoria.
- CPU con selección de jugadas en niveles Fácil, Normal y Experto.
- Cuatro cristales sorpresa dinámicos que entregan Escudo, Turbo, Pegamento, Retroceso, Cárcel o Bomba.
- Premio de movimiento de 20 por captura y 10 por llevar una ficha a casa.
- Penalización por tres dobles consecutivos.
- Animación de dados con giro, escala y sombra.
- Movimiento de fichas animado casilla por casilla, incluyendo el giro correcto hacia el pasillo de meta, con rebote suave.
- Al seleccionar una ficha, cada movimiento legal marca y pulsa su casilla exacta de destino con el mismo color de su botón. Los dados usan azul y rojo y el bono de 10 usa verde. El bono de 20 utiliza una guía individual F1–F4: cada ficha y su destino comparten un color estable.
- Tienda visual, ajustes, políticas y publicidad móvil integrada.
- Persistencia local del perfil.
- Pruebas automatizadas del motor y de siete tamaños de pantalla.

Pendiente para producción:

- Continuar afinando el aspecto del tablero tradicional de 68 casillas sin cambiar su geometría ni sus posiciones funcionales.
- Completar animaciones de captura, cubos, objetos, victoria y resultados.
- Añadir sonidos, tutorial y resultados completos.
- Backend de cuentas, base de datos, partidas online reales y reconexión.
- Validación de recibos de compras en servidor y activación de los cinco
  productos consumibles en App Store Connect y Google Play Console. El catálogo
  cosmético y el cliente de compras ya están implementados.
- Validar en producción la configuración regional de consentimiento, privacidad
  y tratamiento adecuado para la edad del usuario.
- Políticas legales definitivas y sistema de moderación en servidor.

El nombre de jugador permite entre 3 y 12 caracteres. El prototipo incluye validación local y una lista básica de palabras bloqueadas; la moderación definitiva deberá ejecutarse también en el servidor. El perfil se guarda localmente durante esta primera fase.

## Diseño adaptable

- Teléfono pequeño: el tablero cuadrado empieza arriba y ocupa el 100 % del
  ancho seguro; sus controles aparecen inmediatamente debajo.
- Teléfono grande: la misma jerarquía, sin margen lateral artificial y con un
  tablero que crece exactamente con el ancho seguro.
- Tabletas de 7, 10 y 11 pulgadas: cuadrícula de contenido, paneles amplios y navegación adaptable.
- macOS y Windows: navegación lateral, tablero cuadrado y panel de control a la derecha.
- La ventana inicial de macOS se centra y calcula su tamaño según el área visible del monitor. El mínimo inicial definido es 760 x 620.
- Tamaños de prueba iniciales: 390 x 844, 402 x 874, 440 x 956, 600 x 960, 800 x 1280, 834 x 1194 y 1180 x 820.

## Publicidad

- Android e iOS muestran un banner adaptable fijo en la parte inferior de todas
  las pantallas. La franja pertenece al contenedor global de la aplicación, no
  a cada pantalla individual, para evitar duplicados al navegar.
- El banner siempre queda fuera del tablero y de los controles. Nunca cubre
  fichas, información de turno ni ventanas de movimiento; el contenido recibe
  su espacio disponible por encima de la franja.
- La tienda ofrece un anuncio recompensado voluntario de `+100` monedas en
  Android e iOS. Las monedas se acreditan únicamente cuando la red confirma
  que el usuario completó el anuncio; cerrar, cancelar o fallar no entrega el
  premio.
- Al iniciar la aplicación móvil se actualiza el estado de consentimiento.
  Los anuncios se solicitan solamente cuando se permite hacerlo y Ajustes
  ofrece `Opciones de privacidad de anuncios` cuando el proveedor lo exige.
- Durante desarrollo se utilizan unidades publicitarias oficiales de prueba;
  las compilaciones de publicación usan las unidades propias de Parchese Pop.
- macOS no carga el SDK, no reserva espacio, no muestra banners y no ofrece
  anuncios recompensados. Su monetización se resolverá mediante un sistema
  separado. Windows tampoco utiliza AdMob.
- No se mostrará un anuncio intersticial obligatorio en cada turno. Los intersticiales se reservarán para pausas naturales, preferiblemente al finalizar una partida, y los anuncios recompensados serán opcionales.
- Las animaciones que aparecen brevemente dentro de una base de color al capturar, activar una bomba o disparar una trampa serán avisos del propio juego, no anuncios publicitarios reales ni elementos pulsables.
- No se insertará un anuncio de red que cubra una base o el tablero durante un evento de la partida. Además de interrumpir la jugada, esa ubicación aumenta el riesgo de toques accidentales y rechazo por políticas publicitarias.
- AdMob se utiliza solamente en Android e iOS.

## Soporte, privacidad y recursos de tiendas

- Correo oficial de soporte: `sales@liisgo.com`.
- Política pública de privacidad:
  `https://liisgo.com/#/apps/ParchesePop/privacy`.
- Los recursos finales de Google Play están en
  `store_assets/google_play/`: `feature-graphic-1024x500.png`,
  `icon-512.png` e `icon-512-rgba.png`.
- Las capturas finales de iOS son
  `store_assets/ios/01-home-1284x2778.png`,
  `store_assets/ios/02-gameplay-1284x2778.png` y
  `store_assets/ios/03-shop-1284x2778.png`. Los archivos `*-source.png` de esa
  carpeta son fuentes de trabajo y no se suben a la tienda.
- Las capturas finales de macOS son
  `store_assets/macos/01-settings-1440x900.png`,
  `02-gameplay-1440x900.png`, `03-traps-1440x900.png` y
  `04-bomb-trap-1440x900.png`.
- Los iconos fuente seleccionados se conservan en `assets/branding/`.

## Reglas de la versión de referencia

- Cada jugador controla cuatro fichas.
- El objetivo es sacar las cuatro fichas, completar el recorrido y llevarlas a la meta.
- Se utilizan dos dados.
- Una ficha sale de la cárcel únicamente cuando uno de los dados muestra físicamente un 5; no se forma la salida sumando ambos dados.
- Un doble 5 permite sacar dos fichas.
- Mientras quede alguna ficha en la cárcel y la casilla de salida esté disponible, cada dado con valor 5 debe utilizarse para una SALIDA. Solo cuando todas las fichas estén fuera, o la salida esté bloqueada, ese 5 se convierte en un movimiento de cinco pasos.
- Los valores de los dados pueden repartirse entre fichas o utilizarse con una misma ficha cuando el movimiento sea legal. Mientras los dos dados físicos originales sigan disponibles, el jugador puede elegir `TODOS` para sumar ambos y hacer un único movimiento con una sola ficha.
- `TODOS` es una llegada final atómica: consume los dos dados juntos y las capturas, cristales, trampas y meta se resuelven solamente en la casilla final, no en una casilla intermedia.
- `TODOS` no combina bonos de 10 o 20 y desaparece en cuanto se consume uno de los dados. Una suma que dé 5 no cuenta como un cinco físico para `SALIDA` ni para la captura especial de entrada. Si existe un 5 físico obligado para sacar una ficha, ese dado no puede gastarse mediante `TODOS` con una ficha que ya está en juego.
- Para capturar una ficha rival hay que caer exactamente en su casilla.
- Capturar devuelve la ficha rival a la cárcel y concede un movimiento de 20 casillas que no puede dividirse.
- Las casillas con estrella son seguras.
- Dos fichas de colores distintos nunca pueden terminar juntas en una casilla segura. Una ficha sí puede pasar sobre un rival solitario situado en un seguro, pero no puede terminar allí.
- Excepción de salida: si una sola ficha rival ocupa la salida propia y se utiliza un 5 para sacar una ficha, la rival es capturada y se concede el bono de 20. Si dos fichas rivales forman una barrera en esa salida, no se puede sacar.
- Regla especial de entrada: una ficha rival solitaria situada en la puerta de entrada al pasillo bloquea cualquier movimiento normal que intente llegar o cruzar esa puerta. La única excepción ocurre cuando una ficha propia está exactamente en la casilla anterior y utiliza un dado físico con valor 5: captura a la rival al cruzar la puerta, completa los cinco pasos dentro de su pasillo y recibe el bono de 20.
- En un doble 5, cada dado sigue siendo independiente. La captura especial consume solamente uno de los cincos y el otro permanece disponible. Un bono de 10 o 20 y una suma de dados no activan esta regla.
- Dos fichas rivales juntas en la puerta forman una barrera que no puede romperse ni con un 5. Si todavía queda una ficha propia en la cárcel y la salida está disponible, la obligación de usar el 5 para `SALIDA` tiene prioridad sobre la captura de entrada.
- Una ficha propia puede compartir su salida o cualquier otro seguro con una segunda ficha propia; las dos forman una barrera.
- Dos fichas del mismo color en una casilla forman una barrera.
- Los dobles conceden otra tirada.
- Tres dobles consecutivos anulan el tercer movimiento y envían a la cárcel la ficha más adelantada, excepto si ya está protegida en su pasillo final.
- Para entrar a la meta se requiere el número exacto.
- Gana quien lleva primero sus cuatro fichas a la meta.

### Geometría del recorrido y entrada a casa

- El tablero completo contiene 68 casillas numeradas globales.
- Una ficha no recorre las 68 antes de entrar a casa: desde su propia salida recorre 64 casillas comunes y luego gira hacia su pasillo de color.
- Cada pasillo de meta contiene siete casillas. La meta final se alcanza en el progreso interno 71.
- Todas las fichas de un mismo color, sin importar cuál de las cuatro se movió primero, entran siempre por el mismo punto y recorren el mismo pasillo.

| Color | Casilla anterior | Puerta segura y última casilla común | Primera casilla del pasillo |
|---|---:|---:|---|
| Rojo | 63 | 64, índice global 63 | Coordenada del tablero `(1.5, 10)` |
| Verde | 12 | 13, índice global 12 | Coordenada del tablero `(10, 18.5)` |
| Amarillo | 29 | 30, índice global 29 | Coordenada del tablero `(18.5, 10)` |
| Azul | 46 | 47, índice global 46 | Coordenada del tablero `(10, 1.5)` |

La longitud global de 68 se utiliza para numeración, seguros, cubos, trampas y posiciones compartidas. La longitud individual de 64 se utiliza para movimiento, capturas, barreras, CPU, animación y decisión de entrada al pasillo. Estos dos valores no deben volver a tratarse como si fueran el mismo concepto.

### Selección y previsualización del movimiento

- Después de tirar los dados, al pulsar una ficha aparece un menú pequeño junto a ella con todos sus movimientos legales.
- Si ambos dados originales siguen disponibles y su suma produce un movimiento legal, el menú añade un botón violeta `TODOS` con el total. Su destino se identifica con una insignia `Σ` y también puede tocarse directamente para ejecutar el movimiento.
- Cada opción ilumina simultáneamente la forma exacta de la casilla donde terminará la ficha.
- El destino pulsa con relleno translúcido, borde luminoso y una insignia con el número del movimiento. Una salida de cárcel muestra `S` y el menú dice `SALIDA`.
- En la captura especial de entrada, el popup dice `CAPTURAR`, una `X` roja pulsa sobre la ficha rival en la puerta y el número 5 marca por separado la casilla final real dentro del pasillo.
- El color del destino debe ser siempre el mismo que el del botón correspondiente: primer dado azul, segundo dado rojo y bono de 10 verde. Para el bono de 20, F1 es violeta, F2 cian, F3 fucsia y F4 coral; el halo de origen, la casilla de llegada y el botón de 20 conservan ese mismo color.
- Si el destino está en una unión especial, en el pasillo o en el triángulo final, se resalta la forma real de esa zona; no un rectángulo aproximado.
- Las señales desaparecen al mover, cancelar la selección o cambiar de turno.
- La ficha recorre visualmente todas las casillas intermedias. Al cruzar hacia casa debe pasar por la última casilla común y girar por las casillas de su propio pasillo, sin saltos ni trayectorias diagonales.

## Cubos sorpresa, objetos y trampas

Ciertas casillas incluyen un cristal triangular animado. La ficha debe caer exactamente en la casilla para recoger un objeto. Siempre existe un cristal en cada lado del recorrido: rojo entre las casillas 2 y 17, verde entre 19 y 34, amarillo entre 36 y 51 y azul entre 53 y 68. Cuando alguien recoge uno, desaparece y reaparece de inmediato en otra casilla válida del mismo lado, nunca en un seguro, una trampa ni en su ubicación anterior.

Existen dos comportamientos. Escudo y Turbo se guardan como poderes del jugador: Turbo se activa cuando el jugador decide usarlo y el Escudo permanece en espera para sus cuatro fichas, activándose automáticamente cuando cualquiera cae en una trampa rival. Al bloquear, consume el Escudo y la trampa, cancela por completo el daño y muestra “¡PROTEGIDO!”. Pegamento, Retroceso, Cárcel y Bomba son trampas ofensivas: se arman automáticamente y quedan ocultas en la misma casilla donde se recogió el cristal. No ocupan el espacio del poder guardado y cada jugador puede mantener varias trampas simultáneas en el tablero. Solamente su dueño ve los símbolos, tipos y ubicaciones; los demás jugadores ven únicamente la cantidad de trampas ocultas, hasta que una se activa y el juego revela su tipo mediante animación y mensaje.

Objetos iniciales recomendados:

- Pegamento: la próxima ficha rival que caiga en la casilla pierde un turno.
- Retroceso: intenta retroceder hasta 6 casillas a la próxima ficha rival que
  caiga allí. Nunca atraviesa una barrera ni termina en una casilla ilegal; si
  el destino de seis no es válido, usa la casilla legal más cercana y, si no
  existe ninguna, la ficha permanece donde está.
- Cárcel: devuelve a la cárcel a la próxima ficha rival que caiga allí.
- Bomba: explota y devuelve a la cárcel a la próxima ficha rival que caiga allí.
- Escudo: se activa automáticamente y protege la ficha contra una trampa rival. Es de un solo uso.
- Turbo: mueve hasta 3 casillas la ficha propia más adelantada. Si esa llegada
  captura o entra a meta, conserva respectivamente los bonos +20 o +10.

Objetos futuros posibles: dado bloqueado, cambio de posición, barrera temporal, dado dorado, fantasma, robo y teletransporte.

Reglas de balance:

- Cada jugador puede guardar un Escudo o Turbo y, al mismo tiempo, mantener varias trampas armadas en el tablero.
- Tener un poder guardado o trampas activas nunca impide recoger otro cristal; si el espacio de poder ya está ocupado, el cristal concede una trampa ofensiva.
- Hay exactamente un cristal activo por lado y el cristal recogido reaparece inmediatamente en otro punto de ese mismo tramo.
- No se colocan trampas en seguros, salidas ni pasillos de meta.
- La distribución definitiva por rareza sigue pendiente. En el prototipo, los
  objetos disponibles tienen la misma probabilidad.
- Ningún jugador puede ser afectado repetidamente en el mismo turno.
- El Escudo bloquea únicamente trampas. No evita una captura normal ni la
  captura especial de salida.
- Deben existir modos Clásico, sin objetos, y Caos, con objetos.

## CPU e inteligencia de juego

El CPU debe evaluar todas las jugadas legales y priorizar meta, capturas, seguridad, barreras, salida de cárcel, cubos y defensa de fichas adelantadas. Nunca puede conocer resultados futuros de los dados ni trampas ocultas que no haya visto.

Los niveles seleccionables para jugar contra CPU serán Fácil, Normal y Experto.

El CPU también debe saber cuándo usar Turbo y cómo aprovechar los objetos
automáticos. El Escudo se guarda a nivel de jugador y se consume solo al
bloquear una trampa. Las trampas ofensivas se arman automáticamente en el
cristal que las entrega, por lo que el CPU decide qué ficha intenta acercar a
los cristales y no elige manualmente una casilla de colocación. Debe usar Turbo
para llegar a un seguro, capturar o entrar a meta.

## Partida Rápida local y futuro online

- El modo Contra CPU permite seleccionar dificultad.
- Al pulsar `PARTIDA RÁPIDA` se presenta el mismo selector grande de reglas que
  en Contra CPU: `Tradicional` o `Caos`. No exige cuenta, inicio de sesión ni
  dificultad.
- La versión actual prepara toda la mesa en el dispositivo y completa
  automáticamente los tres asientos restantes con rivales del juego. No busca
  ni conecta jugadores por red.
- El modo seleccionado se muestra durante la preparación, se guarda dentro de
  la sesión local y gobierna la partida completa. Tradicional desactiva
  cristales, poderes y trampas; Caos los mantiene activos.
- Partida Rápida utiliza los primeros 8 segundos para preparar la mesa. Durante
  ese período los tres asientos restantes permanecen en `Preparando…`.
- La incorporación visual de rivales comienza en el segundo 9:
  entra un rival en el segundo 9, otro en el 10 y el último en el 11. La
  partida abre después de mostrar brevemente el tercer perfil.
- Los rivales de respaldo pueden tener nombre, avatar, bandera, personalidad,
  tiempos de respuesta variables y mensajes contextuales. El nombre y la
  bandera se seleccionan como un perfil curado completo, nunca desde dos
  listas aleatorias independientes. Cada nombre admite únicamente banderas
  culturalmente plausibles, incluidas opciones de diáspora como Estados
  Unidos o Canadá cuando corresponda.
- La interfaz utiliza etiquetas neutrales: `Tú` para el jugador local y `Rival` para cualquier oponente. No muestra etiquetas técnicas sobre quién controla al rival ni afirma que sea una persona real.
- Los participantes automáticos conservan fichas, objetos, turnos, trampas,
  perfil y estado durante toda la partida.
- Los tipos internos conservan una frontera preparada para integrar
  multijugador real en una versión futura, pero esa función no se anuncia en
  la versión actual.

## Mensajes y personalidad

Se utilizarán mensajes pregrabados y reacciones, por ejemplo: “¡Buena jugada!”, “Tuviste suerte”, “¡Voy por ti!”, “Eso estuvo cerca”, “No vi esa trampa”, “¡Remontada!” y “Buena partida”.

El CPU seleccionará mensajes relacionados con los eventos reales de la partida y tendrá estilos de personalidad como agresivo, defensivo, coleccionista de cubos o equilibrado.

## Monetización y tienda

La monetización se concentrará en elementos cosméticos:

- Diseños de fichas.
- Diseños de dados.
- Temas completos de tablero.
- Fondos, marcos, pisos, centros, cárceles y casillas.
- Efectos de movimiento, captura, cubos, trampas y victoria.
- Avatares, marcos y reacciones.
- Paquetes temáticos y pases de temporada.
- Moneda obtenida jugando y moneda premium.
- Anuncios recompensados voluntarios de `+100` monedas en la tienda móvil.

No se deben vender ventajas competitivas como dados manipulados, trampas más poderosas o probabilidades superiores.

## Personalización del tablero

El tablero se construye con capas independientes. Un conjunto completo se llama `board_theme`. La apariencia puede cambiar sin alterar la posición ni la función de los elementos.

Regla esencial: los elementos visuales pueden cambiar de textura, forma, imagen, animación o sonido; los elementos funcionales conservan su posición, propósito y comportamiento. Un seguro siempre debe reconocerse como seguro y una casilla de cubo nunca debe confundirse con una casilla normal.

## Nomenclatura principal

### Tablero

| Nombre | Identificador |
|---|---|
| Fondo de pantalla | `game_background` |
| Marco del tablero | `board_frame` |
| Piso del tablero | `board_surface` |
| Esquinas del tablero | `board_corners` |
| Centro del tablero | `board_center` |
| Triángulo central | `center_triangle` |
| Camino principal | `main_track` |
| Casilla normal | `normal_tile` |
| Casilla segura | `safe_tile` |
| Símbolo de seguro | `safe_icon` |
| Casilla del cubo | `item_tile` |
| Cubo sorpresa | `item_box` |
| Casilla de salida | `start_tile` |
| Flecha de salida | `start_arrow` |

### Área del jugador

| Nombre | Identificador |
|---|---|
| Base | `player_base` |
| Cárcel | `player_nest` |
| Fondo de la cárcel | `nest_background` |
| Borde de la cárcel | `nest_border` |
| Posición encarcelada | `nest_slot` |
| Nombre del jugador | `player_nameplate` |
| Avatar | `player_avatar` |
| Bandera | `player_flag` |
| Camino a la meta | `home_lane` |
| Casilla de meta | `home_tile` |
| Meta final | `finish_area` |
| Contador de fichas | `token_counter` |

### Piezas y objetos

| Nombre | Identificador |
|---|---|
| Ficha | `token` |
| Diseño de ficha | `token_skin` |
| Base de ficha | `token_base` |
| Efecto de movimiento | `token_trail` |
| Efecto de captura | `capture_effect` |
| Dados | `dice_set` |
| Diseño del dado | `dice_skin` |
| Bandeja de dados | `dice_area` |
| Inventario | `item_slot` |
| Trampa colocada | `placed_trap` |
| Indicador de turno | `turn_indicator` |
| Barrera | `blockade` |

### Interfaz

| Nombre | Identificador |
|---|---|
| Botón de lanzar | `roll_button` |
| Temporizador | `turn_timer` |
| Botón de mensajes | `quick_chat_button` |
| Panel de mensajes | `quick_chat_panel` |
| Botón de objetos | `item_button` |
| Menú de pausa | `pause_menu` |
| Estado de conexión | `connection_status` |
| Marcador de jugador | `player_hud` |
| Animación de victoria | `victory_effect` |
| Pantalla de resultados | `results_screen` |

## Decisiones pendientes

1. Definir probabilidades y rareza de cada objeto.
2. Definir duración exacta de turnos y reconexión.
3. Crear y activar en App Store Connect y Google Play Console los cinco
   productos consumibles que ya consulta `CoinStore`, y añadir validación de
   recibos en servidor antes del lanzamiento público. Las recargas locales
   permanecen disponibles únicamente en modo de depuración.
4. Definir tecnología, plataformas y arquitectura online.

## Estado jugable actual (26 de julio de 2026)

- El menú principal tiene estilo arcade y permite entrar como invitado.
- El registro es opcional y Partida Rápida no lo exige.
- El tablero, las fichas, los dados y los objetos están dibujados dentro de Flutter.
- Se puede jugar contra tres rivales controlados por CPU.
- Están implementadas la salida con cinco, movimiento, captura, seguros, barreras, entrada a casa, turno extra por dobles y victoria.
- Al seleccionar una ficha encarcelada con un 5 disponible, el popup muestra “SALIDA” en lugar de “5 pasos”. Cuando todas las fichas están fuera, vuelve a mostrar “5 pasos”.
- Los objetos disponibles son Escudo, Turbo, Pegamento, Retroceso, Cárcel y Bomba.
- El jugador activo aparece destacado y cada jugador muestra cuántas fichas completó.
- Las fichas que pueden moverse tienen un aro luminoso pulsante.
- Los dados cambian con animación y muestran caras de dado.
- La distribución visual y el tablero se adaptan a teléfono, tableta y macOS.
- Al completar la cuarta ficha de un jugador se muestra su celebración. Si
  quedan rivales, puede seguir viendo exactamente la misma partida. El cierre
  definitivo ocurre solamente cuando los cuatro puestos están completos;
  después de mostrar la clasificación final, la aplicación regresa
  automáticamente a la pantalla principal.
- El recorrido común usa las 68 casillas numeradas de la referencia.
- Cada color dispone de siete casillas privadas antes de la meta central.
- Las salidas son 1 roja, 18 verde, 35 amarilla y 52 azul.
- Los seguros con estrella son 8, 13, 25, 30, 42, 47, 59 y 64.
- Las cuatro salidas de color también son seguras, para un total de 12 casillas protegidas.
- Una ficha ubicada en cualquiera de los 12 seguros no puede ser capturada por un movimiento ordinario y ningún rival puede terminar su movimiento en esa casilla.
- Una ficha solitaria no bloquea el paso por un seguro; solamente impide que un color contrario aterrice allí.
- Sacar con 5 captura una ficha rival solitaria situada en la salida propia. Una barrera rival de dos fichas bloquea la salida.
- Una rival solitaria en la puerta de entrada bloquea el paso. Desde 63 roja, 12 verde, 29 amarilla o 46 azul, un dado físico de 5 permite capturarla al cruzar, completar los cinco pasos y obtener el bono de 20; el popup muestra `CAPTURAR`, la puerta se marca con `X` y el destino final con `5`.
- Una barrera rival de dos fichas en la puerta continúa siendo infranqueable, incluso con doble 5.
- Las barreras de dos fichas no pueden ser atravesadas; una de esas fichas sí puede moverse para abrir su propia barrera.
- Una barrera tampoco puede ser capturada: ningún dado, salida con 5, bono de 20, Turbo ni decisión del CPU puede atravesarla, aterrizar sobre ella o enviar sus dos fichas a la cárcel. La protección se valida tanto al calcular el movimiento como dentro de la función central de captura.
- Las dos fichas de una barrera se muestran separadas y simétricas a lo largo de la casilla, de modo que ambas quedan visibles. Al formarse o romperse la barrera, las dos posiciones cambian mediante animación.
- Antes de jugar contra CPU se puede seleccionar modo Tradicional o modo Caos.
- Tradicional conserva las reglas del parchís y desactiva cubos, objetos y trampas.
- Caos activa cubos sorpresa, inventario, escudo, turbo, bomba y trampas.
- Las trampas disponibles son Pegamento, Retroceso de hasta seis pasos, Cárcel y Bomba.
- El catálogo de música y efectos que se deben producir se conserva en `BRIEF_DE_AUDIO_PARCHESE_POP.md`.
- Hay exactamente cuatro cristales sorpresa activos: uno en cada tramo de color. Al recoger uno, reaparece en otra casilla válida y distinta del mismo tramo.
- Una trampa obtenida de un cristal se arma automáticamente en la casilla exacta que ocupaba el cristal; no existe colocación manual.
- Nunca se coloca una trampa en un seguro, una salida, un pasillo de meta ni sobre otro cristal o trampa.
- Las trampas son de un solo uso, no afectan a su dueño y un escudo puede bloquearlas.
- El dueño de una trampa es el único que ve su tipo, símbolo y ubicación. El panel de un rival solo muestra “Trampa oculta activa”.
- Pegamento hace perder el próximo turno; Retroceso mueve la ficha hasta seis pasos hacia atrás; Cárcel y Bomba devuelven esa ficha a su base.
- Los CPU de dificultad Normal y Experto pueden guardar, usar y colocar sus objetos.
- El tablero mantiene la paleta Arcade Pop y usa degradados, biseles, luces y sombras para producir profundidad 2.5D.
- Los dados tienen puntos dibujados y una animación de giro tridimensional.
- Las casillas sorpresa muestran un cristal triangular 3D que gira continuamente, cambia de cara, flota, proyecta sombra y lleva un destello orbitando; ya no usan una imagen estática con signo de interrogación.
- Cada jugador dispone de un espacio para Escudo o Turbo, separado de las trampas que ya están armadas en el tablero.
- Un jugador puede acumular varias trampas. Cada una permanece hasta que una ficha rival la activa o un Escudo la bloquea.
- En pantallas anchas, el panel derecho muestra por separado el poder guardado y la cantidad de trampas. El dueño ve tipo y casilla de cada una; nunca se revelan esos datos de los rivales.
- En teléfono, el botón de mochila situado a la derecha de la barra superior abre el estado de poderes y trampas de los cuatro jugadores con la misma regla de privacidad.
- Después de lanzar, el jugador selecciona primero una ficha y luego elige explícitamente cuál dado utilizar mediante botones separados como “2 pasos” o “3 pasos”.
- Mientras ninguno se haya consumido, el mismo popup ofrece `TODOS` para avanzar con la suma de los dos dados físicos. La opción consume ambos, muestra el total y marca la llegada violeta con `Σ`; no incluye bonos +10/+20 ni convierte una suma de 5 en una salida.
- El selector de movimiento es un popup contextual compacto anclado a la ficha elegida; ya no ocupa espacio dentro del panel inferior.
- Cada casilla de destino iluminada también funciona como botón. Después de seleccionar una ficha, el jugador puede ejecutar el movimiento tocando el botón flotante o tocando directamente la casilla donde caerá; esa casilla consume exactamente el dado o bono que representa.
- Si el jugador toca el centro de otra ficha propia jugable, la selección cambia inmediatamente a esa ficha: el popup anterior desaparece y se reconstruye con sus movimientos, sin consumir dados ni exigir pulsar la `X`. Si una ficha propia ocupa una casilla de destino, tocar la ficha cambia la selección y tocar el área coloreada libre de la misma casilla ejecuta el movimiento anterior.
- Después de una captura aparece `BONO +20`. Antes de elegir una ficha, el tablero muestra simultáneamente todos los destinos legales de 20 pasos mediante las guías F1–F4 y sus colores. Las fichas encarceladas, terminadas o bloqueadas no reciben una guía. Al tocar una ficha se ocultan los demás destinos y queda enfocado únicamente el suyo; si varios destinos coinciden, sus insignias se separan para seguir siendo identificables.
- El popup se coloca arriba o abajo de la ficha, evita cubrir las casillas de destino cuando existe espacio y se ajusta en los bordes para permanecer completamente dentro del tablero en teléfono, tableta y escritorio.
- El marco azul y amarillo vive fuera de la cuadrícula jugable; debe conservarse un margen dedicado para que las cuatro casillas seguras del perímetro, sus estrellas y cualquier ficha situada allí nunca queden recortadas.
- Una nueva jugada anima únicamente las fichas cuya posición cambió; las fichas movidas en turnos anteriores nunca deben repetir su recorrido.
- Las bases de color rellenan completamente sus cuadrantes, sin esquinas blancas interiores, y los nombres CPU 2 y CPU 3 siempre se leen derechos.
- Las parejas 4/5, 21/22, 38/39 y 55/56 tienen exactamente la misma área visual. La diagonal de cada esquina del centro se prolonga hasta la esquina de la base correspondiente, sin mini-casillas ni espacios blancos.
- Al consumir un dado, su cara queda atenuada y el panel indica cuántos dados siguen disponibles.
- El dado restante puede utilizarse con otra ficha; el motor nunca debe sustituir silenciosamente un valor inválido por otro dado.
- Los dobles muestran una sola opción de valor, pero cada movimiento consume solamente una de las dos copias.
- Los objetos y trampas producen una explosión animada, anillos de color, un símbolo y un rótulo específico en la casilla donde ocurre el efecto: Pegamento, Retroceso −6, Cárcel, Bomba, Escudo o Turbo.
- Al activar Retroceso, Cárcel o Bomba, la ficha se anima en dos etapas: primero llega a la casilla oculta y después retrocede o vuela hasta su cárcel. Los controles permanecen bloqueados brevemente mientras se resuelve la reacción para que el efecto no se pierda entre jugadas.
- Al sacar una ficha de la cárcel, la casilla de salida muestra una flecha y una estela animadas con el color del equipo y el rótulo `¡SALIDA!`. La dirección coincide siempre con el próximo tramo real: rojo apunta a la casilla 4 (derecha), azul a la 55 (abajo), amarillo a la 38 (izquierda) y verde a la 21 (arriba).
- Una captura muestra un impacto radial naranja y blanco con el rótulo `¡CAPTURA!` exactamente sobre la casilla donde fue enviada la ficha rival a su cárcel.
- Si una salida con 5 captura una rival que ocupaba esa salida, ambas acciones se presentan como un solo efecto especial: `¡SALIDA + CAPTURA!`.
- Cuando una ficha completa su recorrido y entra al centro, la meta muestra un halo, confeti dorado con el color del equipo y el rótulo `¡FICHA EN META!`.
- Los efectos de salida, captura y meta son visuales y no alteran las reglas: se conservan el bono de 20 por captura, el bono de 10 por meta, los dados pendientes y el turno correspondiente.
- Si la cuarta ficha llega al centro, la celebración final espera 1,650 ms para permitir que primero se vea completa la entrada a meta.
- La barra de la partida incluye un botón permanente de `Historial`. Abre una cronología con los 100 eventos más recientes, ordenados del más nuevo al más antiguo, e identifica número de turno, orden, jugador, color, tirada, ficha y resultado.
- El historial registra inicio y cambio de turno, dados, movimientos, salidas, formación y apertura de barreras, capturas, falta de movimientos, poderes, trampas, meta, victoria y penalización por tres dobles. Si tres dobles devuelve una ficha que formaba parte de una barrera, el evento dice expresamente qué ficha volvió a la cárcel y que la barrera se abrió.
- La partida completa fue verificada en un simulador iPhone 14 de 390 por 844 puntos.

## Iteración de producto del 27 de julio de 2026

- El menú principal fue rediseñado como una pantalla de juego: hero arcade,
  botones grandes Online/CPU, cuatro accesos circulares y saldo visible.
  Los elementos principales caben en un iPhone 14 vertical sin depender de una
  pantalla de registro.
- La tienda dejó de ser una maqueta. `wallet.dart` conserva saldo, artículos
  poseídos y un artículo equipado por categoría mediante
  `SharedPreferences`. El catálogo es la única fuente de nombre, descripción,
  precio y categoría para evitar que la tarjeta y la compra se desincronicen.
- La tienda contiene 33 cosméticos: 6 temas, 9 dados, 10 juegos de fichas y
  8 avatares. Cada categoría tiene una opción clásica gratuita, poseída desde
  el inicio, para que el jugador siempre pueda volver al diseño original sin
  comprar nada. `Destacados` es una selección curada de 8 artículos y no una
  copia completa del catálogo.
- Los temas nuevos son Selva Viva (1,050), Arcade Retro (1,350) y Aurora
  Ártica (1,500). Los dados nuevos son Perla (425), Prisma (525) y
  Medianoche (625). Las fichas nuevas son Cristal (550), Cohete (600) y
  Corona (675), Pulso Neón (650), Escarabajo Solar (700), Tótem Selvático
  (650), Pixel Blaster (725) y Fragmento Aurora (800). Los avatares nuevos son
  Cometa Pop (275), Axolotl Splash (350) y Tucán Turbo (425). Se conservaron
  todos los IDs, precios e inventarios anteriores.
- Cada artículo tiene una rareza visible —Básico, Especial, Raro, Épico o
  Legendario— y un renderer propio centralizado. Un producto no puede
  publicarse en el catálogo sin una apariencia registrada para tienda y juego.
  Los avatares son ilustraciones vectoriales internas y no dependen de emoji
  del sistema.
- Durante desarrollo, un único botón grande `+ MONEDAS` dentro de la tienda
  abre paquetes de moneda local para probar el ciclo completo, incluida una
  caja de 10,000. El control está protegido por el modo debug: no aparece en
  Inicio ni en una compilación publicada, y quedarse sin saldo en producción
  nunca abre la caja de prueba. En publicación, `CoinStore` consulta los
  productos oficiales de App Store o Google Play, muestra el precio localizado
  de la tienda e inicia una compra consumible.
- Comprar descuenta el precio, agrega el artículo a la colección y lo equipa.
  Un artículo comprado puede volver a equiparse y todo persiste después de
  cerrar la aplicación.
- Las tarjetas muestran mini tableros con paleta propia, dados 2.5D con patrón
  y material, cuatro fichas vectoriales del diseño elegido y medallones de
  avatar dibujados por código. El botón táctil de cada tarjeta mide al menos
  44 puntos y la compra abre un panel temático con vista previa, saldo actual,
  saldo restante y confirmación explícita.
- Todos los temas, dados y fichas del catálogo se reflejan dentro de la partida.
  En Partida Rápida, el tablero conserva el tema local, los dados cambian según el
  jugador del turno y cada color conserva su propio diseño de ficha. El avatar
  equipado aparece en inicio, perfil, búsqueda y paneles de la partida.
- `online_match.dart` conserva el nombre interno histórico y crea una sola sesión
  local estable desde la preparación hasta la
  partida, la victoria y la revancha. Cada participante conserva nombre,
  bandera, avatar, nivel, color y su propia combinación de tema, dados y fichas
  del catálogo.
- Los perfiles de respaldo usan el catálogo `profilePool`: por ejemplo,
  `JuanPop` se combina con banderas latinas, española o estadounidense, y
  `MohammedPlay` con banderas plausibles del norte de África, Medio Oriente o
  su diáspora. Las pruebas recorren 240 perfiles generados y rechazan cualquier
  combinación de nombre y bandera que no pertenezca al mismo perfil curado.
- La versión publicada completa los tres asientos con perfiles automáticos
  variados. En toda la interfaz, cualquier oponente se identifica solamente
  como `Rival`.
- Los cosméticos se aplican por participante: cada jugador puede tener sus
  propias fichas, y los dados visibles cambian según el perfil cuyo turno está
  activo. Los nombres de Partida Rápida sustituyen las etiquetas genéricas CPU 1, CPU 2 y
  CPU 3 en el tablero y en el panel de jugadores.
- La preparación local usa dos fases visibles: segundos 1–8 de preparación y
  ocupación progresiva de los asientos restantes desde el segundo 9. Los tres
  asientos permanecen en `Preparando…` durante toda la primera fase; después
  entran uno por uno.
- Los nombres nunca se abrevian con puntos suspensivos. En búsqueda, roster,
  panel de poderes, encabezado y bases del tablero se conserva el nombre
  completo y se reduce automáticamente el tamaño de la tipografía cuando sea
  necesario.
- `game_guide.dart` contiene la pantalla completa `Cómo jugar`, con selector
  Tradicional/Caos, las reglas aprobadas, referencias rápidas y un laboratorio
  interactivo para Escudo, Turbo, Pegamento, Retroceso, Cárcel y Bomba.
- El laboratorio permite tocar cualquier tarjeta o pulsar `Ver todos` para
  reproducir los seis efectos en secuencia. Cada uno tiene una reacción propia
  de 2,200 ms: cúpula del Escudo, estela de Turbo, charco de Pegamento, seis
  marcas de Retroceso, barrotes de Cárcel y explosión de Bomba. El escenario
  permanece a ancho completo durante toda la animación en iPhone.
- El Escudo guardado ya no requiere pulsar `Usar`. Se identifica como
  `Escudo listo · automático`; cuando una ficha cae en Pegamento, Retroceso,
  Cárcel o Bomba rival, el motor consume ambos objetos, mantiene la ficha en la
  casilla, evita toda penalización y reproduce `ESCUDO BLOQUEÓ`.
- Debajo del nombre aparecen por separado el poder guardado y las trampas
  activas. Un Escudo se identifica como `PODER · Escudo listo · AUTO`; las
  trampas muestran cantidad y, para su dueño, tipo y casilla. Estos indicadores
  aparecen tanto en el panel de turno como en `Jugadores`, se reducen sin
  puntos suspensivos y nunca revelan el tipo ni la casilla de trampas rivales.
- El menú principal y Ajustes tienen acceso directo a `Cómo jugar`. El menú
  principal también tiene un botón visible `Trampas`.
- Antes de jugar contra CPU aparece un diálogo de dos pasos con tarjetas
  grandes: primero Tradicional o Caos y después Fácil, Normal o Experto. Ya no
  se usa el panel inferior anterior.
- Sonido, música y vibración son interruptores reales y persistentes. Idioma,
  políticas y ayuda abren información concreta en vez de callbacks vacíos.
  El selector de idioma contiene `Idioma del sistema`, `Español` e `English`.
  `Idioma del sistema` es la opción predeterminada; sigue el idioma del
  dispositivo cuando es español o inglés y usa español como respaldo para
  cualquier idioma no compatible. Las opciones explícitas guardan el código
  estable `es` o `en`. Cualquier selección cambia inmediatamente toda la
  aplicación, sin reiniciarla, y se restaura al volver a abrirla.
- En teléfono horizontal y en ventanas pequeñas de escritorio se usa un panel
  contextual a la derecha con tres pestañas: `Jugar`, `Jugadores` y
  `Trampas/Reglas`. El tablero ocupa casi todo el alto disponible. Cuando
  cambia el turno, el panel muestra automáticamente dados para el jugador
  local y jugadores durante el turno del CPU.
- El tablero de una partida siempre conserva una proporción exacta de 1:1. En
  vertical ocupa todo el ancho seguro y se alinea arriba; en horizontal usa el
  lado máximo que permiten la altura y el panel derecho. Ya no existe el
  límite artificial de 760 píxeles, por lo que también crece en tabletas y
  ventanas grandes de macOS.
- La barra superior alta fue retirada de la partida. Atrás, modo, mochila,
  ayuda y ajustes viven ahora en una barra de juego compacta integrada en la
  parte superior en vertical y sobre el panel contextual en horizontal. Todo
  el ancho y alto restante se utiliza sin deformar el tablero.
- En teléfono vertical, esa barra de juego es ahora el primer elemento de la
  pantalla, antes del tablero. Ocupa todo el ancho seguro sin márgenes laterales,
  se une visualmente al borde superior como una barra real de aplicación y
  conserva únicamente las esquinas inferiores redondeadas.
- La partida continúa siendo compatible con vertical. La recomendación de
  diseño es menú/tienda en vertical y partida en horizontal. No se bloquea la
  orientación global para conservar la multitarea de tabletas y el soporte de
  macOS.
- La reacción visual de una trampa o poder dura 2,200 ms, un segundo más que
  la versión anterior. El motor bloquea los controles y el CPU espera hasta
  que termine el efecto.
- El menú principal tiene accesos independientes para `Cómo jugar` y
  `Trampas`. `Cómo jugar` conserva la guía completa. `Trampas` abre una
  pantalla dedicada que muestra solamente Pegamento, Retroceso, Cárcel y
  Bomba, con una demostración individual y una secuencia animada de las cuatro;
  no incluye reglas generales, Escudo ni Turbo. El botón `Probar efectos`
  durante una partida Caos abre esa misma pantalla.
- El inicio no utiliza una barra corporativa de “Hola” ni íconos de play
  decorativos. La tarjeta del jugador muestra directamente su nombre, bandera,
  nivel y el avatar equipado en la tienda. Toda la tarjeta abre Perfil o
  Registro. Online y Contra CPU son botones arcade completos con gradiente,
  extrusión, ilustración y estado de presión.
- Para un jugador registrado, tanto la tarjeta superior como `Mi perfil`
  abren el mismo panel compacto sobre el lobby, con el tema Arcade Pop, avatar,
  nombre, bandera, nivel, correo, botón de edición y una X visible para volver.
  El editor también usa una tarjeta compacta sobre el fondo arcade y siempre
  permite regresar mediante Cancelar, Atrás del sistema o su botón visible.
  Guardar un perfil, incluso por primera vez, actualiza el inicio y cierra el
  editor; el usuario nunca queda atrapado en una pantalla vacía de perfil.
- El fondo exclusivo del inicio tiene una animación de entrada finita con
  fichas, estrellas, casillas y cubo sorpresa. La decoración está excluida de
  lectores de pantalla y se inmoviliza cuando el sistema solicita reducir
  movimiento. En iPhone vertical, Online y CPU se apilan; en landscape,
  tabletas y macOS se muestran lado a lado desde 620 píxeles útiles.
- En Android e iOS, una sola franja adaptable real se integra al pie del
  contenedor global y permanece al navegar por todas las pantallas. macOS no
  crea la franja ni reserva su espacio.
- Las pantallas negras de Tienda y Ajustes quedaron eliminadas: ambas rutas
  tienen `Scaffold`, fondo arcade y contenido alineado desde arriba.
- El fondo arcade se extiende hasta todos los bordes seguros del iPhone, sin
  dejar una franja vacía debajo del contenido principal.
- En teléfono vertical, el panel de turno ya no es una lista alta de
  controles. Es un HUD arcade compacto: identidad, fase y modo arriba; estado
  del poder y las trampas directamente debajo del nombre; dados a la izquierda y
  acciones `Lanzar`/objeto a la derecha; y una cinta inferior independiente
  para el mensaje de la partida. El diseño conserva botones táctiles grandes,
  cabe completo incluso a 320 píxeles de ancho y no altera el panel contextual
  de landscape o macOS.
- La verificación actual contiene 267 pruebas aprobadas, análisis estático sin
  incidencias, compilación iOS
  Simulator aprobada y compilación macOS Debug aprobada. La cobertura incluye
  compras y equipamiento de los 33 artículos, sus efectos dentro de la partida,
  las reglas Tradicional/Caos y una prueba visual de flujo en inglés que
  recorre Inicio, Ajustes, Tienda, Partida y Cómo jugar, además de verificar el
  cambio inmediato entre el idioma del sistema, español e inglés.
- Se verificó visualmente el lobby Arcade Pop rediseñado en el simulador
  iPhone 14 y en macOS, incluyendo el avatar del jugador, los botones 3D, el
  dock y el fondo animado. También se verificaron: inicio, tienda,
  ajustes, guía Caos, preparación con perfiles de Partida Rápida y partida tanto vertical
  como horizontal con el tablero al máximo tamaño seguro, además del nuevo HUD
  vertical de turno. También se verificó la partida en macOS con tablero de
  altura completa y panel contextual. El selector de idioma cambia
  inmediatamente entre español e inglés y quedó seleccionado
  `Idioma del sistema`. La vista de Partida Rápida también fue revisada con perfiles
  curados como `MohammedPlay 🇨🇦`, `LucPixel 🇫🇷` y `ChloePlay 🇦🇺`; los nombres
  aparecen completos, sin puntos suspensivos.
- El panel compacto de perfil y sus rutas de salida se verificaron visualmente
  en macOS y en el simulador iPhone 14. La X vuelve inmediatamente al lobby y
  el editor mantiene visible su control de regreso sin desperdiciar la
  pantalla.
- `preview.dart` es una entrada exclusiva de desarrollo para abrir pantallas
  específicas durante control visual. Acepta
  `PARCHESPOP_PREVIEW_LANGUAGE=system|es|en` para revisar cualquiera de los
  tres estados de idioma, incluso en la vista `home`. El arranque normal
  continúa en `main.dart`.

### Actualización de Partida Rápida, cuenta y tienda — 28 de julio de 2026

- Al activar una trampa se muestra una franja rectangular entre el tablero y
  el HUD con el nombre exacto y la consecuencia: Pegamento, Retroceso, Cárcel,
  Bomba o Escudo activado. El mismo texto no se duplica en el HUD durante la
  animación; allí se indica solamente que la trampa se está resolviendo.
- El selector de movimientos dejó de superponerse al tablero. Aparece como una
  franja compacta entre el tablero y el panel del jugador con las opciones de
  un dado o `TODOS`. Tocar una casilla de destino ejecuta el mismo movimiento.
  Tocar una zona vacía, una ficha que no puede moverse, cualquier otra ficha o
  cualquier área de la interfaz fuera del tablero y del selector cancela o
  sustituye la selección sin gastar dados.
- La victoria de Partida Rápida ofrece `SEGUIR VIENDO LA PARTIDA`. Al usarlo se conserva
  el ganador y el orden de llegada, se saltan automáticamente los jugadores
  que ya terminaron y los demás continúan hasta completar la clasificación.
  Cuando llega el cuarto jugador se presenta el cierre final de la partida.
  El botón depende de que queden jugadores por terminar, no de una etiqueta
  de sesión; por eso aparece en la mesa local con rivales automáticos.
- El regreso automático al inicio se programa únicamente cuando los cuatro
  puestos de la clasificación están completos. Ganar primero y elegir
  `SEGUIR VIENDO LA PARTIDA` nunca reinicia el tablero ni abre una partida
  nueva. El panel final muestra `Volviendo al inicio…` antes de cerrar la mesa.
- Las partidas rápidas tienen un botón de mensajes rápidos. No existe entrada
  de texto libre: solamente se pueden enviar doce frases curadas en español e
  inglés, con límite de frecuencia. Las respuestas automáticas también se
  limitan al mismo catálogo seguro.
- Cuando el usuario decide crear su perfil, la cuenta solicita correo, clave y
  confirmación. La clave local de desarrollo se guarda con sal aleatoria y
  resumen criptográfico, nunca como texto. El perfil permite cambiar la clave
  y ofrece la acción de recuperación. En iOS la interfaz admite Correo, Google
  y Apple; en Android admite Correo y Google. Google, Apple y el envío real de
  correos permanecen desactivados de forma explícita hasta conectar las
  credenciales y el backend de autenticación de producción; nunca se simula un
  inicio de sesión externo exitoso. Crear una cuenta sigue siendo opcional y
  Partida Rápida nunca bloquea a un invitado ni exige autenticación.
- Los avatares equipados ya aparecen también en el HUD de turno, el roster y
  la celebración de victoria. Los perfiles de la sesión rápida conservan su
  avatar propio.
- Las barras de estado de poder y trampa usan un fondo claro opaco, texto
  azul marino de alto contraste y borde visible. Esto incluye el estado
  `Sin poder ni trampa`, que debe mantenerse legible sobre el HUD oscuro.
- La partida muestra un cronómetro transcurrido desde `00:00`. En teléfono
  aparece en la barra superior y en landscape/macOS en la cabecera del panel
  lateral. Se pausa al finalizar la partida, continúa si el ganador elige
  seguir observando y el tiempo final aparece en la celebración de victoria.
- Cada tarjeta de tienda tiene acciones separadas `PREVIEW` y
  `COMPRAR/USAR`. `PREVIEW` abre una vista grande contextual del tema, dados,
  fichas o avatar. El diálogo de compra está limitado al alto seguro del
  dispositivo, es desplazable y usa un botón de 56 puntos que no corta el
  texto. Una compra aprobada se equipa inmediatamente.
- Los temas de tablero ahora dibujan motivos visibles dentro de las cuatro
  bases y forman un escenario completo alrededor del tablero, por lo que la
  diferencia no queda oculta detrás de las casillas.
- La cobertura añadida verifica las cuatro trampas y sus mensajes, posición y
  cierre del selector, continuación como espectador, chat seguro, política de
  proveedores por plataforma, credenciales locales sin clave en texto,
  preview y compra sin recorte en iPhone 14, aplicación de cosméticos y la
  regresión completa de reglas.

### Paquetes consumibles de monedas — 29 de julio de 2026

- `CoinStore` utiliza `in_app_purchase` para consultar precios e iniciar
  compras consumibles en App Store o Google Play. Los mismos identificadores se
  usan en ambas tiendas:

  | Identificador | Monedas | Precio de referencia |
  |---|---:|---:|
  | `com.liisgo.parchesepop.coins.500` | 500 | USD 0.99 |
  | `com.liisgo.parchesepop.coins.1200` | 1,200 | USD 1.99 |
  | `com.liisgo.parchesepop.coins.3000` | 3,000 | USD 4.99 |
  | `com.liisgo.parchesepop.coins.7000` | 7,000 | USD 9.99 |
  | `com.liisgo.parchesepop.coins.16000` | 16,000 | USD 19.99 |

- El precio localizado devuelto por cada tienda es la fuente de verdad para la
  interfaz. Los precios anteriores son valores de respaldo y referencia.
- Al confirmarse la compra, el paquete acredita su cantidad al saldo local y la
  transacción consumible se completa. La validación de recibos en servidor
  continúa pendiente para producción.
- Las monedas solo desbloquean cosméticos y no conceden ventajas competitivas.
- El diálogo de monedas de prueba es independiente, se limita a compilaciones
  de depuración y nunca realiza un cobro.

### Telemetría y Analytics — 29 de julio de 2026

- `game_analytics.dart` conserva los identificadores internos históricos
  `online_match_started` y `cpu_match_started`; el primero representa Partida
  Rápida en la versión actual. Esto permite probar cuándo se
  solicitaría una medición sin acoplar la partida a un proveedor.
- La compilación actual inicializa siempre `NoopGameAnalytics`. No incluye los
  paquetes de Firebase, no carga una configuración Firebase y no transmite
  eventos ni datos de Analytics.
- Las pruebas pueden inyectar un grabador en memoria para verificar el tipo de
  partida, modo, revancha, dificultad y métricas de búsqueda. Esa grabación
  existe únicamente dentro de la prueba y no representa recopilación en la
  aplicación publicada.
- Si se activa un proveedor de analíticas en el futuro, primero deben
  actualizarse la política pública, las declaraciones de privacidad de las
  tiendas y el flujo de consentimiento correspondiente.

### Temas dinámicos completos — 28 de julio de 2026

- Los identificadores guardados y las compras existentes se conservan, pero
  cada tema tiene ahora una identidad visual completa:
  - `theme_neon_rush`: **Ciudad Futurista**, con rascacielos, ventanas
    encendidas, circuitos, cuadrícula de perspectiva y barrido de neón.
  - `theme_golden_night`: **Templo de las Pirámides**, con sol, dunas,
    partículas de arena y pirámides iluminadas.
  - `theme_tropical_splash`: **Selva Viva**, con follaje, río, hojas y
    luciérnagas en movimiento.
  - `theme_celestial_carnival`: **Arcade Retro**, con atardecer pixelado,
    cordillera, edificios, rejilla de perspectiva, scanlines, destellos y una
    nave luminosa en movimiento.
  - `theme_velvet_lounge`: **Aurora Ártica**, con tres capas de luces polares,
    cielo estrellado, nieve, montañas de hielo y reflejos animados.
- Arcade Retro reemplaza completamente al antiguo Bosque de Hongos y Aurora
  Ártica reemplaza completamente a la antigua Cascada Niágara. Se conservaron
  los IDs, precios, rarezas, inventarios y selección equipada; una compra
  anterior recibe automáticamente el nuevo diseño.
- La escena se aplica en cinco niveles: fondo completo de la partida, superficie
  del tablero, decoración de las cuatro bases, emblema del centro y marco.
  Las casillas, números, estrellas seguras, colores de equipo y fichas
  permanecen por encima con contraste suficiente.
- La tienda muestra una mini escena claramente distinta detrás de cada tablero.
  La animación de esas tarjetas tiene una duración finita para no consumir
  recursos continuamente; la vista de partida sí anima de forma suave el tema
  equipado.
- Si el sistema activa `Reducir movimiento`, el escenario se mantiene en una
  composición estática representativa en vez de repetir la animación.
- `preview.dart` acepta
  `PARCHESPOP_PREVIEW_THEME=<identificador_del_tema>` para abrir y revisar
  directamente cualquiera de los cinco escenarios en el simulador.
- Verificación visual completada para Ciudad Futurista, Templo de las
  Pirámides, Selva Viva, Arcade Retro y Aurora Ártica, además de las nuevas
  miniaturas de la tienda. Las pruebas comparan píxeles entre fotogramas para
  exigir animación real, no solo repintado. Verificación automática del
  proyecto: 267 pruebas aprobadas y análisis estático sin incidencias.

### Colecciones de fichas coordinadas por tema — 28 de julio de 2026

- Cada tema premium tiene ahora su propio juego de cuatro fichas, manteniendo
  siempre como color dominante el azul, amarillo, rojo o verde del jugador:
  - Ciudad Futurista usa **Fichas Pulso Neón** (`tokens_neon_pulse`).
  - Templo de las Pirámides usa **Fichas Escarabajo Solar**
    (`tokens_solar_scarab`).
  - Selva Viva usa **Fichas Tótem Selvático** (`tokens_jungle_totem`).
  - Arcade Retro usa **Fichas Pixel Blaster** (`tokens_pixel_blaster`).
  - Aurora Ártica usa **Fichas Fragmento Aurora** (`tokens_aurora_shard`).
- Cada colección se compra y se equipa de forma independiente. El jugador
  puede usar el conjunto recomendado o mezclar un tablero con otras fichas;
  equipar un tema nunca reemplaza silenciosamente la ficha que ya eligió.
- Las tarjetas de temas muestran sus cuatro fichas compañeras directamente
  sobre el mini tablero. Las tarjetas de fichas usan una cuadrícula 2 por 2
  centrada para que los cuatro colores tengan el mismo espacio en teléfonos.
- El mismo dibujo vectorial se utiliza en la tienda y en la partida. Los cinco
  motivos son circuito de neón, escarabajo solar, máscara selvática, nave
  pixelada y cristal de aurora.
- Los perfiles preparados para completar una Partida Rápida reciben una
  combinación coherente de tema y fichas. La herramienta de vista previa usa
  también la ficha compañera del tema seleccionado.
- Los nombres, descripciones y mensajes de compra están disponibles en español
  e inglés; el mensaje inglés traduce también el nombre del artículo.
- Verificación terminada con vistas reales de tienda a tamaño iPhone 14,
  compra, equipamiento, persistencia, aplicación dentro de `GameScreen`,
  coordinación de Partida Rápida y 267 pruebas aprobadas. El análisis estático no reporta
  incidencias.

### Rotación libre de pantalla — 28 de julio de 2026

- El teléfono ya no fuerza la partida ni ninguna otra pantalla a `landscape`.
  La aplicación sigue la posición física del dispositivo y puede verse en
  vertical, horizontal hacia la izquierda u horizontal hacia la derecha.
- La orientación vertical es la presentación natural cuando el teléfono está
  derecho. `Landscape` queda disponible como una opción automática cuando el
  jugador gira el equipo; no es un requisito para entrar al juego.
- La aplicación principal y las vistas de demostración usan la misma política
  de rotación. iOS declara vertical y ambos lados horizontales; Android no
  contiene ningún bloqueo de orientación. Las tabletas conservan además el
  soporte vertical invertido del sistema.
- El lobby, la tienda y la partida reorganizan sus controles según el espacio.
  La partida conserva el mismo estado, turno y progreso de las fichas al pasar
  de vertical a horizontal y al regresar, sin reiniciarse.
- La entrada normal de iOS volvió a `lib/main.dart`; ejecutar una vista de
  demostración ya no deja el proyecto configurado accidentalmente para abrir
  una pantalla de prueba.
- Verificación completada en Parchese Pop iPhone 14 con la secuencia
  vertical → horizontal → vertical, sin recortes. También se aprobaron pruebas
  específicas para ambas direcciones horizontales y para conservar una
  partida activa durante el giro. Resultado total: 267 pruebas aprobadas y
  análisis estático sin incidencias.

### Versión visible y prueba simultánea iOS/Android — 28 de julio de 2026

- La versión canónica continúa definida en `pubspec.yaml`; la compilación
  actual es `1.0.0+1`.
- La cinta inferior de la partida muestra `v1.0.0+1` junto al mensaje de turno.
  En landscape, la misma versión aparece en la línea de estado del panel
  lateral compacto.
- La etiqueta obtiene en tiempo de ejecución la versión y el número de build
  realmente instalados mediante `package_info_plus`. Por eso también refleja
  correctamente una compilación creada con `--build-name` o
  `--build-number`, sin mantener una segunda versión escrita manualmente.
- El texto accesible “Versión del juego” está disponible en español e inglés.
- La imagen lateral de Android era un estado de rotación del emulador: la
  superficie estaba en landscape dentro de un marco físico vertical. No se
  añadió ningún bloqueo a la aplicación. Android conserva rotación libre y se
  corrigió usando la rotación física simulada del AVD.
- La misma compilación `1.0.0+1` se verifica en Parchese Pop iPhone 14 con
  iOS 18.6 y Pixel 9 Pro XL con Android 16/API 36. El Android queda abierto en
  landscape real, con marco lógico y físico horizontales.

### AdMob, consentimiento y seguridad familiar — 29 de julio de 2026

- AdMob se usa exclusivamente en Android y iOS. macOS continúa usando el
  controlador sin anuncios y no reserva espacio para banners ni ofrece
  recompensas publicitarias.
- Los mensajes de **Regulaciones europeas** y **Regulaciones estatales de
  Estados Unidos** están publicados en AdMob para las dos apps móviles; cada
  sección muestra `1 active`. Los mensajes están disponibles en inglés y
  español latinoamericano.
- Las unidades activas verificadas son dos banners y una recompensa por
  plataforma. El código utiliza el banner principal y la recompensa de
  producción correspondientes a cada sistema; las compilaciones de depuración
  usan únicamente los IDs oficiales de prueba de Google.
- La recompensa configurada en AdMob es de **100 monedas** tanto en Android
  como en iOS. El juego acredita las monedas solamente cuando recibe el evento
  que confirma que el anuncio recompensado fue completado.
- Las dos apps quedaron limitadas a la clasificación publicitaria
  **General Audiences (G)**. También se bloquearon las categorías de
  procedimientos cosméticos, citas, drogas y suplementos, enriquecimiento
  rápido, referencias sexuales, salud sexual y reproductiva, casino social y
  pérdida de peso. Alcohol y apuestas para mayores ya estaban bloqueados.
- La misma clasificación `G` se aplica en el código antes de inicializar el
  SDK, después de obtener el consentimiento mediante UMP.
- iOS contiene los 50 `SKAdNetworkIdentifier` de la lista oficial de Google,
  sin duplicados. No se solicita ATT ni acceso al IDFA; por eso el mensaje
  explicativo de IDFA no se publica y no se considera una función pendiente.
- La política de privacidad pública explica que Analytics está desactivado en
  la compilación actual, además de banners, recompensas, compras, consentimiento,
  exclusión de macOS y ausencia de rastreo IDFA.
- El Centro de políticas de AdMob no reporta incidencias. `app-ads.txt` ya está
  publicado y verificado en `https://liisgo.com/app-ads.txt` para las apps
  aprobadas de la cuenta.
- Pendiente de publicación, no de implementación: AdMob mantiene Parchese Pop
  con `Requires review / Limited ad serving` hasta que las fichas reales de
  Google Play y App Store estén publicadas y se añadan a las dos apps. En ese
  momento debe usarse `liisgo.com` como sitio del desarrollador para que AdMob
  detecte el mismo `app-ads.txt`.
- Firebase no forma parte de la compilación actual. No debe documentarse ni
  declararse recopilación mediante Firebase Analytics mientras
  `initializeGameAnalytics()` continúe devolviendo el servicio `no-op`.

### Corrección estructural completada

La ruta simplificada anterior de 52 casillas fue sustituida por el tablero tradicional de 68 posiciones, siete pasos privados y meta central. La geometría visual usa una cuadrícula lógica de 20 por 20 para reproducir las casillas rectangulares, las bases, los giros y el centro de la referencia, conservando la regla local de salir con cinco.

## Regla de mantenimiento

Toda decisión aprobada debe añadirse a este archivo. Las ideas no aprobadas deben permanecer en “Decisiones pendientes” hasta que se confirmen. No se deben reemplazar reglas aprobadas sin registrar el cambio.
