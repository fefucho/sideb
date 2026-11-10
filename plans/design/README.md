# Prototipo de cola — PLAN-018

[Plan y reglas](../PLAN-018-queue-recommendations.md). [Prototipo](queue-recommendations.html).

La propuesta permite explorar dos escenarios: playlist de tres canciones y radio. Usar Siguiente/Al final sobre propuestas, avanzar con el transporte y desplegar Anteriores. Clic derecho o Shift+F10 abre las acciones de una canción; Alt+flecha arriba/abajo reordena pendientes. Arrastrar una recomendación a la cola la convierte en elección manual.

Las canciones, artistas, álbumes y carátulas son ficticios. No hay audio, solicitudes de red, credenciales, persistencia ni cambios sobre la app instalada. Biblioteca, playlist, compartir, enlaces e iniciar otra radio muestran un destino simulado: se representa su ubicación en el menú sin implementar esas integraciones.

## Verificación reproducible

El script [queue-recommendations.check.mjs](queue-recommendations.check.mjs) usa Playwright y Chrome headless. Reutilizar una instalación de Playwright o instalarla fuera de las dependencias de la app:

```sh
npm install --prefix /tmp/sideb-queue-qa --no-audit --no-fund playwright
node plans/design/queue-recommendations.check.mjs /tmp/sideb-queue-qa/node_modules/playwright/index.mjs
```

Ejecutar desde la raíz de SIDE B. Requiere Google Chrome instalado; el script usa `channel: 'chrome'`, un contexto nuevo y cierra el navegador al terminar. No inicia servidor ni controla la ventana del usuario.

Resultado de la ejecución de 2026-10-30: **35 comprobaciones aprobadas**, sin errores de JavaScript. Cubren el orden elegido antes de radio, promoción individual, duplicados intencionales, navegación anterior, selección inmediata, shuffle reversible del ejemplo, repetir/avance manual, Like/quitar, menú, drag, foco y anchos 320/390/480/728.

## Alcance de la evidencia

El prototipo reconstruye un DOM pequeño con seis canciones ficticias. No es una implementación del renderer virtualizado de Side B ni un benchmark de listas grandes. Su shuffle es una permutación determinista del ejemplo, no el algoritmo aleatorio nativo. No simula páginas del proveedor, condiciones de carrera reales, restauración ni política completa de cursores y exclusiones. Esos requisitos se conservan en PLAN-018 y requieren pruebas de integración propias.

La auditoría independiente de rendimiento y la comparación de la futura implementación nativa con `f7fc479` se registran por separado. Ninguna comprobación de este script permite afirmar igualdad de FPS, memoria o latencia con la cola nativa actual.
