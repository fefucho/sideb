# PLAN-007 — Volumen exponencial opcional

- Fecha: 2026-10-10 (America/Montevideo).
- Estado: implementación y revisión terminadas; build-0008 release aprobada, escucha física pendiente.
- Objetivo: opción activable arriba en configuración de Inicio para facilitar volumen bajo en equipos con salida fuerte. Desactivada por defecto; conservar 0 como silencio y 100 como máximo existente.
- Ámbito: integración Windows y preferencias nativas por cuenta/invitado. Apple sólo lectura y core protegido intacto. Antecedentes FIX-134 (persistencia) y FIX-063 Apple; UI de volumen FIX-121-2/FIX-059.

## Pasos

- [x] Rastrear curva existente: Player.set_volume entero ya aplica curva perceptual de 60 dB. Evitar remapeo UI con redondeo que produciría un tramo muerto.
- [x] Integrar atenuación exponencial opcional mediante ganancia adicional Windows, preservando ganancia original del stream y porcentaje visible.
- [x] Persistir flag con default false, exponer DTO/comando y añadir checkbox ES/EN al inicio de configuración.
- [x] Verificar cambio de canción, mute/unmute, restore, carreras, fallo recuperable y límites de curva con pruebas pertinentes.
- [x] Revisión cruzada, check/suite/build apropiados, FIXES/PARIDAD y cierre (FIX-143/PAR-024).

## Contratos y revisión

- Atenuación adicional lineal en dB (amplitud exponencial): −30 × (1−porcentaje/100) dB, sólo activada y con volumen positivo. Conserva normalización existente del stream, no la redefine; no persiste ganancia de stream ni URLs.
- Slider y lastAudible permanecen 0–100 en el runtime. Modo/volumen/mute y carga aplican el estado actual bajo el mismo lock de reproducción; no duplicar curva en frontend.
- Guardar modo dentro del envelope existente de cuenta e incluirlo en detección de cambios. Migración de registros viejos usa false. Restauración pausada aplica volumen/flag; nueva canción obtiene su propia ganancia del stream.
- Revisión del subagente: guardar normalización RAM sólo tras guards de generación/auth, leer volumen/modo actuales al cargar, mute sin lectura obsoleta separada, y rollback de ajustes si falla el motor.
- El código Windows ya pasa loudness_db directamente a Player.load; se conserva esa semántica en este pedido, sin adjudicar un arreglo de normalización.

## Cierre

Implementado en FIX-143/PAR-024. Check 0/0, 80 pruebas Tauri/lib y 37 focales frontend aprobadas. Revisión cruzada corrigió progreso que descartaba el bit, rollback tras carga fallida y checkbox DOM rechazado. Fixture HomeSettings real comprueba ubicación inicial, bloqueo pendiente, aceptación y rechazo. Build integrada build-0008 release aprobada. Separar pruebas/compilación de audio audible; escucha y percepción física pendientes. Sin commit/push/publicación.

Cierre integrado 2026-10-10 14:42: **631 pruebas aprobadas** (frontend273/nativas358), check0/0, cero fallos,14 live ignoradas. `builds/windows/build-0008/sideb-windows.exe`, BUILD.json compiled/sourceChangedDuringBuild=false y cuatro SHA256 correctos. Escucha física y port Apple pendientes. Sin abrir EXE/cuenta real ni cambiar Apple/core.
