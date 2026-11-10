# PLAN-020 — LyricsPlus primero y fuente por canción

Estado: implementado en fuentes; verificación nativa pendiente por pedido «no compiles».
Objetivo: LyricsPlus → Boidu → resto, calidad palabra > línea > plano, selección manual sin fallback.
Ámbito: core compartido, menús/controladores de letras Mac y Windows; no sidebar, builds, LRC.red/KRC ni romanización.

- [x] Priorizar LyricsPlus y conservar resultados inferiores mientras se buscan palabras.
- [x] Selector por canción: Automático, LyricsPlus, Boidu, LRCLIB, Netease, QQ, Kugou.
- [x] Usar preferencias existentes `lyrics_source:<videoId>` en core; contrato UniFFI intacto. Clientes conservan selección local y la transmiten antes de resolver; Tauri agrega argumento opcional source.
- [x] Separar caché manual/auto, v6 detallada y v2 clásica para revalidar antiguos aciertos permanentes.
- [x] Limpiar documento al cambiar fuente y descartar respuestas obsoletas; ausencia manual explícita, error de red separado.
- [x] Tests frontend focales y diagnóstico Svelte sin build.
- [ ] Ejecutar pruebas Rust y Swift preparadas, verificar ambas apps con binarios nuevos cuando se autorice compilar.

Límites: YT timed sigue en cadena clásica y caché de fallback detallada. Selector no ofrece YT todavía. No se agregó control global de frecuencia LyricsPlus. No se revalidaron proveedores en vivo.
Referencia: FIX-276 / PAR-047. Preservados cambios de sidebar y LyricsPlus anteriores.
