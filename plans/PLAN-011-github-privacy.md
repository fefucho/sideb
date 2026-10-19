# Privacidad del historial público y exclusión de cachés

- Fecha: 2026-10-19 (America/Montevideo).
- Estado: completado; ramas/tags publicados y verificados, caché excluida y protecciones activadas; copias históricas de PR/Actions fuera de la purga.
- Objetivo: reemplazar el Gmail personal de autoría por la dirección noreply de GitHub, excluir la caché local y habilitar detección/bloqueo de secretos.
- Ámbito: metadatos de commits/taggers de las cuatro ramas y veinte tags públicos; `.gitignore`, documentación de cierre y configuración de seguridad de GitHub. Capturas, fuentes, contenido de releases y datos locales conservados.
- Referencias: [FIX-227](../FIXES.md#fix-227), [FIX-130](../FIXES.md#fix-130), [publicación anterior](PLAN-001-git-publication.md).

## Pasos y comprobaciones

- [x] Respaldar referencias públicas y repositorio local completo, parches e inventarios de los tres worktrees fuera del repositorio publicable.
- [x] Sustituir únicamente el correo personal identificado por la dirección noreply del mismo autor con git-filter-repo. Conservar nombres, fechas, mensajes y topología.
- [x] Comparar el árbol de cada uno de los 103 commits públicos y de los 20 tags: todos idénticos; 54 campos de autor/committer reemplazados. Las firmas de dos commits anteriores no sobreviven a la reescritura.
- [x] Excluir `/.cache/`; verificar que no existe contenido de esa carpeta en las ramas/tags públicos. La caché permanece en disco.
- [x] Activar y releer `secret_scanning` y `secret_scanning_push_protection`: ambos enabled; sin alertas de secretos al consultar.
- [x] Publicar únicamente las cuatro ramas y veinte tags con actualización atómica y leases sobre sus SHA anteriores, preservando las releases existentes.
- [x] Verificar referencias, árboles de tags, IDs/digests de assets, protecciones y ausencia del correo en las referencias públicas actualizadas.
- [x] Sincronizar las referencias de los worktrees locales con sus equivalentes de árbol idéntico sin reset/stash ni pérdida de cambios; aplicar exclusión y cierre documental a la copia de trabajo principal.

## Límites

Se verificó que las referencias `refs/pull/1/head` y `refs/pull/2/head` conservan la historia anterior; son de solo lectura para pushes. GitHub también puede conservar commits anteriores por SHA y en metadatos de ejecuciones antiguas. Esta operación no afirma purgar esas copias, otros clones ni el historial de Actions. Las capturas de Home muestran perfil/colección y la documentación conserva algunas rutas personales; no contienen credenciales y no se alteran en este pedido. Los respaldos externos conservan deliberadamente el estado original y no deben publicarse. No se recompila ni se publica una nueva release.

La comparación remota conserva las 16 releases y sus 45 assets (IDs, tamaños, digests y fechas). El workflow de releases se deshabilitó sólo durante la actualización de tags y se restauró a active. Los parches e índices de los tres worktrees se comprobaron idénticos antes/después de sincronizar sus referencias; los datos de usuario y cachés permanecen en disco.
