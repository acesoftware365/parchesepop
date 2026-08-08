# Parchís Pop · fases de la versión 2

Versión de aplicación: **2.1.0+10**
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
- No hay anuncios obligatorios al reanudar, volver al inicio o pedir revancha.
- Los cosméticos no cambian movimientos ni probabilidades.

## 5. Quick Pop

- Dos fichas por jugador, colocadas en la salida desde el comienzo.
- No exige sacar un cinco para iniciar.
- Victoria al llevar las dos fichas a meta.
- Formato independiente de Tradicional/Caos, con guardado compatible y reglas
  versionadas.
- Automovimiento solo cuando el motor confirma una única jugada legal.

## 6. Sistemas avanzados protegidos

- Contrato para que un servidor sea dueño de dados, turnos y movimientos.
- Comandos validados e idempotentes para la base local del protocolo.
- Modelos de checkpoints, reconexión, presencia y abandono.
- Rango y eventos solo aceptan resultados verificados por la autoridad.
- Guardas contra pago por ventaja, entrada con monedas, premio aleatorio pago
  y publicidad obligatoria.

Estos sistemas son una base de contrato comprobable, pero permanecen
desactivados en la interfaz pública. Antes de habilitarlos hay que conectar un
servidor real, hacer que la autoridad ejecute cada transición, implementar la
toma efectiva de turnos por CPU y sincronizar por completo Caos (inventario,
trampas y efectos), además de probar reconexión y continuación extremo a
extremo.
La mesa rápida que incluye esta compilación es local y etiqueta claramente a
los participantes automáticos como **CPU**.

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
