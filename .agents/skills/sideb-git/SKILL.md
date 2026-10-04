---
name: sideb-git
description: Guardar cambios de Side B en un commit o subir/sincronizar el código compartido cuando el usuario lo pida. Usar para guardar en Git, commit o push; no para publicar releases.
---

# Guardar y subir código

Leer README y AGENTS. Revisar status, rama, remote, diff y staged; identificar lo que el usuario pide guardar. Conservar cambios previos y evitar `git add .`/`git add -A` indiscriminados. «Guardar todo» puede incluirlos, tras revisar el conjunto concreto.

Comprobar el registro único `FIXES.md`: ID, tag de ámbito, antecedentes, explicación del cambio y verificación; también evaluación de paridad y plan si existe. Seleccionar rutas explícitas, revisar `git diff --cached --check` y el diff staged, y crear el commit incluyendo los IDs FIX correspondientes en el mensaje para poder localizarlo por antecedente. No incluir builds, secretos, datos locales o toda `temp/` por comodidad. Revisar también eliminaciones/movimientos documentales.

«Guardar» autoriza commit local; «subir a Git»/«push» incluye envío al remote. Aprovechar autorización existente sin repetir confirmaciones. Si sólo se pidió guardar, informar que el commit sigue local.

Ambas plataformas convergen en `main`. Antes de subir, fetch y revisión de `origin/main`. Integrar ramas temporales conservando commits ajenos, sin reset, stash automático ni force push. Si un conflicto necesita una decisión no inferible del contrato/código, dejar el estado concreto y pedir esa decisión.

Con cambios commiteados y árbol limpio usar `bash Scripts/sync.sh push` en Mac/Git Bash o `powershell -NoProfile -File Scripts/sync.ps1 -Action push` en Windows. Suben la rama actual: comprobar `main`; no integran ramas por sí solos. Si hay otros cambios sin guardar, conservarlos y usar push explícito de commits autorizados tras verificar rama/remote; no guardarlos sólo para satisfacer el script.

No usar `release_update.sh`: cambia versión, crea tags y publica. Releases/tags/force push requieren un pedido específico. Informar commit, rama, destino y resultado real; un push fallido no borra el commit local.
