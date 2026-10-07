# GLINT RUSH — prototipo vertical Godot

Prototipo arcade Match‑3 offline-first para Android. El tablero usa un atlas original de seis gemas con iluminación y volumen, un prisma multicolor separado y tres fondos fantasy seleccionables al azar. La interfaz, partículas y efectos de sonido son propios; no contiene assets de Bejeweled. La entrega incluye una fundación SQL de Supabase, todavía sin autenticación ni funciones de partida en línea.

## Abrir y ejecutar

1. Instala Godot **4.3 o superior**.
2. Descomprime `glint-rush.zip`.
3. En Godot Project Manager elige **Importar** y abre `project.godot`.
4. Pulsa **F6** para ejecutar la escena o **F5** para correr el proyecto.
5. En PC y Android puedes arrastrar una gema hacia una vecina en un solo gesto, o tocar dos gemas vecinas. Durante la partida hay controles para reiniciar o salir, ambos con confirmación; Atrás/Escape abre la confirmación de salida.

Para repetir las pruebas lógicas desde una terminal ubicada en la carpeta del proyecto: `godot --headless --path . --script res://tests/smoke_test.gd`.

El proyecto usa GDScript y renderizador **Compatibility**. No requiere plugins ni paquetes externos. Incluye efectos separados de intercambio, match, especial de línea/cruz, prisma, cascada, cuenta regresiva y final, además de una base musical arcade en loop.

## Exportar y probar en Android

1. En Godot abre **Editor → Manage Export Templates → Download and Install**.
2. Instala Android Studio o Android SDK y configura en **Editor → Editor Settings → Export → Android** las rutas al SDK, JDK y Android build-tools.
3. Activa **Opciones de desarrollador** y **Depuración USB** en el teléfono; conéctalo por USB.
4. En **Project → Export**, añade un preset Android. Para instalar directamente, exporta un APK de debug; para Play Store, prepara un AAB firmado.
5. Pulsa **Export Project** y guarda el APK. Instálalo en el teléfono y permite la instalación desde esa fuente si Android lo solicita.

La exportación iOS requiere macOS/Xcode. El proyecto fue diseñado para Android primero.

## Ajustes rápidos

Todos los parámetros de partida están al comienzo de `scripts/game.gd`, en `CONFIG`:

- `ROUND_SECONDS`: duración.
- `COUNTDOWN_STEP_SEC`, `COUNTDOWN_GO_SEC`, `COUNTDOWN_FONT_SIZE`: ritmo de 3–2–1–¡YA! y tamaño del impacto. El reloj, los controles y la música se activan juntos al aparecer ¡YA!.
- `LOCAL_RIVALS`: perfiles de puntuación simulados que alimentan la clasificación visible durante la partida; no son jugadores online.
- `ROWS`, `COLS`, `GEM_TYPES`: tablero y colores.
- `POINTS_PER_GEM`, `SPECIAL_CREATE_BONUS`, `SPECIAL_ACTIVATE_BONUS`, `CHAIN_SCORE_CAP`: puntuación.
- `SWAP_TIME`, `CLEAR_TIME`: duración del intercambio y del brillo/ruptura. El umbral de drag táctil se calcula como el 22% del tamaño de una casilla en `_drag_direction()`.
- `FALL_BASE`, `FALL_PER_SQRT_ROW`, `FALL_MAX`: velocidad de caída; la distancia usa raíz cuadrada para que un trayecto largo no multiplique el tiempo. Las gemas nuevas comienzan por encima del tablero.
- `CLEAR_STAGGER`: intervalo de propagación en los rayos de fila/columna.
- `SHAKE_CAP`: intensidad máxima del screen shake.
- `GEM_GLOW`: resplandor de especiales.
- `IDLE_GLINT_INTERVAL`: intervalo entre destellos ambientales; como máximo se animan dos gemas a la vez y cada reflejo dura 0,38 segundos.
- `HUD_ENTRY_TIME`: duración de la entrada animada del HUD.
- `SPEED_WINDOW_SEC`: ventana para encadenar matches manuales válidos.
- `SPEED_MULTIPLIERS`: multiplicador de puntos por número de match manual consecutivo; cascadas automáticas no avanzan esta lista.
- `SPEED_PITCH_SEMITONES`: escala ascendente de tonos para las confirmaciones de match; la lista se repite en su último nivel si la racha sigue creciendo.
- `SPEED_GLOW_PER_MATCH`, `SPEED_GLOW_MAX`, `SPEED_DECAY_SEC`: crecimiento y apagado suave del brillo de SPEED.
- `SPEED_SCORE_POP`, `SPEED_PARTICLE_BONUS`: energía de números flotantes y partículas cuando la racha sube.
- `SPEED_SHIMMER_START`, `SPEED_HARMONY_START`, `SPEED_SHIMMER_DB`, `SPEED_HARMONY_DB`, `SPEED_HARMONY_INTERVAL`: umbrales, mezcla e intervalo musical de las capas de SPEED.
- `SFX_MATCH_DB`, `SFX_PITCH_MAX`, `SFX_POLYPHONY`: nivel del match, techo de pitch y voces de efectos simultáneas.
- `SFX_CREATE_DB`, `SFX_SPECIAL_DB`, `SFX_CROSS_DB`, `SFX_PRISM_DB`, `SFX_PRISM_PAIR_DB`, `SFX_PRISM_TRANSFORM_DB`, `SFX_FINAL_WARNING_DB`, `SFX_FINAL_DB`: mezcla por familia de efectos.
- `SPECIAL_SHAKE_BASE`, `SPECIAL_SHAKE_PER_WAVE`, `FINAL_SHAKE`, `SHAKE_CAP`: respuesta de cámara de especiales y Final Blast.
- `CROSS_ACTIVATE_BONUS`: puntos extra para la especial de fila + columna.
- `FINAL_BLAST_TEXT`, `FINAL_ZERO_PAUSE_SEC`, `FINAL_NO_SPECIAL_DELAY_SEC`, `FINAL_SPECIAL_DELAY_SEC`, `FINAL_MAX_WAVES`: identidad, pausas, intervalo de detonación y límite defensivo del final.
- `PRISM_TRANSFORM_SEC`: duración del barrido que convierte el color objetivo en especiales antes de la detonación.
- `MUSIC_BASE_DB`, `MUSIC_URGENT_DB`: mezcla de música normal y la elevación sutil en los últimos 10 segundos.
- `TIMEBAR_HEIGHT`: grosor de la barra integrada bajo el tablero.
- `MENU_GLOW`: intensidad de los halos de la pantalla inicial.
- `HAPTICS_ENABLED`, `SOUND_ENABLED`: feedback.

La interpolación y el overshoot se ajustan en `_fall_ease()`. La respuesta del gem swap y el rebote inválido están en `_begin_swap_visual()`. Los efectos de especial se dibujan en `_draw_special_visuals()`.

Los colores están en `GEM_COLORS`, su correspondencia en `GEM_SPRITE_INDEX`, el atlas de seis gemas en `assets/gems/gem_atlas.png` y el prisma original en `assets/gems/prism_core.png`. `_draw_gem()` y `_draw_charged_aura()` dibujan las piezas; `_gem_points()` se usa solo en cristales decorativos de la portada. Los paneles y marcos ornamentales se ajustan en `_make_ui_styles()` y `_draw_ornamental_frame()`; la distribución de partida está en `_draw_hud()`, `_draw_board()` y `_draw_timebar()`. Como máximo hay dos destellos idle simultáneos. Los tres fondos están en `assets/backgrounds/` y se elige uno al azar por partida. Los WAV editables están en `assets/sfx/`; el bus de música permanece bajo los efectos y sube suavemente en los últimos 10 segundos.

## Controles

- Arrastra una gema hacia una casilla adyacente (horizontal o vertical) para intentar el intercambio al superar un umbral de 22% de casilla; un gesto solo puede originar un swap. También se conserva el control de tocar dos gemas vecinas.
- Un intercambio que no forme combinación vuelve a su sitio.
- Especiales: línea horizontal/vertical de 4; cruz de fila + columna para T/L; prisma por 5 en línea. Si una especial existente participa de un match, su efecto se activa en cadena y el nuevo especial del match se conserva.
- Dos prismas limpian el tablero.
- Prisma + línea convierte las gemas normales del color de esa línea en especiales alternadas horizontal/vertical; Prisma + cruz las convierte en cruces. La búsqueda es row-major para que la orientación sea determinista.
- Al llegar a 0:00 se bloquea el input, termina cualquier resolución ya iniciada y se activan en orden estable las especiales que queden. Cada detonación y las cascadas resultantes suman al puntaje antes de fijar el resultado. Sin especiales, la transición es corta.
- Los matches de caída aumentan el multiplicador visual sin límite; el multiplicador matemático de puntaje se limita por `CHAIN_SCORE_CAP`.
- SPEED registra solo combinaciones iniciadas por movimientos manuales válidos. Su ventana, multiplicador de puntos, escala musical, glow y decay se configuran de forma independiente; las cascadas conservan su contador y feedback propios.
- El récord se guarda localmente en `user://glint_rush.cfg`.
- Al pulsar JUGAR se crea el tablero y corre 3–2–1–¡YA! sobre él. No se aceptan movimientos durante los tres números; el reloj de 60 segundos, la música y el input arrancan al mismo tiempo que ¡YA!.
- La clasificación de la partida muestra tu puntaje frente a tres rivales locales de demostración. Sus nombres y ritmo final se editan en `LOCAL_RIVALS`; la lista no consulta ningún servidor.

## Assets temporales

El atlas de seis gemas, el prisma y los tres fondos son ilustraciones originales generadas para GLINT RUSH. Se pueden reemplazar manteniendo la correspondencia de color/atlas en `GEM_SPRITE_INDEX`, el sprite cuadrado del prisma y las tres rutas en `_ready()`. Los marcos, destellos, auras y partículas se dibujan sin shaders. La música y los WAV son assets temporales originales de prototipo y conviene reemplazarlos por una mezcla final antes de publicar. La tipografía usa la fuente integrada de Godot.

## Límites de validación

Las pruebas de lógica cubren generación del tablero, countdown, input bloqueado, reloj, clasificación local, intercambio inválido, caída, puntaje, match T/L, cruz completa y reacciones en cadena, transformaciones deterministas de Prisma a líneas/cruces, Prisma doble, SPEED y liquidación Final Blast con/sin especiales. En esta iteración se amplía el smoke test con IDs por ronda, eventos y comportamiento offline. El smoke test existente y los casos nuevos están en `tests/smoke_test.gd`. En este entorno no hay ejecutable Godot, así que las pruebas no se pueden ejecutar aquí. Tampoco se exportó APK ni se midieron FPS en teléfono. Los efectos de tablero usan `_draw()` y no crean nodos por gema o partícula; el rendimiento final debe medirse en el Android objetivo.

## Fase 5 — UX y game feel

La pantalla de partida incluye botones **REINICIAR** y **SALIR** con diálogo de confirmación. El reinicio genera una ronda nueva sin tocar AuthService y cancela resoluciones, tweens y audio diferido de la ronda anterior. El botón **SALIR DE LA CUENTA** aparece centrado en la pantalla inicial. Consulta [`docs/phase5_gamefeel.md`](docs/phase5_gamefeel.md) para el detalle de input, resolución de especiales, pruebas y pendientes.

## Fundación online

Esta entrega agrega un autoload `OnlineService`, IDs UUID por ronda y la base SQL inicial de Supabase. El juego continúa en modo local y no envía scores. Para migraciones y pruebas del backend local, consulta [`supabase/README.md`](supabase/README.md) y el [contrato online](docs/online_architecture.md). El archivo `backend_config.cfg` es opcional, está ignorado por Git y solo admite URL/clave pública; no copies una clave `service_role`.
