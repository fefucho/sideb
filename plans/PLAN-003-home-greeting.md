# Saludo de Inicio en Mac y Windows

- Objetivo: retirar el subtítulo y usar su altura para un saludo grande, actualizado según la hora local.
- Estado: implementado y revisado; ejecución Swift/build Mac aprobadas, aceptación nativa pendiente.
- Alcance: cabecera de Inicio y reloj local en ambas integraciones. Core, fuentes del feed, avatar y acciones conservados.
- Referencias: FIX-098, FIX-113-2, FIX-122/123 y PAR-003.

## Pasos y cierre

- [x] Confirmar lógica existente y geometría: ambas apps usan hora local; Mac no tiene actualización periódica.
- [x] Retirar subtítulo, aumentar saludo y preservar medidas del feed nativo/controles.
- [x] Alinear franjas: días 06–11:59, tardes 12–19:59, noches 20–05:59; actualizar al volver y sin actividad bajo fullscreen.
- [x] Revisar diff, probar límites/zona horaria y comprobar frontend/presentación Windows; documentar límites Mac.
- [x] Registrar FIX-150 y evidencia en PAR-003; entrega inicial sin build standalone.

## Resultado

FIX-150 / PAR-003. Windows280/280, check0/0, build frontend aprobado y fixture1000/500 verificado; dos pruebas Swift preparadas para Mac sin toolchain local. Sin build standalone nueva.

## Build posterior solicitada

Windows build-0012/sideb-windows.exe release compiled (FIX-151),646 aprobadas/check0/0/cero fallos y fuentes estables/cuatro hashes. Incluye saludo y últimas correcciones147/149, icono incrustado redondeado verificado. Ejecución Swift/Mac y aceptación nativa pendientes.

## Verificación Mac posterior — 2026-10-10

FIX-156/build-0070: las dos pruebas de HomeGreetingTests aprobaron los límites 06/12/20 y el mismo instante en Montevideo/Madrid/Tokio. Runner completo:574 pruebas aprobadas (182 Rust, 140 XCTest, 252 Swift Testing), build release arm64/SDK 27.0 compiled, fuentes estables y firma verificada. La ejecución Swift y compilación Mac quedan comprobadas; presentación, reactivación física y cuenta/audio reales siguen pendientes.
