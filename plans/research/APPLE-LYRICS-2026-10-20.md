# Letras detalladas de Apple, TTML original y Octave

Fecha: 2026-10-20, America/Montevideo. Investigación posterior a la primera entrega experimental de [PLAN-025](../../apple/plans/PLAN-025-word-synced-lyrics.md), FIX-228/229 y build0141. Pedido: buscar recursos de GitHub para letras de Apple con karaoke más detallado y evaluar Octave como alternativa.

Estado: investigación y propuesta; no se implementa otro proveedor ni se modifica la app en esta etapa. [Evidencia resumida](APPLE-LYRICS-2026-10-20-evidence.json), sin letras completas ni credenciales. Las respuestas completas y fuentes inspeccionadas están fuera de Git en `/tmp/sideb-apple-lyrics-research/`.

## Hallazgo principal

El modo experimental ya consume TTML con segmentos por palabra/sílaba mediante Boidu. Conviene conservar ese documento con todo su detalle antes de añadir intermediarios: las tres respuestas de Octave probadas agrupan algunos segmentos que el TTML mantiene separados.

La procedencia y el formato deben distinguirse. `itunes:timing="Word"`, namespaces de Apple y spans temporizados indican un documento compatible con su formato, pero no prueban por sí solos que la respuesta provenga directamente de Apple. El código actual de Better Lyrics puede resolver TTML por LRC.red/ISRC y usar Apple como alternativa; `/getLyrics` no devuelve la fuente original de cada documento. Reservar la etiqueta «Apple Music» para un origen comprobado, y mostrar «TTML / Boidu» o «TTML / LRC.red» cuando eso sea lo conocido.

## Consultas reales repetidas

Se consultaron sin cuenta ni API key `POST https://api.octavestreaming.com/api/lyrics` y `GET https://lyrics-api.boidu.dev/getLyrics`, con los IDs/metadatos previamente comprobados. Las seis respondieron HTTP200. Todas las muestras Boidu fueron `X-Auth-Mode: cache` / `X-Cache-Status: HIT`; no demuestra acceso libre a búsquedas no cacheadas.

| Canción | Boidu: spans temporizados TTML | Octave: elementos de palabra JSON | Líneas en ambas |
|---|---:|---:|---:|
| Blinding Lights — The Weeknd | 275 | 253 | 35 |
| DtMF — Bad Bunny | 486 | 480 | 62 |
| De Música Ligera — Soda Stereo | 109 | 87 | 23 |

Se compara cantidad de segmentos, no precisión auditiva ni segmentación lingüística. Algunos spans corresponden a voces de fondo. Las tres respuestas Octave declaran `source: lrcred-karaoke`, ofrecen alternativas y no incluyen TTML crudo en esta ruta.

Comprobación más fuerte que el conteo: los87 elementos Octave de De Música Ligera se reconstruyen agrupando los109 spans del TTML en el mismo orden, con texto normalizado sólo para espacios/Unicode;20 grupos combinan varios spans y los87 conservan los mismos tiempos exteriores. Por lo tanto, ese JSON pierde fronteras internas reales para el karaoke. Blinding Lights y DtMF también permiten agrupar todos sus segmentos para obtener las palabras Octave, pero algunos tiempos exteriores difieren; no se afirma igualdad temporal completa.

También respondió HTTP200 `https://lrc.red/s/USUG11904206.ttml`:35 líneas/275 spans. El documento no es idéntico byte por byte al de Boidu, pero las275 tuplas texto/inicio/fin son idénticas. Es una vía comprobada para conservar el mismo detalle de esa grabación sin pasar por el JSON de Octave.

Un lookup público `https://lrc.red/api/v1?track=De%20M%C3%BAsica%20Ligera&artist=Soda%20Stereo&duration=213` devolvió cuatro resultados, incluyendo remaster, versión SÉP7IMO DÍA y cover. La búsqueda no debe elegir ciegamente el primer resultado: artista, duración, álbum, edición e ISRC siguen siendo necesarios. La duración enviada no produjo un filtro exacto.

La [referencia de BiniLyrics](https://lyrics.binimum.org/developers) documenta búsquedas por metadata/ISRC y respuestas con `timing_type` y `lyricsUrl`. El [cliente actual de lyric-player](https://github.com/Ruytha/lyric-player/blob/0fca6a2d006dbf62cf27aa41bc5a8dfb9e285bca/src/binilyrics.js) usa directamente LRC.red y restringe las URLs de descarga a ese host. La ruta por ISRC está implementada también en [Better Lyrics](https://github.com/better-lyrics/api/blob/8b0ac346ac90ae38be0636611fcadbe8fe351106/services/providers/ttml/lrcred.go).

## Recursos de GitHub útiles

| Proyecto / revisión inspeccionada | Acceso y utilidad | Encaje en Side B |
|---|---|---|
| [MusanovaKit](https://github.com/rryam/MusanovaKit/tree/1ead3053f3c69428a7caf28335b7b72902095dc0), MIT | Swift, TTML crudo y parser de segmentos/sílabas. `MusicLyricsRequest` solicita `/catalog/{sf}/songs/{id}/syllable-lyrics` mediante `MusicPrivilegedDataRequest`; exige token de desarrollador privilegiado. | Referencia nativa útil. No es una API anónima de Apple ni queda lista con agregar el paquete. Nuestro parser puede recibir TTML sin importar todo el framework. |
| [applemusic-private](https://github.com/anselmoshim/applemusic-private/tree/98e35a04a1367c3f3b632c527594193a6ac4a91c), MIT declarado en pyproject (sin LICENSE separado en el árbol inspeccionado) | Python pequeño, ruta privada de Apple con bearer del reproductor web y media-user-token de una suscripción. Documenta que su vía no necesita un developer token privilegiado. | Referencia concreta del acceso autenticado y del endpoint; no introducir Python como runtime de Side B. No se probó con cuenta. |
| [lyric-player](https://github.com/Ruytha/lyric-player/tree/0fca6a2d006dbf62cf27aa41bc5a8dfb9e285bca), AGPL-3.0 en LICENSE | Electron/web, login en music.apple.com y consulta de letras dentro de la sesión del reproductor web. Requiere suscripción; también integra LRC.red y AMLL DB. | Referencia de flujo optativo «Conectar Apple Music» y proveedor TTML. No se copia su código ni se importa Electron. Las afirmaciones de autenticación se comprobaron por README/bridge; no se ejecutó el flujo. |
| [apple-music-lyrics](https://github.com/Takpap/apple-music-lyrics), MIT | AppKit/macOS, lee respuestas TTML ya cacheadas por Music.app; no descarga un catálogo de letras por su cuenta. | Buen parser/render de referencia, poca utilidad como fuente principal para pistas YTM que no hayan pasado por Music.app. No se leyó la caché del usuario. |
| [AMLL TTML DB](https://github.com/amll-dev/amll-ttml-db) | Base comunitaria en formato TTML, con índices y relaciones por ID de Apple/NetEase/QQ/Spotify. | Fuente adicional de archivos y variantes, sin confundir «formato Apple» con «letras oficiales descargadas de Apple». Su README distingue material de terceros de aportes propios CC0. |
| [Better Lyrics API](https://github.com/better-lyrics/api/tree/8b0ac346ac90ae38be0636611fcadbe8fe351106), GPL-3.0 | Servicio Go ya usado por Side B. `resolveLyrics` elige LRC.red o Apple según prioridad; la rama Apple usa una cuenta del servidor. | Puede autoalojarse, pero no elimina la necesidad de mantener cuentas/credenciales del proveedor. No distribuir un token de cuenta compartido dentro de la app. |

No se encontró una descarga de letras por sílaba documentada como API pública anónima de Apple. Los recursos revisados usan una ruta privada, una sesión de suscripción, una caché local o un intermediario. No se efectuaron peticiones autenticadas a Apple ni se inspeccionaron cookies/cuentas locales.

## Recomendación para Side B

1. Priorizar **TTML completo con sus segmentos originales**. Evaluar LRC.red como fuente directa por ISRC y por matching conservador; conservar Boidu como fuente y alternativa existente. Sus resultados de caché ya pueden tener el detalle buscado.
2. Añadir Octave como alternativa y comparación de versión, con identidad externa validada. No convertir su JSON agrupado en la única fuente: no permite recuperar sílabas que ya agrupó. Se conserva la advertencia de disponibilidad/condiciones del [informe Octave](OCTAVE-2026-10-20.md); estas pruebas sólo acreditan acceso técnico puntual.
3. Mantener segmentos temporizados separados de palabras visuales: una palabra puede tener varias sílabas, cada una con su inicio/fin. Preservar espacios, voces `x-bg`, agente y documento crudo en la próxima versión de modelo/caché. El experimento actual conserva segmentos en `words`, pero no expone voces/romanización ni agrupa palabras sostenidas como entidades visuales propias.
4. Medir si el renderer aprovecha esas fronteras: relleno por sílaba y animación de palabra sostenida, fondo/voz principal separados y líneas simultáneas. Cambiar de fuente por sí solo no implementa esa presentación.
5. Como opción posterior para quien tenga suscripción, evaluar un proveedor directo autenticado de Apple dentro de una sesión aislada. El inicio se haría en Apple, con soporte de desconexión y sin compartir credenciales con Octave/Boidu. No es requisito para conseguir el TTML detallado comprobado aquí.

La siguiente implementación debería permanecer tras el botón experimental: selector de fuente/automático, procedencia visible, matching/cache por versión, descarte por reproducción/revisión y fallback al panel existente. Comparar al menos30–50 pistas/ediciones y escuchar sincronización antes de decidir prioridad por defecto.

Esta investigación actualiza el plan; no registra un nuevo FIX, build o port Windows. Las opciones nuevas siguen pendientes de implementación y validación.

## Seguimiento: indicadores de intro e interludio

La [guía oficial de Apple para TTML](https://help.apple.com/itc/videoaudioassetguide/en.lproj/static.html) documenta `itunes:song-part` con valores sugeridos Intro, Outro, Instrumental, Verse, Chorus y otros. Aclara que esas etiquetas de sección no se muestran como tales al usuario. Las marcas visuales de espera no deben confundirse con ese metadato ni con el flag de una canción enteramente instrumental. No se verificó un algoritmo público de Apple que defina exactamente el umbral o la animación de sus indicadores.

Los indicadores pueden derivarse de los intervalos sin letra temporizada: intro antes de la primera entrada, hueco entre el fin vocal y el siguiente inicio, y cierre tras la última entrada cuando hay duración confiable. Se deben unir primero los intervalos de todas las voces, incluyendo fondo y líneas superpuestas; no marcar un instrumental mientras otra voz sigue cantando. La ausencia de letra temporizada no demuestra ausencia de voz en el audio.

Prueba estructural sobre las muestras Boidu, sin escuchar audio: con un umbral **elegido sólo para esta exploración** de4s, De Música Ligera tiene intervalos sin letra temporizada en0–23,119s,67,148–84,883s,113,604–146,810s y162,578–169,119s. Ninguna de las tres muestras tenía una sección declarada Instrumental. El cálculo usa la unión de segmentos temporizados de todas las voces, no sólo la resta de inicios de líneas.

Propuesta pendiente: modelo de intervalos intro/interludio/outro con origen explícito/inferido, indicador de tres puntos con progreso hasta la próxima entrada y transición a la línea siguiente. Usar tiempos de AVPlayer, aplicar el mismo desfase y responder a pausa/seek; evitar indicadores para respiraciones cortas. Con Reducir movimiento conservar indicación estática. No animar una cuenta de beats sin datos de tempo/compás. El experimento actual sólo tiene el estado de pista completamente instrumental; todavía no dibuja estos intervalos y su pulso se suspende durante gaps, por lo que el indicador necesitaría su propio estado temporal local.

## Seguimiento: ad-libs y voces de fondo

TTML permite `ttm:role="x-bg"` para voces de fondo y `ttm:agent` para identificar voces/intérpretes. Comprobación sobre las respuestas guardadas: Blinding Lights de Boidu contiene2 grupos x-bg; DtMF12 y agentes v1/v1000/v2000; De Música Ligera ninguno. El archivo directo LRC.red de Blinding Lights también conserva sus2 grupos x-bg. Son grupos etiquetados, no un conteo de ad-libs musicales ni de personas; no se infiere que toda interjección tenga una etiqueta especial.

Las tres respuestas Octave inspeccionadas sólo tienen start/end/text/words por línea y start/end/word por palabra: no conservan esos roles/agentes en el richSync recibido. Podrían contener el texto de una voz secundaria sin la separación estructural, por lo que no son suficientes para reconstruir capas con certeza.

La [guía de letras de Apple](https://help.apple.com/itc/musicstyleguide/en.lproj/itc3ae5d4dea.html) pide separar voces de fondo y trata las vocalizaciones no verbales según su función en la canción; no garantiza que todo ad-lib esté transcrito. [Braccato](https://github.com/better-lyrics/braccato/blob/master/packages/parsers/README.md) documenta lectura de x-bg y agent. El experimento Side B todavía aplana ese contenido dentro de la línea: preservar rol/agente/capa y renderizar voces secundarias con tiempos propios es parte del próximo tramo propuesto, sin cambios de app en esta consulta.
