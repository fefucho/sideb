> Archivo histórico del port Windows. El flujo vigente está en [windows/README.md](../../../../windows/README.md).

# W21 — Cuenta y Biblioteca Windows

Fecha: 2026-09-30. Estado: integrado; paridad completa todavía parcial. Plan: [PLAN-017](../plans/PLAN-017-windows-cuenta-biblioteca.md).

## Trabajo

Tres agentes GPT-6 Luna: backend/DTOs, Biblioteca y playlist, sidebar/reproductor. Codex integró controller, navegación, historial y reproducción. Se detectó otro chat activo en la misma carpeta; con autorización del usuario se acordó propiedad por archivos en [W21-coordination](W21-coordination.md). Se conservaron Inicio paginado y detalles de álbum/artista de ese chat.

- Biblioteca real: Canciones, Playlists, Álbumes, Artistas; estados de carga, vacío, error y sesión invitada.
- Tus Me Gusta usa LM; lectura de todas sus páginas para conocer likes de canciones antiguas. La UI publica los IDs progresivamente. Continuación manual de playlists/canciones con reintento y protección frente a tokens repetidos.
- Perfil y listas reales de sidebar, abrir playlist/álbum/artista, historial por día. Navegar conserva audio y cola.
- Corazón compartido entre tablas y barra; rate_song LIKE/INDIFFERENT. Guardar canción usa feedback token específico y está separado de Me Gusta. Album/playlist guardado y seguir artista refrescan la colección correspondiente.
- Crear playlist privada con diálogo nativo, foco, Escape y error real. Edición/eliminación y privacidad editable no incluidas aún.
- Backend serializa cuenta con login/logout y valida generación; respuestas viejas no actualizan nueva sesión. Controller invalida pendientes al salir o recargar la vista. Tokens sólo en memoria.
- Reproducción de una fila genera cola de canciones cargadas con identidad por ocurrencia. Se corrigió índice de playCollection cuando el video se repite. Se corrigió ancho de transporte de la barra (44 → 102): tres botones se solapaban con portada.
- Medidas Mac: título32, horizontal32, extra trailing110 cabecera Biblioteca; cuadrícula adaptable160–220, gaps18/24, portada radio10/círculo artista, fila52, playlist180/gap24, reserva inferior130. Se corrigió cuadrícula CSS que elegía columnas usando220 en vez160 y agrandaba portadas.

## Verificación

- `corepack pnpm check` desde windows: 0 errores, 0 avisos.
- `corepack pnpm build`: aprobado.
- `node --test scripts/account-controller.test.mjs`: 6/6, respuestas de sesión vieja, error/doble mutation, feedback independiente de rating, retry/token repetido/ocurrencias, éxito de mutation viejo y like retirado durante hidratación.
- `cargo build --manifest-path src-tauri/Cargo.toml` con VS2022 x64 y SIDEB_MPV_DIR: aprobado (1m57s). Avisos del core/linker existentes, sin cambios en core/Apple.
- App real, sesión restaurada: sidebar con playlists, canciones guardadas, álbumes, artistas con fotos y playlists con tarjetas cargan. Historial carga por día. LM muestra 100 canciones iniciales y metadata total del proveedor. No publicar identificadores/datos personales de cuenta en el informe.
- Diálogo nueva playlist abre, enfoca Nombre y cierra con Escape restaurando foco; no se envió una creación de prueba.
- Reproducción desde LM: tiempo avanzó y portada/título/corazón visible. Navegar/recargar frontend conserva snapshot de backend. Tras corregir transporte, siguiente cambió título/portada. Audibilidad física no se volvió a medir en esta entrega (usuario la confirmó previamente).

## Pendientes explícitos

- Las mutaciones reales de likes/guardados/crear playlist no se ejecutaron sobre la cuenta sólo para probar; tests locales validan consistencia, no respuesta final del proveedor a cada mutation.
- Comparación visual lado a lado con captura macOS del mismo escenario, DPI/ventana estrecha y recorrido completo de teclado pendientes. Geometría tomada del código Mac; no afirmar UI idéntica por build.
- Edición/eliminación de playlist, agregar canciones a playlist, menús completos, dislike y autocompletar cola desde continuación al llegar a última canción cargada pendientes; continuación manual funciona por command y tests locales, no recorrido de1997 canciones en app.
- Historial se muestra con tablas por grupo; Mac usa tabla única seccionada. Puede consolidarse sin cambiar datos.
- Tests de logout/cambio real de cuenta pendientes para conservar sesión del usuario; protección validada con mocks y guards Rust.

## Archivos

`windows/src-tauri/src/lib.rs`, `windows/src/lib/types.ts`, `account/controller.ts`, `account/types.ts`, `components/library/{LibraryView,AccountTrackTable,HistoryView}.svelte`, `detail/PlaylistDetailView.svelte`, `sidebar/Sidebar.svelte`, `player/PlayerBar.svelte`, `routes/+page.svelte`, `scripts/account-controller.test.mjs`.
