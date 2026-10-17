# PLAN-018: tres cápsulas nativas de navegación

- Fecha: 2026-10-16 (America/Montevideo).
- Estado: implementación visual completada en0122, búsqueda funcional diferida; reemplaza la propuesta suspendida de PLAN-016 por pedido del usuario.
- Objetivo: trasladar el prototipo AppKit verificado a la toolbar real, conservando selección, historial, sidebar y optimizaciones de FIX-186/192.
- Alcance: Apple; búsqueda visual editable sin solicitudes ni navegación por consulta en esta etapa. Sin cambios nuevos de core ni Windows.

## Referencias y decisión vigente

El usuario proporcionó `implementation_plan.md` y `scratch/TopNavComparisonApp.swift` en el laboratorio local `30924033-9a71-4f1d-835a-128ad40def32`. La captura posterior elige `.extraLarge Amplio` de 42 pt, tres segmentos de 80 pt, vidrio exterior, pista gris oculta mediante KVO, **Fusión Exacta** de 298 pt y Back/Forward con **divisor sutil**. Con sidebar abierta: lupa izquierda y flechas derecha. Esta decisión reemplaza las alternativas de 360 pt y cápsula sin divisor del plan inicial.

La expansión actualiza el frame real con un display link nativo, solicita hasta 120 Hz según la pantalla y se puede invertir desde el estado visible. No se infiere fluidez física a partir de compilar.

## Etapas

- [x] Geometría de 42 pt, destinos deterministas sin `sizeToFit`, supresión KVO y nuevo historial independiente; `swift build` de fase.
- [x] Campo visual localizado, foco, Escape y borrado/cierre, sin conectar el motor de búsqueda.
- [x] Header de tres bloques, búsqueda 42→298, flechas inmóviles durante expansión y extremos separados con sidebar; display link y accesibilidad; `swift build` de fase.
- [x] Integrar lupa/⌘F/⌘K con estado visual independiente del Spotlight anterior; conservar búsqueda de página y acciones del menú; `swift build` de fase.
- [x] Regresiones de posiciones, reversas, frame real, historial/foco y actualización incremental; suite apropiada y build numerada oficial.
- [x] Revisar UI nativa y registrar evidencia y límites en FIXES/PARIDAD; actualizar este plan.

## Cierre

Comprobar los tres bloques en ventana mínima y amplia, ambos estados de sidebar y búsqueda, cierre/reapertura rápidos, fullscreen, Reduce Motion/Transparency, destinos y Back/Forward funcionales. La consulta es un borrador visual y no agrega historial ni hace solicitudes. Registrar ruta exacta de build y separar pruebas de una eventual medición de FPS.

Antecedentes: FIX-090/107/184/186/192. Paridad: PAR-007 mantiene la exclusión del selector y transición Mac solicitada anteriormente; no reabre un port Windows.

## Validación en curso

0117/0118 compilan con690pruebas ejecutadas aprobadas y14live omitidas. QA0117 confirma geometría, ambos atajos, foco, Escape/borrador y Back/Forward, pero detecta lente ausente.0118 cambia el fundido al contenedor exterior; el arranque espera autorización del llavero de macOS, por lo que la corrección visual sigue pendiente. El diagnóstico scratch cambió durante0118; la siguiente build mantendrá el snapshot quieto. No se da por cerrado el rediseño hasta revisar la app real.

A/B posterior: la lente aparece en la app0121fixture al montar la misma cabecera como overlay del plano de contenido, fuera de NSToolbar; el toggle lateral permanece en la toolbar. Coordenadas y tamaños nativos conservados. Se desactiva el marcador excluido al entrar en fullscreen. Suite691aprobadas; revisión visual final y entrega estable en curso.

## Entrega0122

Build oficial compiled/sourceChangedDuringBuild=false,691pruebas ejecutadas aprobadas,14live omitidas, firma estricta y10hashes válidos. Sesión real1321×831pt: lente nativa, destinos, atajos/foco/Escape, historial durante expansión y ambos estados de sidebar verificados. Fixture960×680pt: cabecera/selección/Forward/fullscreen y retorno. App0122 abierta en Inicio con sidebar cerrada y reproducción pausada.

Límites: sin medición física de120FPS ni runtime15/26. Escape previo al foco no está garantizado (X y Escape en editor cierran); recorte del viewport de Inicio observado en fixture mínimo queda para investigación de layout separada, sin compensar paddings ni tocar su renderer. No afecta la geometría validada de las cápsulas. Búsqueda de resultados sigue desconectada según alcance del usuario.
