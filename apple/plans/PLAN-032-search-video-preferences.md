# PLAN-032: Videos en resultados de búsqueda

- Objetivo: preferencia persistente en Configuración para mostrar/ocultar videos en búsqueda completa y sugerencias.
- Ámbito: Apple; sin cambiar core, reproducción, Inicio ni biblioteca. Windows pendiente en PAR-048.
- Referencias: FIX-086 y proyecciones de búsqueda actuales; FIX-280.
- [x] Ajuste local, activado por defecto.
- [x] Proyección de secciones y sugerencias, conservando payloads por ocurrencia, roles y continuación.
- [x] 57 pruebas focales de búsqueda aprobadas (11 XCTest + 46 SwiftTesting), incluidas cuatro nuevas; traducciones verificadas (825 claves).
- [ ] Suite Swift global: 273 XCTest aprobadas; fallos en SwiftTesting de otros componentes y ejecución interrumpida, sin conclusión causal. Véase FIX-280.
- [ ] Validación manual en app instalada; sin nueva build solicitada.
