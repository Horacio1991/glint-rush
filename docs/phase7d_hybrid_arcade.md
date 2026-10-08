# Phase 7D — interfaz arcade híbrida

## Alcance

Esta pasada actualiza la presentación de la partida sobre la copia adjunta de Phase 7BC. Conserva las gemas, animaciones, reglas Match-3, reloj, SPEED, cascadas, Final Blast, controles táctiles y servicios competitivos existentes. No modifica autenticación, solicitudes online, audio ni datos del ranking.

## Cambios visuales

- Se incorporó `assets/backgrounds/glint_arena.jpg`, un fondo vertical original de cañón fantástico cristalino. Se muestra también en el menú y mantiene un centro oscuro para que texto y tablero sigan siendo legibles. El recurso está preparado a 720 × 1280.
- El atlas actual `assets/gems/gem_atlas.png` y el núcleo del prisma permanecen intactos: ya contienen gemas originales con volumen y transparencia, y forman una buena base para esta composición.
- El HUD se divide en tres paneles translúcidos ornamentales: PUNTAJE/RÉCORD/posición, SPEED/RACHA con medallón y seis segmentos, y TIEMPO con anillo de progreso.
- Los últimos diez segundos aumentan gradualmente la pulsación y cambian el acento del panel/anillo hacia rosa coral, sin tocar el reloj ni el audio.
- El marco del tablero gana peso dorado y sombra violeta; se oscurecieron las casillas para reducir el efecto de grilla.
- La barra de tiempo se mantiene inmediatamente debajo del tablero y se hizo algo más alta. El panel competitivo queda debajo como bloque separado.
- El objetivo competitivo conserva el mismo snapshot de partida. Ahora presenta META, TU PUNTAJE y una barra independiente de progreso. Se retiró la frase “TE FALTAN” y el número de diferencia.
- Los controles inferiores se organizan en REINICIAR, PAUSA y SALIR, con superficies volumétricas y colores distintos.

## PAUSA

PAUSA es por ahora un espacio visual sin interacción. Esta iteración es de interfaz y no introduce una mecánica para detener el reloj o bloquear input. REINICIAR y SALIR conservan sus hit areas y comportamiento actuales.

## Parámetros visuales

Los tamaños se ajustan en `scripts/game.gd`, dentro de `_draw_hud()`, `_draw_timebar()`, `_competitive_target_rect()` y `_draw_game_footer()`:

- paneles HUD: altura `151.0`, margen `14.0`, separación `8.0`;
- reparto horizontal del HUD: score `36%`, SPEED `30%`, tiempo ocupa el espacio restante;
- medallón SPEED: radio base `34.0` y barra de seis segmentos;
- anillo del reloj: radio base `45.0`;
- marco del objetivo: altura `126.0`;
- botones inferiores: alto `54.0`.

La configuración de partida, puntuación y SPEED no cambia.

## Assets y procedencia

`glint_arena.jpg` se generó expresamente para GLINT RUSH. Prompt de producción: “fondo vertical 9:16 para juego arcade móvil fantástico, sin texto/interfaz/logos/tablero/gemas; cañón cristalino luminoso, cielo azul cobalto/cyan, montañas violetas y luz dorada, composición pintada por capas, cristales y vegetación en los bordes, zona central índigo despejada para superponer un tablero, fondo original de juego casual premium”. Se recortó a 720 × 1280 y se guardó como JPEG de calidad 88.

Se conservaron los tres fondos previos. El nuevo fondo ocupa el primer lugar de la rotación actual; `sky_observatory.jpg` y `prism_gorge.jpg` siguen disponibles. `crystal_valley.jpg` no se borra del proyecto.

## Validación

- Se añadieron verificaciones al smoke test para la presencia del fondo, las hit areas de REINICIAR/SALIR y el contenido de TU PUNTAJE/progreso; también se comprueba que el HUD no use “TE FALTAN”.
- **Smoke test Godot: NO EJECUTADO.** El entorno de trabajo no dispone de Godot 4.7.
- **Revisión en Android y comparación visual en ejecución: PENDIENTE.** Hay que abrir el proyecto en Godot, dejar que importe el nuevo JPEG, correr los smoke tests existentes y revisar una partida a 720 × 1280 y en el Samsung objetivo.

## Archivos de esta fase

- Modificado: `scripts/game.gd`
- Modificado: `tests/smoke_test.gd`
- Nuevo: `assets/backgrounds/glint_arena.jpg`
- Nuevo: `docs/phase7d_hybrid_arcade.md`
