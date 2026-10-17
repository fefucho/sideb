# Release 1.2.1

- Fecha: 2026-10-17 (America/Montevideo).
- Estado: entregada; v1.2.1 publicada como Latest con seis assets verificados. Mac build-0131 de1c0b2f4 y Windows CI39071362949 de c123b59; procedencia pública por plataforma.
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
- [x] Aprobar build/test native de ambas plataformas, checksums y publicación conjunta:747 pruebas Mac build-0131 y761 ejecuciones Windows CI; detalles bajo FIX-206. El workflow original permanece fallido por el formato de bindings; entrega recuperada con nueva build Mac validada y paquetes Windows originales verificados.
- [x] Verificar Latest/tag/versión, descargas y digests; seis descargas públicas idénticas a staging, registros cerrados con enlaces y límites físicos.

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

### Regresión de vida útil y tercer intento de release

Run39071204981 reproduce la regresión nueva en la copia sin Arc: native_handle_outlives_player_until_event_receiver_closes falla con «the live event stream must retain its native handle», exit101. El paso negativo requería reconocer ese exit esperado en pwsh; corregido sin alterar aserción. [Run focal39071355691](https://github.com/fefucho/sideb/actions/runs/39071355691) verifica la producción5 tests/20 repeticiones. [Release39071362949](https://github.com/fefucho/sideb/actions/runs/39071362949) se despacha al commit c123b59678b2538c9d3c2e155f366f7905c67d97, con FIX-204/205. Se reemplaza sólo el segundo borrador vacío/tag no publicado tras finalizar ese run fallido; Latest1.2.0 no se modifica. Resultados finales pendientes.

Run focal39071355691 aprobado: la copia sin dueño falla con0xc0000005/STATUS_ACCESS_VIOLATION (la ejecución anterior39071204981 había fallado con aserción/exit101) y el producto actual aprueba5 tests más20 repeticiones completas:105 ejecuciones aprobadas con libmpv real, sin omisiones ni cambio de condiciones de release. No se afirma que esto pruebe audio audible ni que reproduzca determinísticamente el acceso inválido inicial.

### Cierre del tercer intento y recuperación de entrega — FIX-206

Run39071362949 terminó con Windows aprobado (32min, incluyendo23min33 de verificación/build y6min11 de caché); artefactos release-windows12116106628 y diagnósticos12116445077 conservados. Mac aprueba Rust/Swift, compila y firma, pero rechaza la entrega por cambios del binding Swift generado. Publicación conjunta omitida; v1.2.1 sigue como borrador vacío y Latest1.2.0 permanece publicada.

La imagen hospedada incluye SwiftFormat0.63.1; UniFFI0.28.3 lo ejecuta automáticamente y este Mac no lo tiene. FIX-206 fija `--no-format` sin cambiar código Rust ni los bindings versionados. Pedido actual: reparar Mac y completar la subida; optimización de caché diferida. Se verificará generación real con formateador presente/ausente, se compilará Mac mediante el runner numerado y se recuperarán los paquetes Windows aprobados tras comparar íntegramente sus fuentes/dependencias con el commit de origen. Se conservará procedencia por plataforma y hashes públicos. No se reutilizará un paquete con fuentes Windows/core divergentes.

- [x] Aprobar la regresión de generación independiente de SwiftFormat y los checks de release: UniFFI real con formateador simulado reproduce cambio en modo automático; `--no-format` conserva exactamente el binding versionado.17 pruebas runner/release, preflight y shell/diffcheck aprobados.
- [x] Guardar/subir FIX-206 (1c0b2f4831e345a2cef6bc8258ef95f8193c2d6e) y producir Mac build-0131:747 pruebas aprobadas, compiled/sourceChangedDuringBuild=false, versión1.2.1/build14, arm64/mínimo15, diez hashes y firma deep/strict correctos antes/después de extraer ZIP.
- [x] Recuperar y verificar Windows run39071362949:382frontend+97InnerTube+91core+93core/bridge+5player+93Tauri=761 ejecuciones aprobadas;14live ignoradas. Check0/0, hashes instalador/portable y cuatro runtimes internos verificados. Comparación Git de Windows/core/version.env/scripts de build/release/workflow sin diferencias entre c123b59 y1c0b2f4.
- [x] Publicar ambos sistemas, checksums y procedencia; Latest1.2.1/tag1c0b2f4/versión/build/seis assets/digests aprobados. Descarga pública nueva de los seis archivos idéntica a staging.

### Publicación completada

[Side B1.2.1](https://github.com/fefucho/sideb/releases/tag/v1.2.1), release416075215, publicada2026-10-17 19:18:47 (America/Montevideo). Se conservó el borrador existente; sólo su tag antes no publicado se avanzó de c123b59 a1c0b2f4 mediante actualización fast-forward. Mac se subió primero para clientes antiguos; instalador/portable Windows, checksums y `SideB-build-info.json` completan los seis assets. Se cotejaron tamaños y digests remotos antes de publicar; después se verificaron Latest y las seis descargas nuevas contra los archivos locales. Releases anteriores e historial de Actions intactos; no se presenta el workflow fallido como aprobado.

Procedencia: Mac build-0131 local de1c0b2f4, Windows job117509535174 aprobado de c123b59. Sus fuentes/dependencias Windows/core coinciden; sólo difieren script de generación Apple y documentación/notas. No se relabelaron binarios anteriores. ZIP/checksum Mac y evidencia de procedencia conservados en `builds/macos/build-0131/`; ver FIX-206 y el manifiesto público. Aceptación física de audio/cuenta/instalación/trackpad y notarización Mac siguen fuera de esta entrega. Caché diferida por pedido.
