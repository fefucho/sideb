# PLAN-006: configuración de Inicio y recomendaciones de playlists

- Objetivo: añadir configuración exclusiva de Inicio a la derecha de Atrás/Adelante; abrir un panel lateral derecho que permita elegir álbumes o playlists destacadas conservando la misma UI.
- Estado: completado en Apple, build-0021; tres ámbitos delegados y revisión/integración final del agente principal. Port Windows pendiente en PAR-006.
- Alcance: toolbar nativa, panel derecho del shell, preferencia local persistente, proyección de recomendaciones del feed existente y tarjetas/acciones de playlists.
- Decisión del usuario: panel superpuesto por encima del contenido, sin mover ni achicar Inicio ni cambiar el centrado del reproductor; debajo del fullscreen. No colapsar la sidebar izquierda al abrirlo.
- Exclusiones: sin nuevas preferencias ajenas al pedido, algoritmo propio de recomendaciones, endpoints/core nuevos, cambios Windows, commits/push ni publicación.
- Referencias: [FIX-090](../../FIXES.md#fix-090), [FIX-095](../../FIXES.md#fix-095), [FIX-098](../../FIXES.md#fix-098), [FIX-100](../../FIXES.md#fix-100), [FIX-102](../../FIXES.md#fix-102), [FIX-103](../../FIXES.md#fix-103), [FIX-104](../../FIXES.md#fix-104).

## Diseño y contratos

Engranaje con tamaño/estilo nativo del botón Actualizar, después de Adelante. Sólo en Inicio y habilitado cuando éste es interactivo. Panel derecho con material/márgenes/radio coherentes con la sidebar izquierda, título, cierre y selector «Álbumes / Playlists». Cerrarlo al salir de Inicio o mostrar fullscreen/buscador; no reabrirlo automáticamente al volver.

Álbumes permanece como opción predeterminada. Guardar la preferencia local entre ejecuciones. Cambiarla reconstruye la proyección de las secciones ya cargadas, sin refrescar red ni perder continuación, filtros o feed. Seleccionar hasta seis colecciones únicas de la clase elegida y mantener la geometría/paginado existentes. En playlists priorizar mixes personales del proveedor y después categorías habituales; no sustituir por álbumes si no hay playlists.

Portada/título abren detalle correcto; reproducir/aleatorio usan el catálogo completo sólo al ejecutar la acción de reproducción. Metadata de tarjetas sólo consulta primera página de playlists visibles, con concurrencia máxima dos y LRU seis. Cancelación/sesión/generación protegen respuestas; no cargar miles de canciones para mostrar la tarjeta. Créditos y resumen reales, sin año o total inventado.

## Trabajo

- [x] Leer instrucciones/antecedentes y comprobar estado inicial; preservar cambios de FIX-101–104.
- [x] Delegar shell/toolbar/panel, selección/persistencia y tarjetas/metadata en ámbitos de archivos separados.
- [x] Integrar preferencia y proyección sin recargar red ni alterar paginación.
- [x] Integrar navegación, reproducción y shuffle de playlists recomendadas con protección de cola/cuenta/petición.
- [x] Revisar toolbar, panel superpuesto y orden de capas respecto a fullscreen/Spotlight.
- [x] Verificar regresiones relevantes de preferencias, selección, metadata acotada, acciones y layout/hit testing.
- [x] Ejecutar pruebas completas y producir build numerada con sideb-build-macos.
- [x] Abrir y comprobar en ventana real: engranaje sólo Inicio, overlay sin movimiento, cambio de tipo, cierre, navegación y fullscreen.
- [x] Registrar FIX-105, paridad Windows y resultados/límites de la build; revisar diff final.

## Cierre

Las pruebas y compilación verifican contratos y empaquetado; las comprobaciones de ventana verifican geometría, contenido y acciones visibles. No deducir audio audible ni FPS. El feed real puede traer menos de seis playlists/álbumes. Mantener la fluidez lograda conservando el contrato de tamaño y reciclaje, sin volver a pools/rebind descartados.

## Comprobaciones en curso

Build-0019 conservada: compilación Swift detenida por inferencia de CheckedContinuation<Void, Error>, corregida. Las cinco regresiones de reproducción utilizan señales de solicitud para coordinar Core mock con el main actor, sin contar yields durante montaje AppKit. Runner focal de playlists/álbum que reemplaza playlist: 15 pruebas aprobadas. Revisión independiente de selección, persistencia, metadata y reproducción sin otros hallazgos; conflicto de Espacio con foco de panel corregido por ventana.

Build-0020: runner completo aprobado (180 Rust, 43 XCTest, 161 Swift Testing/5 suites), release/arm64/firma verificada/compiled/sourceChangedDuringBuild false. Ventana real confirma playlists en vivo y fullscreen sin panel/engranaje. Escape desde foco AppKit falló: corregido con shortcut nativo Cancelar y retirado foco forzado al abrir. Repetir build y comprobar Escape desde tabla/selector; conservar 0019/0020.

## Resultado final

[FIX-105](../../FIXES.md#fix-105), [PAR-006](../../PARIDAD.md), `builds/macos/build-0021/Side B.app`. Runner completo aprobado: 180 Rust, 43 XCTest y 161 Swift Testing/5 suites, sin fallos y con live omitidas; release/arm64/SDK 27/mínimo macOS15/firma ad hoc/compiled/sourceChangedDuringBuild false. Core y Windows sin modificaciones.

Ventana real: panel superpuesto, selector en vivo, preferencia restaurada desde build-0020 al abrir 0021, engranaje sólo en Inicio, Biblioteca sin configuración, regreso conservando tipo, scroll con panel abierto, cierre explícito/Escape desde Inicio/selector/tabla, búsqueda y fullscreen cerrando panel y ocultando engranaje. Nueva build queda abierta en Inicio con playlists y panel cerrado. Reproducción completa/aleatorio/obsolescencia verificados con Core simulado; detalle real My Supermix abre 100 pistas. No se certifican audio audible ni FPS. Conservadas builds0019 fallida, 0020 previa y versiones anteriores. Documentos actualizados después de compilar; sin commit/push/publicación.
