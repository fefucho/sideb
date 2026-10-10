# PLAN-002 — Álbum correcto al reproducir Acceso rápido

- Objetivo: mostrar el álbum real al reproducir Inicio/Speed Dial en Apple y Windows, conservando su destino y sin alterar audio/cola.
- Estado: implementado y revisado en ambas integraciones; pruebas Windows y ejecución Swift/build Mac aprobadas, aceptación nativa pendiente.
- Ámbito: conversiones y enriquecimiento de metadata de ambas integraciones; core sólo lectura inicialmente. No refactor visual, commit ni publicación. Entrega inicial sin build numerada; verificación Mac posterior en FIX-156.
- Antecedentes: FIX-138/PAR-022; parser compartido `metadata.rs::split_subtitle` toma un grupo posicional como álbum. El arreglo Windows anterior conserva cualquier etiqueta si hay albumId: ese ID no demuestra que el texto sea álbum.

## Contrato común a verificar

Un contador del subtítulo de Home no debe convertirse en nombre de álbum aunque exista albumId. Conservar el ID/destino por separado; buscar metadata canónica del video cuando falta el nombre. Aplicar sólo a la misma canción/petición vigente, sin reiniciar stream, cambiar ocurrencia, progreso o cola. Distinguir el subtítulo ambiguo de metadata canónica: no borrar títulos legítimos por contener Views/Plays/números. Si no hay álbum verificable, no inventarlo.

## Pasos

- [x] Leer instrucciones, Git y antecedente FIX-138/PAR-022.
- [x] Seguir Acceso rápido → conversión → reproducción → enriquecimiento en cada plataforma.
- [x] Agente Apple: implementar contrato en fuentes y pruebas Apple; Windows/core sólo lectura.
- [x] Agente Windows: implementar contrato en fuentes y pruebas Windows; Apple/core sólo lectura.
- [x] Integrador: contrastar estrategias y revisar carreras, nombres legítimos y destino coherente.
- [x] Ejecutar regresiones pertinentes, comprobaciones disponibles y registrar límites Apple en host Windows.
- [x] Registrar fixes por plataforma, actualizar PAR-022 y cerrar plan con evidencia.

## Cierre

Fixtures: artista + contador con albumId válido; álbum real de igual video y destino; colaboraciones; subtítulos localizados/duración; nombre legítimo parecido a estadística; ausencia/error canónico; respuesta tardía tras cambiar canción/cuenta. Prueba en cuenta/audio reales fuera de alcance. SwiftUI y compilación nativa Apple requieren Mac, sin declarar verificación desde Windows.

## Evidencia y límites

- FIX-148 Apple: cinco archivos,10regresiones Swift preparadas, firmas/static diff revisadas y13fixtures del patrón extraído en Python; no hay Swift/Mac en host Windows. No se afirma ejecución de pruebas nativas Apple.
- FIX-149 Windows: tres archivos,278frontend y15nativas focales aprobadas; check0/0 y buildfrontend exit0. Guardas y rebase de metadata, ambos órdenes de carga/radio y error revisados. No build numerada/EXE nueva.
- PAR-022 actualizada; core sin cambios, cuenta/audio/proveedor y aceptación física pendientes. No se cierra paridad perceptual/nativa mediante pruebas parciales.
- Revisión integrador corrigió colaboradores que podían crear falso álbum, estadísticas reintroducidas desde radio, identidad de solicitudes canceladas y hueco Windows si radio termina antes del stream. Nombre/destino se mantienen coherentes; AlbumDetail legítimo100Plays se conserva.
- Verificación Mac posterior (2026-10-10), FIX-156/build-0070: las diez regresiones de HomeSongMetadataTests se ejecutaron y aprobaron dentro de 574 pruebas (182 Rust, 140 XCTest, 252 Swift Testing). Compilación release arm64/SDK 27.0, firma y fuentes estables verificadas. Se comprueban metadata canónica, orden de radio/álbum y respuestas tardías con fixtures; cuenta/audio/proveedor reales y aceptación física siguen pendientes. Core intacto.
- Pedido paralelo Genius: FIX-147 (Windows TrackInformation), reverso768 ocupa100% sin tope640; modo independiente intacto, seis tamaños y24focales Genius aprobados, incluido en suite frontend278. Capturas locales ignoradas, servidor/tab cerrados.

## Build posterior solicitada

Windows build-0012/sideb-windows.exe release compiled: incluye FIX-147/149,646 aprobadas/cero fallos/14live omitidas y check0/0, fuentes estables/cuatro hashes verificados. Ejecución con proveedor/audio y Swift/Mac pendientes.
