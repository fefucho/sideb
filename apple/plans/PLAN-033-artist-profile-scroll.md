# Perfil de artista: scroll y reciclado

Estado: implementación y validación focal completas; suite global no aprobada y QA física pendiente. Ámbito Apple; core y Windows sólo consultados.

Objetivo: reservar los gestos horizontales en los carruseles y limitar las vistas/imágenes del perfil a las filas y tarjetas visibles, preservando cabecera, canciones, biografía, Ver todo, reproducción y menús.

Referencias: FIX-129 (propiedad local limitada a Inicio), FIX-172 (catálogos reciclados), FIX-247 (estantes nativos con tarjetas SwiftUI acotadas).

- [x] Contrastar perfil con Inicio y localizar el veto de historial limitado a Home.
- [x] Extender regiones horizontales explícitas a todos los destinos y cubrir contactos/inercia.
- [x] Reemplazar pila/carruseles por tabla y colecciones nativas recicladas con alturas estables, offsets por ocurrencia y cancelación de hosts fuera de pantalla.
- [x] Probar reciclado, scroll profundo/resize, actualización de datos, acciones y gestos. Ejecutar suite Swift.
- [x] Registrar fix/paridad, diff y límites. QA física/Instruments pendiente salvo medición nueva explícita.

Cierre: [FIX-281](../../FIXES.md#fix-281), [PAR-049](../../PARIDAD.md). 54pruebas focales aprobadas; suite global:276XCTest aprobadas y fase SwiftTesting con fallos en reproducción/cola e interrupción tras quedar sin progreso. Sin nueva build empaquetada ni medición FPS/Instruments. Confirmación de fluidez/gestos con cuenta y trackpad reales pendiente.
