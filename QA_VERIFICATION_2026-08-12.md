# Parchís Pop · verificación multiplataforma

**Fecha:** 2026-08-12
**Versión:** 2.2.1+16
**Rama:** `version-2`

## Resultado comprobable

| Área | Resultado |
| --- | --- |
| Suite Flutter completa | **726/726** |
| Firebase smoke multicliente | **5/5** |
| Reglas Firebase | **22/22** |
| Análisis estático | sin diagnósticos nuevos (también limpio en la copia temporal de QA) |
| macOS | build Debug limpio en copia temporal fuera del disco externo; Home arrancó y mostró Quick Pop, Quick Table, CPU y Pass & Play |
| iOS | iPhone 16e e iPhone 17 Simulator instalados/arrancados; capturas de Home guardadas |
| Android | APK Debug compilado en copia temporal; los AVD disponibles iniciaron con ADB inestable y no permitieron una captura de la app repetible |
| Windows | `DefaultFirebaseOptions.windows` configurado con el registro Web del mismo proyecto; no se puede ejecutar un build Windows desde este Mac |

## Qué cubren las suites online

- Quick Pop: dos clientes antes del límite, cancelación del rival, fallback a
  CPU a los diez segundos y estados ambiguos sin doble sala.
- Quick Table: cuatro clientes, sala privada/pública, código, ready, tirada
  inicial, desempate, orden hacia la derecha, cierre del anfitrión y salida del
  invitado.
- Recompensas por jugar, bonus voluntario por anuncio, Quick Messages seguros,
  reportar salas, sincronización, reconexión y reemplazo por CPU.

## Evidencia visual

Las capturas están en:

`/Users/juanpolanco/Desktop/Parchese_Pop_Test_Evidence_2026-08-12`

- `macOS/01_home.png`
- `iOS/01_home_iphone16e.png`
- `iOS/01_home_iphone17.png`
- `iOS/03_app_iphone17_loaded.png`

Las carpetas Android y Windows quedan preparadas para completar la captura en
un AVD estable y en un equipo Windows, respectivamente. No se debe presentar
esa parte como prueba manual completada.

## Pendiente para declarar compatibilidad de producción

1. Ejecutar Windows en una máquina Windows real y comprobar sala/cross-play con
   iOS, Android y macOS.
2. Repetir Quick Pop y Quick Table con cuatro clientes independientes en red
   real, no solo el smoke controlado.
3. Confirmar AdMob/consentimiento/rewarded reales y audio/hápticos físicos.
4. Repetir los formatos Fold, Flip y tablet con AVD que mantengan ADB estable,
   y revisar accesibilidad/font scaling con capturas.

El APK Debug de QA no es un artefacto de publicación y no se envió a ningún
contacto.
