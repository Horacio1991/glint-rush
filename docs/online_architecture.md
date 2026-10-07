# Contrato online de GLINT RUSH

## Estado actual

La Fase 6 conecta el final de partidas autenticadas con Supabase y agrega una consulta de ranking semanal. El juego sigue siendo offline-first: gameplay, timer, cascadas, SPEED, especiales, Final Blast, revancha y récord local no dependen de HTTP. No hay matchmaking, PvP realtime, amigos operativos, compras ni anuncios.

## Responsabilidades

- `scripts/game.gd`: reglas, estado visual, transición resultados→menú y pantalla de ranking. No contiene peticiones HTTP.
- `scripts/online_contract.gd`: versiones de juego/protocolo y generación del `client_match_id` UUIDv4.
- `scripts/services/auth_service.gd`: OAuth Authorization Code + PKCE, refresh token y perfil público. Conserva `has_java_method()` para el JNISingleton Android.
- `scripts/services/online_service.gd`: configuración pública, autenticación previa a RPC, envío asíncrono, carga del ranking y errores de red.
- `supabase/migrations/`: tablas ya existentes, RLS, grants y RPCs versionados.

## Envío del resultado

`_finish_round()` espera a que termine Final Blast, persiste el récord local y abre resultados. Emite `round_finished(client_match_id, final_score, game_version, online_protocol_version, match_session_id)`. `OnlineService` conserva la señal pero hace POST a `submit_match_score` sin bloquear el hilo del juego. Solo se envían rondas con identidad autenticada disponible y versión de protocolo compatible.

El body contiene `p_client_match_id`, `p_game_version` y `p_score`; no contiene `user_id`, `season_id` ni email. El servidor usa `auth.uid()`, `get_current_season()` y `client_match_id` único por usuario. Los reintentos de la misma ronda son idempotentes y no pueden cambiar el score original.

Esta fase acepta el score reclamado por el cliente para desarrollo. La fila de `matches` usa `pending_review`, `score_verified` queda vacío y `session_id` es `NULL`: no se fabrica un ticket. Una partida sin sesión de Auth continúa localmente y conserva su récord.

## Temporadas y ranking

`get_current_season()` calcula semanas ISO en UTC usando hora PostgreSQL y crea la fila de esa semana. `submit_match_score()` inserta el historial en `matches` y hace upsert del máximo en `weekly_scores`; un score inferior no sustituye al mejor. Las temporadas anteriores y sus filas no se borran.

`get_weekly_leaderboard(p_limit)` devuelve posición, `handle`, `best_score`, `is_me`, clave de temporada y cierre UTC. La UI pide 20, muestra hasta 25 si se configura así, y recibe la fila propia adicional cuando queda fuera del top. Si aún no hay score propio, informa que no se clasificó esa semana. No incluye email. La carga ocurre al abrir la pantalla o actualizar; la respuesta se descarta si quedó obsoleta.

## RLS y claves

RLS sigue activo. `authenticated` no recibe escrituras directas a sesiones, partidas ni puntuaciones. `submit_match_score()` es `SECURITY DEFINER`, fija `search_path` vacío, exige `auth.uid()` y solo se concede a `authenticated`. El propietario de la fila se deriva del JWT. `get_weekly_leaderboard()` es `SECURITY INVOKER` y lee solo columnas ya concedidas por la fundación.

`backend_config.cfg` sigue fuera de Git. El juego solo utiliza URL y clave pública de Supabase. Nunca incluir `service_role`, una secret key ni Google Client Secret. El package Android sigue siendo `com.glintrush.game`; OAuth mantiene el deep link `glintrush://auth/callback`, PKCE y almacenamiento seguro Android.

## Fallos y modo offline

Los errores de configuración, Auth, HTTP, timeout o respuesta no válida producen un texto amigable. No detienen el cierre local de la partida ni el botón de revancha o regreso al menú. No hay cola local de scores para sincronizar más tarde. El ranking requiere sesión autenticada.

## Seguridad pendiente antes de competencia pública

El RPC limita score a rango no negativo, propietario, temporada del servidor e idempotencia, pero no valida que el cliente haya jugado legítimamente. Antes de publicación competitiva se necesita ticket server-side por partida, seed y versión de reglas, RNG de gameplay separado de efectos, registro/replay determinista, verificador de score en servidor, rate limits y ranking que cuente solo estados verificados. Consultar [`phase6_competitive.md`](phase6_competitive.md).
