# Parchís Pop · fases de la versión 2

Versión de aplicación: **2.2.1+16**
Rama: **version-2**

## 1. Base segura

- Los anuncios recompensados son voluntarios; nunca bloquean reanudar, volver
  al inicio ni jugar una revancha.
- Analítica anónima apagada por defecto y disponible mediante opt-in explícito
  en Ajustes para medir primera tirada, partida terminada, abandono,
  reanudación, revancha, tutorial, misiones y tienda.
- Guardado compatible con partidas anteriores y recuperación redundante de la
  libreta de monedas para evitar pagos duplicados.
- La mesa rápida local identifica claramente a todos los rivales automáticos
  como **CPU** y nunca toma el control del jugador al pausar la aplicación.

## 2. UX/UI y tutorial

- Estado de interacción único: tirar, elegir ficha, elegir destino o esperar.
- El tablero y el HUD no cambian de tamaño durante una elección.
- Tutorial persistente de seis pasos que reacciona a jugadas reales.
- Sonido para los eventos principales y respuesta háptica proporcional para
  movimiento, seguro, captura, meta y victoria.

## 3. Retención

- Recompensa por completar la partida y por posición.
- Bonificación por la primera partida del día.
- Tres misiones diarias: mover 20 casillas, sacar una ficha y terminar una
  partida.
- Objetivo semanal de siete partidas terminadas.
- Todos los premios son persistentes e idempotentes.

## 4. Monetización básica

- La progresión normal permite alcanzar cosméticos sin depender de anuncios.
- El anuncio posterior a la partida es voluntario y duplica únicamente el
  premio base de partida y posición.
- El CTA de bonus por anuncio recompensado es permanente en los resultados de
  Tradicional, Caos, Quick Table y Quick Pop en Android/iOS, contra CPU, local
  y online. Un modo o rediseño nuevo debe conservarlo; si el anuncio está
  cargando o no disponible cambia su estado, no se oculta, y después del cobro
  se transforma en confirmación sin permitir pagos duplicados.
- No hay anuncios obligatorios al reanudar, volver al inicio o pedir revancha.
- Los cosméticos no cambian movimientos ni probabilidades.

## 5. Quick Pop

- Dos fichas por jugador, colocadas en la salida desde el comienzo.
- No exige sacar un cinco para iniciar.
- Victoria al llevar las dos fichas a meta.
- Formato independiente de Tradicional/Caos, con guardado compatible y reglas
  versionadas.
- Automovimiento solo cuando el motor confirma una única jugada legal.
- En la prueba online controlada busca durante diez segundos. Si al llegar al
  límite no existe un compromiso humano compartido, abre la partida local
  contra CPU. Si el servidor ya pudo comprometer una partida humana pero la
  conexión no permite confirmar el mismo resultado en ambos dispositivos, la
  pantalla pide revisar la conexión y volver; nunca adivina un resultado que
  pueda separar a los dos jugadores.

## 6. Sistemas avanzados protegidos

- Quick Pop casual online y Quick Table casual están activos únicamente para
  QA controlado sobre Firebase.
- Quick Table permite sala pública o privada, código de seis caracteres,
  invitación compartible, hasta cuatro jugadores y tirada inicial sincronizada
  para decidir quién comienza; después continúa el orden hacia la derecha.
- El protocolo usa comandos validados e idempotentes, checkpoints, presencia,
  reconexión y abandono. Los participantes automáticos se identifican como
  **CPU**.
- Rango, eventos y premios competitivos solo podrán aceptar resultados
  verificados por una autoridad confiable.
- Se conservan las guardas contra pago por ventaja, entrada con monedas,
  premio aleatorio pago y publicidad obligatoria.

Antes de presentar estas funciones como online de producción todavía hace
falta una autoridad confiable del servidor, App Check, moderación,
observabilidad y endurecimiento operativo. También deben completarse las
pruebas de reconexión y continuación extremo a extremo, y la sincronización
autoritaria de todas las variantes de Caos (inventario, trampas y efectos).

Las recompensas diarias locales usan la fecha persistida del dispositivo como
una protección de mejor esfuerzo. Antes de habilitar rangos, eventos o premios
competitivos, el servidor deberá proporcionar la hora autoritativa además del
resultado firmado de cada partida.

## Verificación requerida para publicar

1. `flutter analyze` sin problemas.
2. Suite completa de pruebas aprobada.
3. APK release de QA generado con `--dart-define=QA_TEST_ADS=true` y compilación
   iOS simulador generados desde una copia interna.
4. Prueba visual en teléfono pequeño y iPhone 17.
5. Copia del código y bundle Git en el disco externo.

## Cierre QA · 2026-08-11

- Análisis estático limpio y suite Flutter completa aprobada (711 pruebas).
- Repetición online: 68 pruebas críticas aprobadas; reglas Firebase 21/21;
  smoke multicliente 5/5, incluido Quick Table con cuatro clientes, ready,
  opening roll, orden de turnos y cierre.
- Manual: Traditional y Chaos contra CPU, Quick Pop humano y fallback CPU a
  los diez segundos, Quick Table privado/público con código e invitación,
  compartir por Android y Pass & Play en ambos modos.
- iPhone 13 e iPhone 17 reinstalados y arrancados desde cero.

La publicación de producción todavía requiere ejecutar la misma matriz con
Firebase/AdMob de producción y cuatro ventanas táctiles desbloqueadas; el APK
QA enviado no debe publicarse en una tienda.
