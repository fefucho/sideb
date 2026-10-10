# Idioma de la app Windows

Los 688 textos compartidos se generan directamente de `apple/Localization/fragments/`; `catalog.json` no se edita a mano. `windows.json` contiene sólo claves `windows.*` para funciones específicas del destino. Español con voseo; conservar el glosario editorial Apple (lista de reproducción/lista, Ahora suena, Acceso rápido, reproducción aleatoria).

Desde la raíz: `node windows/scripts/sync-localizations.mjs` para actualizar y `--check` para comprobar ambos idiomas, argumentos y plurales. La suite frontend ejecuta la comprobación. Vite incluye ambos JSON mediante imports estáticos, sin depender del filesystem de la máquina de desarrollo.

Svelte importa `t`, `language` y `setLanguage` desde `$lib/i18n` y usa `$t('common.cancel')`. Los plurales se resuelven con `count('common.songCount', cantidad, $language)`. La preferencia `sideb.ui.language.v1` pertenece a la instalación, con español predeterminado/respaldo; no cambia cuenta, rankings, consultas ni reproducción. Si el almacenamiento está deshabilitado, la preferencia sigue funcionando en la sesión.

Guardar errores nuevos como `message(clave, argumentos)` y resolverlos al presentar con `resolveMessage(descriptor, $language)`. El adaptador `translateOwnText` sólo se aplica a etiquetas/errores anteriores de la app; nunca a nombres, títulos, letras, descripciones o notas externas. Encabezados del proveedor conocidos se clasifican por el original y después se traducen mediante `providerHeading`.

Cambiar idioma no introduce claves de identidad, reinicios de controladores, consultas ni limpieza de cachés. No usar idioma en bloques `{#key}`, estados de reproducción ni parámetros de red. La comprobación automática no acredita Narrator, audio ni gestos físicos.
