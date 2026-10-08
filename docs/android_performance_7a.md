# Phase 7A — Android performance

Baseline reference: `v0.6-phase6-stable`, commit `c8db3d8471ce0bc5027a44706c019c1a404c7d77`.

This iteration is intentionally limited to allocation reduction in the ambient background draw path and this profiling guide. Match-3 rules, rendering style, timing, effects, audio, input, Android/auth/online code, and renderer are unchanged.

## Diagnóstico con la medición disponible

En el Samsung SM-A245M (Mali-G57 MC2), la captura representa unos 20–23 ms por frame en menú y hasta 30 ms durante juego, con 48 FPS observados. `Script Functions` y `_draw()` aportaban aproximadamente 4,4–4,9 ms; `_draw_background()` aportaba 2,9 ms en menú y 3,58 ms en gameplay. El Visual Profiler mostraba menos de 2 ms en CPU de render/canvas y 0,0 ms en GPU, cifra de GPU que no se toma como medición válida.

La diferencia entre el tiempo de frame/proceso y las funciones del script no permite atribuir los 20–30 ms a `_draw()` ni a la GPU. Puede incluir espera/presentación de frame, trabajo del renderer/driver, el modo remoto/debug u otro coste no visible en esas columnas. Para separar esas causas hacen falta capturas repetibles del mismo dispositivo y, de ser posible, una comparación adicional de export debug frente a release. No se ha medido el rendimiento posterior a este cambio en Android.

### Inventario de texturas del proyecto

Dimensiones de los cinco archivos de imagen que se cargan como texturas:

| Recurso | Tamaño | Formato fuente | Mipmaps | Estimación de memoria sin compresión |
|---|---:|---|---|---:|
| `assets/gems/gem_atlas.png` | 1536×1024 | RGBA8 | Sí | 8,0 MiB con cadena mip completa; 6,0 MiB sin mipmaps |
| `assets/gems/prism_core.png` | 1254×1254 | RGBA8 | No | 6,0 MiB |
| Cada fondo JPG (3) | 720×1280 | RGB8 | No | 2,64–3,52 MiB por fondo, según almacenamiento RGB/RGBA del driver |
| Tres fondos juntos | 720×1280 c/u | RGB8 | No | 7,91–10,55 MiB |

El presupuesto esperado para estas cinco texturas es aproximadamente **21,9–24,5 MiB**. Esto no incluye glyph caches, buffers de render, superficies de la pantalla ni recursos internos del driver. El proyecto mantiene en memoria los tres fondos para poder elegir uno al comenzar cada ronda; el juego carga una atlas de gemas y un prisma. No se encontró otra imagen de juego ni una segunda carga explícita de esas texturas en `game.gd`.

Los cinco `.import` usan `compress/mode=0` (Lossless), `metadata.vram_texture=false`; solo la atlas genera mipmaps. La opción global `textures/vram_compression/import_etc2_astc=true` no obliga por sí sola a comprimirlos si el import individual sigue en Lossless. La medición de 183,6 MiB es entre **7,5 y 8,4 veces** el presupuesto de estas cinco texturas y queda sin explicar con la evidencia disponible. No se debe tratar ese total como el consumo de esos cinco PNG/JPG sin abrir el desglose de Video RAM y verificar qué recursos aparecen.

No se cambió la compresión de importación. La documentación de Godot advierte que VRAM Compressed puede producir artefactos visibles en texturas 2D, sobre todo en resoluciones bajas; eso puede perjudicar las gemas y sus gradientes. La comprobación debe hacerse por textura y con comparación visual en el teléfono antes de adoptar una compresión. Cambiar `project.godot` a otro renderer no forma parte de esta fase.

## Cambios de bajo riesgo

`scripts/game.gd` conserva la animación del fondo y las mismas formas y colores de sus estrellas. `_make_stars()` ahora genera una sola vez los dos `PackedVector2Array` de los destellos de cada octava estrella. Antes `_draw_sparkle()` construía ambos arrays en cada redraw: hasta 18 arrays temporales por frame solo para los nueve destellos ambientales. Ahora `_draw_background()` usa esa geometría precalculada.

También se lee el reloj monotónico una vez al comienzo de `_draw_background()` y se usa ese valor para el pulso y los rayos. Antes se consultaba de nuevo dentro del bucle de 72 estrellas. Todas siguen pulsando con el mismo seno, fase, radio y alpha; la diferencia de submilisegundos entre consultas individuales deja de existir.

El smoke test verifica que sigan existiendo las 72 estrellas y que los 9 pares de geometría precalculada estén creados. No prueba FPS ni sustituye una inspección visual.

## Investigado y no cambiado

- **Compresión ETC2/ASTC de gemas:** no se activa sin inspección visual en el SM-A245M; `vram_compression` no es lo mismo que `Lossy`, y la compresión VRAM puede alterar bordes, transparencias y gradientes.
- **Compresión de fondos:** se deja para una prueba aislada posterior; el ahorro máximo estimado de los tres fondos es pequeño frente a los 183,6 MiB informados, y no explica esa discrepancia.
- **Caché de todo el fondo en una textura/viewport:** no se implementa. Requiere memoria de render adicional y puede congelar los rayos/pulsos o cambiar el orden de composición.
- **Redraw continuo:** se conserva porque el juego anima reloj, efectos, gemas, HUD, partículas y fondo durante cada frame. `low_processor_mode` tampoco es apropiado para una partida que necesita redibujarse continuamente.
- **FPS y VSync:** `application/run/max_fps` no estaba configurado, por lo que aplica su valor por defecto (`0`). No se fija en 60: un límite no elimina un frame que ya supera 20–30 ms y puede recortar pantallas con refresh superior. El resultado de 48 FPS no basta para demostrar que la falta de un cap sea la causa.
- **Audio/SFX, ranking ficticio, sorting, efectos, renderer y número de partículas:** no se alteran; el alcance prohíbe cambios de game feel/sistema y no hay evidencia de que esas partes expliquen la medición de memoria.

## Validación disponible

- Confirmada estáticamente la configuración de renderer, viewport, imports y recuento/dimensiones de imágenes.
- El entorno de entrega no tiene binario `godot`/`godot4` ni `adb`; el smoke test de Godot y la ejecución Android quedan **NO EJECUTADOS**.
- No hay una captura de profiling posterior en el SM-A245M. No se afirma una mejora de FPS ni de frame time.
- No se modificaron reglas, controles, cascadas, especiales, SPEED, Final Blast, auth, plugin Android, `has_java_method()`, Supabase, migraciones ni RLS. Las dos migraciones de corrección presentes en el commit estable se incluyen sin cambios.

## Cómo repetir la medición en el Samsung SM-A245M

### Preparación

1. Abrir por separado el ZIP estable de `v0.6-phase6-stable` y el ZIP Phase 7A en Godot **4.7.2**. Esperar a que termine la importación en ambos.
2. Exportar ambos con la misma plantilla Android, perfil debug, arquitectura arm64 y método de instalación/depuración remota. Mantener la pantalla del teléfono en la misma frecuencia de refresco, brillo y resolución; desactivar ahorro de energía y cerrar apps en segundo plano.
3. Dejar que el teléfono vuelva a una temperatura similar antes de cada toma. Usar la misma conexión y el mismo modo (remoto/debug) para ambos. Si es posible, repetir después también con export release; no comparar una captura debug con una release.
4. Reiniciar la app, esperar 20 segundos tras llegar al menú y registrar temperatura/modo de refresh. Hacer tres capturas por estado y comparar mediana, además de los picos.

### Profiler

1. Conectar la ejecución Android desde el editor Godot y abrir **Debugger → Profiler**.
2. Activar/registrar `Frame Time`, `Process Time`, `Physics Time` y `Script Functions`; seleccionar la llamada `_draw_background()` y `_draw()` en el árbol de funciones.
3. Capturar 30 segundos de menú quieto.
4. Iniciar una partida; esperar a que termine la cuenta atrás. Capturar 30 segundos de juego activo y repetir una ruta de movimientos/cascadas comparable. No introducir el gesto mientras se toma una muestra de menú.
5. Guardar capturas con etiqueta `stable` o `phase7a`, y anotar mediana y máximo; no comparar un único frame aislado.

### Visual Profiler

1. Abrir **Debugger → Visual Profiler** y comenzar captura para la misma sesión.
2. Repetir menú y gameplay por separado.
3. Registrar `Render Viewport CPU`, `Render Canvas` y GPU si informa un valor real. Si GPU permanece en `0,0 ms`, marcarlo como **sin dato**; no concluir que el render no cuesta tiempo.

### Monitors

1. En **Debugger → Monitors**, registrar `FPS`, `Process`, `Physics`, `Objects Drawn`, `Primitives Drawn`, `Draw Calls`, `Static Memory`, `Video Memory`, `Texture Memory` y `Buffer Memory`.
2. Tomar una muestra estable en menú y otra durante las mismas cascadas. Apuntar valores medios y picos.

### Video RAM

1. Abrir la pestaña **Video RAM** del depurador remoto. Registrar cada textura listada, su ruta, dimensiones y memoria asignada. Guardar una captura con el total.
2. En el FileSystem del editor, seleccionar cada PNG/JPG y revisar el dock **Import**: `Compress > Mode`, `VRAM Compression`, `Mipmaps > Generate` y `Size Limit`.
3. Si el total continúa cerca de 183,6 MiB, comparar la lista con las cinco fuentes de la tabla. Revisar recursos internos/importados o texturas de viewport que aparezcan en esa lista; no asumir que los JPG fuente o el tamaño en disco equivalen al tamaño de VRAM.
4. Una prueba de ETC2, si se hace después, debe ser una variante separada: cambiar un asset por vez, reimportar, exportar e inspeccionar gemas al tamaño real, highlights, alpha y halos en Android. Revertir si aparecen bloques, bandas o bordes dañados.

### Tabla para comparación antes/después

| Indicador | Estable | Phase 7A |
|---|---:|---:|
| Menú: FPS / Frame Time / Process Time | | |
| Menú: `_draw()` / `_draw_background()` | | |
| Gameplay: FPS / Frame Time / Process Time | | |
| Gameplay: `_draw()` / `_draw_background()` | | |
| Gameplay: draw calls / primitives | | |
| Video Memory / Texture Memory / Buffer Memory | | |
| Dispositivo, renderer, refresh, build, temperatura | | |

El cambio de geometría de estrellas debería reflejarse principalmente en el coste CPU de `_draw_background()`; el ahorro de arrays por sí mismo no permite prometer cuántos milisegundos. Esta medición del teléfono decide si es relevante.
