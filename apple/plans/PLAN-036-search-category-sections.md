# PLAN-036: Búsqueda por categorías (estilo Apple Music) con resultados de YouTube Music

- Fecha: 2026-11-12 (America/Montevideo).
- Estado: **etapas 1–3 implementadas y probadas en la app real (2026-11-12)**, con las recomendaciones de D1–D6 como valores por defecto; «Listen again» queda fuera por decisión del usuario. Pendientes: ajuste de Configuración (D5), etapa 0 formal con fixtures, Windows y build numerada ([FIX-332](../../FIXES.md#fix-332), [PAR-057](../../PARIDAD.md)).
- Objetivo: mostrar la página de búsqueda como secciones por categoría (Artistas, Álbumes, Canciones, Playlists…), como hace Apple Music, rellenadas con resultados reales de YouTube Music, **conservando el bloque del resultado principal** y su orden de relevancia.
- Ámbito: Apple (SwiftUI/AppKit). Sin cambios en `core/` en las etapas 0–4; la red y el parseo del proveedor siguen igual. Windows queda como paridad posterior (PAR nueva).
- Fuera de alcance: llamar a la API de Apple Music (los datos siguen siendo de YouTube Music), pestañas «Apple Music / Biblioteca», búsqueda en biblioteca, cambiar el ranking del proveedor, inventar resultados.
- Referencias: [PLAN-016](../../plans/PLAN-016-search-presentation.md) (principal y relacionadas; **este plan revierte a propósito su punto 4**, ver «Conflicto con PLAN-016»), [PLAN-027](PLAN-027-search-density-and-performance.md), [PLAN-032](PLAN-032-search-video-preferences.md), FIX-246/FIX-331 (ancho y filas realizadas fuera de pantalla), PAR-042.

## 1. Evidencia (medida el 2026-11-12 en la app real, con cuenta)

### Lo que entrega YouTube Music hoy en la búsqueda general
Volcado de accesibilidad de Side B con la consulta «kendrick lamar» (28 filas realizadas):

| Bloque | Contenido | Observación |
|---|---|---|
| Principal | Artista «Kendrick Lamar» + «Related results» (canciones asociadas) + Shuffle/Mix/Abrir | Ya implementado (PLAN-016) |
| «Listen again» | 8 canciones | Sección **personalizada** del proveedor; no es una categoría |
| Lista mixta sin título | Artista ×1, Álbumes ×3, Artistas ×2, Playlists ×5, Perfiles ×3, Podcasts ×3 | Una sola lista, en **rachas por tipo** y en orden de relevancia |

Con «sudaca» pasa lo mismo: principal (canción), lista mixta sin encabezados. Es decir: **el proveedor no entrega secciones por categoría en la búsqueda general**; Side B hoy las muestra como una lista plana con una etiqueta de tipo por fila.

Hallazgos que condicionan el diseño:
1. **Pocos elementos por tipo** en la lista mixta (3–5 álbumes/artistas, casi ninguna canción fuera del principal y de «Listen again»). Apple Music muestra ~5 artistas, ~6+ álbumes y ≥9 canciones; con sólo la lista mixta las categorías quedarían casi vacías.
2. **El tipo no se deduce de `BrowseCardRecord.kind`.** Los *perfiles* llegan como `kind = artist` (subtítulo «Profile • @handle») y los *podcasts* como `kind = playlist` (subtítulo «Podcast»). El tipo textual viaja en el subtítulo, que depende del idioma de la respuesta. `BrowseCardRecord` no trae `pageType`.
3. **Las categorías completas sí existen**: la página trae chips con `params` (Songs, Artists, Videos, Albums, Community playlists, Episodes, Profiles, Featured playlists, Podcasts), y `core.searchPage(query:params:)` devuelve la lista completa de **un solo tipo**. Es la vía «Ver todo» actual.
4. La etiqueta duplicada («Artists · Artist», «Album · Album») desaparece sola cuando el tipo lo da la sección.

### Cómo lo muestra Apple Music (una captura, consulta «kanye»; no se comparó con la misma consulta en ambas apps)
- Secciones con título y flecha («Artistas ›», «Álbumes ›», «Canciones ›», «Playlists ›»).
- Artistas: carrusel horizontal de círculos con el nombre debajo.
- Álbumes: carrusel horizontal de tarjetas cuadradas (título + artista).
- Canciones: **cuadrícula de 3 columnas** de filas compactas (portada, título, artista, botón «…», marca de favorito).
- Sin chips de filtro ni etiqueta de tipo por fila.

## 2. Diseño propuesto

### Estructura de la página
```
[ editor de búsqueda ]
[ chips de categoría ]                     ← se conservan: son la ruta «Ver todo»
┌─ Principal (sin cambios) ────────────────────────────────────────────────┐
│ [portada]  Kendrick Lamar            Related results                      │
│            Artist • 132M …           ▸ N95 …  ▸ Money Trees … (3 filas)   │
│            [Shuffle][Mix][Abrir][⋯]                                       │
└───────────────────────────────────────────────────────────────────────────┘
Artistas  ›                                    ← categorías, orden de relevancia (D1)
  (●)   (●)   (●)   (●)   (●)  →               carrusel de círculos 150 pt
Álbumes  ›
  [▣]  [▣]  [▣]  [▣]  [▣]  →                   carrusel de tarjetas 160 pt
Canciones  ›
  ▸ fila  ▸ fila  ▸ fila                       cuadrícula de filas 58 pt:
  ▸ fila  ▸ fila  ▸ fila                       3 col ≥ 1000 pt, 2 col ≥ 700, 1 col debajo
  ▸ fila  ▸ fila  ▸ fila
Playlists ›  /  Perfiles ›  /  Podcasts ›  /  Videos ›
```
Anchos útiles (sidebar abierta): 618 pt a 960 de ventana hasta ~1098 a 1440 (PLAN-016).

### Reglas
- **Principal intacto**: mismo bloque, mismas relacionadas, mismos payloads por ocurrencia.
- **«Listen again» y demás secciones personalizadas del proveedor no se muestran** en la vista por categorías (decisión del usuario, 2026-11-12). Se reconocen porque llevan título y no coinciden con ninguna categoría conocida. La vista «lista del proveedor» (D5) las sigue mostrando.
- **Orden de secciones = orden de aparición del tipo en la lista mixta** (relevancia del proveedor), no un orden fijo. Mitiga el riesgo de PLAN-016.
- **Cabecera de sección**: título + flecha; la flecha usa el mecanismo actual `openProviderSection` / chip `params` (= «Ver todo»).
- **Videos** sólo si `SearchPreferences.showVideos` (PLAN-032). El filtro se aplica antes de agrupar.
- **Sin etiqueta de tipo por fila** en las filas de categoría.
- Alturas de carrusel/cuadrícula **calculadas por constantes** (portada + texto con su límite de líneas + padding), nunca por medición asíncrona: es la causa probable de otras desalineaciones del viewport (el carrusel actual fija 232 pt y su contenido con título y subtítulo de dos líneas necesita ~248 pt; estimado, no medido).

## 3. Cómo se llenan las categorías

1. **Inmediato**: se agrupa la lista mixta que ya llegó, para que haya algo en pantalla sin esperar.
2. **Relleno**: por cada categoría relevante se pide su página con el `params` del chip (`core.searchPage(query:params:recordHistory:false)`) y se reemplaza el contenido provisional por la primera página del tipo. Independiente del idioma y garantiza el tipo (resuelve el hallazgo 2).
3. **Presupuesto de red**: máx. 3 peticiones simultáneas; se piden primero las 4 categorías con más peso en la lista mixta y el resto al acercarse al viewport; cancelación por generación de consulta (`queryGeneration` ya existe); caché por `(consulta, params)` mientras dure la consulta; error por sección con «Reintentar» (`partialErrors[.categories]` ya existe).
4. **Sin saltos**: el reemplazo provisional → completo no se anima y conserva la posición de scroll; las alturas por constantes evitan remedición.
5. Una categoría sin resultados no se muestra; un fallo no vacía las demás.

## 4. Decisiones abiertas (con recomendación)

| ID | Pregunta | Recomendación |
|---|---|---|
| D1 | Orden de secciones | **Implementado: orden de los chips del proveedor** (su ranking de categorías para esa consulta; estable desde la primera respuesta, sin saltos). Alternativa: orden fijo estilo Apple. |
| D2 | Canciones: cuadrícula o lista | Cuadrícula 3/2/1 columnas, 9/6/5 filas visibles, como Apple; «Ver todo» abre el chip Songs. |
| D3 | Fuente de relleno | Híbrido: mezcla inmediata + una petición por categoría (sección 3). Sólo-mezcla deja categorías casi vacías. |
| D4 | Chips actuales | Conservarlos sobre las secciones; son «Ver todo» y filtro. Quitarlos es posible más adelante. |
| D5 | Vista anterior | Mantener la lista plana del proveedor como ajuste «Vista de resultados: por categorías / lista». Por categorías por defecto. Costo bajo: el código actual no se borra. |
| D6 | Perfiles y podcasts | Secciones propias («Perfiles», «Podcasts») usando el relleno por chip; no mezclarlos con Artistas/Playlists. **«Listen again»: fuera de la vista por categorías (decidido).** |

## 5. Conflicto con PLAN-016
PLAN-016 eligió «Resultado mixto ordenado» y advirtió que separar en bolsas por tipo «cambia la experiencia y puede alterar la relevancia recibida». Este plan lo hace a pedido del usuario (2026-11-12). Se mitiga con D1 (orden de relevancia), D5 (ajuste para volver a la lista) y conservando el principal. Al implementarlo hay que actualizar PLAN-016 y PAR-042 para que no se contradigan.

## 6. Etapas

- [ ] **Etapa 0 — Evidencia y contrato.** Capturar 8–10 respuestas reales (anónimas, como `search-provider-README.md`): general + una por chip, en consultas de artista, canción, álbum y cola larga. Confirmar cantidad por tipo y cómo distinguir perfil/podcast (subtítulo localizado, prefijo de `browseId` o `pageType`). Si hace falta exponer el tipo desde el parseo, es un cambio **compartido** (core protegido): fix `[Compartido]` y PAR con Windows; si no, se resuelve con el relleno por chip.
- [x] **Etapa 1 — Proyección pura (Swift).** (`ProviderSearchCategories.swift`, 9 pruebas) `SearchCategorySection` + agrupación en rachas conservando orden e identidad de ocurrencia, filtro de videos, exclusión de «Listen again» y del principal. Pruebas con fixtures: duplicados, tipos mezclados, vacíos, continuación.
- [x] **Etapa 2 — ViewModel.** (`SearchViewModel.startCategoryFill`: máx. 3 peticiones simultáneas, cancelación por generación, `categoryView` en `SearchPreferences`, activado por defecto). Sin caché por consulta ni «Reintentar» por sección todavía. Almacén de páginas por categoría, política de prefetch/cancelación/caché/errores (sección 3). Pruebas de generación obsoleta y de límite de concurrencia.
- [x] **Etapa 3 — Vistas.** (carrusel de tarjetas/círculos 252 pt, cuadrícula de canciones 3 filas × 1/2/3 columnas, marcador de carga; alturas constantes verificadas por prueba). Nuevas entradas del viewport: carrusel de círculos, carrusel de tarjetas, fila de cuadrícula de canciones (las columnas dependen de un *bucket* de ancho, no del píxel, para no reconstruir filas al redimensionar). Alturas por constantes con prueba «contenido ≤ altura de fila» por layout/idioma/localización.
- [ ] **Etapa 4 — Ajuste D5 y compatibilidad.** Preferencia de vista, textos ES/EN mediante `Scripts/sync-localizations.mjs`, accesibilidad (foco/teclado por carrusel y cuadrícula), menús contextuales ya existentes.
- [ ] **Etapa 5 — Validación.** Hecha en parte: «kendrick lamar» y una consulta de cola larga con cuenta real en un bundle debug; 1384/960 pt, redimensionar y hacer scroll sin huecos ni solapes (medición por accesibilidad); «Show all» abre el chip. Falta: comparación lado a lado con Apple Music, Videos (el usuario los tiene ocultos en Configuración), Instruments, build numerada. Pruebas focales + suite; revisión con cuenta real en 960/1100/1384 pt, redimensionar **y hacer scroll** (regresión de FIX-331), comparación lado a lado con Apple Music con las mismas consultas (kanye, sudaca, kendrick lamar, una de cola larga); perfil con Instruments (más hosts y carruseles anidados en una tabla nativa).
- [ ] **Etapa 6 — Paridad.** Fila PAR nueva; Windows adopta la proyección en su propio plan. Sin cerrar paridad sin evidencia nativa.

## 7. Riesgos
- **Scroll anidado**: carruseles horizontales dentro de la tabla vertical nativa; revisar los antecedentes de gestos horizontales (`plans/research/QUEUE-HORIZONTAL-SCROLL-2026-10-31.md`, FIX-261) antes de la etapa 3.
- **Más peticiones por consulta** (hasta 1 + 4 al inicio): límites de tasa y consumo; por eso presupuesto, caché y carga diferida.
- **Relevancia**: agrupar puede ocultar un resultado muy relevante tras una categoría poco relevante (D1/D5 lo mitigan).
- **Clasificación por texto localizado** si la etapa 0 no encuentra una señal estable.
- **Duplicados entre mezcla y categoría**: se reemplaza, no se concatena.

## 8. Cierre
Plan terminado cuando: etapas 0–5 marcadas, `swift test --build-system native --package-path apple` sin fallos nuevos, revisión visual aprobada por el usuario y FIXES/PARIDAD/PLAN-016 coherentes. Enlazar fixes y builds aquí al ejecutar.
