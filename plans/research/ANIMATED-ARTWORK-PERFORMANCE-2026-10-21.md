# Carátulas animadas — aceptación de rendimiento tras el reinicio

Fecha:2026-10-21, America/Montevideo. [PLAN-012](../PLAN-012-animated-artwork.md), [implementación y builds](ANIMATED-ARTWORK-2026-10-21-results.md).

## Decisión vigente del usuario

El usuario cancela expresamente las mediciones A/B: «no vamos a hacer el test ya comprobé que funcionó». Se registra su confirmación funcional; no se retoma la prueba ni se pide desbloqueo. No hubo métricas instrumentales nuevas. La automatización queda desactivada.

## Estado del intento anterior

La reanudación programada se ejecutó después del reinicio, a las15:01. La build actual es0155 Release (incluye carátulas FIX-237/238 y estilo/fallback de Letras FIX-239); el binario en ejecución corresponde a ese paquete y su SHA256 coincide con BUILD.json. Hay otra app instalada en ejecución, así que el futuro perfil debe apuntar al PID/ruta exactos de0155.

**Bloqueo:** Computer Use no pudo seleccionar la ventana y la comprobación de superficies confirmó que el Mac está bloqueado y no puede desbloquearlo automáticamente. Se pidió al usuario desbloquearlo y avisar cuando quede libre. No se alteró la app, sesión, controles de seguridad ni preferencias, ni se inició un perfil con una escena no verificable.

No hay baseline A/B nueva, CPU/GPU/RAM comparativas, FPS, hitches ni P95/P99 de este intento. Los pilotos anteriores con escena dudosa siguen descartados como controles comparables. Ni las959 pruebas de0155, ni la frecuencia del MP4 ni soporte VideoToolbox equivalen a rendimiento medido.

## Preparación comprobada sin interactuar con la app

- Binario0155 compilado/fuentes estables, hash de ejecutable verificado. M1Pro/16GB/macOS27/Xcode27.1 según la evidencia del mismo host.
- Cinco assets de motion ya están en caché, todos1080×1080 HEVC,24/25/29,97/30fps; no se encontró aquí un asset60fps. After Hours1080HEVC30 (20.794.505bytes) y Graduation1080HEVC30 (13.479.725bytes) son recursos reales ya comprobados. No se descargó nada para este intento.
- Time Profiler y Activity Monitor existen. Consultar `--show-recording-options` sólo lee configuración y no inició captura. El summarizer de time-profile previo distingue CPU main/otros stacks y pesos inclusivos; no calcula frames.
- Espacio disponible observado≈6,5GiB. No repetir una captura Animation Hitches grande: el intento anterior produjo≈21GB y falló. Un instrumento de frames sólo sirve si entrega eventos/duraciones válidos del proceso y de la ventana objetivo.

## Instrumentación revisada

La revisión de Luna y el integrador conserva un límite importante: las capturas anteriores no contienen frames utilizables. Core Animation FPS estaba deshabilitado para Mac, display-surface-swap tenía cero filas y Frame Lifetimes presentaba tiempos inválidos. No hay una vía de FPS de bajo coste ya validada en este host. El Power Profiler instalado describe soporte iOS/iPadOS; no se cuenta como energía de Mac medida.

Después del desbloqueo, un piloto acotado de10–15s con instrumentación estrecha puede explorar hitches reales. Antes hay que comprobar que el instrumento sea compatible con el destino y después validar atribución al proceso, filas no vacías, timestamps/duraciones finitos y coherencia de eventos; que una tabla exista en TOC no demuestra datos válidos. Evitar un template completo pesado y aplicar un límite operativo de tamaño, sin tratarlo como umbral científico. Ningún piloto se ejecutó durante este intento.

## Protocolo listo para completar con el Mac libre

1. Seleccionar0155 por ruta y confirmar PID, título/canción/álbum, documento rico cargado, fuente36/Karaoke y estado de sidebar. Capturar viewport/escala/refresh efectivo y política energética/térmica. Mantener esos valores en cada par; no comparar con0150/0154.
2. Usar el mismo álbum con asset local1080/30 y documentar esta frecuencia, sin declarar validado60fps. Confirmar visualmente video presentado antes de medir on; para off usar el toggle real de Apariencia. Registrar/restaurar la preferencia original al terminar.
3. Mismo cue y documento de Letras, caché caliente. Realizar tres pares alternando el orden off/on; reposo y scroll manual continuo, pausa y reproducción, sidebar cerrada y después abierta. Volver/clic en el mismo cue restablece seguimiento antes de cada réplica. Verificar escena antes/después y guardar horario/ROI de gestos.
4. **Pausa:** el controller libera buffers tras30s de inactividad. Calentar motion reproduciendo, pausar y medir un ROI de unos15s dentro de esos30s. No mezclar una muestra con frame/buffers retenidos con otra que ya los liberó. La pausa larga y la reanudación tras liberación son escenarios separados.
5. Dirigir scroll al área AX real de Letras, con secuencia fija y suficiente recorrido; no reutilizar coordenadas ambiguas. Separar gestos de la lectura AX lenta; registrar límites de ROI y rechazar pruebas con navegación accidental, respuesta del usuario o escena diferente. No derivar FPS de timestamps de gestos.
6. Capturas acotadas Time Profiler para CPU/main/layout/composición y medición de memoria del mismo proceso; misma instrumentación/condiciones para cada par. GPU/energía y frames/hitches sólo si hay datos reales exportables y atribuibles, con límites explícitos si faltan. Comparar medianas y dispersión; no generalizar un run.
7. Tratar carga fría (búsqueda→descarga→validación→primer frame/fade) aparte del coste estable; no borrar caché del usuario para simularla sin un mecanismo aislado y controlado. El usuario ya reportó espera inicial excesiva; ese síntoma no demuestra un problema de FPS.
8. Comprobar toggleoff/salida/ocultamiento, loop/revelado y ciclos repetidos con memoria estable, así como seek/seguimiento/manual/Volver y voces/Unicode. Corregir sólo defectos demostrados de este ámbito; sin tocar Recomendados ni reducir calidad por defecto. Si hay código nuevo: revisión, pruebas, FIX/PARIDAD y build oficial antes de comparar otra vez.

La medición queda cancelada por decisión del usuario. El protocolo anterior se conserva como referencia histórica; no es trabajo activo ni implica validación instrumental.
