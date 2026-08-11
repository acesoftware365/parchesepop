# Parchís Pop Privacy Policy

**Effective date: August 9, 2026**

This Privacy Policy explains how Parchís Pop handles information when you use
the game on Android, iOS, macOS, or another supported platform.

## Information stored on your device

Parchís Pop stores game information locally on your device, including:

- your optional player profile, such as display name, email, flag, and avatar;
- coins, cosmetic purchases, equipped items, level, game progress, tutorial
  progress, and a saved match;
- language, sound, music, vibration, hand preference, and other settings; and
- local account credentials when the prototype email account option is used.

Raw passwords are not stored. The local prototype stores a salted password
digest. You may play against the CPU without creating a profile. The email and
password entered for this local profile are not sent to Firebase to start an
online match.

## Online services and multiplayer

When you choose an online feature, Parchís Pop uses Google Firebase
Authentication to create or reuse an anonymous identifier for that installation
and Firebase Realtime Database to operate matchmaking and games. Online data
may include:

- the anonymous Firebase user identifier, display name, avatar, timestamps, and
  equipped cosmetic information;
- room code, public or private room status, membership, presence, opening rolls,
  queue and matchmaking status;
- game actions, current game state, recovery checkpoints, results, and
  connection status; and
- preapproved quick-chat phrases. Parchís Pop does not provide free-form
  in-game chat.

Other players in the same room can see the player information, game state, and
preapproved messages needed to play the match. During an active Quick Pop
search, other players actively searching in the same matchmaking queue can see
the anonymous Firebase identifier, display name, ticket identifiers, and timing
or status fields in that queue entry so the clients can choose and verify a
match. After that search window, a player cannot list the queue; access is
limited to their own ticket and the exact opponent ticket linked to their
verified match claim. Only the two players named by a resulting match claim can
read that claim, and each synced profile is readable only by its owner. If a
host marks a room
public, the app may show a limited room listing to other players. If a real
player is not found for Quick Pop within the displayed search period, the game
may start with computer-controlled opponents.

Parchís Pop also uses Firebase Remote Config to obtain service-availability,
minimum-version, update-message, and update-link settings. Google Firebase SDKs
may process technical identifiers, app-instance or installation information,
IP address, device and operating-system information, diagnostics, and network
activity needed to provide and secure these services.

## Analytics

Anonymous analytics collection is off by default. You may enable or disable it
at any time from **Settings > Anonymous analytics**. When enabled, Parchís Pop
uses Google Firebase Analytics to understand how the game is used and improve
its design. Analytics events may include anonymous app-session starts and days
since first use for aggregate retention metrics; entry, search, creation, join,
invitation, cancellation, failure, and success steps in Quick Pop and Quick
Table; elapsed time and broad failure categories; match starts and completions;
abandonment and resume events; selected modes; tutorial progress; optional-ad
choices; currency rewards; and shop interactions. The exact first-use timestamp
remains on the device. The game does not intentionally include your display
name, email, chat messages, flag, avatar, room codes, Firebase UID, or raw error
text in these analytics events.

Google may process technical information such as device identifiers, app
instance information, approximate location derived from IP address, operating
system, and interaction data according to Google's policies.

## Advertising

The Android and iOS versions use Google AdMob:

- adaptive banner advertisements may appear in a reserved strip at the bottom
  of the screen, including during gameplay, the game guide, and matchmaking.
  The banner does not cover game controls, pause the game, open a full-screen
  advertisement, or interrupt a move; and
- optional rewarded advertisements may be offered in the **Shop** for the coin
  bonus shown on the button and after the whole table finishes to double an
  eligible match reward. A rewarded advertisement opens only after the player
  explicitly chooses it, and the reward is granted only after the advertisement
  is completed.

Rewarded advertisements are always voluntary. Resume, Play Again, Back to Home,
rolling the dice, and moving a piece never trigger a full-screen or rewarded
advertisement. The reserved bottom banner may remain visible.

The macOS version does not request or display AdMob banner or rewarded
advertisements.

Parchís Pop currently does not request permission to track activity across
other companies' apps or websites and does not request access to Apple's
Advertising Identifier (IDFA).

Depending on your region and consent choices, Google and its advertising
partners may process device identifiers, IP address, diagnostic data, ad
interactions, and information used to provide, measure, limit, or personalize
advertising. Parchís Pop uses Google's User Messaging Platform to request
consent when required. You may review or change available advertising privacy
choices from the app's **Settings > Privacy and policies** screen.

For more information about how Google handles data, see:

- [How Google uses information from sites or apps that use its services](https://policies.google.com/technologies/partner-sites)
- [Google Privacy Policy](https://policies.google.com/privacy)

## Data sharing

Parchís Pop does not sell personal information. Information may be processed by
Google services used to operate the app, including Firebase Authentication,
Firebase Realtime Database, Firebase Remote Config, Firebase Analytics, AdMob,
and the User Messaging Platform, subject to Google's terms and your available
consent choices. Information may also be disclosed when required by law or to
protect users, the service, or legal rights.

## Retention and deletion

Local profile, credentials, preferences, progress, saved matches, coins, and
cosmetic data remain on the device until you remove them, clear the app's
storage, or uninstall the app. **My Profile > Delete account and data** removes
this local information, deletes the anonymous Firebase Authentication identity,
and removes the player's online profile, active matchmaking ticket, pending
join request, presence, and removable waiting-room membership when available.

Resolved matchmaking tickets and claims, resolved matches, immutable chat, and
shared room records can contain state belonging to other players and may remain
for service integrity, abuse prevention, diagnostics, or legal requirements
until they are deleted or anonymized under the service retention process.
Access to retained matchmaking records remains restricted to their owner or the
verified participants as applicable. An older online identity created before
direct account deletion was available may also require verified backend cleanup.
To request deletion of retained or legacy server-side data, email
**sales@liisgo.com**. We may ask for limited information needed to locate and
verify the relevant records; never send a password.

Analytics and advertising providers retain information according to their own
policies and legal obligations. Available advertising consent choices can be
changed from the privacy screen.

## Security

Reasonable technical measures are used to protect information, including
Firebase authentication and access rules for online data. However, no
electronic storage or transmission method is completely secure. Do not include
sensitive personal information in a player display name.

## Children and families

Parchís Pop is a general-audience game. Users who are not old enough to provide
valid consent under the laws of their country should use the game only with the
permission and supervision of a parent or guardian. We do not knowingly ask
children to send sensitive personal information through the game.

## Your privacy rights

Depending on where you live, you may have rights to access, correct, delete,
restrict, or object to certain processing of personal information, or to
withdraw consent. Advertising consent and opt-out choices are presented when
required by applicable law. Contact **sales@liisgo.com** for a privacy or data
request.

## Changes to this policy

This policy may be updated as Parchís Pop and its services change. The effective
date at the top of this page identifies the latest revision.

## Contact

For privacy, support, or data requests:

- Email: **sales@liisgo.com**
- Project repository:
  [https://github.com/acesoftware365/parchesepop](https://github.com/acesoftware365/parchesepop)

---

# Política de privacidad de Parchís Pop

**Fecha de vigencia: 9 de agosto de 2026**

Esta Política de privacidad explica cómo Parchís Pop maneja la información
cuando utilizas el juego en Android, iOS, macOS u otra plataforma compatible.

## Información guardada en tu dispositivo

Parchís Pop guarda localmente en tu dispositivo:

- tu perfil opcional, como nombre visible, correo electrónico, bandera y avatar;
- monedas, compras cosméticas, artículos equipados, nivel, progreso, avance del
  tutorial y una partida guardada;
- idioma, sonido, música, vibración, preferencia de mano y otros ajustes; y
- credenciales locales cuando se utiliza la opción de cuenta por correo del
  prototipo.

Las contraseñas no se guardan en texto plano. El prototipo local conserva un
resumen de contraseña con sal. Puedes jugar contra el CPU sin crear un perfil.
El correo y la contraseña del perfil local no se envían a Firebase para iniciar
una partida online.

## Servicios online y multijugador

Cuando eliges una función online, Parchís Pop utiliza Google Firebase
Authentication para crear o reutilizar un identificador anónimo de esa
instalación y Firebase Realtime Database para operar la búsqueda de jugadores y
las partidas. Los datos online pueden incluir:

- el identificador anónimo de Firebase, nombre visible, avatar, fechas y datos
  de los cosméticos equipados;
- código de sala, estado público o privado, participantes, presencia, tiradas
  iniciales y estado de la cola o búsqueda;
- acciones, estado actual, puntos de recuperación, resultados y estado de
  conexión de la partida; y
- frases preaprobadas del chat rápido. Parchís Pop no ofrece chat libre dentro
  de la partida.

Los demás jugadores de la misma sala pueden ver la información del jugador, el
estado de la partida y los mensajes preaprobados necesarios para jugar. Durante
una búsqueda activa de Quick Pop, los demás jugadores que estén buscando
activamente en la misma cola pueden ver el identificador anónimo de Firebase,
nombre visible, identificadores del ticket y campos de tiempo o estado de esa
entrada para que los clientes puedan elegir y verificar un emparejamiento.
Después de esa ventana de búsqueda, un jugador no puede enumerar la cola; el
acceso queda limitado a su propio ticket y al ticket exacto del rival vinculado
a su acuerdo verificado. Solo los dos jugadores indicados en el acuerdo
resultante pueden leer ese acuerdo, y cada perfil
sincronizado es legible únicamente por su propietario. Si el anfitrión marca una
sala como pública, la aplicación puede mostrar un listado limitado de la sala a
otros jugadores. Si Quick Pop no encuentra un jugador real durante el período
de búsqueda mostrado, la partida puede comenzar con oponentes controlados por
computadora.

Parchís Pop también utiliza Firebase Remote Config para obtener ajustes sobre
disponibilidad del servicio, versión mínima, mensaje y enlace de actualización.
Los SDK de Google Firebase pueden procesar identificadores técnicos, información
de la instancia o instalación, dirección IP, datos del dispositivo y sistema
operativo, diagnósticos y actividad de red necesarios para ofrecer y proteger
estos servicios.

## Analíticas

La recopilación de analíticas anónimas está apagada por defecto. Puedes
activarla o desactivarla en cualquier momento desde **Ajustes > Analítica
anónima**. Cuando está activa, Parchís Pop utiliza Google Firebase Analytics
para comprender cómo se usa el juego y mejorar su diseño. Los eventos pueden
incluir inicios de sesión anónimos y días desde el primer uso para métricas
agregadas de retención; pasos de entrada, búsqueda, creación, unión, invitación,
cancelación, fallo y éxito en Quick Pop y Quick Table; tiempo transcurrido y
categorías generales de fallo; inicio y final de partidas; abandono y
reanudación; modos elegidos; avance del tutorial; decisiones sobre anuncios
opcionales; premios de monedas e interacciones con la tienda. La fecha exacta
del primer uso permanece en el dispositivo. El juego no incluye
intencionalmente tu nombre visible, correo, mensajes, bandera, avatar, códigos
de sala, UID de Firebase ni textos de error sin filtrar en estos eventos.

Google puede procesar información técnica, como identificadores del dispositivo,
información de la instancia de la aplicación, ubicación aproximada derivada de
la dirección IP, sistema operativo y datos de interacción, conforme a sus
políticas.

## Publicidad

Las versiones de Android e iOS utilizan Google AdMob:

- pueden mostrar banners adaptables en una banda reservada en la parte inferior,
  incluso durante la partida, la guía del juego y la búsqueda de jugadores. El
  banner no cubre los controles, no pausa el juego, no abre un anuncio a
  pantalla completa ni interrumpe una jugada; y
- pueden ofrecer anuncios recompensados opcionales en la **Tienda** por la
  bonificación de monedas indicada en el botón y después de que termine la mesa
  completa para duplicar una recompensa elegible. El anuncio recompensado se
  abre únicamente cuando el jugador lo elige de forma explícita y la recompensa
  se entrega solo después de completarlo.

Los anuncios recompensados son siempre voluntarios. Reanudar, Jugar otra vez,
Volver al inicio, tirar los dados y mover una ficha nunca activan un anuncio a
pantalla completa o recompensado. El banner inferior reservado puede permanecer
visible.

La versión de macOS no solicita ni muestra banners o anuncios recompensados de
AdMob.

Actualmente, Parchís Pop no solicita permiso para rastrear actividad entre
aplicaciones o sitios web de otras compañías ni solicita acceso al identificador
de publicidad de Apple (IDFA).

Según tu región y tus decisiones de consentimiento, Google y sus socios
publicitarios pueden procesar identificadores del dispositivo, dirección IP,
datos de diagnóstico, interacciones con anuncios e información utilizada para
ofrecer, medir, limitar o personalizar publicidad. Parchís Pop utiliza la
plataforma de mensajería para usuarios de Google para solicitar consentimiento
cuando corresponde. Puedes revisar o cambiar las opciones disponibles desde
**Ajustes > Privacidad y políticas** dentro del juego.

Para conocer cómo Google maneja los datos, consulta:

- [Cómo usa Google la información de sitios o aplicaciones que utilizan sus servicios](https://policies.google.com/technologies/partner-sites?hl=es)
- [Política de privacidad de Google](https://policies.google.com/privacy?hl=es)

## Intercambio de información

Parchís Pop no vende información personal. La información puede ser procesada
por los servicios de Google utilizados para operar la aplicación, incluidos
Firebase Authentication, Firebase Realtime Database, Firebase Remote Config,
Firebase Analytics, AdMob y la plataforma de mensajería para usuarios, conforme
a las condiciones de Google y a tus opciones de consentimiento. También se
puede divulgar información cuando la ley lo exija o para proteger a los
usuarios, el servicio o derechos legales.

## Retención y eliminación

El perfil, las credenciales, preferencias, progreso, partidas guardadas, monedas
y cosméticos locales permanecen en el dispositivo hasta que los elimines, borres
los datos de la aplicación o desinstales la aplicación. **Mi perfil > Eliminar
cuenta y datos** elimina esa información local del dispositivo. Esa acción
también elimina la identidad anónima de Firebase Authentication y, cuando están
disponibles, el perfil online, la búsqueda activa, la solicitud pendiente de
entrada, la presencia y la membresía removible de una sala en espera.

Los tickets y acuerdos de emparejamiento resueltos, las partidas resueltas, el
chat inmutable y los registros de salas compartidas pueden contener estado de
otros jugadores y conservarse para mantener la integridad del servicio,
prevenir abusos, realizar diagnósticos o cumplir obligaciones legales hasta que
se eliminen o anonimicen según el proceso de retención. El acceso a los
registros de emparejamiento conservados sigue limitado a su propietario o a los
participantes verificados, según corresponda. Una identidad online antigua,
creada antes de que existiera el borrado directo, también puede requerir una
limpieza verificada del servidor. Para solicitar la eliminación de datos
retenidos o antiguos, escribe a
**sales@liisgo.com**. Podemos pedir información limitada para localizar y
verificar los registros; nunca envíes una contraseña.

Los proveedores de analíticas y publicidad conservan información de acuerdo con
sus propias políticas y obligaciones legales. Las opciones disponibles de
consentimiento publicitario pueden cambiarse desde la pantalla de privacidad.

## Seguridad

Se utilizan medidas técnicas razonables para proteger la información, incluidas
la autenticación de Firebase y reglas de acceso para los datos online. Sin
embargo, ningún método de almacenamiento o transmisión electrónica es
completamente seguro. No incluyas información personal sensible en el nombre
visible del jugador.

## Menores y familias

Parchís Pop es un juego para una audiencia general. Los usuarios que no tengan
la edad necesaria para dar un consentimiento válido según las leyes de su país
deben usar el juego únicamente con el permiso y la supervisión de un padre,
madre o tutor. No solicitamos deliberadamente que los menores envíen información
personal sensible mediante el juego.

## Tus derechos de privacidad

Según el lugar donde vivas, puedes tener derecho a acceder, corregir, eliminar,
restringir u oponerte a ciertos usos de información personal, o retirar el
consentimiento. Las opciones de consentimiento y exclusión publicitaria se
presentan cuando lo exige la ley aplicable. Escribe a **sales@liisgo.com** para
una solicitud de privacidad o datos.

## Cambios a esta política

Esta política puede actualizarse cuando cambien Parchís Pop o sus servicios. La
fecha al principio de esta página identifica la revisión más reciente.

## Contacto

Para solicitudes de privacidad, soporte o datos:

- Correo: **sales@liisgo.com**
- Repositorio del proyecto:
  [https://github.com/acesoftware365/parchesepop](https://github.com/acesoftware365/parchesepop)
