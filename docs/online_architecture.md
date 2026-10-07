# Contrato online de GLINT RUSH (Fases 1–3)

## Alcance de esta versión

Este documento fija el límite entre el juego local y futuros servicios online. La partida sigue siendo local y offline-first. `OnlineService` no realiza login, no crea tickets de partida, no envía resultados y no sustituye el ranking de demostración. No existen todavía perfiles creados automáticamente ni un endpoint que acepte scores.

La base SQL sí reserva las tablas y permisos para las siguientes fases. `get_current_season()` es el único RPC funcional de esta etapa.

## Responsabilidades

- `scripts/game.gd`: gameplay, tablero, timer, puntuación, récord local, clasificación simulada y presentación. No hace consultas HTTP ni espera al backend.
- `scripts/online_contract.gd`: `GAME_VERSION`, `ONLINE_PROTOCOL_VERSION` y generación del `client_match_id`.
- `scripts/services/online_service.gd` (autoload `OnlineService`): configuración de URL/clave pública, peticiones HTTP JSON genéricas y no bloqueantes, timeout, reintentos acotados, estado y errores de transporte. No contiene reglas del juego.
- `supabase/migrations/`: esquema SQL, constraints, índices, permisos y RLS.

## Eventos y correlación

Al comenzar cada ronda local, `_start_game()` genera un UUIDv4 aleatorio mediante `Crypto.generate_random_bytes()`. No usa el RNG compartido por el juego y los efectos visuales. El mismo ID vive desde el countdown hasta el resultado. Se emite:

- `round_started(client_match_id, game_version, online_protocol_version)` al preparar la ronda.
- `round_finished(client_match_id, final_score, game_version, online_protocol_version, match_session_id)` cuando `_finish_round()` ya liquidó Final Blast, guardó el mejor récord local y cambió el estado a resultados.

El ID identifica un intento del cliente; no prueba identidad, score ni legitimidad. La identidad futura se obtiene exclusivamente de `auth.uid()` dentro del backend. El `match_session_id` está vacío en esta fase y no se debe inventar.

## Versiones

- `GAME_VERSION = 0.1.0`: versión inicial para el contrato; se sube cuando un cambio en gameplay o score afecta la interpretación de una partida.
- `ONLINE_PROTOCOL_VERSION = 1`: versión del formato de mensajes cliente/backend; solo cambia al cambiar su forma o semántica.

Ambas constantes viven en `OnlineContract`, no dispersas en `game.gd`. La siguiente fase debe asignar una versión de producto antes de aceptar partidas competitivas.

## Partida local y futura partida rankeada

Una partida sin ticket de backend (`match_session`) siempre se juega, puntúa y llega a resultados; persiste el récord en `user://glint_rush.cfg` y permite revancha. No puede incorporarse al ranking semanal.

Una futura partida rankeada necesitará un ticket de servidor que vincule `user_id`, `season_id`, seed, versión y caducidad. La temporada y sus tiempos se derivan de PostgreSQL UTC. El cliente no elige esos valores. No se aceptará score hasta que exista un `submit_match` seguro y una sesión auténtica; ambos están deliberadamente fuera de esta entrega.

## Persistencia y ranking

- `matches`: historial de partidas, con clave idempotente por `(user_id, client_match_id)` y un solo consumo por `session_id`.
- `weekly_scores`: máximo un agregado por `(season_id, user_id)`, independiente del récord local. Solo backend podrá escribirlo.
- Orden futuro: `best_score DESC`, `achieved_at ASC`, `user_id ASC`.
- `season_awards`: snapshot de podios con `display_name_snapshot`; `user_id` anulable para conservar el podio al anonimizar/eliminar la cuenta.
- Los scores de usuario no se borran al rotar de semana. Esta etapa no automatiza cierre ni premia ganadores.

## Offline y errores

`OnlineService` informa errores de configuración, red, timeout, JSON y HTTP por señales. No se invoca desde `_process()` ni es dependencia de `_start_game()` o `_finish_round()`. Sin URL/clave el servicio queda `unconfigured`; caída/timeout deja el servicio `offline`. Ambos estados preservan el juego local.

Los reintentos están limitados y solo pueden solicitarse para GET/HEAD o una operación con `idempotency_key`; no se reintenta un POST no idempotente. No se guardan scores offline pendientes en esta fase.

## Configuración pública y secretos

`SUPABASE_URL` y `SUPABASE_PUBLIC_KEY` identifican el proyecto cliente. Pueden ir en el build; la clave pública no reemplaza RLS. Se pueden cargar desde `backend_config.cfg` o variables de entorno. Ese archivo real está ignorado por Git. No poner `service_role`, secretos Google, contraseñas ni refresh tokens en recursos del juego. Tokens se añadirán con Auth y almacenamiento seguro en otra fase.

## Seguridad SQL actual

RLS está activado en todas las tablas. Los roles `anon` y `authenticated` no pueden escribir tablas de temporada, amistades, sesiones, matches, scores o podios directamente. `profiles` permite lectura autenticada de columnas públicas y concede escritura futura solo a `display_name` y `avatar_key`, sujeta a policy de propietario; el `handle` es permanente. `get_current_season()` requiere usuario autenticado, usa reloj PostgreSQL UTC, fija `search_path` vacío y no acepta timestamps del cliente.

No hay `start_match`, `submit_match`, Auth trigger, Google OAuth, cierre automático, ranking RPC ni CRUD RPC de amigos.

## Deuda técnica para replay/anticheat

El RNG de gameplay actualmente comparte generador con glints, partículas, estrellas y shake. No lo cambiamos para no variar generación observable. Antes de reproducir una partida en servidor habrá que separar streams de RNG, fijar reglas de orden y tie-break internos, y registrar intercambios manuales aceptados con tiempo relativo y versión del simulador.
