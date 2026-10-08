# Phase 7D.1 — Arcade gameplay refinement

## Alcance

Trabajo realizado exclusivamente sobre el ZIP adjunto de Phase 7D. No se consultó ni modificó GitHub. Se preservan las reglas Match-3, tablero 8×8, input táctil, puntuación, SPEED, cascadas, especiales, Final Blast, sonidos, autenticación y servicios online.

## Seis gemas nuevas

Se generaron sprites originales con fondo transparente, mismo lenguaje de iluminación/material y siluetas distintas. Cada pieza fuente mide 512×512; el atlas de runtime mide 1536×1024, con una celda de 512×512 por gema.

| Color | Silueta | Archivo fuente |
|---|---|---|
| Rojo | Rubí cuadrado, esquinas recortadas | `assets/gems/arcade/ruby_red.png` |
| Azul | Zafiro diamante vertical | `assets/gems/arcade/sapphire_blue.png` |
| Verde | Esmeralda octogonal | `assets/gems/arcade/emerald_green.png` |
| Amarillo | Topacio rombo | `assets/gems/arcade/topaz_yellow.png` |
| Violeta | Amatista triangular | `assets/gems/arcade/amethyst_violet.png` |
| Naranja | Citrino hexagonal | `assets/gems/arcade/citrine_orange.png` |

`assets/gems/arcade_gem_atlas.png` es el atlas que carga el juego. Mantiene el orden de celdas que ya usa `GEM_SPRITE_INDEX`: rojo, verde, azul, violeta, amarillo y naranja. `_draw_gem()` lo dibuja como una sola textura de atlas con factor de tamaño `GEM_ATLAS_DRAW_SCALE = 2.12`, para ocupar la casilla sin que las gemas vecinas se toquen. Los seis PNG individuales quedan incluidos como fuentes editables/documentadas; el runtime no los carga por separado.

Vista conjunta de las seis fuentes: `docs/phase7d1_gems_preview.png`.

Las gemas usan color saturado, grandes planos luminosos, borde oscuro y reflejos blancos. La inspección de la hoja de contacto confirma seis contornos reconocibles con transparencia fuera de cada piedra. El fallback procedural también quedó alineado con las mismas siluetas: rubí cuadrado, zafiro diamante, esmeralda octogonal, topacio rombo, amatista triangular y citrino hexagonal.

## Especiales

No se cambiaron las reglas ni la resolución. Línea horizontal/vertical, bomba T/L y prisma siguen dibujándose sobre la gema base. Por eso los especiales conservan el color y la forma nuevos; los indicadores direccionales y el marcador radial siguen a cargo de `_draw_special()`. Prisma y combos entre especiales mantienen sus representaciones actuales.

## HUD, tiempo y competencia

- Se quitó el botón PAUSA y no se agregó ninguna acción de pausa voluntaria.
- REINICIAR y SALIR ocupan dos áreas simétricas, más anchas y conservan sus confirmaciones/comportamiento.
- La barra inmediatamente bajo el tablero usa `_time_remaining_ratio()`: 60 segundos = 100%, 30 = 50%, cero = vacía. El aro circular y el valor numérico usan el mismo ratio/reloj.
- `_timer_urgency()` sólo altera color y pulso: normal sobre 15 s; transición tenue entre 15–11; progresión más visible de 10–6; pulso alto de 5–0. La duración real y Final Blast no cambian.
- El panel competitivo ya no muestra “TE FALTAN”, diferencia ni barra de progreso de objetivo. Muestra el título adecuado, jugador/handle, puntaje de referencia, y TU PUNTAJE.
- Para objetivos online de rival/Top 25 se presenta el puntaje estricto a superar. Para RÉCORD LOCAL se muestra el récord guardado, aunque el comparador interno siga usando best+1 para determinar si se superó.
- El HUD muestra `#N SEMANAL` sólo cuando existe una posición válida. Sin posición, no dibuja una etiqueta.
- Se aumentó la jerarquía del puntaje actual; récord sigue como información secundaria. SPEED/medallón no cambia.

## Ciclo de vida Android

No se añadió pausa al volver de segundo plano. La ronda sigue usando el deadline monotónico existente; el juego no se puede detener para pensar. Verificar manualmente en dispositivo que, al volver después de pasar el deadline, el proceso reanude la resolución de timeout/Final Blast sin dejar el tablero en un estado bloqueado.

## Procedencia de los assets

Sprites producidos con la herramienta integrada ImageGen, usando el mockup del usuario sólo como referencia de paleta, tamaño de facetas y legibilidad; no se copiaron gemas ni elementos del diseño. Prompt común: “sprite original para juego móvil Match-3 GLINT RUSH, gema única centrada, transparente, color intenso, silueta reconocible, cuatro a seis facetas grandes y luminosas, highlight blanco, volumen de cristal arcade amigable, legible a tamaño pequeño; sin texto, símbolos, aura, fuego, marco, sombra ni otros objetos”. Se generó una variante por silueta: rubí cuadrado rojo, zafiro diamante azul, esmeralda octogonal verde, topacio rombo amarillo, amatista triangular violeta y citrino hexagonal naranja.

## Archivos de Phase 7D.1

Modificados:

- `scripts/game.gd`
- `tests/smoke_test.gd`

Nuevos:

- `assets/gems/arcade_gem_atlas.png`
- `assets/gems/arcade/ruby_red.png`
- `assets/gems/arcade/sapphire_blue.png`
- `assets/gems/arcade/emerald_green.png`
- `assets/gems/arcade/topaz_yellow.png`
- `assets/gems/arcade/amethyst_violet.png`
- `assets/gems/arcade/citrine_orange.png`
- `docs/phase7d1_gems_preview.png`
- `docs/phase7d1_arcade_refinement.md`

No se modificaron fondos, menú, audio, configuración Android, AuthService, OnlineService, Supabase ni migraciones.

## Tests y pendientes

El smoke test suma comprobaciones para la textura runtime, los seis sprites fuente, temporizador completo/mitad/vacío, ausencia de etiqueta de ranking sin posición, simetría de controles y ausencia de pausa, diferencia y barra de objetivo. También conserva la cobertura previa de countdown, selección de objetivo, especiales, cascadas, score, timeout y Final Blast.

- **Smoke test de Godot: NO EJECUTADO** — Godot 4.7 no está instalado en este entorno.
- **Prueba Android: NO EJECUTADA** — requiere importar el proyecto y exportar/ejecutar en el dispositivo.
- La validación de imagen de las seis fuentes y la hoja de contacto sí se realizó localmente; revisar los tamaños de gema en el dispositivo antes de aprobar la escala final.
