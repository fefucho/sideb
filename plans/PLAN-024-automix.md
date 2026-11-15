# PLAN-024 — Automix: transiciones automáticas con stems

- Fecha: 2026-11-15 (America/Montevideo).
- Estado: experimento. Existe un banco de pruebas por línea de comandos; nada integrado a las apps ni al core.
- Rama / carpeta: `feature/automix-lab` (`sideb-wt-automix-lab/`), código en [`labs/automix-lab/`](../labs/automix-lab/README.md).
- Objetivo: que Side B una dos canciones como lo haría un DJ (tempos sincronizados, entrada en compás, cambio de bajo, una sola voz a la vez) en vez de un crossfade.

## Idea central

La transición no se mezcla en vivo: se renderiza por adelantado mientras suena la canción actual y se reproduce como un archivo más, empalmado entre las dos canciones. Eso permite separar stems sólo del final de una canción y el principio de la otra, y en el futuro renderizar varias candidatas y elegir la mejor.

## Alcance y exclusiones

Incluye por ahora: banco de pruebas (`labs/automix-lab`), que baja audio de YouTube Music de forma anónima con el crate `innertube` y escribe un WAV con la transición y otro con un crossfade común para comparar.

Excluye por ahora: cambios en `core/`, en el reproductor (AVPlayer en Mac, libmpv en Windows) y en cualquier UI. El banco no usa la cuenta ni las cookies de la app.

## Referencias

- [BitChord](https://github.com/kushagrasinghx/BitChord) (GPL-3; su analizador viene de [Orchard](https://github.com/SFG5453/Orchard), AGPL-3): cliente con automix. Mezcla en vivo y cae a crossfade simple casi siempre; sirve como referencia de diseño de la escalera de confianza.
- [Mosaikbox](https://repositum.tuwien.at/bitstream/20.500.12708/212628/1/Sowula-2024-Mosaikbox%20Improving%20Fully%20Automatic%20DJ%20Mixing%20Through%20Rule-ba...-vor.pdf): mezcla automática con reglas sobre stems.
- [Post de Len Vande Veire](https://lenvdv.github.io/2018-03-20-autodj): pipeline completo de un auto-DJ.

## Pasos

- [x] Banco de pruebas: carga, grilla de beats local, time-stretch con mapa de tiempo, stems (HT-Demucs), plantilla «cambio de bajo», crossfade de comparación.
- [x] Pruebas automáticas con pistas sintéticas: tempo y primer tiempo recuperados; beats de ambas canciones alineados durante toda la mezcla; bordes idénticos al original.
- [x] Descarga desde YouTube Music por búsqueda, id o URL.
- [ ] Escucha del usuario con pares reales variados; anotar qué falla (primer tiempo mal detectado, entrada en mal lugar, choque de tonalidad).
- [ ] Elegir dónde entra B (primer momento fuerte) y dónde sale A por estructura, no sólo por fin del audio.
- [ ] Tonalidad: detectar compatibilidad y, si conviene, transponer B durante la mezcla.
- [ ] Más plantillas (puente de batería, salida con eco para tempos incompatibles) y elección por puntaje entre candidatas.
- [ ] Medir y bajar el costo de stems (hoy cerca de 1× tiempo real por ventana en un M1 Pro, sin aceleración).
- [ ] Prueba de empalme sin clic en AVPlayer y libmpv: canción A hasta el corte, archivo de transición, canción B desde su punto de entrada.
- [ ] Decidir integración (dónde vive el motor, caché de análisis, comportamiento con álbumes y playlists ordenadas).

## Comprobaciones

`cargo test --manifest-path labs/automix-lab/Cargo.toml`: 4 pruebas aprobadas (2026-11-15). Un render real completo (Daft Punk, «One More Time» → «Around the World», 16 compases) terminó sin errores; **su calidad sonora no está evaluada**: falta la escucha.

## Límites conocidos

- El primer tiempo del compás se decide con una heurística (cambio de armonía); puede errar por 1 a 3 beats. El banco permite corregirlo a mano con `--a-downbeat` / `--b-downbeat`.
- Sólo funciona con tempo estable y tempos a menos de 18% entre sí; fuera de eso se niega a mezclar.
- Los umbrales de confianza están calibrados con muy poco material.
