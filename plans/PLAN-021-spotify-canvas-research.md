# PLAN-021: Investigación de Spotify Canvas

Fecha: 2026-11-01. Estado: **reporte entregado; integración sin implementar**.

## Objetivo y alcance

Comparar proyectos públicos que resuelven Canvas, recomendar la base técnica para Side B y documentar funcionamiento, mantenimiento, licencias, permisos y pruebas faltantes. Ámbito compartido de investigación; no modifica el core ni los shells.

## Trabajo realizado

- [x] Buscar candidatos y revisar repositorios/manifiestos/código público.
- [x] Distinguir REST Protobuf de Pathfinder y client-token de Bearer de usuario.
- [x] Revisar autenticación, errores, pruebas, licencias y alertas de mantenimiento.
- [x] Contrastar los hallazgos con el motor de artwork de Mac/Windows.
- [x] Redactar [reporte](research/SPOTIFY-CANVAS-EVALUATION-2026-11-01.md) y [manifiesto de evidencia](research/SPOTIFY-CANVAS-SOURCES-2026-11-01.json).
- [x] Validar enlaces locales, JSON y diff documental.

## Continuación propuesta, pendiente y fuera del trabajo realizado

- [ ] Aclarar una vía permitida para combinar Canvas y reproducción YTM.
- [ ] Prueba positiva/ausencia con track ID explícito, sesión propia y mecanismo de secretos.
- [ ] Fixtures de errores y renovación; correspondencia YTM–Spotify y caché por pista.
- [ ] Propuesta de arquitectura de ambas plataformas conforme al core protegido.
- [ ] Prueba nativa Mac/Windows de loop, consumo y ciclo de vida.

## Decisión y límites

Wolframe es la mejor referencia de consulta Rust para un prototipo, con correcciones y sin asumir login resuelto. SpotifyScraper e InstaZDLL son referencias complementarias. Ningún candidato queda aprobado para una build pública por esta investigación. No se usaron cuentas, no se descargaron videos y no se ejecutó código de terceros. Sin fix, build, commit ni push. Referencias locales: PLAN-012 y reglas de core protegido.


Continuación autorizada: [PLAN-022](PLAN-022-optional-visual-providers.md), FIX-283: host Mac genérico y ejecutable Spotify separado; Apple primero y alternativa sólo lateral. El estado de este reporte conserva su alcance documental.
