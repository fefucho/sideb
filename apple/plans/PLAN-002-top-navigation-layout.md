# PLAN-002: selector superior centrado y salida vertical

- Estado: implementación y comprobaciones automáticas terminadas; validación visual pendiente del usuario.
- Objetivo: centrar el selector nativo dentro del vidrio y retirarlo por arriba al abrir la sidebar, con su misma animación.
- Ámbito: layout/presentación AppKit Apple y pruebas de vistas en memoria. Core, Windows, acciones de navegación y controles de ventana excluidos.
- Referencias: captura del usuario del 2026-10-02; FIX-003/FIX-026/FIX-058 históricos como antecedentes de shell, sin atribuirles la regresión actual.

## Pasos

- [x] Contrastar la captura con el layout actual: altura interna fija y origen vertical sin reajuste; recorrido de salida de sólo 8 puntos.
- [x] Medir el control nativo y centrarlo tras layout del vidrio; conservar ancho y comportamiento nativo.
- [x] Compartir progreso SwiftUI existente con sidebar y calcular recorrido hasta el borde superior real; conservar fade accesible para reducir movimiento.
- [x] Comprobar centrado, hit testing, recorrido completo, inversión y acciones sin crear ventanas: 23 XCTest aprobados; suite Swift Testing sin fallos, excluyendo el montaje con NSWindow.
- [x] Compilar con sideb-build-macos y registrar [FIX-090](../../FIXES.md#fix-090): build-0002 release, SDK 27.0, firma verificada, `BUILD.json: compiled`.
- [ ] Usuario valida aspecto/animación/coordenadas en la ventana real con `builds/macos/build-0002/Side B.app`.

## Cierre

Pruebas automáticas no certifican aspecto ni fluidez percibida. Validación visual por el usuario: cerrar/abrir sidebar, invertir rápidamente la animación, cambiar destino y redimensionar. No automatizar su laptop.

## Seguimiento de porteo revisado — 2026-10-04

[PAR-007](../../PARIDAD.md), [guía §1](../../PORTEO-INICIO.md#1-barra-superior), [FIX-110](../../FIXES.md#fix-110): registrar selector/destinos/salida coordinada y grupo de acciones permanente como comportamiento Windows pendiente; NSSegmentedControl/vidrio/coords siguen siendo implementación Apple. Sin cambiar el estado de validación visual ni implementar Windows.
