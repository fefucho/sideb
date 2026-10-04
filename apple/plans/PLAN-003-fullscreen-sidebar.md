# PLAN-003: fondo de fullscreen y movimiento conjunto de portada/metadata

- Estado: retomado con captura del primer frame de build-0007. FIX-095 corrige orden de capas y está comprobado automáticamente en build-0008; validación visual pendiente.
- Objetivo: continuar el fondo de fullscreen detrás de sidebar y evitar saltos/separación al abrirla/cerrarla.
- Ámbito: shell, presentación fullscreen y pruebas Apple. Core y Windows excluidos.
- Referencias: capturas del usuario 2026-10-02; FIX-028 (animaciones/blur), FIX-056 (recorte y hit testing) históricos; FIX-090 (progreso común de navegación/sidebar).

## Pasos

- [x] Revisar jerarquía del fondo y recalculado de GeometryReader/tipografía.
- [x] Extraer una sola superficie visual al fondo del shell completo; impedir hit testing y preservar recorte de fullscreen interactivo.
- [x] Interpolar tamaño una vez y calcular columnas/portada/metadata/paneles desde el mismo frame; altura metadata estable y fuentes continuas.
- [x] Verificar tamaños intermedios, inversión, umbrales tipográficos y espacio de player/metadata: 3 nuevas pruebas aprobadas, 26 XCTest en total; revisión de acciones/vistas existentes preservadas.
- [x] Compilar con skill Mac y registrar [FIX-091](../../FIXES.md#fix-091): build-0004 release, SDK 27.0, firma verificada, `BUILD.json: compiled`; bundle conservado para prueba manual.
- [ ] Usuario revisa fondo tras sidebar, movimiento, clics, cola/letras y flip de portada en ventana real.

## Cierre

## Revisión tras feedback (FIX-092)

- [x] Contrastar build-0004: backdrop con fade separado del movimiento fullscreen; interpolación de viewport dentro del GeometryReader ya redimensionado.
- [x] Canvas fullscreen estable a tamaño ventana con fondo/foreground bajo una sola transición; shell superpuesto conserva sidebar/player/Spotlight.
- [x] Eliminar interpolación de propuesta geométrica y animar sólo reserva de sidebar con el progreso común 0→1→0; fondo e identidad de imágenes independientes.
- [x] Comprobar invariantes y compilar fuentes estabilizadas con skill Mac: build-0005 release/SDK 27.0 firmada, 26 XCTest y suite Swift Testing sin fallos.
- [x] Entregar build-0005; el usuario aportó capturas intermedias que muestran la franja causada por desplazar el canvas completo.

## Revisión con capturas intermedias (FIX-093)

- [x] Contrastar el corte horizontal de las capturas con `.move` aplicado al canvas completo y el background opaco de la columna al salir de fullscreen.
- [x] Mantener canvas fijo, backdrop con fade de ventana completa y foreground con movimiento; misma transacción, sin timers ni cambios en la reserva de sidebar.
- [x] Eliminar la capa opaca redundante que cubría el fondo al empezar la salida; conservar color base, capas, acciones y montaje condicional del contenido.
- [x] Verificar diff, pruebas y build numerada con skill Mac: build-0006 compiled, SDK 27.0, firma verificada; 180 pruebas Rust, 26 XCTest y suite Swift Testing sin fallos. Fuentes estables durante compilación.
- [x] Usuario revisó build-0006 y reportó que sigue igual; revisión continuada en FIX-094.

## Backdrop independiente tras resultado negativo (FIX-094)

- [x] Contrastar que fondo y foreground todavía pertenecían a una misma rama condicional, pese a transiciones distintas. No afirmar comportamiento del compositor sin evidencia de ventana real.
- [x] Montar un solo backdrop persistente en root detrás del shell, con opacidad explícita; foreground separado, sin paneles ocultos ni timers.
- [x] Verificar diff, pruebas y build numerada Mac: build-0007 compiled, SDK 27.0, firma verificada; pruebas Rust/Swift aprobadas, fuentes estables durante build.
- [x] Usuario aportó primer frame mostrando color diferente tras sidebar; lectura de procesos confirmó build-0007. Continúa en FIX-095.

## Orden de capas con primer frame (FIX-095)

- [x] Contrastar background opaco de HomeView por encima del backdrop sólo en zona de contenido: composición asimétrica durante fade, aunque el backdrop sea persistente.
- [x] Ordenar capas hermanas páginas → backdrop → fullscreen → sidebar → player → Spotlight; mantener callbacks, estados, vidrio nativo y reserva de ancho.
- [x] Comprobar geometría, diff y build numerada: build-0008 compiled, fuentes estables, SDK 27.0 y firma verificada; 180 pruebas Rust, 26 XCTest y suite Swift Testing sin fallos. No se abrió/controló app ni se crearon NSWindow.
- [ ] Usuario revisa primer frame y fade completo de fullscreen, sidebar, centrado/interacción del player y Spotlight.

Intento build-0003: compiló una versión intermedia del módulo antes de agregar `isInterpolating`, mientras las pruebas ya incluían ese acceso; falló la compilación de pruebas. No es bundle listo; conserva diagnóstico en `builds/macos/build-0003/`. Repetir con archivos estabilizados.

No probar controlando la laptop ni crear NSWindow. Tests/compilación no certifican fluidez/FPS ni apariencia. Un único blur de imagen a 300 px en fullscreen; no añadir material/blur global a Inicio.

## Seguimiento de porteo revisado — 2026-10-04

[PAR-008](../../PARIDAD.md), [guía §1](../../PORTEO-INICIO.md#1-barra-superior), [FIX-110](../../FIXES.md#fix-110): el resultado visible de fondo continuo detrás de sidebar y geometría estable sí se registra para Windows, aunque SwiftUI/AppKit/transacciones no se trasladen literalmente. Windows actual limita backdrop al ancho posterior a sidebar; referencia final FIX-095. No se cierran validaciones ni se reintroducen intentos 091–094.
