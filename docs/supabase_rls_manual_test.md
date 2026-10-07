# Prueba manual de RLS con usuarios A, B y anon

Hacerlo solo en Supabase local o en un proyecto de desarrollo descartable. El test pgTAP automático verifica grants/RLS habilitado; este procedimiento verifica las policies con identidad simulada por JWT dentro de Postgres.

## 1. Preparar usuarios de prueba locales

1. Ejecutar `supabase start` y abrir Studio local.
2. En **Authentication → Users**, crear tres usuarios de prueba locales. No usar cuentas reales de Google ni datos personales. Copiar UUID de A, B y C.
3. En SQL Editor local, reemplazar `UUID_A`, `UUID_B`, `UUID_C` por esos UUIDs y ejecutar:

```sql
do $fixture$
declare
  a uuid := 'UUID_A';
  b uuid := 'UUID_B';
  c uuid := 'UUID_C';
  s uuid;
  session_b uuid;
  match_b uuid;
  week_start timestamptz := timestamptz '2026-10-05 00:00:00+00';
begin
  insert into public.profiles (id, handle, display_name)
  values (a, 'testa01', 'Test A'), (b, 'testb01', 'Test B'), (c, 'testc01', 'Test C')
  on conflict (id) do nothing;

  insert into public.seasons (season_key, starts_at, ends_at)
  values ('2026-W41', week_start, week_start + interval '7 days')
  on conflict (season_key) do nothing;
  select id into s from public.seasons where season_key = '2026-W41';

  insert into public.friendships (user_low, user_high, requested_by, status, responded_at)
  values (least(b, c), greatest(b, c), b, 'accepted', pg_catalog.clock_timestamp())
  on conflict (user_low, user_high) do nothing;

  insert into public.match_sessions (user_id, season_id, seed, game_version, started_at, expires_at)
  values (b, s, 12345, '0.1.0', week_start, week_start + interval '60 seconds')
  returning id into session_b;

  insert into public.matches (user_id, season_id, session_id, client_match_id, game_version, score_claimed, status)
  values (b, s, session_b, '00000000-0000-4000-8000-0000000000b1', '0.1.0', 12345, 'received')
  returning id into match_b;

  insert into public.weekly_scores (season_id, user_id, best_score, best_match_id, achieved_at)
  values (s, b, 12345, match_b, week_start + interval '30 seconds')
  on conflict (season_id, user_id) do nothing;
end
$fixture$;
```

If the test seeding script is re-run and hits a uniqueness/FK conflict, reset the local database with `supabase db reset` and recreate test users before running it again.

## 2. Simular authenticated A

En SQL Editor local, usando UUID_A:

```sql
begin;
set local role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub', 'UUID_A', true);

-- Debe devolver 0: A no lee las partidas de B.
select count(*) as visible_matches_from_b
from public.matches where user_id = 'UUID_B';

-- Debe devolver 0: A no lee la relación de amistad B–C.
select count(*) as visible_friendships_between_b_and_c
from public.friendships
where user_low = least('UUID_B'::uuid, 'UUID_C'::uuid)
  and user_high = greatest('UUID_B'::uuid, 'UUID_C'::uuid);

-- Debe devolver 1: los scores son visibles a usuarios autenticados.
select count(*) as visible_public_score
from public.weekly_scores where user_id = 'UUID_B';
rollback;
```

## 3. Intentos que deben fallar

Ejecutar cada bloque por separado. Resultado esperado: `permission denied`/SQLSTATE `42501`; el juego jamás ejecuta estas escrituras directamente.

```sql
begin;
set local role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub', 'UUID_A', true);
update public.weekly_scores set best_score = 999999999 where user_id = 'UUID_B';
rollback;
```

```sql
begin;
set local role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub', 'UUID_A', true);
insert into public.match_sessions (user_id, season_id, seed, game_version, expires_at)
values ('UUID_A', (select id from public.seasons where season_key = '2026-W41'), 99, '0.1.0', pg_catalog.clock_timestamp() + interval '1 minute');
rollback;
```

```sql
begin;
set local role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub', 'UUID_A', true);
insert into public.matches (user_id, season_id, session_id, client_match_id, game_version, score_claimed)
select 'UUID_B', season_id, session_id, '00000000-0000-4000-8000-0000000000b2', '0.1.0', 999999999
from public.matches where user_id = 'UUID_B' limit 1;
rollback;
```

Para comprobar una fila de perfil propia sí se puede actualizar `display_name` o `avatar_key`; intentar cambiar `handle` debe producir error de privilegios. `anon` debe carecer de SELECT en perfiles y scores.

> Importante: SQL Editor tiene privilegios administrativos; los `SET LOCAL ROLE` y el claim simulado son solo una prueba local de policies. No usar este método para autenticar una app ni confiar en claims que un cliente pudiera establecer directamente. En producción, PostgREST valida el JWT firmado por Supabase Auth.
