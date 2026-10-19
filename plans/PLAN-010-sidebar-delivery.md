# PLAN-010: entregar la sidebar y sus opciones

- Fecha: 2026-10-19 (America/Montevideo).
- Estado: frontend y build Mac local aprobados; publicación/verify Windows en CI pendientes.
- Pedido: actualizar desde GitHub, recuperar la sidebar local, exponer sus opciones y publicar otra actualización.
- Alcance: navegación vertical y colección lista/cuadrícula en Mac y Windows; Apariencia en Configuración con vista de colección y fondo de Inicio; preferencias por instalación. Preservar actualizaciones remotas de colecciones/cipher, controles y feedback de cuenta de 1.2.5.
- Aislamiento: checkout dedicado `sideb-release-1.2.6` desde origin/main; la carpeta original conserva todo su trabajo pendiente. No reset/stash ni copia indiscriminada de archivos compartidos.
- Antecedentes: FIX-174/195/221/222/223 y sidebar local no publicada de PLAN-023 Apple/PLAN-010 Windows. Sus IDs de borrador coinciden con otros fixes ya publicados: se conserva el historial original local, sin importar entradas con IDs duplicados. Esta integración se registra como FIX-224 y PAR-036.

## Pasos

- [x] Actualizar referencias Git y revisar 8f38bfe/23f1df5; conservar sus fuentes y verificaciones.
- [x] Recuperar únicamente sidebar/apariencia y sus traducciones/pruebas; integrar los hunks de shell sobre GitHub.
- [x] Añadir Apariencia en Configuración, vista de colección sincronizada con el botón directo y fondo Colores de las portadas/Liso.
- [x] Aprobar frontend y regresiones de estado, persistencia, navegación, menú y modo compacto.
- [x] Revisar visualmente ambas vistas y opciones con datos aislados; no usar cuenta real.
- [ ] Aprobar build local Mac numerada y verify/build Windows en CI; distinguir compilación de aceptación física.
- [ ] Revisar diff/protección de core y trabajo anterior, registrar evidencia, publicar y verificar 1.2.6.

## Contratos

Sidebar expandida 253 px/pt; navegación y perfil permanecen fijos mientras desplaza la colección. La vista inicial es lista y la cuadrícula conserva IDs, pestaña seleccionada, acciones y menús. Mac interpreta las preferencias antiguas classic/desconocidas como colección y conserva covers. Windows mantiene rail compacto 60 px y seis accesos.

La sección Apariencia usa las mismas preferencias que el botón de vista de la sidebar. Se persiste por instalación, sin alterar cuenta, fuentes de recomendaciones o contenido. Liso #211E21 desmonta el ambiente de Inicio; el ambiente de detalles y fullscreen conserva su comportamiento.

No se incorporan prewarm del core/audio, bindings de su API local, ni la reorganización local de viewports ajena a esta entrega. La selección única Buscar/Explorar sí forma parte de los helpers recuperados de la sidebar y tiene una regresión específica.

## Verificación y límites

Pendiente: check/test/build frontend, QA browser, build local Mac y CI de release. Cuenta/proveedor real, audio audible, instalación interactiva, Narrator/VoiceOver y aceptación física no se certifican por compilar. Fuentes antiguas y builds existentes se conservan.

## Evidencia local previa a publicar

- Frontend: check 0 errores/0 advertencias, 399 tests aprobados y 1 fixture exclusiva Windows omitida, build web aprobado; suite DOM de sidebar incluye 7 casos y sincronización Configuración/botón directo. 752 claves ES/EN generadas/verificadas.
- Browser 1280×720 con componentes reales y cuenta de ejemplo: selección de Cuadrados y Liso por controles, conservación al recargar, botón directo actualiza el selector de Configuración y compacto conserva seis accesos. Capturas `builds/releases/v1.2.6/sidebar-browser/{grid-settings,list-settings}.png`. No hay cuenta real ni audio.
- Mac local `builds/macos/build-0001/Side B.app`: compiled, sourceChangedDuringBuild=false; Rust 97+91, 239 XCTest y suite Swift Testing de 344 tests aprobados con live desactivados; 764 tests ejecutados aprobados y 14 live omitidos. Versión 1.2.6/build 19, arm64, diez hashes y firma deep/strict comprobados. Renders nativos de lista/cuadrícula revisados; `sidebar-native/` conserva fixtures, no capturas de cuenta real.
- El primer intento de inicialización falló antes de reservar una build porque el snapshot trataba un enlace de caché como archivo. Se conserva su log y se usa una caché física clonada; sin cambiar scripts, fuentes ni resultados previos.
- Tras terminar la build Mac sólo se ajusta el ancho/espaciado de los selectores Windows y se alinea el CI Mac general con `--no-parallel`, igual que el builder oficial: evita carreras del estado compartido sin omitir tests. La release de CI recompila el commit final completo y verificará fuentes estables de ambas plataformas.
- Core, bindings y runtime Tauri sin cambios contra 23f1df5; conserva íntegramente sus correcciones de colecciones/cipher y 1.2.5.
