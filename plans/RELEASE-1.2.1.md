# Release 1.2.1

- Fecha: 2026-10-17 (America/Montevideo).
- Estado: preparada; CI nativo y publicación pendientes.
- Pedido: publicar una actualización pequeña al terminar FIX-199 y revisar lo completado por Gemini/FIX-200. Autorización explícita de commit, push, tag y release; no instalación ni cambio de datos de cuenta.
- Versión:1.2.1/build14, tag v1.2.1. Continúa beta; el tag numérico evita el aviso repetido de FIX-163. Los actualizadores consultan Latest, por eso se mantiene distribución numérica normal con aviso beta en notas.
- Ámbito: fuentes actuales revisadas de FIX-165–201 para macOS y Windows, incluyendo motor/biblioteca compartidos, TopNav/Spotlight Apple, volumen sólo en carátula/control, descenso reparado y selección/actividad Windows. Core previo compartido conservado; ningún cambio de core nuevo por FIX-199/201/202.
- Entrega: workflow existente con draft y paquetes de ambas plataformas verificados antes de publicación. ZIP portable usa windows minúscula, siguiendo FIX-162 para clientes Mac antiguos. Notas en inglés por convención de releases existentes. Fuentes/paquetes actuales, sin relabel de binaries anteriores.

## Revisión y verificación

- [x] Fetch y revisar remoto, commits salientes y cambios de Gemini. Main local/remoto0f0b343 al iniciar; ninguna reescritura ni checkpoint saliente.
- [x] Reproducir/corregir descenso Mac y conservar build0130 con747 pruebas, firma/hashes/fuentes estables. 62 focales de navegación/volumen aprobadas; QA física diferida.
- [x] Corregir fallo restante de duplicados/shuffle/foco Windows tras FIX-200. 381 frontend/una omitida, check0/0 y build frontend aprobados;45 pruebas del módulo queue.rs real en harness Mac. Tauri/WebView2 se verifican en host Windows.
- [x] Elegir versiones/notas/paquetes y aprobar preflight real. Pruebas runner/release detectan una fixture de packaging desactualizada: faltaba preflight de localización y bundle de recursos. Fixture completada sin cambiar guardas de producto; 17 pruebas finales aprobadas;741 claves de localización verificadas.
- [x] Revisar rutas y patrones de secretos. .cache y prototipos suspendidos quedan fuera de Git; fixtures de proveedores son anónimas/sanitizadas. Coincidencia de cookie en lib.rs corresponde a tres fixtures sintéticas históricas. Bindings UniFFI conservados tal cual generados; sus espacios finales se documentan sin editar generación manualmente.
- [x] Commit b07ace912d34906a805fe99d2c24ab8c63d060f3:210 rutas explícitas de fuentes/tests/fixtures/planes/fixes/notas; artefactos, .cache y prototipos suspendidos fuera.
- [x] Push main y dispatch manual [run39069262028](https://github.com/fefucho/sideb/actions/runs/39069262028) al commit b07ace9; preflight aprobado, tag/draft v1.2.1 verificados en esa revisión. Publicada1.2.0 conservada.
- [ ] Aprobar build/test native de ambas plataformas, checksums y publicación conjunta.
- [ ] Verificar Latest/tag/versión, descargas y digests; cerrar registros con enlaces y límites físicos.

## Límites

La app Mac no se abre por la revisión física diferida. Los tests no certifican audio audible, cuenta real, fluidez ni instalación/actualización interactiva. Mac ad hoc sin notarización; Windows con WebView2/libmpv. No se elimina material local ni se altera el historial público existente.

## Compilación hospedada

Run39069262028 iniciado2026-10-17T21:02:42Z; preparación aprobada y ambos trabajos nativos en ejecución. GitHub redirige el nombre histórico del repositorio a fefucho/sideb; no se cambian remotes ni identidad de actualizadores por este movimiento. El commit incluye [skip ci] para evitar duplicar las builds de push; dispatch de release ejecuta su verificación completa. Resultado/paquetes pendientes.

### Primer intento: fallo de fixture Windows

Windows llega a frontend check0/0 y suite con379 aprobadas/3 fallos (382 totales, sin omisiones en host destino). Fallan sólo playlists/albums/artists en presentación lista: la fixture detecta un sufijo de ruta POSIX y no siembra la preferencia en Windows. FIX-203 usa path.join igual que la carga; ocho focales SSR aprobadas en Mac, aserciones visuales intactas. No se cambia producto ni se declara verificado Windows hasta repetir CI. Mac sigue en ejecución; publicación conjunta queda bloqueada y Latest1.2.0 permanece intacta. Se reemplazará únicamente el borrador vacío/tag no publicado de este intento para la revisión corregida; los runs/diagnósticos se conservan.

Reintento: commit e2c6169a9c75c494cd4ec422b3e1bd7a5945be9a subido; [run39069529111](https://github.com/fefucho/sideb/actions/runs/39069529111) despachado para v1.2.1. Se comprobó que el borrador anterior era propio, vacío y no publicado antes de reemplazar borrador/tag de ese intento. Referencias de releases publicadas intactas; el reintento espera el grupo de concurrencia existente.

Se cancela el run obsoleto39069262028 después del fallo Windows, para liberar el grupo y permitir la verificación corregida de ambas plataformas. CI Mac de ese intento no se presenta como aprobada; build local0130 mantiene su evidencia747. Los diagnósticos Windows y el historial de Actions se conservan.

Run corregido39069529111: preparación aprobada; draft vacío y tag v1.2.1 apuntan a e2c6169a9c75c494cd4ec422b3e1bd7a5945be9a. Ambos jobs iniciados. El log del Mac cancelado confirma188 pruebas Rust aprobadas y XCFramework terminado antes de interrumpir compilación Swift; no se confunde con el resultado final pendiente.

### Segundo intento: pruebas nativas

Run39069529111: Windows aprueba382 frontend/check/build,97 InnerTube+91 core+93 bridge (14 live ignoradas) y tres pruebas puras player. La prueba real libmpv termina con acceso inválido0xc0000005; no se omite ni se declara audio aprobado. Mac compila y ejecuta222 XCTest/344 Swift Testing, pero falla cuatro aserciones de viewport y dos de redondeo nativo. FIX-204 corrige ambos supuestos de fixture; cinco focales locales aprobadas sin cambiar producto.

Investigación libmpv: workflow diagnóstico manual en copia temporal de player; primer intento39070618224 falló antes de ejecutar por ejemplo ausente en la copia, corregido. Run39070749039 aprueba original serial instrumentado y variante con vida útil retenida (4+20 ejecuciones). No reproduce aún la caída original ni permite atribuirla definitivamente al teardown. Un tercer diagnóstico retiene el receptor tras soltar Player para comprobar esa vida útil; fuentes productivas core sin cambios durante investigación.

### Vida útil nativa detectada durante investigación — FIX-205

El diagnóstico39070910401 aprueba ambas variantes con receptor retenido; no confirma por sí solo el origen del acceso inválido. La inspección comprueba que EventContext usa el raw handle sin dueño. Bajo el pedido explícito de reparar lo necesario para terminar la entrega, se acota una excepción al wrapper Rust nativo: Arc retenido por worker y fin acotado al cerrar receptor, sin cambios a proveedor/ABI/curva/AVPlayer. Nueva regresión nativa verifica ambas condiciones. Workflow focal comprueba roja en copia sin dueño y5 tests exactos/20 repeticiones de producción antes de volver a release completa.
