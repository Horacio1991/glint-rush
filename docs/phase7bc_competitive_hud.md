# Phase 7B/7C — Competitive HUD foundation

## Alcance

Esta fase reemplaza únicamente la clasificación ficticia debajo del tablero por un objetivo competitivo tomado del ranking semanal existente. No cambia reglas Match-3, tablero 8×8, velocidad de caída, controles, SPEED, cascadas, especiales, Final Blast, sonido, assets, autenticación, envío de resultados, SQL, RLS ni renderer.

## Arquitectura

- `scripts/services/online_service.gd` conserva la RPC `get_weekly_leaderboard`; esta fase no modifica el servicio.
- Al iniciar cada ronda, `game.gd` llama una vez a `OnlineService.fetch_weekly_leaderboard(25, generation)` antes del countdown.
- La respuesta existente incluye hasta 25 filas y también la fila propia si la cuenta quedó fuera del Top 25.
- `scripts/competitive_target.gd` es una función pura que convierte esa respuesta en un snapshot local. Conserva solamente posición, `@handle`, mejor score y `is_me`; no copia email ni otros datos privados.
- La respuesta se acepta mientras corre 3–2–1 y se congela cuando aparece `¡YA!`. Respuestas tardías o de rondas anteriores no cambian el objetivo de la partida activa.
- El panel debajo de la barra de tiempo se repinta usando el score local para actualizar `TE FALTAN`; no realiza consultas.

## Selección del objetivo

| Estado semanal al tomar el snapshot | Objetivo local |
|---|---|
| Cuenta en posición 2–25 | Jugador de la posición inmediatamente superior. |
| Cuenta en posición 1 | Superar su mejor score semanal actual. |
| Cuenta fuera del Top 25 y existe fila #25 | Superar el score del puesto #25 para entrar provisionalmente. |
| Menos de 25 jugadores y la cuenta aún no figura | Superar 0; cualquier score positivo abre un lugar dentro del Top 25. |
| RPC falla, no hay sesión/configuración, ranking vacío o no hay temporada | Superar el récord local guardado en el dispositivo. |

Para declarar un adelantamiento se requiere **un punto más** que el score de referencia. Por eso el objetivo mostrado es `score de referencia + 1`; `TE FALTAN` es objetivo menos score actual, nunca baja de cero.

Si se supera al #1 del snapshot, el panel dice `NUEVO #1 PROVISIONAL`. Si el jugador estaba fuera del Top 25, dice `¡TOP 25 PROVISIONAL!`. El estado queda como provisional hasta que el envío final y el ranking servidor confirmen la posición. Si se supera el propio récord semanal/local, el texto identifica cuál de los dos se mejoró. No se selecciona un nuevo rival durante esa ronda.

## Tráfico de red

- **Antes de la ronda:** una llamada a `get_weekly_leaderboard` por cada inicio/reinicio, lanzada antes del countdown. Si falta autenticación o backend, el servicio resuelve el fallo sin bloquear la partida. Un refresh de token puede agregar su llamada de autenticación habitual.
- **Durante los 60 segundos:** ninguna consulta de objetivo, refresh de ranking ni cambio de rival es iniciado por el HUD. La respuesta del snapshot se ignora después de `¡YA!`; si la red sigue lenta, la RPC iniciada antes puede todavía estar en curso, pero no puede cambiar la partida.
- **Al finalizar:** se conserva el envío de score existente, una llamada a `submit_match_score` si el usuario está autenticado y la configuración está disponible. No se vuelve a consultar el ranking desde el resultado.

`AuthService` conserva su mantenimiento de sesión existente y puede refrescar una sesión próxima a vencer; ese comportamiento no se cambió ni forma parte de la lógica del objetivo.

La llamada usa el timeout HTTP existente de `OnlineService` (hasta 8 segundos); el countdown no espera a la respuesta. Si no llegó al aparecer `¡YA!`, el snapshot local de récord personal queda fijado para esa partida. Esta decisión mantiene el inicio ágil y el juego offline-first; una red lenta puede hacer que esa ronda use fallback aunque luego se recupere.

## Offline

El fallback se prepara localmente al iniciar la ronda. La partida, el temporizador y el input no esperan Internet. Un resultado de red fallido durante el countdown confirma el fallback; si no llega antes de `¡YA!`, el fallback se congela igualmente. No se guardan datos de ranking local ni se afirma una posición online definitiva.

## Archivos

Modificados:

- `scripts/game.gd`: solicitud única al iniciar, bloqueo del snapshot en GO, eliminación de ranking local ficticio y nuevo panel de objetivo.
- `tests/smoke_test.gd`: cobertura de objetivos, fallback, superación y respuesta tardía.
- `README.md`: configuración y descripción actualizadas.

Nuevo:

- `scripts/competitive_target.gd`: lógica pura de selección y progreso del objetivo.
- `docs/phase7bc_competitive_hud.md`: esta documentación.

No se modifican `OnlineService`, `AuthService`, plugin Android, backend config de ejemplo, migrations ni tests SQL. El archivo local ignorado `backend_config.cfg` no se distribuye en este ZIP; el ejemplo sigue incluido.

## Tests y validación

Se agregaron asserts al smoke test para:

- posición dentro del Top 25 y selección del rival inmediato;
- posición #25;
- cuenta fuera del Top 25 y score de corte;
- cuenta #1 y nuevo récord semanal;
- ranking vacío y error de red con fallback local;
- cálculo local de puntos restantes;
- nuevo #1 provisional y Top 25 provisional;
- objetivo superado en gameplay;
- snapshot tardío ignorado después de GO.

**NO EJECUTADOS en este entorno:** smoke test Godot, pruebas SQL, integración Supabase, autenticación Google en Android y exportación Android. No hay ejecutable Godot, `psql`, Supabase CLI ni Android SDK/ADB disponibles aquí. Requieren abrir el proyecto con Godot 4.7.x y usar una cuenta/dispositivo de prueba para los casos online.

## Pruebas manuales pendientes

1. Cuenta autenticada dentro del Top 25 en posición intermedia: confirmar el rival inmediato superior y el valor `score + 1`.
2. Cuenta fuera del Top 25: confirmar que la fila #25 determina el corte.
3. Cuenta #1: confirmar que se usa su mejor score semanal más uno.
4. Superar un #1: confirmar la palabra **PROVISIONAL** antes de que finalice/envíe la partida.
5. Desconectar Internet o retirar la configuración backend: confirmar que 3–2–1 y el juego local comienzan normalmente con récord local.
6. Probar red lenta: si la RPC no concluye durante countdown, confirmar que el objetivo queda congelado como récord local y no cambia a mitad de ronda.
7. Finalizar una partida autenticada: confirmar que sigue funcionando el envío existente y que no se dispara una consulta adicional de leaderboard.
