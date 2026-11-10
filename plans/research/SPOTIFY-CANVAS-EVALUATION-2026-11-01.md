# Spotify Canvas en Side B: evaluación de proyectos

Fecha de consulta: **1 de noviembre de 2026**, America/Montevideo. Investigación documental y revisión estática de código público. **No se ejecutaron clientes de terceros, no se usaron cookies/cuentas y no se verificó una descarga real.** Estado: reporte terminado; integración no implementada.

## Recomendación

**La mejor referencia técnica para un prototipo nativo es Wolframe-spotify-canvas, mediante un adaptador Rust pequeño y revisado. No recomiendo incorporar ninguno de los proyectos directamente como dependencia de producción.**

Wolframe utiliza Pathfinder y permite aislar la consulta de Canvas sin añadir Python, Node, Docker ni un servidor local. Sin embargo, no obtiene ni renueva el token de usuario de Spotify: su automatización cubre el `client-token`, que es otra credencial. Habría que resolver sesión, correspondencia de canciones, validación del video y mantenimiento. [README](https://github.com/squeeeezy/Wolframe-spotify-canvas/blob/main/README.md), [cliente](https://github.com/squeeeezy/Wolframe-spotify-canvas/blob/main/src/lib.rs).

Para estudiar autenticación y casos de prueba, **SpotifyScraper** es la referencia complementaria más completa de las revisadas. **InstaZDLL/spotify-canvas-downloader** aporta una implementación Rust de sesión y tests, pero consulta la ruta REST antigua y trae infraestructura de servicio HTTP innecesaria para Side B. Estas son preferencias de arquitectura basadas en código, no un ranking de funcionamiento medido.

**Para distribuir la función hay un problema previo de permisos:** Spotify no publica una API de Canvas y su política restringe combinar su contenido con servicios ajenos. Side B reproduce YouTube Music. Una licencia MIT/GPL del cliente no autoriza el uso de los videos de Spotify. Mi recomendación de producto es mantener el proveedor actual y evaluar Canvas sólo como investigación hasta aclarar una vía permitida; llamarlo “experimental”, usar un plugin o silenciar el video no resuelve esa restricción. [Política, III.5–7](https://developer.spotify.com/policy), [Términos, IV](https://developer.spotify.com/terms).

## Qué son y qué hay que resolver

Canvas se asocia a una **canción**, puede cambiar con el tiempo y no está presente en todas. Las especificaciones oficiales admiten 3–8 segundos, formato vertical 9:16, 720–1080 píxeles de alto y MP4 o JPG. La altura publicada no significa un video de 1080×1920. No debe confundirse con un videoclip completo ni con el motion artwork de un álbum. [Especificaciones y actualización](https://support.spotify.com/us/artists/article/canvas-guidelines/).

La cadena de trabajo propuesta sería:

1. Identificar la grabación de YouTube Music y encontrar su equivalente exacto en Spotify.
2. Obtener una sesión admitida por el mecanismo elegido y mantenerla.
3. Resolver Canvas para el Spotify track ID.
4. Distinguir video existente, ausencia real, sesión vencida, cambio de API y fallo temporal.
5. Validar y mostrar el recurso con el reproductor visual de Side B, sin afectar el audio.

Los proyectos centrados en Canvas suelen cubrir el paso 3. Ninguno de los revisados entrega resuelta toda esta cadena para Side B.

### Dos familias de consulta

| Familia | Formato | Proyectos observados | Evaluación |
|---|---|---|---|
| `spclient.wg.spotify.com/canvaz-cache/v0/canvases` | Petición/respuesta Protobuf | Delitefully, Paxsenix0, yt-dlp plugin, SpCanvas, InstaZDLL | Implementación histórica; no elegir como única base de un desarrollo nuevo sin prueba actual |
| `api-partner.spotify.com/pathfinder/…/query` | GraphQL con consulta persistida y JSON | Wolframe: POST v2; SpotifyScraper: GET v1 | Mejor punto de partida documental; también privado y sujeto a cambios |

Ambos clientes Pathfinder revisados usan la operación `canvas` y la variable `trackUri`. No son intercambiables sus métodos, cabeceras ni autenticación. La afirmación del README de Wolframe de que REST dejó de funcionar es la afirmación del autor: **esta investigación no demostró que todos los endpoints REST estén caídos actualmente**. [Wolframe](https://github.com/squeeeezy/Wolframe-spotify-canvas/blob/main/README.md), [registro de operaciones de SpotifyScraper](https://github.com/AliAkhtari78/SpotifyScraper/blob/master/src/spotify_scraper/api/pathfinder.py).

## Comparación principal

Las versiones corresponden al manifiesto consultado; las fechas son del último commit de la rama predeterminada consultada, no de “updated_at” o “pushed_at”. Actividad reciente, estrellas o CI verde no certifican acceso real a Canvas.

| Proyecto | Versión / commit más reciente | Licencia declarada | Consulta y sesión | Papel recomendado |
|---|---|---|---|---|
| [Wolframe](https://github.com/squeeeezy/Wolframe-spotify-canvas) | Cargo 1.0.4; 2026-01-22 | MIT | Pathfinder v2; Bearer externo + client-token propio | Primera referencia para adaptador Rust |
| [SpotifyScraper](https://github.com/AliAkhtari78/SpotifyScraper) | 3.9.2; 2026-06-26 | MIT | Pathfinder v1; cookie y TOTP | Referencia de sesión, modelos y pruebas |
| [InstaZDLL](https://github.com/InstaZDLL/spotify-canvas-downloader) | Cargo 0.2.0; 2026-07-31 | GPL-3.0-only | REST Protobuf; cookie y TOTP | Referencia Rust secundaria; no integrar el servidor |
| [Delitefully](https://github.com/Delitefully/spotify-canvas-downloader) | Sin versión verificada; 2025-06-02 | GPL-3.0 según metadata de GitHub | REST Protobuf; cookie y TOTP fijo | Antecedente histórico |
| [Paxsenix0](https://github.com/Paxsenix0/Spotify-Canvas-API) | Sin versión verificada; 2025-12-02 | GPL-3.0 según metadata de GitHub | REST Protobuf; cookie y catálogo TOTP remoto | Descartar como base directa |
| [qbnu/yt-dlp](https://github.com/qbnu/yt-dlp-SpotifyCanvas) | Release de código 2025.11.21; 2025-11-21 | Unlicense | REST Protobuf; cookies y catálogo remoto | Herramienta de diagnóstico, si se valida |
| [SpCanvas](https://github.com/mwndl/spcanvas) | Sin versión verificada; 2025-07-07 | MIT | REST Protobuf y sesión web | Referencia de experiencia visual |
| [bartleyg](https://github.com/bartleyg/my-spotify-canvas) | Sin versión verificada; 2022-05-09 | Sin licencia detectada en inventario | Implementación histórica web | Documentación histórica; no copiar código sin aclarar licencia |

La [matriz visual](SPOTIFY-CANVAS-COMPARISON-2026-11-01.html) resume las familias de consulta. Los SHA completos y las URLs reproducibles están en [el manifiesto de evidencia](SPOTIFY-CANVAS-SOURCES-2026-11-01.json). Las consultas a crates.io/docs.rs no fueron accesibles desde la herramienta web: **1.0.4 es la versión del Cargo.toml, no una publicación del registro verificada**.

### Wolframe: mejor ajuste de arquitectura, con fallos concretos que corregir

El [manifiesto](https://github.com/squeeeezy/Wolframe-spotify-canvas/blob/main/Cargo.toml) usa Rust 1.83+, reqwest 0.11 con TLS predeterminado y Tokio con features amplias. Side B usa reqwest 0.12/rustls. Añadir la crate sin adaptar introduciría versiones y configuración HTTP adicionales; su constructor de cliente compartido recibe el tipo de reqwest 0.11, por lo que no acepta directamente el cliente actual.

La [gestión de client-token](https://github.com/squeeeezy/Wolframe-spotify-canvas/blob/main/src/token.rs) renueva antes de su vencimiento, pero simula una versión y un dispositivo concretos. No contiene login de usuario ni conversión cookie→Bearer. Ese flujo seguiría siendo responsabilidad de nuestra integración.

La revisión del [cliente](https://github.com/squeeeezy/Wolframe-spotify-canvas/blob/main/src/lib.rs) encontró:

- Añade `Bearer ` al argumento, aunque parte de la documentación muestra el prefijo dentro del argumento: riesgo de duplicarlo.
- Lee errores GraphQL pero no los clasifica; un HTTP 200 con error puede terminar como “no encontrado”.
- 401 no se convierte expresamente en el error de token vencido anunciado.
- Escribe la URL de Canvas en logs y lee cuerpos completos; faltan límites apropiados para Side B.
- No valida host/formato del recurso ni descarga un archivo.

Su [CI](https://github.com/squeeeezy/Wolframe-spotify-canvas/blob/main/.github/workflows/ci.yml) declara formato, Clippy y tests en Ubuntu. El árbol inspeccionado no contiene una suite dedicada de integración ni fixtures de Canvas. No se comprobó ejecución nativa en Mac/Windows ni acceso en vivo. El [archivo MIT](https://github.com/squeeeezy/Wolframe-spotify-canvas/blob/main/LICENSE) permite estudiar y adaptar código conservando sus avisos; no otorga derechos sobre los assets.

### SpotifyScraper: mejor referencia de apoyo

Ofrece clientes sync/async, modelo de Canvas, parser, tests de presentes/ausentes y errores de autenticación. La [sesión por cookie](https://github.com/AliAkhtari78/SpotifyScraper/blob/master/src/spotify_scraper/auth/cookies.py) mantiene tokens en caché, renueva antes de caducar y diferencia una cookie rechazada de versiones TOTP retiradas. Las [versiones TOTP](https://github.com/AliAkhtari78/SpotifyScraper/blob/master/src/spotify_scraper/auth/totp.py) siguen siendo material que rota: no es autenticación oficial ni mantenimiento gratuito.

La [persistencia de sesión](https://github.com/AliAkhtari78/SpotifyScraper/blob/master/src/spotify_scraper/auth/session.py) dispone de backend de archivo y opción explícita de keyring. Para Side B convendría almacenamiento protegido del sistema y un flujo de desconexión propio, sin importar cookies de otros navegadores automáticamente.

No recomiendo empaquetar toda la biblioteca Python sólo para Canvas. Su [descargador](https://github.com/AliAkhtari78/SpotifyScraper/blob/master/src/spotify_scraper/media/video.py) carga el cuerpo en memoria y escribe el archivo; no reemplaza los límites, validación, temporales y leases de nuestro motor.

**Alerta de mantenimiento interpretada con cuidado.** La [issue #166](https://github.com/AliAkhtari78/SpotifyScraper/issues/166), abierta el 01/11, anuncia un fallo de extracción. Sin embargo, los [jobs del run asociado](https://api.github.com/repos/AliAkhtari78/SpotifyScraper/actions/runs/41272623718/jobs) señalan fallo en la instalación de Chromium, antes del paso de pytest. No demuestra una rotura del endpoint Canvas. Además, los [tests reales de Canvas](https://github.com/AliAkhtari78/SpotifyScraper/blob/master/tests/live/test_visual.py) se omiten sin cookie y aceptan ausencia como resultado; un run verde tampoco demuestra que se descargó un MP4. Es buena observabilidad, pero hace falta una prueba positiva específica.

### InstaZDLL: Rust y tests útiles, otra estrategia de consulta

La [reescritura Rust](https://github.com/InstaZDLL/spotify-canvas-downloader/commit/a4b464bd96de81357d33a871c7c25ce144301a94) incorpora un cliente separable de Axum. Su [código de Canvas](https://github.com/InstaZDLL/spotify-canvas-downloader/blob/main/src/spotify/canvas.rs) tiene timeout de diez segundos, reintento acotado tras 401, manejo de 429 y tests del parser. El [test real](https://github.com/InstaZDLL/spotify-canvas-downloader/blob/main/tests/live_spotify.rs) está ignorado por defecto y requiere cookie y canción conocida.

Su [autenticación](https://github.com/InstaZDLL/spotify-canvas-downloader/blob/main/src/spotify/auth.rs) coordina renovación con un mutex, usa catálogo TOTP remoto y permite override. El reloj local genera también el valor enviado como tiempo del servidor: merece una prueba de desfase. El [manifiesto](https://github.com/InstaZDLL/spotify-canvas-downloader/blob/main/Cargo.toml) exige Rust 1.85+, reqwest 0.13 y dependencias de servidor/Protobuf. Adoptarlo completo aumenta infraestructura. Su consulta sigue siendo REST; no se ha probado su disponibilidad actual.

El [README](https://github.com/InstaZDLL/spotify-canvas-downloader/blob/main/README.md) reconoce expresamente que el mecanismo es privado y advierte sobre los términos de Spotify. Es un aviso del proyecto, no una autorización.

### Delitefully: antecedente que no elegiría hoy

El [resolver](https://github.com/Delitefully/spotify-canvas-downloader/blob/master/src/canvas.py) usa Protobuf y elige aleatoriamente un resultado; no comprueba el estado HTTP antes de parsearlo. La [autenticación](https://github.com/Delitefully/spotify-canvas-downloader/blob/master/src/auth.py) fija una versión TOTP antigua y hace requests sin timeout explícito. Hay [issues abiertas](https://github.com/Delitefully/spotify-canvas-downloader/issues) por errores y falta de funcionamiento desde 2023–2025. Es evidencia de incidencias reportadas, no una prueba ejecutada de su estado actual. Requeriría corregir demasiado para justificarlo frente a una base Rust pequeña.

### Paxsenix0 y qbnu: dependencia externa delicada

[Paxsenix0](https://github.com/Paxsenix0/Spotify-Canvas-API/blob/main/services/spotifyCanvasService.js) expone un servicio Node y convierte errores de consulta en `null`. Su [autenticación](https://github.com/Paxsenix0/Spotify-Canvas-API/blob/main/services/spotifyAuthService.js) descarga parámetros TOTP desde otro repositorio y actualiza periódicamente. La [issue #5](https://github.com/Paxsenix0/Spotify-Canvas-API/issues/5) reporta que ese repositorio fue retirado; no se verificó en vivo la recuperación del catálogo.

El [plugin de qbnu](https://github.com/qbnu/yt-dlp-SpotifyCanvas/blob/main/yt_dlp_plugins/extractor/spotifycanvas.py) comparte esa dependencia y la consulta REST, pero aprovecha la infraestructura de yt-dlp e identifica también Canvas de imagen. Hay detalles a revisar: selección lexicográfica de versión y cálculo de tiempo del servidor. Puede servir para comparar resultados durante una investigación; no añadiría Python/yt-dlp a Side B únicamente por esta función.

### Aplicaciones y servicios secundarios

- **SpCanvas:** [Next.js](https://github.com/mwndl/spcanvas/blob/main/README.md), pantallas completas y seguimiento de lo que reproduce Spotify. Su [consulta](https://github.com/mwndl/spcanvas/blob/main/src/lib/canvasService.js) usa REST. Útil para estudiar la experiencia, pero Side B ya conoce su canción activa y no necesita polling del reproductor de Spotify.
- **bartleyg:** antecedente citado por Canvas Downloader; árbol sin LICENSE detectada. La ausencia de licencia visible no concede permiso para incorporar código.
- **[Spicetify-Canvas](https://github.com/itsmeow/Spicetify-Canvas):** MIT y archivado; se ejecuta dentro del cliente Spotify y aprovecha su entorno. No es una biblioteca autónoma para Side B. Su README contiene requisitos de CEF históricos que no deben extrapolarse a nuestra app.
- **[CanvasSync](https://github.com/pkgFiles/CanvasSync/blob/v2/README.md):** MIT, orientado a iOS y wallpaper. Su autor indica que falta el subproyecto CanvasSyncSpotify y que no compila directamente. No ofrece una base completa y reproducible para Mac/Windows.
- **[Canvas Downloader](https://www.canvasdownloader.com/about):** sitio que anuncia descarga manual y acredita a bartleyg. No se encontró en lo revisado un contrato público versionado/SLA de API para integrar. No lo usaría mediante scraping como dependencia principal, ni enviaría cookies a ese servicio.
- La búsqueda también devolvió generadores de Canvas y herramientas de tarjetas gráficas: producir videos nuevos o dibujar portadas no recupera los Canvas originales. No son candidatos equivalentes.

## Encaje real en nuestro código

La inspección se hizo sobre el árbol de trabajo existente, que tiene modificaciones pendientes. Commit base: `f7fc4796cd70fef4712dab10253690bdbb0b234f`. No se alteró código de producto durante esta investigación.

| Componente actual | Se puede aprovechar | Trabajo adicional necesario |
|---|---|---|
| [Motor de artwork](../../core/crates/sideb-core/src/animated_artwork/mod.rs) | Cancelación, single-flight, leases y asset local tipado | Separar proveedor e identidad por canción |
| [Proveedor actual](../../core/crates/sideb-core/src/animated_artwork/provider.rs) | Validación HTTP y selección de recursos como referencia | Resolver Spotify por separado; su allowlist sólo admite hosts Apple |
| [Caché](../../core/crates/sideb-core/src/animated_artwork/cache.rs) | Presupuestos y escritura controlada | Namespace por proveedor, track y asset; ausencia no se comparte con Apple |
| [Reproductor visual Mac](../../apple/Sources/SideB/Views/Fullscreen/Artwork/AnimatedArtworkController.swift) | AVQueuePlayer silenciado y AVPlayerLooper | Comprobar MP4 vertical, primer frame, pausa, visibilidad y energía |
| [Puente Windows](../../windows/src-tauri/src/commands/animated_artwork.rs) | Comandos tipados y ciclo de vida de peticiones | Mantener DTO/consumidor y validar en Windows real |
| [SongItemRecord](../../core/crates/sideb-core/src/lib.rs) | ID YTM, título, artistas, duración y edición | No contiene ISRC ni Spotify ID; falta correspondencia fiable |

**Error de diseño que hay que evitar:** la clave actual agrupa por álbum cuando existe metadata de álbum. Dos canciones del mismo disco podrían compartir por error un Canvas si sólo cambiamos el proveedor. Canvas necesita identidad por pista y proveedor, con alias de correspondencia verificados; el motion Apple puede conservar su identidad de álbum.

El contrato actual de asset ya incluye ruta, dimensiones y códec. Esto ayuda al renderer, pero no significa que el motor acepte un proveedor Spotify con sólo pasarle una URL. El core está protegido por las reglas del repositorio: este reporte no autoriza modificarlo; una futura propuesta tendría que justificar y verificar ambos consumidores.

## Diseño sugerido para una prueba posterior

Las siguientes son **propuestas**, no capacidades medidas ni funciones implementadas.

### Sesión y correspondencia

- Usar inicialmente un Spotify track ID elegido explícitamente, para separar “obtener Canvas” de “encontrar la canción”. Después evaluar correspondencia automática.
- ISRC puede ayudar si se dispone de él y de una vía autorizada de búsqueda, pero no existe hoy en nuestro record. Sin él, exigir coincidencia conservadora de título, créditos, edición/remix/live/clean y duración; permitir corrección manual y rechazar ambigüedad.
- No asumir que OAuth público/Client Credentials equivale a un Bearer del Web Player aceptado por Pathfinder. No se verificó tal equivalencia.
- No pedir la contraseña ni importar cookies ajenas de forma silenciosa. Una eventual sesión debe tener almacenamiento protegido, expiración, desconexión y limpieza. El uso de cookies sigue requiriendo resolver el problema de permisos.
- Tratar rotación de TOTP, consulta persistida y client-token como tres cambios distintos. Evitar descargar parámetros arbitrarios de terceros sin revisión y versionado.

### Resolver y mostrar

Proponer un adaptador con resultados separados: `Ready`, `ConfirmedAbsent`, `AuthRequired`, `RateLimited`, `UnsupportedResponse`, `TemporaryFailure` y `Cancelled`. Un 200 con error GraphQL o un 401 **nunca** deben convertirse en ausencia persistida.

Mantener el transporte de audio independiente. Preparar únicamente el visual de la pista visible, con una descarga efectiva, cancelación y descarte de respuestas tardías. Reusar el concepto de asset local y lease, sin crear un segundo reproductor por proveedor. Conservar la imagen mientras carga o falla.

La selección visual debería ser explícita: priorizar Canvas o carátula animada actual, con alternativa a imagen. No inferir esa decisión de la relación de aspecto ni reemplazar una portada cuadrada sin explicar la opción. No interpolar FPS, reescalar para inventar resolución ni sincronizar el loop con palabras.

Antes de mostrar un recurso: HTTPS, host aprobado y redirects controlados; límite de cuerpo/tamaño y timeout; tipo real de archivo, dimensiones, duración, códec y ausencia de contenido inesperado. Aceptar que algunos Canvas son JPG. No reutilizar literalmente el presupuesto de un motion de álbum largo para un loop corto.

### Producción y permisos

La [política de Spotify](https://developer.spotify.com/policy) restringe integración con otros servicios, sincronización audiovisual y mezcla con audio ajeno; los [términos](https://developer.spotify.com/terms) también restringen acceso no autorizado, extracción y obtención de credenciales fuera de los mecanismos previstos. **Inferencia para Side B:** mostrar Canvas junto con reproducción YTM presenta un conflicto directo que debe aclararse antes de distribuir la función. No afirmo una conclusión judicial ni que una licencia de código lo resuelva.

MIT exige conservar sus avisos. La incorporación de componentes GPL-3.0-only debe conservar sus obligaciones y revisarse frente al GPL-3.0-or-later de Side B; no debe asumirse relicenciamiento libre. La licencia del programa y los derechos de exhibición/descarga de los videos son asuntos diferentes.

## Pruebas que faltan para cambiar la recomendación

| Puerta | Evidencia requerida |
|---|---|
| Acceso actual | Una canción conocida con Canvas produce un recurso positivo; otra sin Canvas produce ausencia válida. Registrar versión/fecha sin guardar tokens ni URLs firmadas |
| Sesión | Renovación, cookie revocada, token anónimo, client-token vencido y reloj desfasado; sin filtración en logs |
| Respuesta | Fixtures de presente, null válido, error GraphQL 200, hash retirado, 401/403/429/5xx, JSON/Protobuf truncado y esquema nuevo |
| Correspondencia | Canciones con mismo título, versiones clean/explicit, live/remix, artistas invitados y dos pistas del mismo álbum |
| Archivo | Validación del MP4/JPG, límites durante streaming sin Content-Length, escritura atómica, redirect inesperado y respuesta HTML |
| Ciclo de vida | A→B→A, cambios rápidos, cuenta nueva, apagar ajuste, cerrar vista y limpiar caché con descarga/player activos |
| Mac y Windows | Muestra real, primer frame y loop, pausa y reentrada, consumo y accesibilidad; compilación sola no acredita reproducción |
| Distribución | Vía permitida para Canvas + audio YTM y revisión de licencias/avisos; no se sustituye por un test técnico |

No se dan porcentajes de cobertura, latencias, tasas de éxito, consumo ni estimaciones horarias: no se midieron. Una investigación positiva con una canción tampoco demuestra cobertura general.

## Decisión propuesta

1. **Para estudiar y prototipar:** Wolframe como referencia de consulta Pathfinder, auditado y adaptado al cliente HTTP de Side B.
2. **Para completar sesión y tests:** comparar SpotifyScraper y el código Rust de InstaZDLL, sin importar sus runtimes/servidores enteros.
3. **Para incluir hoy en una build pública:** ninguno. Falta prueba positiva de extremo a extremo y una vía compatible con los permisos del proveedor.
4. **Para continuar mientras tanto:** mantener las carátulas actuales; evaluar material suministrado/autorizado por el usuario o titulares como una función distinta, sin prometer acceso al catálogo Canvas.

La documentación de terceros permite formular un prototipo; todavía no permite prometer una integración automática, estable y distribuible.

## Alcance de la evidencia

Se revisaron búsquedas web y GitHub, árboles/manifiestos, código de consulta/autenticación, archivos de licencia seleccionados, tests y metadata de CI. No se ejecutaron builds de estos repositorios ni una auditoría completa de dependencias o seguridad. No se siguieron instrucciones de instalación ni se accedió a una sesión privada.

El [manifiesto JSON](SPOTIFY-CANVAS-SOURCES-2026-11-01.json) conserva identidades, commits y fuentes. El [plan de investigación](../PLAN-021-spotify-canvas-research.md) distingue el reporte terminado de las pruebas futuras pendientes. No se modificó FIXES/PARIDAD porque no se implementó un fix ni un port.

