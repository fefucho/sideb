# Planes generales

Herramientas compartidas o fixes para ambas plataformas. [Formato](../.agents/WORKFLOW.md#planes). El core conserva su restricción aunque exista un plan.

| Plan | Estado |
|---|---|
| [Release 1.2.1](RELEASE-1.2.1.md) | FIX-199–202; fuentes y verificaciones locales listas, CI nativo/publicación conjunta pendientes |
| [Motor e interfaz de búsqueda](PLAN-008-search-engine-ui.md) | Implementado: sugerencias/correcciones YouTube Music, UI compacta e historial por intención; FIX-178/PAR-027. Mac build-0089 estable, 646 pruebas ejecutadas y Spotlight/Play/reciente comprobados; Windows frontend364/check/build, nativo pendiente. FIX-179 corrige cabecera/fondo Mac, build0090/646 pruebas y página/desplegable/colapso de sidebar nativos comprobados; port visual Windows pendiente. Ranking propio diferido (2026-10-12) |
| [Controles homogéneos en macOS y Windows](PLAN-007-unified-controls.md) | Implementado Apple/Windows: categorías48/acciones40/utilidades32 y fullscreen compacto40; FIX-176 elimina doble bezel del preview rechazado, cuatro focales y clic/arrastre nativo verificados,FIX-177 engrosa bezel Mac28→36 sin cambiar host40, 640pruebas/build-0087 Mac y clic/arrastre normal/compacto verificados;354frontend Windows previas; aceptación en apps completas pendiente, FIX-174/175/176/177 y PAR-030 |
| [Spotlight con recientes y Biblioteca personal](PLAN-005-search-library.md) | Implementado Apple/Windows; recientes por intención, resultados progresivos y Biblioteca personal con categorías recicladas; 635 pruebas Mac/build-0081 y348 frontend Windows aprobadas; FIX-180 alinea acciones de Biblioteca con categorías en Mac, build0091/646 pruebas y revisión nativa aprobadas; port de posición Windows pendiente, FIX-165/166/168/169/172/180, PAR-027/028 |
| [Enlaces a invitados mencionados en títulos](PLAN-006-featured-artist-links.md) | Implementado Apple/Windows; segmentación, destinos automáticos, caché/correcciones e interacción con hover sólo brillo; 635 pruebas Mac/build-0081 y348 frontend Windows aprobadas; aceptación física pendiente, FIX-167/170/171, PAR-029 |
| [Public GitHub README](PLAN-004-public-readme.md) | Published/visually verified; internal guide preserved, About updated; optional native screenshots pending, FIX-154 |
| [1.2.0 — macOS & Windows Feature Parity](RELEASE-1.2.0-beta.1.md) | FIX-162 delivery + FIX-163: same release now tagged v1.2.0 to stop repeated prompts in installed clients; comparator/build-0075 (587 tests) and Rust logic verified, FIX-164 catalog current; original packages unchanged, physical/native Windows recheck pending; PAR-026 |
| [Saludo de Inicio](PLAN-003-home-greeting.md) | FIX-150/156, PAR-003; Windows comprobado, dos pruebas Swift/build Mac aprobadas; aceptación física pendiente |
| [Álbum de Acceso rápido](PLAN-002-quick-access-album-metadata.md) | FIX-148/149/156, PAR-022; pruebas Windows y diez regresiones Swift/build Mac aprobadas; aceptación física pendiente |
| [Historial público y material local](PLAN-001-git-publication.md) | Completado; checkpoints retirados de main/tags y temp excluida, fuentes/releases conservadas |
| [Release 1.1.8](RELEASE-1.1.8.md) | Beta publicada; entonces Latest en GitHub; build-0068, 562 pruebas, ES/EN y descarga/hash verificados |
| [Release 1.1.7](RELEASE-1.1.7.md) | Beta publicada; entonces Latest en GitHub; build-0062, 532 pruebas y descarga/hash remoto verificados |
| [Release 1.1.6](RELEASE-1.1.6.md) | Beta publicada; entonces Latest en GitHub; build-0040 y descarga/hash remoto verificados |
| [Release 1.1.5](RELEASE-1.1.5.md) | Beta publicada; entonces Latest en GitHub; build-0032 y hash remoto verificados |

Los planes previos reunidos en `temp/documentation/plans/` son material local de importación, no compromisos vigentes. Trasladar sólo lo que se retome y verificarlo contra el código.
