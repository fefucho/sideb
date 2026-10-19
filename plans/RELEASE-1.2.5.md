# Release 1.2.5

- Fecha: 2026-10-19 (America/Montevideo).
- Estado: publicada como Latest; compilaciones nativas, paquetes y descargas públicas verificados.
- Objetivo: publicar los botones refinados y las acciones de cuenta inmediatas de FIX-221/222 mediante el actualizador.
- Versión: 1.2.5 / build 18, tag v1.2.5, Latest numérica con aviso beta como 1.2.4.
- Autorización: «subi la uptadte» continúa el pedido de corregir Windows y autoriza commit/push/tag/release; no requiere otra confirmación.
- Base: origin/main 0ca3f64, Latest 1.2.4/c86454e verificada en GitHub. Conservar su arreglo de rueda y todos los commits remotos. Las versiones anteriores permanecen publicadas.
- Alcance: FIX-221/222 y metadatos/notas/registro de publicación. Apple/core funcionales se mantienen iguales a origin/main. Cambios locales anteriores de sidebar/apariencia, prewarm del core y diagnósticos sin relación permanecen en la carpeta original; no se incluyen por compartir archivos.
- Aislamiento: worktree Git dedicado `sideb-release-1.2.5`, porque el workspace original conserva trabajo pendiente. El creador de worktrees del app no reconoce el repositorio anidado; se usa `git worktree` sin modificar ese árbol.

## Pasos

- [x] Consultar remoto, versiones y workflows; no había release nueva ni compilación activa del destino.
- [x] Trasladar únicamente las fuentes/planes de FIX-221/222 sobre 1.2.4 y preservar la corrección remota del volumen.
- [x] Actualizar version.env/manifests/paquete propio en Cargo.lock/default manual del workflow/notas 1.2.5.
- [x] Aprobar preflight, pruebas de release/runner y frontend de este checkout aislado; diff y fuentes Apple/core revisados.
- [x] Commit/push a main y tag de ese SHA exacto; seguir el workflow de release.
- [x] Aprobar los builds/pruebas nativos de Mac/Windows y publicar sus cinco assets conjuntamente.
- [x] Verificar Latest, tag/commit, versiones/hashes de artefactos y descargas públicas.
- [x] Registrar entrega y límites físicos, cerrar el estado del plan y la paridad que tenga evidencia nueva.

## Límites

Las pruebas locales de FIX-221/222 se hicieron en un árbol con otros cambios; esta release repite frontend en el checkout exacto. La mejora de latencia física de cuenta/proveedor real y la instalación del usuario necesitan prueba en su Windows. No se mide audio audible ni FPS. Mac mantiene firma ad hoc sin notarización. No se instala ni abre una app local al publicar.

## Preflight del checkout de entrega

Preflight v1.2.5/build 18, 20 tests release/runner y 396 tests frontend aprobados, 1 fixture nativa omitida; check 0 errores/0 advertencias y build frontend aprobado. Apple/core y fuentes de volumen idénticos a origin/main. Cargo.lock cambia sólo la versión del paquete propio. Diff revisado, fuentes anteriores ajenas conservadas en el árbol original.

## Entrega en GitHub

Commit de fuentes: `4dc54c2606170acfeecc38d03b6990a378273725`; tag anotado `v1.2.5`, enviado sin force. [Workflow 39287591174](https://github.com/fefucho/sideb/actions/runs/39287591174): validación, ambos builds y publicación conjunta aprobados en el intento 2. El tag conserva el SHA exacto; no se reemplazan releases anteriores.

Primer intento macOS: Rust y generación del framework aprobados; Swift Testing aprueba 344 tests, pero XCTest falla una única aserción en `VolumeScrollIntegrationTests.testFeedbackRearmsHidesCancelsAndDoesNotRetainOwner`, línea 491 (espera de dos tramos de 500 ms frente a un Timer de 900 ms). Producción y prueba Apple son idénticas a 1.2.4, cuya suite completa aprobó. Se preserva el diagnóstico y se reintenta el job exacto sin omitir ni debilitar pruebas; el segundo intento aprueba la suite completa y el build. GitHub rechaza reintentar un job mientras su workflow sigue activo. Evidencia local ignorada: `builds/releases/v1.2.5/actions/attempt-1-failed-macos/build-0001/`.

Investigación local: copia exacta de `VolumeScrollFeedback.swift` y del método XCTest, repetido cinco veces, en paquete Swift aislado con stubs sólo de localización/tipo de zona; 5/5 aprobados sin cambiar producción ni omitir la espera. Evidencia `builds/releases/v1.2.5/timer-repro.log`. Apoya un fallo de scheduling del runner; no sustituye la suite completa ni la verificación del paquete Mac.

Windows CI: check 0/0, 397 tests frontend aprobados sin omisiones; Rust innertube 97, core 91 y variante windows-bridge 93 (7 live omitidas en cada variante), player 5 y Tauri 97 aprobados, incluidos los cuatro tests nuevos de SessionOperations. Build release numerado `build-0001`, 1.2.5/build 18, commit exacto y fuentes estables antes/después. Instalador y portable descargados desde Actions: checksums de ambos paquetes y hashes de los cuatro archivos de runtime coinciden; PE x64 y VS_FIXEDFILEINFO 1.2.5.0 comprobados sin ejecutar el EXE. El job terminó correctamente; su paquete se publica junto con macOS.

[Intento 2](https://github.com/fefucho/sideb/actions/runs/39287591174/attempts/2): se reintenta sólo macOS y su publicación dependiente, reteniendo los artefactos Windows aprobados. Diagnóstico fallido preservado como `verification/failed-macos-attempt-1.zip`, SHA-256 `66f6b846fe21989ec13ef42fc7a0dfddee9a7ef40ce80fa7f5bb656c54ed34ae`; se retira únicamente su artefacto temporal de Actions para permitir subir el diagnóstico nuevo con el nombre fijo del workflow. No se modifica el tag, código, pruebas ni release publicada. La acción [upload-artifact v4](https://github.com/actions/upload-artifact/blob/v4/README.md) exige nombres únicos y no sobrescribe por defecto.

CI macOS general, separado de la release: [39287591207](https://github.com/fefucho/sideb/actions/runs/39287591207) falla en Swift Testing con pruebas paralelas y estado compartido; también fallaba en 1.2.4 ([39157077748](https://github.com/fefucho/sideb/actions/runs/39157077748)). El builder oficial de release ya usa `--no-parallel`, aprueba esa suite y no se modifica ni se omite ninguna prueba para esta entrega. El fallo del primer intento de release fue la aserción XCTest del temporizador descrita arriba.

## Cierre de entrega

- [Release pública 1.2.5](https://github.com/fefucho/sideb/releases/tag/v1.2.5), Latest numérica, publicada el 2026-10-19 a las 17:36:11 UTC (14:36:11 Uruguay).
- El intento 2 aprueba macOS, conserva Windows aprobado y publica ambos paquetes; no se modifica el código ni el tag durante el reintento.
- Mac: 236 XCTest sin fallos, incluido el temporizador (2,118 s), suite Swift Testing de 344 tests aprobada con live desactivados, Rust 97+91 aprobadas; plist 1.2.5/18, arm64 y codesign estricto correctos. Diez hashes internos coinciden con BUILD.json. El build final, incluido el bundle de producción, termina a las 17:34:41 UTC.
- Cinco descargas públicas sin autenticación comprobadas: tamaños/digests de GitHub, archivos SHA-256 y bytes idénticos a Actions; cuatro hashes de runtime Windows y diez Mac coinciden con los manifests del commit exacto. Ningún instalador ni app se ejecutó.
- API Latest del repo actual y del nombre anterior usado por la app: v1.2.5; el selector Windows elige el instalador EXE correcto. Versiones anteriores permanecen publicadas.
- Evidencia ignorada: `builds/releases/v1.2.5/verification/{delivery.json,workflow.json}`, los diagnósticos de ambas plataformas, el ZIP del primer fallo Mac y paquetes en `public/`. Sin secretos/cuenta real ni binarios agregados a Git.

| Paquete público | Bytes | SHA-256 |
|---|---:|---|
| SideB-macOS.zip | 28075896 | `061f2d293327c7f8efa41de90c7eac83330ade758a994631aafe193c0c4afdf8` |
| SideB-Windows-x64-setup.exe | 51165329 | `5c7a0fb4d9f3bc2675c5850883d96e59c35630dbb8f5a4dc9f72a74e782d8bc8` |
| SideB-windows-x64.zip | 71789070 | `ace5c4725c88eab5e64b1d6f623689faaa2d9845430b7a501471bf9190d3d47f` |
