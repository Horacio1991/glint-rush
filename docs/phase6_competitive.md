# Phase 6 — puntuaciones y ranking semanal

## Alcance

Phase 6 agrega el regreso al menú desde resultados, el envío opcional de scores autenticados y una pantalla con el ranking semanal. La partida, el puntaje local, el récord y el Final Blast siguen siendo locales y no esperan respuestas de red. Una cuenta sigue siendo opcional para jugar.

## Flujo de una partida

1. `game.gd` crea un `client_match_id` UUID al iniciar la ronda.
2. El juego mantiene el identificador durante countdown, partida y Final Blast.
3. Al terminar la liquidación, `_finish_round()` guarda el récord local, cambia a resultados y emite `round_finished`.
4. `OnlineService.on_round_finished()` inicia una llamada asíncrona a `POST /rest/v1/rpc/submit_match_score` cuando hay identidad autenticada. La pantalla de resultados no espera el HTTP.
5. La función SQL deriva el usuario desde `auth.uid()`, toma la temporada del reloj UTC de PostgreSQL, registra el intento en `matches` y actualiza `weekly_scores` solo si mejora el récord semanal.
6. Una repetición del mismo `client_match_id` para ese usuario no vuelve a insertar ni cambia el score original.

El cliente no envía `user_id`, `season_id` ni `session_id`. Los dos primeros los fija el servidor y el último queda `NULL` porque todavía no se crea un ticket de partida. Esto evita inventar una sesión server-side. La fila queda con estado `pending_review`.

## Temporadas y regla de ranking

Se reutiliza `public.seasons`, creada por `get_current_season()`. La temporada es ISO semanal UTC: lunes 00:00 a lunes siguiente 00:00. Cada clave semanal identifica una fila distinta. No se borran scores al cambiar de semana; el historial queda asociado a temporadas anteriores.

`public.weekly_scores` mantiene un agregado por `(season_id, user_id)`. Un score menor o igual no reemplaza el mejor de esa persona durante la semana. El orden es `best_score DESC`, `achieved_at ASC` y `user_id ASC` como desempate estable.

`public.get_weekly_leaderboard(p_limit)` devuelve hasta 25 filas (la UI solicita 20), únicamente con posición, handle, score y si la fila corresponde a la sesión. Si el usuario autenticado quedó fuera del Top N, el RPC incluye su fila adicional para mostrar **TU POSICIÓN**. Si todavía no puntuó esa semana, la pantalla lo indica. No se devuelve email.

## RLS, permisos y funciones

- Se reutilizan `matches`, `weekly_scores`, `seasons` y `profiles`; no se duplican tablas.
- No se habilitan INSERT/UPDATE/DELETE directos de `matches` ni `weekly_scores` para clientes.
- `submit_match_score()` es `SECURITY DEFINER`, fija `search_path` vacío, exige `auth.uid()`, deriva el propietario del token y está concedida solo a `authenticated`.
- `get_weekly_leaderboard()` es `SECURITY INVOKER`, requiere sesión autenticada y lee las columnas públicas ya autorizadas por grants/RLS.
- La migración nueva hace nullable `matches.session_id` para registrar estos resultados sin crear una sesión de servidor falsa. Las partidas con tickets server-side siguen pudiendo utilizar ese campo y conserva su unicidad.
- `backend_config.cfg` continúa ignorado por Git. El cliente utiliza únicamente URL y clave pública. Nunca incluir `service_role`, secret key ni Google Client Secret.

La función de score es **client-authoritative para desarrollo**: limita formato/valor, identidad, temporada e idempotencia, pero acepta el número que envía el juego. `pending_review` describe esa limitación; no significa que exista verificación de score.

## Uso sin conexión

- Sin sesión: la partida termina normalmente y queda como resultado local.
- Sin configuración, error HTTP, timeout o JSON inesperado: se muestra un mensaje breve y la partida no se bloquea.
- El envío no se guarda en una cola offline. Para volver a intentarlo se juega una nueva partida; el historial local y el récord personal siguen disponibles.
- El ranking se consulta solo al abrir esa pantalla o al tocar **ACTUALIZAR**. Una respuesta tardía se descarta si el jugador ya volvió al menú o abrió otra consulta.

## Pruebas

Smoke test de Godot:

```sh
godot --headless --path . --script res://tests/smoke_test.gd
```

Supabase local:

```sh
npx --yes supabase@latest start
npx --yes supabase@latest db reset
npx --yes supabase@latest test db
```

El test pgTAP de Phase 6 verifica permisos, score mejor semanal, repetición idempotente, clasificación del usuario fuera del Top solicitado y uso del handle público. Revisar también [`supabase_rls_manual_test.md`](supabase_rls_manual_test.md) antes de aplicar la migración a un proyecto remoto de desarrollo.

## Validación server-side necesaria antes de publicar competencia

1. Crear un RPC `start_match` que emita ticket firmado/almacenado con `user_id`, temporada UTC, seed, versión de reglas y vencimiento.
2. Separar el RNG de gameplay de los efectos visuales y definir una simulación determinista versionada.
3. Registrar movimientos válidos o un replay compacto con tiempos relativos y límites de tamaño.
4. Verificar el resultado en servidor, imponer rate limits y reglas de score, y aceptar al ranking público solo scores verificados.
5. Mantener el score del cliente como dato reclamado para soporte, nunca como autoridad del ranking público.

Hasta completar esa verificación, esta implementación sirve para integración y pruebas con usuarios de desarrollo; no evita modificaciones del cliente ni trampas deliberadas.
