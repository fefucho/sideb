# PLAN-001: playlists por tandas y shuffle reversible

- Estado: implementado y comprobado automáticamente (FIX-097/build-0011); validación manual pendiente.
- Objetivo: llevar a Mac el comportamiento Windows conservando ocurrencias, orden original y transporte al alternar shuffle.
- Ámbito: player/integración/viewmodels/tests Apple. Core excluido; la guía original no requiere cambios Rust.
- Referencias: [PAR-001](../../PARIDAD.md), [FIX-087](../../FIXES.md#fix-087), [contrato y casos](../../archive/PLAYLIST_SHUFFLE_PORT.md).

## Pasos

- [x] Contrastar la guía con QueueManager, PlayerViewModel y PlaybackStateStore actuales.
- [x] Definir identidad, orden de fuente, anclas y migración de persistencia.
- [x] Integrar catálogo completo/tandas y shuffle reversible sin recargar audio.
- [x] Probar duplicados, PlayNext/Append, arrastre, eliminación, cuenta/generación y restauración.
- [x] Ejecutar pruebas Apple y entregar build numerada para validar audio/comportamiento.
- [x] Registrar fix Apple y actualizar PAR-001 con evidencia/límites.

## Cierre

Conservar escenarios del contrato original, incluido catálogo de 2000 ocurrencias y ON/OFF/ON. Separar pruebas automáticas y manuales. Enlazar fix/build cuando existan.

## Contrato de implementación

Cola completa por ocurrencias UUID, rango original y anclas After/Before/End. Publicación de prefijo de 100, ampliado cerca del límite; transporte sobre todo el catálogo. Shuffle inicial elige en toda la fuente; ON conserva el prefijo activo y OFF restaura fuente y anclas sin resolver audio. Persistencia v2 guarda identidad/orden completo; v1 mezclada conserva orden legado sin inventar rangos. Catálogo compartido en memoria por sesión, invalidado por refresco/mutación/cuenta y sin guardar resultados parciales.

## Evidencia y validación pendiente

[FIX-097](../../FIXES.md#fix-097), [build-0011](../../builds/macos/build-0011/BUILD.json). 22 regresiones nuevas aprobadas; runner completo: 180 Rust, 26 XCTest y suite Swift Testing de 104 casos sin fallos (7 live omitidos en cada plataforma de pruebas). NSWindow de Home excluido; no se abrió la app. Intentos de pruebas fallidos conservados en build-0009/0010, con correcciones documentadas en el fix.

- [ ] Usuario: iniciar una playlist nueva grande y un álbum, alternar ON/OFF/ON durante audio; debe conservar canción/tiempo y restaurar orden completo.
- [ ] Usuario: PlayNext/Append, duplicados y arrastres antes/después de desactivar shuffle; llegar al final de la fuente sin perder canciones.
- [ ] Usuario: Tus Me Gusta, refrescos/mutaciones, cambio de cuenta y reinicio; datos privados aislados y restauración pausada.

Las colas v1 mezcladas carecen de orden original; se conserva su secuencia guardada sin inventar ese dato. La validación manual parte de una colección iniciada con esta versión. No se modificaron fuentes del core ni Windows.

## Inicio de pistas sin espera de catálogo — FIX-112

Corrección posterior a FIX-111/build-0030: `playPlaylist` normal con canciones disponibles comienza inmediatamente y completa el catálogo en segundo plano. No reemplazar audio ni ocurrencias al añadir el resto; conservar movimientos/eliminaciones/anclas y mezclar fuente pendiente si se activó shuffle mientras cargaba. El shuffle inicial mantiene la elección sobre todo el catálogo. Fallo conserva audio y continuación; cuenta/cola/contexto/solicitud rechazan resultados tardíos. [FIX-112](../../FIXES.md#fix-112), [PAR-010](../../PARIDAD.md); 11 pruebas focales aprobadas; [build-0031](../../builds/macos/build-0031/BUILD.json) compilada con fuentes estables y runner completo aprobado: 180 Rust (7 live ignorados), 52 XCTest y 194 Swift Testing. Latencia audible real pendiente; documentación finalizada después de compilar, código sin cambios posteriores.
