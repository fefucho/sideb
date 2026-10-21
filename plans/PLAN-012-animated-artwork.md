# PLAN-012 — Carátulas animadas en Fullscreen

- Fecha: 2026-10-21 (America/Montevideo).
- Estado: **implementado en core, Mac y frontend/bridge Windows; build0154 Mac Release aprobada con FIX-238; aceptación pendiente**. El usuario pide entregar la build para probar él y pospone las mediciones de rendimiento hasta el reinicio de cuota. No se declara ausencia de regresión de FPS.
- Objetivo: mostrar la animación del álbum cuando exista y coincida de forma fiable, conservando respuesta inmediata, continuidad visual y fluidez de Letras.
- Calidad acordada con el usuario: priorizar la mejor variante disponible hasta **1080×1080 y 60 fps nativos**, conservando detalle y movimiento. Esta decisión sustituye la propuesta inicial de 768/960 y 30 fps; las muestras HTTP anteriores mantienen sus valores reales.
- Alcance implementado: resolución/caché compartidas, presentación Mac y Windows, preferencia de Apariencia y limpieza de caché. La compilación/runtime nativos Windows se verifican aparte.
- Exclusiones: animaciones en listas/sidebar/Inicio, fondo animado a partir del video, cambios a Recomendados, transporte de audio, créditos o nuevas fuentes de letras.
- Origen: plan de Gemini `plan_caratulas_animadas.md`, conservado sin editar en `/Users/stefano/.gemini/antigravity/brain/017bd21c-ac05-45bf-97c6-71422e0f6b24/`. Esta propuesta cambia decisiones técnicas; no registra una implementación de aquel plan.
- Antecedentes: [PLAN-026 Letras](../apple/plans/PLAN-026-fullscreen-lyrics-performance.md), [resultados FIX-236](../apple/plans/research/LYRICS-PLAN026-RESULTS-2026-10-21.md), FIX-122/123/185/191/192/198/199/224/236 y [estudio de Octave](research/OCTAVE-2026-10-20.md).

## Opinión y cambios respecto a Gemini

La dirección visual es apropiada: imagen permanente, video superpuesto, transición breve y reproductor independiente. La condición de entrega debe ser **ausencia de regresión perceptible y medible**, sin prometer coste cero. Decodificar, mantener buffers y componer un video consume recursos incluso con aceleración por hardware.

| Tema | Conservar | Cambiar o completar |
|---|---|---|
| Presentación | Imagen actual debajo, video silencioso y gestos intactos | Revelar al tener primer frame presentable, no sólo `readyToPlay`; mismo tamaño/radio y feedback por encima |
| Descarga | Archivo reutilizable | Primera versión descarga una vez a archivo completo; no streaming AVPlayer más descarga paralela del mismo recurso; aceptar el peso de la calidad elegida |
| HLS → MP4 | Aprovechar recursos únicos cuando existan | Leer las URI reales de la playlist y su mapa; no fabricar la URL cambiando el sufijo |
| Calidad | Elegir una variante cuadrada compatible | Priorizar hasta 1080×1080 y 60 fps nativos; validar rendimiento a esa calidad y justificar cualquier alternativa con evidencia |
| Ciclo de vida | Visibilidad, pausa, flip y Reduce Motion | Añadir energía/temperatura, cancelación real, memoria y limpieza; `pause()` no demuestra cero consumo |
| Caché | Separar veredicto y video, límite 150 MiB | Diferenciar ausencia de fallo, TTL de URL distinto, LRU explícito, archivos en uso y temporales contabilizados |
| Matching | Álbum y artista antes de mostrar | No aceptar primer resultado; preservar edición y país; respuestas ambiguas mantienen imagen estática |
| Arquitectura | Resolución compartida y render nativo | Mantener red/persistencia en el servicio Rust; evitar otro descargador independiente en Swift/Svelte |
| Preferencia | Toggle en Apariencia | Apagado cancela carga y libera reproductor; cero nuevas consultas/downloads de motion; ES/EN y persistencia local |
| Validación | Tests y builds | A/B de scroll real de Letras, GPU/energía/RAM y carga fría/caliente antes de dar rendimiento por validado |

## Evidencia de la revisión inicial — anterior a implementar

Consultas públicas sin cookies ni cuenta; resultados mínimos en [evidencia JSON](research/ANIMATED-ARTWORK-2026-10-21-evidence.json). No se guardan videos, HTML completos ni URLs CDN en los documentos versionables.

1. **After Hours / The Weeknd**, Apple collection `1499378108`, respuesta con User-Agent Safari macOS: `serialized-server-data` contiene `videoArtwork.dictionary.motionDetailSquare.video`. Master de 14.996 bytes; variantes cuadradas HEVC y H.264, SDR, **30 fps**. En las variantes 768×768 hay cinco segmentos por rangos y un único recurso, compartido con `EXT-X-MAP`, con `ENDLIST` y sin etiqueta de cifrado. El HEAD del recurso devuelve `video/mp4`, rangos y **4.648.890 bytes HEVC / 5.314.135 bytes H.264**. La regla de sufijo de Gemini coincide en estas dos muestras; eso no la vuelve un contrato general. **No se descargó ni reprodujo el MP4**: MIME, rangos y estructura son evidencia HTTP, no validación de AVPlayer/WebView2 o del loop.
2. **DeBÍ TiRAR MáS FOToS**, collection `1787022393`, y **HIT ME HARD AND SOFT**, `1739659134`: sus respuestas consultadas traen `videoArtwork: null`. Billie se comprobó también con Safari. Registrar «esta respuesta no expuso motion»; no concluir disponibilidad universal ni que el User-Agent sea la causa. Sólo After Hours se consultó aquí con resultado positivo.
3. Búsqueda iTunes `Bad Bunny Debi Tirar Mas Fotos`, `entity=album`, `country=us`, `limit=5`: los cinco resultados pertenecen a **otros artistas**, incluidos covers y versiones de piano. Hay que rechazar esos candidatos; ampliar sin límite no garantiza encontrar el correcto. Un fallo de matching no debe convertirse en siete días de «el álbum no tiene video».
4. [FullscreenSceneLayout.swift](../apple/Sources/SideB/Views/Fullscreen/FullscreenSceneLayout.swift) calcula el tamaño según viewport y sidebar, con mínimo 100 pt; **no tiene el máximo fijo de 560 pt que atribuye Gemini**. [artworkFront](../apple/Sources/SideB/Views/Fullscreen/FullscreenNowPlayingView.swift) usa `CachedAsyncImage`, radio compartido y feedback de volumen; su imagen sólo aparece inmediatamente si está disponible. Conservar también el placeholder existente, sin prometer imagen nueva en 0 ms en frío.
5. Fullscreen conserva `.compositingGroup()` sobre la escena; el [backdrop](../apple/Sources/SideB/Views/Fullscreen/FullscreenBackdrop.swift) utiliza una imagen estática desenfocada y la sidebar tiene su propia composición. No hay evidencia de que un nuevo video sea gratis para esas capas ni de que requieran modificaciones. Medir su combinación sin atribuirles un cuello de botella por inspección.

Documentación primaria: Apple distingue el estado del item del [primer frame disponible en AVPlayerLayer](https://developer.apple.com/documentation/avfoundation/avplayerlayer/isreadyfordisplay). [AVPlayerLooper](https://developer.apple.com/documentation/avfoundation/avplayerlooper) administra réplicas del item: medir buffers y desmontarlas, además de pausar. [RFC 8216](https://www.rfc-editor.org/rfc/rfc8216.html), §§3.3/4.3.2.2/4.3.2.5, describe inicialización/rangos/URI; no promete una transformación de nombres `.m3u8` → `.mp4`. [iTunes Search](https://performance-partners.apple.com/search-api) documenta aproximadamente 20 solicitudes/minuto, sujeto a cambio: deduplicar, limitar y respetar `Retry-After`.

## Experiencia propuesta

1. Al entrar a Fullscreen, la carátula o placeholder actual se presenta con el comportamiento existente. No añadir spinner, cambio de tamaño ni mensajes si el enriquecimiento falla o no está disponible.
2. Después de la transición de entrada y con álbum estable, consultar motion sólo si está habilitado, visible, con música reproduciéndose y sin restricciones de movimiento/energía. Un pequeño debounce cancelable de unos 300 ms evita resolver cada pista durante saltos rápidos; no retrasa la portada estática.
3. Si el archivo validado ya está en disco, prepararlo. Si no, descargar **una sola variante**, de forma acotada y fuera de main, a un temporal. Tras completar/validar/promover, preparar el archivo local. La imagen cubre toda la espera. En una primera entrega decorativa prefiero esta espera invisible al buffering o la complejidad de un cargador progresivo propio.
4. Mantener video en opacity 0 hasta `AVPlayerLayer.isReadyForDisplay`; entonces transición de 200–250 ms sin animar geometría. Windows tendrá señal equivalente de frame presentado, por ejemplo `requestVideoFrameCallback` de una sola vez con fallback comprobado. `onplaying` por sí solo no es prueba de composición del primer frame.
5. Orden: **imagen → video recortado al mismo radio → sombreado/porcentaje/icono de play/pausa**. Video sin hit testing, foco ni controles. Mantener clic, menú contextual, volumen con rueda/trackpad y flip 3D.
6. Mismo álbum y mismo asset: conservar reproductor y posición del loop. Otro álbum: retirar de inmediato el video anterior y mostrar la nueva imagen/placeholder, invalidar su petición y comenzar la nueva sólo si sigue siendo elegible. Nunca dejar un video del álbum anterior sobre la portada nueva.
7. Pausa musical: congelar el frame actual sin reiniciar el bucle; en frío y pausado, dejar imagen sin iniciar descarga. Al volver de Info, retomar si corresponde. Error del player: volver a imagen, liberar el player y aplicar backoff; no repetir intentos en cada evaluación de `body`.
8. Fondo, paleta, sidebar, barra, miniaturas y Now Playing del sistema continúan usando su imagen existente. No extraer colores ni fotogramas del video durante reproducción.

## Servicio compartido: identidad, resolución y archivo

La implementación propuesta afecta a ambos consumidores. Debe concretar contrato/pruebas Mac y Windows conforme a [Core AGENTS](../core/AGENTS.md), respetando el core protegido. La implementación aditiva y sus consumidores se describen en el reporte de ejecución. Los bindings se regeneran mediante el flujo oficial.

- Proponer un módulo aditivo `animated_artwork` que coordine proveedor, metadatos y descarga/caché limitada; no insertar motion en el camino crítico de resolución de audio, colas, `/player` o carga de Letras. No agregar búsqueda de motion a cada `SongItemRecord` de una lista.
- El shell pide preparar el asset del álbum actual; recibe un record tipado con identificador estable, ruta local validada, dimensiones y códec. La UI no necesita recibir URLs CDN. Separar resultados `ready`, `confirmedAbsent`, `unresolved` y fallo temporal/cancelación. Nombres definitivos se fijan al implementar ambos consumidores.
- Clave de solicitud versionada con país/storefront, identidad de álbum YTM cuando exista y metadata normalizada. El ID YTM **no es** un collection ID Apple. Persistir alias a Apple sólo tras match fiable. Sin álbum, usar identidad de pista; no unir todas las canciones de un artista bajo un álbum vacío.
- Normalizar Unicode/espacios/case y tolerar puntuación de forma conservadora. Preservar información de edición, remix, live, deluxe, anniversary, remaster y explicit/clean cuando esté disponible. No eliminar esos calificadores para mejorar artificialmente la tasa de acierto.
- Búsqueda inicial por artista/álbum; si no hay candidato fiable, como máximo una búsqueda alternativa de canción con título/artista/versiones/duración conocida. Duración ±4 s es un filtro adicional, no una prueba de identidad. Una duración ausente no debe convertirse en cero. No aumentar consultas hasta que aparezca algo; ante ambigüedad conservar imagen.
- Consultar la página del **álbum identificado** y extraer el objeto de su entidad, sin regex global que pueda capturar videos de recomendaciones/editoriales. Parser con esquema reconocible y fixtures; formato inesperado, bloqueo HTTP o JSON inválido son fallo temporal/unsupported, no ausencia confirmada. Un `null` válido sólo describe aquella entidad/storefront/respuesta durante su TTL.
- Concurrencia máxima: una preparación de álbum activa, con deduplicación por clave. Compartir solicitudes del mismo álbum y liberar al último consumidor. Hacer efectiva la cancelación de HTTP/lectura/escritura al cambiar álbum, cerrar, apagar o cambiar sesión; descartar un resultado tardío no detiene por sí solo el trabajo. Comprobar propagación real de cancelación UniFFI/Tauri.
- Cola de baja prioridad, consultas de búsqueda espaciadas y límite global por debajo del publicado; backoff para 429/5xx. Propuesta inicial: hasta 10 s de resolución total, HTML ≤6 MiB, JSON búsqueda ≤1 MiB y playlist ≤128 KiB. Ajustar con muestras; timeout/cap deja imagen sin error visual.
- Resolver URI relativa contra URL final tras redirects. Para MP4 directo exigir VOD terminado, video cuadrado, sin cifrado, recurso único para inicialización y segmentos y archivo reproducible completo. Un `Content-Type` correcto no basta. Esquema HTTPS y hosts CDN previstos, también en redirects. Si no cumple, mantener portada estática en la primera versión; no incorporar remux, HLS remoto ni proxy como fallback improvisado.

### Selección y presupuestos iniciales

Son límites de diseño a validar, no rendimiento certificado:

| Recurso | Propuesta inicial |
|---|---|
| Reproductores | Uno lógico de motion visible; nunca crear uno por candidato/variante ni precargar otro álbum |
| Video | Cuadrado SDR, hasta 60 fps nativos; conservar 60 cuando exista esa variante. Si la fuente sólo ofrece 24/25/30, conservar su frecuencia sin interpolación |
| Resolución | Mejor variante disponible hasta 1080×1080; 1080×1080/60 si existe y es compatible. Si falta, elegir la mejor variante inferior ofrecida por la fuente, sin reescalar ni transcodificar para inventar calidad |
| Tamaño/duración | Implementado: máximo128 MiB por archivo y60 s; límite de bytes también sin Content-Length. La muestra real1080/30 pesa20.794.505 bytes.60 fps aún sin muestra real verificada |
| Códec | HEVC en Mac con validación real del perfil; H.264 como alternativa. Windows H.264 y comprobación nativa de soporte; ninguno garantiza aceleración en toda GPU |
| Fallback de calidad | No reducir por defecto para ahorrar CPU/red. Otra variante sólo si falta la preferida, resulta incompatible o falla su reproducción/rendimiento de forma comprobada; a lo sumo una alternativa, sin descargar ambas preventivamente ni cambiar resolución al mover sidebar |
| Red | Una descarga efectiva, sin prefetch de feed/siguiente álbum. Plazo de red90 s, inactividad15 s; resolución10 s. Las operaciones de disco iniciadas se esperan antes de limpiar/cancelar. La imagen cubre la espera; no se cambia el transporte de audio |
| Disco | 150 MiB de presupuesto inicial de bytes de archivos propios, incluidos temporales y reservas; separado de ImageCache. Mayor calidad reduce la cantidad de álbumes retenidos, sin bajar calidad para guardar más; revisar capacidad/reserva con las muestras |
| UI | Cero actualizaciones SwiftUI/Svelte por frame de motion; sólo cambios de fase/identidad/elegibilidad |

No imponer 8-bit como requisito universal a HEVC: la muestra anuncia `hvc1.2...` SDR. Perfil/bit depth y coste real deben comprobarse; etiqueta HEVC sola no valida hardware. Seleccionar por calidad visual, dimensiones y frecuencia, considerando bitrate/perfil dentro de cada códec; menor peso no demuestra igual detalle. El primer prototipo y el A/B deben usar la calidad objetivo 1080/60 cuando haya una muestra disponible. La muestra After Hours comprobada aquí ofrece 30 fps: todavía no hay una variante de 60 fps verificada en esta investigación.

## Caché acotada y errores recuperables

- Separar **identidad/veredicto**, **localizador de proveedor** y **archivo validado**. Una URL puede caducar antes que el veredicto y un archivo local válido puede sobrevivir a su URL. No borrar el MP4 útil sólo por vencer la metadata.
- TTL inicial: presencia hasta 30 días; ausencia válida hasta 7 días, con contexto de parser/storefront. `unresolved`, falta de metadata, timeout, 403/429/5xx o cambio de esquema tienen backoff corto y **no escriben ausencia por siete días**. No refrescar metadata desde el hilo UI.
- Si URL responde 403/404, permitir una renovación controlada del localizador en la petición elegible. No convertir error de URL en inexistencia del álbum ni crear ciclos de refresh.
- Índice LRU con tamaño, último uso, identidad/variante y validación. No depender de `atime` del filesystem. Clave de archivo incluye asset/códec/resolución, no sólo collection ID; evitar que Windows y Mac reutilicen una variante equivocada.
- Reservar presupuesto antes de descargar; podar archivos no usados, comprobar bytes reales, escribir `.part` y renombrar de forma atómica al validar. Limpiar temporales huérfanos al iniciar el servicio. Si falta espacio o no se puede reservar, conservar imagen sin descargar.
- Mantener lease de archivo activo. No borrar un MP4 utilizado por AVPlayer o WebView2; Windows puede bloquearlo. Para vaciar, invalidar tareas, desmontar player/looper, soltar lease y limpiar; impedir que una descarga anterior repueble la caché después del clear.
- Core gestiona archivos/red en ejecutores apropiados, con root de caché proporcionado por cada shell; SQLite/recorridos/hash/parseo de archivos fuera de main. Mantener locks cortos y sin esperar red bajo mutex. Revisión de tamaño al escribir, no recorrer la carpeta desde `body`, cada cambio de settings o cada vuelta del video.
- Cálculo de MB de Settings a demanda y con resultado memoizado; botón ocupado durante limpieza. En esta primera versión «Vaciar caché de carátulas animadas» elimina videos/temporales y conserva veredictos útiles. Puede volver a descargar al reabrir o cambiar de álbum; no relanzar inmediatamente durante el mismo clear. No mezclar esta acción con borrar audio, letras o toda ImageCache.

## Render y ciclo de vida

**Mac:** vista hija real con estado local, `NSViewRepresentable` mínima, `AVPlayerLayer` y `AVQueuePlayer`/`AVPlayerLooper`. Configurar muted, sin controles/Now Playing/sesión de audio/PiP y sin impedir reposo. Cargar propiedades de AVAsset de forma asíncrona; mutar AppKit en main. `updateNSView` idempotente: no crear player/items por cada layout, hover, tick de audio o resize. Retener el looper explícitamente y retirar observers/réplicas/items/layer al desmontar. Sin `TimelineView`, display link propio, observer periódico ni `@State` de tiempo de video.

**Windows:** controller y componente aislados, `<video muted loop playsinline>` de archivo local mediante mecanismo Tauri ya autorizado para la carpeta de caché, con CSP/scope mínimo. Crear `src` sólo al ser elegible; `preload=auto` no debe montar descargas ocultas. No usar el libmpv de audio ni actualizar stores en `timeupdate`. Al liberar: pausar, retirar `src`, llamar `load()` y limpiar callbacks/URL/lease. Verificar primer frame, loop y visibilidad/occlusión realmente disponibles en WebView2; `document.hidden` no demuestra por sí solo estar totalmente tapado por otra ventana.

| Condición | Resolución/descarga | Player y presentación |
|---|---|---|
| Habilitado, visible, frente, reproduciendo | Preparar una vez tras estabilizar entrada/álbum | Reproducir y revelar sólo al primer frame |
| Pausa musical | No empezar carga fría; cancelar preparación que pierda elegibilidad | Pausar conservando frame ya visible; liberar si pausa larga/presión de memoria |
| Info/flip | Detener preparación que ya no tenga consumidor visible | Pausar inmediatamente, retomar al volver sin reiniciar álbum |
| Minimizada/oculta/app oculta | Cancelar preparación en curso | Pausar; desmontar tras inactividad o presión de memoria; no presentar hasta visible |
| Salida Fullscreen o cambio de cuenta | Cancelar e invalidar callbacks | Liberar player, observers, items y lease; caché pública puede persistir |
| Toggle apagado | Cancelar sin nuevas consultas/descargas | Mostrar imagen y liberar todos los recursos de video |
| Reduce Motion, ahorro de energía, thermal serio/crítico | No preparar video | Mostrar estática y liberar; recuperar sólo cuando vuelva a ser elegible |
| Error o asset inválido | Backoff acotado; sin bucle de reintentos | Imagen existente, sin aviso intrusivo |

Usar identidad de álbum/asset para reutilizar y revisión de petición + sesión para invalidar. No tomar `videoId` solo como identidad universal ni reiniciar al cambiar de pista del mismo disco. Fuente autoritativa de play/pausa: estado real del reproductor de música, no un booleano local invertido al hacer clic.

Observar cambios de ventana, política energética, movimiento y memoria; evitar polling. Reutilizar el patrón de visibilidad de `ExperimentalLyricsWindowVisibility` sin acoplar el reloj de Letras al video. La política propuesta de pausa prolongada puede comenzar en 30 s y se ajusta midiendo RAM/tiempo de reanudación; el timer es único y cancelable, nunca periódico por frame.

## Configuración

- Apariencia: **«Carátulas animadas en pantalla completa»**, con texto breve «Cuando estén disponibles». Propuesta de producto: activado por defecto al superar aceptación; respetar Reduce Motion/energía y conservar preferencia del usuario aunque una restricción temporal suspenda animación.
- Persistencia de instalación, independiente de recomendaciones y cuenta: ampliar patrón `HomeAppearance.preferences` en Mac y `appearance/preferences.ts` en Windows, preservando valores existentes, defaults y entornos de tests/HomeLab. Sin migración destructiva de Apariencia.
- Apagado significa no cargar motion; no basta poner opacity 0. Rehabilitado sólo solicita si Fullscreen está visible y elegible. No descargar al abrir Settings.
- ES/EN, teclado/foco y accesibilidad de toggle/botón. No mostrar nombres de códecs o detalles de caché en el flujo principal; tamaño de caché sólo junto al botón de vaciar.

## Implementación y comprobaciones de cierre

### Etapa 0 — Viabilidad y baseline

- [x] Revisar plan, código de artwork/layout/settings y antecedentes de Letras/composición.
- [x] Verificar un positivo real, manifiestos y HEAD del recurso; comprobar casos sin motion expuesto y fallo de matching. Alcance exacto arriba y en JSON.
- [ ] Ampliar muestras de parser: varias ediciones/storefronts, ausencia reconocida, bloqueo/schema desconocido y URI única frente a multiarchivo. Guardar fixtures mínimas sanitizadas.
- [ ] Descargar mediante servicio/probe acotado y comprobar duración/tracks/códec/perfil, primer frame y loop del MP4 en AVPlayer; Windows tiene prueba independiente. No dar esto por probado por HEAD.
- [ ] Incorporar muestras 1080×1080 y buscar una fuente de 60 fps reales; comprobar disponibilidad, bitrate, tamaño y compatibilidad sin asumir que todos los álbumes las ofrecen. Fijar límites de archivo, reserva de caché y timeouts que contemplen la calidad acordada.
- [ ] Baseline de build vigente **con motion apagado**, Letras cargadas y mismo álbum/documento/viewport/refresh rate/cache; medir scroll continuo y reposo en pausa/reproducción. No reutilizar la baseline0147 como control del nuevo video: hay cambios posteriores de Letras.

### Etapa 1 — Servicio y caché compartidos

- [x] Fijar contrato y consumidores; matching conservador, DTOs tipados, límites y cancelación hasta HTTP/archivo. `Option<Asset>` público distingue disponible/None; errores recuperables permanecen errores internos, sin persistir ausencia falsa.
- [x] Implementar metadata y LRU con leases/reservas/temporales/clear; limpiar sólo archivos propios. Audio y letras desacoplados.
- [ ] Pruebas con servidor/fixtures: matching, Unicode/ediciones/álbum ausente, `null` vs esquema inesperado, negative TTL vs error, URL expirada, cifrado/multiarchivo/URI relativa/redirect, duración/tamaño/fps, cancelación y varias solicitudes del mismo álbum.
- [ ] Pruebas de caché: límite incluyendo `.part`, cortes de descarga, disco lleno, archivo activo, clear mientras descarga y regreso al mismo álbum. No tests que sólo reflejen detalles de implementación.

### Etapa 2 — Mac y preferencia

- [x] Construir child view/controller y primer-frame/crossfade; integrar entre imagen y overlays sin alterar gestos/flip ni geometría.
- [ ] Conectar elegibilidad y setting; comprobar same-album reuse, cambios rápidos A→B→A, callback tardío, paused-in-cold, salir/volver, flip, minimize/occlusion, Reduce Motion/LPM/thermal y memoria.
- [x] Revisar observación: motion no publica tiempo/frames a SwiftUI/Svelte. El coste de composición y la frecuencia real de invalidación se medirán después; no se modifica composición sin evidencia.
- [ ] Ejecutar regresiones de Letras: voces simultáneas, Unicode, scroll manual/seguimiento/Volver, seek FIX-233/234 y audio. Mantener Recomendados fuera de cambios.

### Etapa 3 — Aceptación de rendimiento y visual

- [ ] A/B **en la misma build**, opción off/on y mismo asset local/cache caliente, priorizando 1080/60 cuando exista: reposo, scroll continuo de Letras pausado y reproduciendo, resize y sidebar abierta/cerrada. Tres repeticiones alternando orden; CPU/GPU, frames/hitches, P95/P99, energía y RAM. Medir también carga fría por separado. Si sólo se consigue fuente 30 fps, declarar sin validar el caso 60 fps.
- [ ] Misma Mac/ventana/escala/pantalla/tasa de refresco/documento/procedimiento. Distinguir video30/60fps de fluidez de interfaz60/120Hz; medir 120 sólo si la pantalla lo permite. Separar tiempo de descarga, preparación y crossfade de FPS estable.
- [ ] Meta: sin regresión de scroll reproducible fuera del ruido de la medición ni nuevos hitches visibles al revelar/loop. Disparadores iniciales para investigar, no resultados: +1 ms en P95 o +2 ms en P99 de duración de frame, crecimiento de hitches >50 ms o caída sostenida de FPS. Exigir trazas de frames válidas, no calcularlos desde CPU muestreada.
- [ ] Medir coste incremental de CPU/GPU/energía mientras se anima; no exigir cero matemático. Al ocultar/apagar, comprobar que desaparezca actividad propia y no siga red. Tras 20 ciclos de abrir/cerrar/cambiar, buffers/items/observadores y RAM deben estabilizarse, sin crecimiento acumulativo.
- [ ] Si hay regresión: perfilar y corregir primero carga, decodificación, buffers, observación y composición de artwork, conservando la calidad objetivo. Evaluar una variante inferior sólo ante limitación comprobada y documentar el motivo; no dar una mejora por validada reduciendo calidad silenciosamente. No ocultar problema convirtiendo Letras a menor frecuencia ni congelando el video cada vez que se hace scroll. No activar por defecto mientras falle aceptación.
- [ ] Inspección visual: imagen y video del álbum correcto, sin flash negro/cambio de layout/corte perceptible en loop, overlays y acciones intactos, transición legible sobre fondos claros/oscuros, reproducción musical ininterrumpida. Red lenta/fallo/no video deben verse como portada normal.

### Etapa 4 — Windows y entrega

- [x] Implementar DTO/Tauri/controller/componente/preferencia con el mismo contrato y caché, adaptando paths/primer frame a Windows. Frontend verificado con componente montado y bridge simulado; runtime nativo pendiente.
- [ ] Verificar H.264, aceleración real, loop, WebView2, file scope/CSP, suspensión y limpieza en Windows; `pnpm` en Mac no certifica esos puntos.
- [ ] Revisar diff completo; suites pertinentes Mac/core/bridge y frontend/runtime Windows según ámbito; regenerar bindings por flujo oficial. Build numerada mediante skills de plataforma cuando haya implementación.
- [x] Registrar FIX-237 y PAR-039 con pruebas/limitaciones reales, actualizar plan y reporte, entregar build0153. A/B pendiente por pedido del usuario; paridad nativa no cerrada.

## Estado de ejecución — 2026-10-21

- Build0153 Release aprobada:946 pruebas ejecutadas/16 omitidas, fuentes estables, firma y diez hashes verificados; [paquete](../builds/macos/build-0153/Side%20B.app).
- Implementación y revisión con subagentes Luna y GPT-6.1 Sol medio; el integrador revisó código y corrigió también fallos de integración reales del proveedor. [FIX-237](../FIXES.md#fix-237), [PAR-039](../PARIDAD.md#animated-artwork-handoff) y [reporte de ejecución](research/ANIMATED-ARTWORK-2026-10-21-results.md).
- Core aditivo: búsqueda conservadora de álbum y una alternativa de canción, parser de la entidad exacta, HLS de recurso único sin cifrado, variantes hasta1080/60, caché150 MiB con LRU/leases/temporales y cancelación real. Ausencia reconocida7 días, presencia30 días; errores/ambigüedad no son ausencia. La UI recibe archivo local y metadata, sin URLs CDN.
- Mac: AVPlayerLayer + AVQueuePlayer/Looper aislados, primera imagen disponible bajo el video, fade225 ms al primer frame, pausa/reutilización por álbum, retiro al apagar/salir/cambiar sesión. Reduce Motion, ahorro de energía, thermal serio/crítico, ocultamiento y presión de memoria; liberación por inactividad30 s. Un único fallback H.264 ante fallo de reproducción HEVC. Sin observador periódico ni actualizaciones SwiftUI por frame de motion.
- Windows: video local H.264, callback único de primer frame, controller con generaciones y barrera de desmontaje/cancelación, cambio de sesión y limpieza coordinada. Scope de archivos limitado a la carpeta de motion. Suspende por foco/document.hidden y Reduce Motion; **energía/thermal/presión de memoria y oclusión completa de WebView2 requieren implementación/validación nativa**. No se igualan por afirmación a las políticas Mac.
- Apariencia ES/EN en ambas apps: toggle activado por defecto en esta build local de prueba y botón de vaciar videos/temporales. Conserva veredictos. Apagado libera y evita nuevas consultas de motion; Settings no prepara videos. No hubo cambios de Recomendados, sidebar, backdrop, transporte de audio ni renderer de Letras por este plan.
- Probe real del servicio completado: After Hours/The Weeknd → MP4 local1080×1080 HEVC30 fps,20.794.505 bytes,20 s, un track de video. AVFoundation lo declara reproducible y este Mac informa soporte hardware HEVC. **No demuestra frame presentado, loop, uso efectivo del decoder hardware ni FPS de la interfaz.**
- Las casillas de aceptación amplias permanecen pendientes cuando incluyen pruebas nativas, escenarios de fallo o métricas aún no ejecutadas; no confundir código presente con matriz funcional/rendimiento completa. Muestra60 fps real pendiente.
- **Pedido posterior del usuario:** no ejecutar más comprobaciones de rendimiento ahora; terminar y compilar para que pruebe él. A/B de la misma build off/on, carga fría/caliente, FPS/hitches/CPU/GPU/RAM y ciclos repetidos quedan aplazados al reinicio de cuota. Los pilotos de CPU previos carecen de escena verificable y no se usan como baseline comparable. No activar una reducción silenciosa de calidad ni afirmar coste cero.

### Reapertura de cobertura — Graduation/Octave

- [x] Corregir ausencia inferida desde una única edición: search entregaGraduation clean1442845779 (`videoArtwork:null`), pero otra versión explícita oficial1451901307 tiene motion. Octave devuelve exactamente ese manifiesto Apple. Comprobar sólo alternativas oficiales del mismo álbum con matching conservador y límite de solicitudes; no tomar editorial/recomendados ni reducir calidad. Invalidar negativos antiguos sin borrar videos válidos.
- [x] Fixtures/regresión de clean-null→otra versión con motion, otra portada/edición/título/artista, loops/cap/schema/fallo; revisar ambos consumidores, registrar fix nuevo y build oficial al implementar. [Evidencia](research/ANIMATED-ARTWORK-OCTAVE-GRADUATION-2026-10-21.json). FIX-238 implementado: un salto/hasta3 versiones compatibles, vínculo recíproco y negativos privadosv2, conservando MP4/positivos. Probe real Graduation1080/30 aprobado;0153 sigue siendo la build anterior, build0154 aprobada,956 pruebas ejecutadas/17 omitidas, firma/diez hashes y fuentes estables.

FIX-238 entregado en0154:40 focales y171 bridge aprobadas, Graduation real1080/30 validado. [Detalle de entrega](research/ANIMATED-ARTWORK-2026-10-21-results.md#entrega-corregida0154). Rendimiento y Windows nativo siguen pendientes. La primera carga completa del video puede demorar; este fix corrige cobertura por ediciones y caché negativa.

Tras completar0154 se redactaron [PLAN-013: indicadores de versión](PLAN-013-explicit-content-indicators.md) y [PLAN-014: preferencia de versiones de audio](PLAN-014-content-version-preference.md), ambos propuestos y sin implementar. Usar video de otra edición compatible sólo enriquece el arte; no aplica una preferencia a la música ni prueba que el audio sea explícito.

## Reanudación de rendimiento —15:01 del21/10

Se intentó retomar sobre0155, que incluye FIX-239 de Letras. Computer Use confirmó **Mac bloqueado**, por lo que no se inició un perfil de escena no verificable. Se pidió desbloqueo manual; A/B/FPS/GPU/RAM siguen pendientes. Binario y assets locales comprobados, sin cambiar preferencias. [Protocolo y estado del intento](research/ANIMATED-ARTWORK-PERFORMANCE-2026-10-21.md). El ROI pausado debe ser menor que los30s de liberación por inactividad para no mezclar estados del player.

### Cierre del seguimiento instrumental por pedido del usuario

El usuario cancela expresamente las mediciones A/B: «no vamos a hacer el test ya comprobé que funcionó». Se registra su confirmación funcional; no se retoma la prueba ni se pide desbloqueo. No hubo métricas instrumentales nuevas. La automatización queda desactivada. La cobertura/validación nativa Windows conserva sus límites; no se infieren FPS medidos a partir de la comprobación funcional.
