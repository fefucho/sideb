# Historial público y material local

- Fecha: 2026-10-08 (America/Montevideo).
- Estado: completado; historial limpio publicado y verificado en GitHub.
- Objetivo: retirar los cuatro commits de checkpoint del historial publicado, conservar el código actual y excluir `temp/` de futuras subidas.
- Ámbito: `main`, los tags de las releases 1.1.5/1.1.6/1.1.7 y las reglas/documentación de publicación. Fuentes, binarios y assets de releases conservados. Ramas remotas que no contienen checkpoints fuera del cambio.
- Referencias: [FIX-130](../FIXES.md#fix-130), [skill Git](../.agents/skills/sideb-git/SKILL.md).

## Pasos y evidencia

- [x] Revisar estado local y remoto: `main` coincide con `origin/main`; sólo `temp/` estaba sin versionar. Sin PR abiertos.
- [x] Guardar un bundle recuperable de todas las referencias locales y un inventario de referencias remotas/releases fuera del repositorio. Conservar `temp/` intacta en disco.
- [x] Auditar rutas de todas las ramas y tags publicados: sin `temp/`, builds/dependencias compiladas, bases de datos, archivos de credenciales o logs locales.
- [x] Escanear el historial publicado con Gitleaks 8.30.1: 65 commits, cero hallazgos. Revisar adicionalmente 1044 blobs de texto para claves privadas, URLs firmadas, cookies y bearer tokens. Las coincidencias de cookies son identificadores de bindings y valores sintéticos de pruebas SQLite.
- [x] Excluir `/temp/` mediante `.gitignore` y exigir revisión de todos los commits salientes en la skill Git.
- [x] Consolidar los tres checkpoints anteriores a 1.1.5 en su commit de release y el checkpoint de Explorar en el commit de 1.1.7. Conservar los demás cambios y sus autores.
- [x] Verificar igualdad exacta de los árboles de los tres tags respecto de sus versiones publicadas; el tip consolidado tiene el mismo árbol que el `main` anterior. El cambio nuevo sólo agrega la higiene/documentación autorizada y `git diff --check` aprueba.
- [x] Publicar `main` y los tres tags de forma atómica, con leases contra los SHA remotos inventariados. Se conservaron los mensajes `[skip ci]`; sin nueva compilación/publicación de binarios.
- [x] Verificar todas las referencias remotas: sólo cambiaron `main` y los tres tags previstos, sin checkpoints alcanzables. `temp/` permanece ignorada y sus 118 archivos conservan tamaño/fecha de modificación. Las ocho releases mantienen IDs, metadata y assets (IDs, tamaños, digests y fechas), sin cambios.

La revisión final compara todas las fuentes de la app por identidad de blobs, valida los árboles exactos de los tres tags y vuelve a escanear el historial preparado: cero hallazgos de Gitleaks. Los informes redactados y la correspondencia entre commits originales/consolidados permanecen fuera del repositorio.

## Límites

La auditoría no demuestra ausencia absoluta de todo dato sensible. El cambio retira los checkpoints del historial alcanzable por las ramas y tags publicados; GitHub puede conservar objetos anteriores accesibles por SHA y otros clones pueden conservarlos. No se eliminan builds, snapshots ni datos locales. Los SHA anteriores en las bitácoras siguen siendo referencias históricas de la evidencia original, recuperable desde el bundle local. No se recompila la app: se compara la identidad de sus blobs y los árboles de las releases.
