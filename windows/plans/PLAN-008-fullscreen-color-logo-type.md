# PLAN-008 — Fondo, logo y tipografía frente a macOS

- Objetivo: igualar composición e intensidad de fondo fullscreen, redondear logo Windows y comprobar tamaños de metadata frente al código Apple vigente.
- Estado: implementado y revisado; build-0010 compilada, aceptación física pendiente.
- Ámbito: presentación y assets Windows; Apple/core sólo lectura. Preservar controles, navegación y reproducción. No sustituir SF Pro ni cambiar la marca.
- Referencias: `FullscreenBackdrop.swift`, `FullscreenSceneLayout.swift`, `FullscreenNowPlayingView.swift`, assets Apple; FIX-137/FIX-142/FIX-144/FIX-145.

## Pasos

- [x] Revisar estado existente y dividir agentes con ámbitos separados.
- [x] Identificar doble oscurecimiento Windows frente a overlay Apple del 72%.
- [x] Verificar fuente real y licencia: Apple `.system`/SF Pro; Windows Segoe UI. SF Pro no se distribuye en Windows.
- [x] Implementar fondo fiel y revisar fallbacks de imagen.
- [x] Comparar y redondear assets de logo sin alterar diseño.
- [x] Auditar tamaños/pesos y corregir diferencias justificadas.
- [x] Revisar diff, comprobar frontend y fixture a tamaños equivalentes.
- [x] Registrar FIXES/PARIDAD y conservar build numerada.

## Cierre

Comprobar título, artista y álbum frente a ancho real de carátula; botones y cola mantienen FIX-144/FIX-145. Revisar iconos con alpha y tamaños Windows. Compilar no demuestra igualdad perceptual entre renderizadores ni aceptación nativa: dejar esos límites explícitos.

Implementación revisada en FIX-146/PAR-025. Fuente SF Pro excluida por licencia oficial Apple: https://developer.apple.com/fonts/index.html. La escala ya coincide; pesos/tonos/interlineado corregidos. Build-0010 release: 635 aprobadas, cero fallos/14live ignoradas, check0/0, hashes correctos y fuentes sin cambios durante build. Aceptación nativa/perceptual pendiente.

## Seguimiento de icono incrustado — FIX-151

- [x] Detectar diferencia entre assets redondeados y PE de build-0010: seis recursos aún cuadrados.
- [x] Declarar directorio icons como dependencia del build-script Cargo.
- [x] Nueva build numerada y comparación de seis RT_ICON con ICO vigente; conservar intento0011 interrumpido.

Build-0012 release compiled,646 aprobadas/14live omitidas/cero fallos, check0/0, fuentes estables/cuatro hashes; seis RT_ICON coinciden con ICO redondeado en bytes y transparencia. Recursos de0010 idénticos al ICO anterior. Shell físico/audio sin comprobar; intento0011 conservado como interrupción, no entregable.
