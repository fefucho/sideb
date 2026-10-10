# Planes generales

Herramientas compartidas o fixes para ambas plataformas. [Formato](../.agents/WORKFLOW.md#planes). El core conserva su restricción aunque exista un plan.

| Plan | Estado |
|---|---|
| [Public GitHub README](PLAN-004-public-readme.md) | Published/visually verified; internal guide preserved, About updated; optional native screenshots pending, FIX-154 |
| [1.2.0 — macOS & Windows Feature Parity](RELEASE-1.2.0-beta.1.md) | FIX-162: existing release now has Mac build-0074 (584 tests), Windows CI packages (646 tests), checksums/provenance and verified remote digests; beta-tag comparison and physical acceptance pending; PAR-026 |
| [Saludo de Inicio](PLAN-003-home-greeting.md) | FIX-150/156, PAR-003; Windows comprobado, dos pruebas Swift/build Mac aprobadas; aceptación física pendiente |
| [Álbum de Acceso rápido](PLAN-002-quick-access-album-metadata.md) | FIX-148/149/156, PAR-022; pruebas Windows y diez regresiones Swift/build Mac aprobadas; aceptación física pendiente |
| [Historial público y material local](PLAN-001-git-publication.md) | Completado; checkpoints retirados de main/tags y temp excluida, fuentes/releases conservadas |
| [Release 1.1.8](RELEASE-1.1.8.md) | Beta publicada; entonces Latest en GitHub; build-0068, 562 pruebas, ES/EN y descarga/hash verificados |
| [Release 1.1.7](RELEASE-1.1.7.md) | Beta publicada; entonces Latest en GitHub; build-0062, 532 pruebas y descarga/hash remoto verificados |
| [Release 1.1.6](RELEASE-1.1.6.md) | Beta publicada; entonces Latest en GitHub; build-0040 y descarga/hash remoto verificados |
| [Release 1.1.5](RELEASE-1.1.5.md) | Beta publicada; entonces Latest en GitHub; build-0032 y hash remoto verificados |

Los planes previos reunidos en `temp/documentation/plans/` son material local de importación, no compromisos vigentes. Trasladar sólo lo que se retome y verificarlo contra el código.
