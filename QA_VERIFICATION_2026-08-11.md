# Parchís Pop · cierre de verificación QA

**Fecha:** 2026-08-11
**Versión:** 2.2.1+16
**Rama:** `version-2`

## Resultado

La versión pasó la batería automatizada y la prueba manual prevista para QA.

| Área | Resultado |
| --- | --- |
| Análisis Flutter | Limpio |
| Suite Flutter completa | 711/711 |
| Suites online críticas repetidas | 68/68 |
| Reglas Firebase | 21/21 |
| Smoke Firebase multicliente | 5/5 |
| Quick Table automatizado | 4 clientes, ready, opening roll, orden y cierre |
| iPhone 13 / iPhone 17 | Instalación limpia y arranque |

## Flujos manuales comprobados

- Traditional CPU y Chaos CPU, incluyendo tirada de dados, tablero, HUD,
  minimapa y banner adaptable.
- Quick Pop online entre dos Android: misma sala, tablero, dados y turno.
- Quick Pop sin rival: fallback a CPU después de diez segundos.
- Quick Table privado: creación, código, entrada, ready, compartir y cierre.
- Quick Table público Chaos: directorio público y entrada por `JOIN`.
- Pass & Play Traditional y Chaos.

Los anuncios de prueba permanecen no intrusivos y el bonus recompensado se
mantiene voluntario. No se envió ningún mensaje automático desde la app.

## Alcance pendiente antes de producción

La matriz de cuatro ventanas táctiles simultáneas y la validación contra
Firebase/AdMob de producción deben repetirse con el Mac desbloqueado y las
credenciales/configuración de producción. El APK QA está firmado para pruebas,
no para publicación en tienda.
