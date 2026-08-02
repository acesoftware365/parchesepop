# Brief de audio — Parchese Pop

Este documento enumera la música y los efectos que deben producirse para la primera versión de Parchese Pop. La dirección general es **juego de mesa arcade moderno**: colorido, enérgico, juguetón y agradable también para adultos. Se pueden combinar fichas de plástico o madera, percusión ligera, sintetizadores brillantes y pequeños metales.

Todo el material debe ser original. No debe copiar melodías, voces, instrumentos distintivos ni efectos reconocibles de Mario, Sonic u otra franquicia.

## Formato de entrega

- Máster: WAV PCM, 48 kHz, 24-bit.
- Música: estéreo y preparada para repetición continua sin silencio al comienzo o al final.
- Efectos cortos: preferiblemente mono; fanfarrias, bomba y ambientes pueden ser estéreo.
- Incluir las variantes solicitadas sin limitarse a cambiar el tono del mismo archivo.
- Los nombres finales deben conservar el prefijo `mus_`, `sfx_` o `stg_`.
- No se necesitan voces en la primera entrega; así un mismo paquete funciona en todos los idiomas.

## Primera entrega — imprescindible

### Música

| Archivo | Se utiliza en | Duración orientativa |
|---|---|---:|
| `mus_menu_main_loop.wav` | Inicio, perfil y ajustes | 60–90 s, loop |
| `mus_match_traditional_loop.wav` | Partida tradicional | 90–150 s, loop |
| `mus_match_chaos_loop.wav` | Partida Caos | 90–150 s, loop |
| `mus_results_victory_bed.wav` | Panel final después de ganar | 10–18 s |
| `mus_results_defeat_bed.wav` | Panel final cuando gana un rival | 8–14 s |

### Interfaz y partida

| Archivo | Evento exacto | Duración | Variantes |
|---|---|---:|---:|
| `sfx_ui_tap_soft_v01.wav` | Botón normal | 0.06–0.12 s | 4 |
| `sfx_ui_play_confirm.wav` | Confirmar modo, dificultad o partida | 0.35–0.55 s | 2 |
| `sfx_ui_back_cancel.wav` | Volver o cancelar | 0.15–0.25 s | 2 |
| `sfx_ui_denied.wav` | Acción ilegal o botón no disponible | 0.20–0.35 s | 2 |
| `sfx_game_start.wav` | Aparece el tablero y comienza la partida | 0.8–1.2 s | 2 |
| `sfx_turn_local.wav` | Comienza el turno del jugador local | 0.35–0.55 s | 3 |
| `sfx_turn_opponent.wav` | Comienza el turno de CPU o rival | 0.20–0.35 s | 3 |
| `sfx_dice_shake_v01.wav` | Empieza el giro de los dados | 0.45–0.55 s | 4 |
| `sfx_dice_land_v01.wav` | Los dados muestran el resultado | 0.12–0.20 s | 6 |
| `sfx_dice_doubles.wav` | Salen dobles | 0.45–0.65 s | 3 |
| `sfx_three_doubles_penalty.wav` | El tercer doble devuelve una ficha a la cárcel | 0.9–1.2 s | 2 |
| `sfx_token_select.wav` | Se toca una ficha legal | 0.10–0.18 s | 4 |
| `sfx_token_step_v01.wav` | Cada casilla recorrida | 0.05–0.09 s | 6 |
| `sfx_token_land_v01.wav` | La ficha termina de caminar | 0.12–0.20 s | 4 |
| `sfx_token_exit_nest.wav` | La ficha sale con un 5 | 0.55–0.80 s | 3 |
| `sfx_move_blocked.wav` | Barrera, seguro ocupado o entrada bloqueada | 0.30–0.48 s | 3 |
| `sfx_no_legal_moves.wav` | El jugador no puede mover después de lanzar | 0.55–0.80 s | 2 |
| `sfx_capture_hit_v01.wav` | Una ficha captura a otra | 0.35–0.50 s | 4 |
| `sfx_token_return_nest_v01.wav` | La ficha capturada regresa a la cárcel | 0.75–1.05 s | 3 |
| `sfx_capture_entry_clear.wav` | Un 5 elimina la ficha que bloquea la entrada | 0.65–0.90 s | 2 |
| `sfx_bonus_20.wav` | Una captura concede 20 | 0.45–0.65 s | 2 |
| `sfx_token_home.wav` | Una ficha llega a la meta | 0.8–1.1 s | 3 |
| `sfx_bonus_10.wav` | Llegar a casa concede 10 | 0.40–0.60 s | 2 |
| `sfx_extra_turn.wav` | Los dobles conceden otra tirada | 0.40–0.60 s | 2 |
| `sfx_turn_skipped.wav` | Se consume un turno perdido | 0.55–0.75 s | 2 |

Los seis sonidos de pasos deben alternarse y limitar su superposición para que los recorridos largos no suenen como una ametralladora.

### Cubos, poderes y trampas

| Archivo | Evento exacto | Duración | Variantes |
|---|---|---:|---:|
| `sfx_cube_pickup.wav` | El jugador recoge el cubo sorpresa | 0.65–0.90 s | 3 |
| `sfx_mystery_opponent_pickup.wav` | Un rival obtiene un poder todavía oculto | 0.45–0.65 s | 2 |
| `sfx_shield_pickup.wav` | Se obtiene Escudo | 0.55–0.80 s | 2 |
| `sfx_shield_activate.wav` | Se activa Escudo | 0.65–0.90 s | 2 |
| `sfx_shield_block.wav` | El escudo bloquea captura o trampa | 0.55–0.80 s | 4 |
| `sfx_turbo_pickup.wav` | Se obtiene Turbo | 0.50–0.75 s | 2 |
| `sfx_turbo_activate.wav` | Se activa Turbo | 0.45–0.65 s | 3 |
| `sfx_turbo_dash.wav` | La ficha avanza por Turbo | 0.45–0.80 s | 3 |
| `sfx_trap_armed.wav` | La trampa queda colocada y oculta | 0.60–0.85 s | 3 |
| `sfx_trap_reveal.wav` | Una trampa oculta se revela | 0.25–0.40 s | 3 |
| `sfx_trap_glue_trigger.wav` | Pegamento atrapa la ficha | 0.9–1.2 s | 3 |
| `sfx_trap_glue_skip.wav` | Pegamento hace perder el próximo turno | 0.50–0.75 s | 2 |
| `sfx_trap_setback_trigger.wav` | Retroceso mueve la ficha seis pasos atrás | 0.9–1.2 s | 3 |
| `sfx_trap_prison_trigger.wav` | Cárcel devuelve la ficha a su base | 0.9–1.2 s | 3 |
| `sfx_trap_bomb_trigger.wav` | Aviso corto, explosión y regreso a base | 1.0–1.2 s | 4 |

La Bomba, Cárcel y Retroceso deben sonar solamente cuando la ficha llega visualmente a la trampa. El sonido de un objeto obtenido por un rival nunca debe revelar cuál objeto recibió.

### Victoria y derrota

| Archivo | Evento exacto | Duración | Variantes |
|---|---|---:|---:|
| `sfx_winner_reveal.wav` | Aparece el trofeo y el panel final | 0.75–1.0 s | 2 |
| `stg_local_victory.wav` | Gana el jugador local | 2.5–3.5 s | 2 |
| `stg_local_defeat.wav` | Gana CPU o rival | 2.0–3.0 s | 2 |
| `sfx_confetti_burst_v01.wav` | Sale el confeti | 0.8–1.4 s | 3 |
| `sfx_results_button.wav` | Revancha o volver al inicio | 0.30–0.50 s | 2 |

Secuencia recomendada:

1. La última ficha reproduce `sfx_token_home`.
2. La música de partida baja entre 8 y 10 dB durante 250 ms.
3. Al aparecer el panel suenan `sfx_winner_reveal.wav` y la fanfarria de victoria o derrota.
4. El confeti entra unos 100 ms después.
5. Al terminar la fanfarria comienza la música corta de resultados.

## Segunda entrega — pulido

| Archivo | Evento |
|---|---|
| `mus_matchmaking_loop.wav` | Búsqueda de rival |
| `mus_final_stretch_layer_loop.wav` | Un jugador tiene tres fichas en meta |
| `mus_shop_loop.wav` | Tienda |
| `sfx_ui_logo_pop.wav` | Aparición del logo |
| `sfx_ui_choice.wav` | Selector de modo, bandera o dificultad |
| `sfx_ui_modal_open.wav` / `sfx_ui_modal_close.wav` | Abrir o cerrar panel |
| `sfx_profile_saved.wav` | Perfil guardado |
| `sfx_matchmaking_pulse.wav` | Últimos tres segundos de búsqueda |
| `sfx_match_found.wav` | Rival encontrado |
| `sfx_chat_received.wav` | Mensaje pregrabado recibido |
| `sfx_coin_gain_v01.wav` | Monedas recibidas |
| `sfx_shop_purchase.wav` | Compra completada |
| `sfx_safe_square.wav` | Caer en una estrella segura |
| `sfx_barrier_created.wav` / `sfx_barrier_broken.wav` | Formar o abrir una barrera |
| `sfx_home_lane_enter.wav` | Entrar al pasillo de color |
| `sfx_cube_spin_loop.wav` | Brillo ambiental de los cubos; un solo loop para todo el tablero |
| `sfx_cube_respawn.wav` | El cubo reaparece en otro lugar |
| `sfx_power_slot_full.wav` | El espacio de poder ya está ocupado |
| `sfx_trap_place_mode.wav` | Empieza la selección de casilla para una trampa |
| `sfx_trap_cancel.wav` | Se cancela la colocación |
| `sfx_results_reward_count.wav` | Contador de monedas o puntos |
| `sfx_results_reward_complete.wav` | Termina el conteo de recompensa |

## Duraciones de animación que debe conocer el diseñador

- Giro de dados: 680 ms.
- Movimiento de ficha: de 420 a 1,050 ms.
- Reacción de poderes y trampas: 2,200 ms. El efecto debe permanecer
  completamente legible durante al menos dos segundos antes de devolver el
  control o cambiar de turno.
- Viaje de una ficha por una trampa: aproximadamente 950 ms.
- Rotación de cubos sorpresa: ciclo de 1,400 ms.
- Aparición del panel de victoria: comienza 650 ms después de la última jugada y dura 720 ms.
