# PLAN-012 — Ejecución de carátulas animadas

Fecha:2026-10-21, America/Montevideo. [Plan](../PLAN-012-animated-artwork.md), [FIX-237](../../FIXES.md#fix-237), [PAR-039](../../PARIDAD.md#animated-artwork-handoff).

## Entrega y validación

Implementación aditiva en Rust, Mac y Windows. Revisión con subagentes Luna para proveedor/Windows y GPT-6.1 Sol medio para motor/render Mac/revisión Windows; el integrador revisa todos los cambios. **Build final0153 Release compilada**, fuentes estables durante todo el flujo (`sourceChangedDuringBuild:false`), firma ad hoc y diez hashes revalidados. [App](../../builds/macos/build-0153/Side%20B.app), [BUILD.json](../../builds/macos/build-0153/BUILD.json). Build0151 queda fallida por una expectativa de orden entre consumidores de un diccionario en el test de clear; se corrigió para exigir que todos se liberen antes de borrar, sin exigir orden entre ventanas. Build0152 Release compilada, fuentes estables y diez hashes registrados, antes de los últimos ajustes de cancelación/ambigüedad/backoff descritos abajo. 0153 incluye las correcciones finales.

- Oficial0153: **946 ejecutadas aprobadas/16 omitidas**:97 InnerTube +159 core +239 XCTest +451 Swift Testing ejecutadas (458 declaradas,7 omitidas;9 omitidas Rust). XCFramework/bindings y791 clavesES/EN regenerados/verificados mediante skill oficial; arm64, versión pública1.2.6/build19 conservada.
- Core final:30 pruebas de motion aprobadas/1live omitida; suite `windows-bridge --lib`:161 aprobadas/9 omitidas. Incluye barreras deterministas de clear tras open/rename, cierre HTTP y backoff global.
- Core antes de revisión final:26 pruebas de motion aprobadas; probe live optativo separado aprobado. Suite oficial0152:97 InnerTube +155 core aprobadas,9 Rust omitidas.
- Mac oficial0152:239 XCTest aprobadas y458 casos Swift Testing declarados,7 omitidos (451 ejecutados);16 pruebas nuevas de motion. Total oficial0152:942 ejecutadas aprobadas y16 omitidas.
- Windows frontend: `pnpm check`0 errores/0 avisos,412 pruebas aprobadas y1 omitida; `pnpm build` aprobado con aviso de tamaño de chunk existente. Pruebas montan el componente Svelte real con bridge simulado y cubren cancelación, cambios A→B, misma identidad de álbum, sesión, primer frame, cold-pause y limpieza.
- Windows nativo/Tauri/WebView2/H.264 efectivo y aceleración **no ejecutados en este Mac**. No hay paquete Windows nuevo ni publicación.

## Comportamiento implementado

- Resolución Apple pública sólo para la portada actual elegible. Matching conservador Unicode/artista/álbum/edición; si falta álbum, una búsqueda alternativa de canción con duración ±4 s cuando se conoce. Ambigüedad mantiene imagen. Sin consultas por tarjetas/listas/sidebar.
- Parser de `serialized-server-data` para la entidad exacta, incluyendo el identificador real `album-detail-header - 1499378108`. Se corrigieron un descarte accidental de resultados de álbum sin `trackName`, el host real `mvod.itunes.apple.com` y la resolución de URI contra la URL final tras redirect.
- Manifiestos VOD cuadrados SDR sin cifrado y de recurso único; no fabricar rutas cambiando sufijos ni remux/transcodificación. Mejor variante hasta1080×1080/60 fps nativos. Mac prefiere HEVC y puede reintentar una sola vez H.264 por fallo de reproducción; Windows exige H.264. No limitar a768/30 por defecto.
- Descarga única a archivo local con límite128 MiB/60 s,90 s de red e inactividad15 s. La imagen existente cubre la espera. No reproducción remota y descarga paralelas. La frecuencia del video no publica cambios de estado al árbol de Letras.
- Servicio global lazy, una preparación activa, deduplicación/consumidores con UUID, leases, cache LRU150 MiB con2 MiB de margen para índice y temporales, índice acotado1 MiB/512 veredictos. Presencia30 días y ausencia válida7 días; error/matching dudoso no son ausencia. Diez búsquedas/minuto y backoff recuperable.
- Cancelación de HTTP y limpieza ordenada. Revisión final corrige la carrera de cancelación durante filesystem: no dropear operaciones `tokio::fs` ya iniciadas; esperar su finalización y cleanup antes de liberar el gate al clear. Respeta Retry-After también entre álbumes y rechaza múltiples collection IDs compatibles.
- Mac: child view + AVPlayerLayer/AVQueuePlayer/Looper silencioso, validación AVAsset asíncrona y fade225 ms al primer frame disponible, sin ticks propios por frame. Reutiliza mismo álbum, pausa al pausar/flip/ocultar, libera por30 s de inactividad o presión, reduce motion/energía/thermal serio. Retira recursos al salir/apagar/cambiar sesión. Gestos y overlays existentes por encima del video.
- Windows: componente local aislado, primer frame con requestVideoFrameCallback único o fallbackRAF, watchdog8 s, desmontaje de src/load antes de liberar lease y clear coordinado. Cancel llega al core original incluso tras cambio de sesión; UUID cancelado antes de registrar el comando deja tombstone. Pausa por foco/document.hidden/reduce motion. Energía/thermal/memoria/oclusión completa requieren trabajo nativo adicional.
- Setting Apariencia ES/EN activado por defecto en la build local de prueba. Apagar libera y evita nuevas cargas de motion. Vaciar elimina sólo videos/temporales de motion y conserva veredictos; no recarga inmediatamente ese mismo álbum durante clear. Tamaño consultado a demanda, sin polling. No se altera audio, renderer de Letras, Recomendados, sidebar ni fondo.

## Evidencia real del recurso

Probe público del servicio en After Hours/The Weeknd completado en15,67 s: archivo20794505 bytes,1080×1080, HEVC/hvc1,30 fps. AVFoundation confirma playable=true,20 s y un track de video; VideoToolbox informa soporte HEVC hardware en este M1 Pro16 GB/macOS27.0/Xcode27.1. Esto **no acredita uso efectivo del decoder hardware, primer frame de la app, loop, suavidad ni FPS de UI**. No se verificó una fuente real60 fps.

Artefactos diagnósticos locales ignorados en `.cache/plan012-execution-2026-10-21/`: live-core-probe.log, native-asset-validation.json, logs de suites/build y probes. No incluir videos, URLs CDN ni datos de cuenta en documentos versionables.

## Rendimiento pospuesto por el usuario

El usuario pidió detener comprobaciones de rendimiento y entregar la app para probarla él, por cuota. No se ejecutan más perfiles ahora. Los pilotos anteriores de CPU0150 no tienen escena/ROI verificables y **se excluyen como baseline**, sin cifras comparativas presentables. No hay comparación A/B válida ni FPS/hitches/P95/P99 de esta función. Compilar/pasar tests no valida rendimiento.

Retomar tras reinicio de cuota (15:01 del21/10): misma build, álbum/documento de Letras, viewport3024×1898/sidebar y caché, toggle off/on alternado tres veces, pausa y reproducción. Capturar CPU/main/GPU/RAM, carga fría/caliente y frames/hitches reales si las herramientas los ofrecen. No usar video30fps, display-link o CPU muestreada como FPS de interfaz. Verificar visualmente revelado/loop,20 ciclos de salida/cambio, suspensión efectiva, voces simultáneas, Unicode y seek/seguimiento/manual/Volver FIX-233/234. El usuario prueba el paquete final; no se declara esta matriz completada.

Cierre documental posterior al empaquetado0153; sin nuevas modificaciones de código compilado, sin abrir/reemplazar la app en uso, sin push ni publicación. El diff de fuentes manuales no presenta errores de whitespace; los bindings autogenerados conservan el formato de UniFFI.

## Seguimiento del usuario — carga inicial

Tras probar0153, el usuario primero reporta que no aparece y luego confirma que After Hours finalmente cargó, con espera excesiva percibida. Repetir el probe del core actual en caché nueva también completa1080HEVC30/20.794.505bytes; no se reprodujo un fallo de matching de After Hours. La primera versión prepara el archivo completo antes de revelar: el fade evita un flash pero no reduce la latencia de búsqueda/descarga. Falta medir esas etapas y evaluar una carga inicial más rápida después del reinicio; no se hicieron perfiles de FPS ni cambios de código durante este seguimiento. El registro negativo de otro álbum no se atribuye a After Hours sin identidad verificable.

## Octave y Graduation — defecto de cobertura confirmado

Por pedido del usuario se consultó [motion de Octave](https://api.octavestreaming.com/api/apple/motion?key=kanyewest~graduation): `hasMotion:true`, relay propio y manifiesto original `mvod.itunes.apple.com`. La URL cuadrada original es **idéntica** a la del header Apple de [Graduation1451901307](https://music.apple.com/us/album/graduation/1451901307), edición explícita. No se deduce cómo funciona el backend privado de Octave; la procedencia de este recurso sí se verificó por igualdad exacta.

Nuestro search devuelve1442845779, edición limpia, tanto con `explicit=Yes` como `explicit=No`. Su header declara `videoArtwork:null`; el proveedor0153 conserva esa ausencia7 días bajo la petición de álbum, aunque su sección oficial `other-versions` enlaza1451901307, que sí expone motionSquare. La ausencia de una edición no equivale a ausencia del álbum en todas sus ediciones. Evidencia mínima sin URLs CDN en [JSON](ANIMATED-ARTWORK-OCTAVE-GRADUATION-2026-10-21.json).

Corrección pendiente: explorar de forma acotada sólo otras versiones oficialmente enlazadas del álbum identificado, contrastando título/artista/edición/portada; no buscar en recomendaciones ni tomar cualquier video. No persistir ausencia amplia antes de resolver esas alternativas; invalidar de forma versionada los negativos creados con el criterio anterior, conservando MP4 válidos. No requiere depender de Octave. **No implementado en0153**; sin nuevo paquete, cambios de producción ni perfiles de rendimiento en esta investigación.

## FIX-238 — Implementación tras la investigación

El usuario pide corregir cobertura y compilar antes de elaborar los planes de versiones explícitas. El proveedor ahora revisa hasta tres alternativas compatibles en un único salto desde `other-versions`, con título que conserva calificadores, artista/número de pistas y vínculo recíproco. Descarta versiones distintas; errores, esquema desconocido o alternativas que exceden el límite no generan ausencia amplia. Mismo DTO público y mismas claves/archivos; `negative_schema:2` privado invalida sólo negativos antiguos. No cambia el audio ni selecciona otra edición musical.

40 pruebas focales aprobadas y2 live omitidas, incluyendo independencia del motion propio respecto de secciones relacionadas desconocidas. Probe real optativo: Graduation/KanyeWest/FlashingLights,237s → búsqueda clean1442845779 → explícita oficial1451901307 → HEVC1080×1080/30fps,13.479.725 bytes. No implica cobertura universal ni valida FPS de interfaz. AVAsset confirma15s/reproducible/un trackvideo1080/30/sin audio. Bridge171 aprobadas/10 omitidas; build oficial en preparación. La build0153 no contiene este fix; el paquete corregido se registra al terminar.

### Entrega corregida0154

Build0154 Release oficial completada:956 pruebas ejecutadas aprobadas y17 omitidas (97InnerTube+169core+239XCTest+451SwiftTesting ejecutadas;10Rust/7Swift optativas), fuentes estables durante compilación, firma y diez hashes revalidados. [App](../../builds/macos/build-0154/Side%20B.app), [BUILD.json](../../builds/macos/build-0154/BUILD.json). Focal final40 aprobadas/2live omitidas y bridge171 aprobadas/10 omitidas; no se repitió frontend sin cambios de contrato/UI. La prueba real de Graduation y el análisis AVAsset validan resolución/archivo; el usuario prueba presentación/loop en la app. Sin medición FPS ni paquete Windows nativo. FIX-238 no reduce calidad ni cambia edición de audio.

El ajuste final también permite motion propio cuando una sección no necesaria de otras versiones cambia de esquema: un error allí sólo impide persistir ausencia, nunca borra un positivo disponible. Se revisaron diferencias Deluxe/live/remaster, fallback tras error de una alternativa, límite de tres compatibles, ciclos/vínculos recíprocos y conservación de positivos/archivos con índice legacy. Cierre documental posterior al paquete.

Seguimiento tras reinicio15:01: intento A/B sobre0155 bloqueado por pantalla del Mac bloqueada. Sin perfiles iniciados ni métricas nuevas; [estado y protocolo](ANIMATED-ARTWORK-PERFORMANCE-2026-10-21.md). Desbloqueo solicitado al usuario.

Decisión posterior del usuario: cancela el test porque ya comprobó que funciona. Confirmación funcional registrada y automatización desactivada; no se volverá a pedir desbloqueo ni ejecutar ese A/B salvo un nuevo pedido.
