> Archivo histórico del port Windows. El flujo vigente está en [windows/README.md](../../../../windows/README.md).

# W10a — Inicio: composición según macOS

**Fecha:** 2026-09-30. **Estado:** implementación integrada; validación visual parcial.

## Trabajo y reparto

Tres subagentes **GPT-6 Luna** trabajaron en archivos separados: HomeView; estantes/tarjetas; presentación/tokens/layout. Codex integró la página, revisó el resultado y corrigió diferencias de composición. No se modificó Rust, Apple, sesión ni el transporte de reproducción.

### Archivos

- `windows/src/routes/+page.svelte`: integra HomeView con datos/callbacks reales; retira markup y CSS del Inicio anterior; quita la cabecera central del prototipo únicamente en Inicio; usa todo el ancho útil y mantiene errores de backend.
- `windows/src/routes/+layout.svelte`: carga tokens comunes.
- `windows/src/lib/styles/tokens.css`: medidas y colores del sistema visual.
- `windows/src/lib/home/presentation.ts`: orden de secciones, formato y claves por ocurrencia.
- `windows/src/lib/components/home/HomeView.svelte`: cabecera, chips, estados y feed.
- `windows/src/lib/components/home/HomeShelf.svelte`: estantes y cuatro filas compactas por columna.
- `windows/src/lib/components/home/HomeCard.svelte`: tarjeta grande, tipos traducidos, metadata y fallback.
- `windows/src/lib/components/home/CompactSongCard.svelte`: fila compacta con reproducción real.

## Revisión de integración

- Márgenes laterales 28, cabecera 24/12, título 27, chips 42, portada 160/140 según ancho del contenido.
- Compactas 330/286 × 56; portada 44 con inset 6; cuatro filas en orden vertical antes de la siguiente columna.
- Región de texto grande 94, título 14/18 hasta dos líneas, metadata 12/16 a 3 de la última línea visible.
- Fuente de estante 19 bold y separación efectiva 24, contrastadas con los componentes AppKit activos.
- Se corrigió el espacio duplicado entre estantes, el alto del carril y el ancho de columnas bajo el breakpoint, y etiquetas redundantes como «Álbum · Album · artista».
- Fallback se reinicia al cambiar URL; IDs vacíos no generan acciones. No se añadieron botones sin acción real.

## Comprobaciones efectivas

| Comprobación | Resultado |
| --- | --- |
| `corepack pnpm check` desde `windows/` | Aprobó: 0 errores, 0 advertencias. |
| `corepack pnpm build` desde `windows/` | Aprobó; salida estática en `windows/build`. |
| Prueba dirigida con Node `--experimental-strip-types --input-type=module` | Aprobó: prioridades/acentos, orden del proveedor con chip, variantes, vacías y claves únicas para secciones/canciones repetidas. |
| Side B real con Vite en 1420 | Inicio cargó contenido de la sesión existente; cabecera/tarjetas/compactas visibles. |
| Tarjeta Blonde → detalle de álbum | Abrió y cargó el detalle real y sus 17 pistas. |
| Sidebar contraída | Se observó Inicio ocupando el ancho disponible y barra flotante presente. |
| Cambios Rust / build Rust | No necesarios; no hubo cambios en el puente. |

Las capturas se mostraron en el chat. No se guardaron imágenes de cuenta como artefactos compartidos. El build web provocó recarga del entorno de desarrollo; esa recarga no es una prueba de restauración de navegación.

## Pendientes y límites

- El intento de redimensionar no produjo una prueba fiable del ancho estrecho. Alt+Espacio abrió el lanzador de Windows; el usuario lo cerró. Se recuperó Side B y se cerró su menú de tamaño. **No se declara validado el breakpoint en runtime.**
- La comparación Mac fue por código y medidas; no se dispuso de captura Mac equivalente ni se probaron distintos DPI.
- No se probaron en esta entrega foco por teclado, imagen fallida, vacío/error forzado ni audibilidad física. W13 mantiene su verificación manual pendiente.
- Artista, playlist, «Ver más», flechas de estante, explicit y continuación se entregan en W10b/W10c y sus dependencias. Playlist/artista siguen informativos en Inicio; canción y álbum usan acciones existentes.
- Se usa el ejecutable debug existente con `devUrl`: Vite debe permanecer activo. Esto no es un paquete autónomo de distribución.

## Incidencia de una comprobación

Una llamada a `corepack pnpm check` se emitió desde la raíz del checkout en lugar de `windows/`. Encontró un `package.json` preexistente en `C:\Users\Stefa` y generó archivos pnpm/dependencias allí; no era el check del proyecto y no se cuenta como prueba aprobada. El intento de eliminar esos archivos fue rechazado automáticamente. Para recuperar la carpeta sin borrar contenido, se verificaron las rutas y las fechas de creación y se trasladaron exclusivamente los archivos nuevos a `scratch/w10a/accidental-pnpm/`, incluidas sus 24 envolturas de comandos nuevas. El `package.json` preexistente se preservó. Los artefactos quedan recuperables en esa carpeta. Las verificaciones del proyecto se ejecutaron después desde `windows/`.

## Siguiente entrega

Completar la comprobación estrecha y continuar con **W10b**: metadata completa, acciones, indicadores de reproducción y navegación. No marcar Inicio con paridad funcional total por esta entrega.
