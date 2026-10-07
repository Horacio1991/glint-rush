begin;
select plan(70);

-- Required tables.
select has_table('public', 'profiles', 'profiles exists');
select has_table('public', 'friendships', 'friendships exists');
select has_table('public', 'seasons', 'seasons exists');
select has_table('public', 'match_sessions', 'match_sessions exists');
select has_table('public', 'matches', 'matches exists');
select has_table('public', 'weekly_scores', 'weekly_scores exists');
select has_table('public', 'season_awards', 'season_awards exists');

-- RLS is enabled on every exposed project table.
select ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = 'public.profiles'::regclass), 'profiles has RLS');
select ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = 'public.friendships'::regclass), 'friendships has RLS');
select ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = 'public.seasons'::regclass), 'seasons has RLS');
select ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = 'public.match_sessions'::regclass), 'match_sessions has RLS');
select ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = 'public.matches'::regclass), 'matches has RLS');
select ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = 'public.weekly_scores'::regclass), 'weekly_scores has RLS');
select ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = 'public.season_awards'::regclass), 'season_awards has RLS');

-- Expected read/owner policies are installed, not just RLS flags.
select ok(exists (select 1 from pg_catalog.pg_policies where schemaname = 'public' and tablename = 'profiles' and policyname = 'profiles_read_authenticated'), 'public profile read policy exists');
select ok(exists (select 1 from pg_catalog.pg_policies where schemaname = 'public' and tablename = 'profiles' and policyname = 'profiles_update_own_public_fields'), 'owner profile update policy exists');
select ok(exists (select 1 from pg_catalog.pg_policies where schemaname = 'public' and tablename = 'friendships' and policyname = 'friendships_read_participants'), 'friendship participant policy exists');
select ok(exists (select 1 from pg_catalog.pg_policies where schemaname = 'public' and tablename = 'seasons' and policyname = 'seasons_read_authenticated'), 'season read policy exists');
select ok(exists (select 1 from pg_catalog.pg_policies where schemaname = 'public' and tablename = 'match_sessions' and policyname = 'match_sessions_read_owner'), 'session owner policy exists');
select ok(exists (select 1 from pg_catalog.pg_policies where schemaname = 'public' and tablename = 'matches' and policyname = 'matches_read_owner'), 'match owner policy exists');
select ok(exists (select 1 from pg_catalog.pg_policies where schemaname = 'public' and tablename = 'weekly_scores' and policyname = 'weekly_scores_read_authenticated'), 'weekly score read policy exists');
select ok(exists (select 1 from pg_catalog.pg_policies where schemaname = 'public' and tablename = 'season_awards' and policyname = 'season_awards_read_authenticated'), 'award read policy exists');

-- Authenticated read grants required by future public leaderboard/profile views.
select ok(has_column_privilege('authenticated', 'public.profiles', 'handle', 'SELECT'), 'authenticated may read the public profile handle');
select ok(has_table_privilege('authenticated', 'public.friendships', 'SELECT'), 'authenticated may select friendships subject to RLS');
select ok(has_table_privilege('authenticated', 'public.seasons', 'SELECT'), 'authenticated may read seasons');
select ok(has_table_privilege('authenticated', 'public.match_sessions', 'SELECT'), 'authenticated may select own sessions subject to RLS');
select ok(has_table_privilege('authenticated', 'public.matches', 'SELECT'), 'authenticated may select own matches subject to RLS');
select ok(has_column_privilege('authenticated', 'public.weekly_scores', 'best_score', 'SELECT'), 'authenticated may read public weekly score values');
select ok(has_table_privilege('authenticated', 'public.season_awards', 'SELECT'), 'authenticated may read awards');

-- Anonymous requests have no direct access to exposed tables.
select ok(not has_table_privilege('anon', 'public.profiles', 'SELECT'), 'anon cannot read profiles');
select ok(not has_table_privilege('anon', 'public.friendships', 'SELECT'), 'anon cannot read friendships');
select ok(not has_table_privilege('anon', 'public.seasons', 'SELECT'), 'anon cannot read seasons');
select ok(not has_table_privilege('anon', 'public.match_sessions', 'SELECT'), 'anon cannot read match_sessions');
select ok(not has_table_privilege('anon', 'public.matches', 'SELECT'), 'anon cannot read matches');
select ok(not has_table_privilege('anon', 'public.weekly_scores', 'SELECT'), 'anon cannot read weekly scores');
select ok(not has_table_privilege('anon', 'public.season_awards', 'SELECT'), 'anon cannot read awards');

-- No direct client writes to competitive/session/social records.
select ok(not has_table_privilege('authenticated', 'public.friendships', 'INSERT'), 'friendships cannot be inserted directly');
select ok(not has_table_privilege('authenticated', 'public.friendships', 'UPDATE'), 'friendships cannot be updated directly');
select ok(not has_table_privilege('authenticated', 'public.friendships', 'DELETE'), 'friendships cannot be deleted directly');
select ok(not has_table_privilege('authenticated', 'public.seasons', 'INSERT'), 'seasons cannot be inserted directly');
select ok(not has_table_privilege('authenticated', 'public.seasons', 'UPDATE'), 'seasons cannot be updated directly');
select ok(not has_table_privilege('authenticated', 'public.seasons', 'DELETE'), 'seasons cannot be deleted directly');
select ok(not has_table_privilege('authenticated', 'public.match_sessions', 'INSERT'), 'match sessions cannot be fabricated directly');
select ok(not has_table_privilege('authenticated', 'public.match_sessions', 'UPDATE'), 'match sessions cannot be modified directly');
select ok(not has_table_privilege('authenticated', 'public.match_sessions', 'DELETE'), 'match sessions cannot be deleted directly');
select ok(not has_table_privilege('authenticated', 'public.matches', 'INSERT'), 'matches cannot be inserted directly');
select ok(not has_table_privilege('authenticated', 'public.matches', 'UPDATE'), 'matches cannot be updated directly');
select ok(not has_table_privilege('authenticated', 'public.matches', 'DELETE'), 'matches cannot be deleted directly');
select ok(not has_table_privilege('authenticated', 'public.weekly_scores', 'INSERT'), 'weekly scores cannot be inserted directly');
select ok(not has_table_privilege('authenticated', 'public.weekly_scores', 'UPDATE'), 'weekly scores cannot be updated directly');
select ok(not has_table_privilege('authenticated', 'public.weekly_scores', 'DELETE'), 'weekly scores cannot be deleted directly');
select ok(not has_table_privilege('authenticated', 'public.season_awards', 'INSERT'), 'awards cannot be inserted directly');
select ok(not has_table_privilege('authenticated', 'public.season_awards', 'UPDATE'), 'awards cannot be updated directly');
select ok(not has_table_privilege('authenticated', 'public.season_awards', 'DELETE'), 'awards cannot be deleted directly');

-- Profile owner may edit only the approved public fields; identity/handle stay fixed.
select ok(has_column_privilege('authenticated', 'public.profiles', 'display_name', 'UPDATE'), 'display_name is an editable profile field');
select ok(has_column_privilege('authenticated', 'public.profiles', 'avatar_key', 'UPDATE'), 'avatar_key is an editable profile field');
select ok(not has_column_privilege('authenticated', 'public.profiles', 'handle', 'UPDATE'), 'handle is not editable by clients');
select ok(not has_table_privilege('authenticated', 'public.profiles', 'INSERT'), 'clients cannot create profiles directly');
select ok(not has_table_privilege('authenticated', 'public.profiles', 'DELETE'), 'clients cannot delete profiles directly');
select ok(not has_column_privilege('authenticated', 'public.profiles', 'last_seen_at', 'SELECT'), 'profile activity timestamps are not public');
select ok(not has_column_privilege('authenticated', 'public.weekly_scores', 'best_match_id', 'SELECT'), 'internal best-match link is not public');

-- RPC access, uniqueness and required ranking index.
select ok(has_function_privilege('authenticated', 'public.get_current_season()', 'EXECUTE'), 'authenticated may call get_current_season');
select ok(not has_function_privilege('anon', 'public.get_current_season()', 'EXECUTE'), 'anon cannot call get_current_season');
select ok(exists (select 1 from pg_catalog.pg_indexes where schemaname = 'public' and tablename = 'weekly_scores' and indexname = 'weekly_scores_leaderboard_idx'), 'weekly ranking index exists');
select ok(exists (select 1 from pg_catalog.pg_constraint where conrelid = 'public.profiles'::regclass and conname = 'profiles_handle_format' and contype = 'c'), 'profile handle format is constrained');
select ok(exists (select 1 from pg_catalog.pg_constraint where conrelid = 'public.weekly_scores'::regclass and contype = 'p'), 'one primary key enforces one weekly score per user/season');
select ok(exists (select 1 from pg_catalog.pg_constraint where conrelid = 'public.matches'::regclass and conname = 'matches_client_idempotency' and contype = 'u'), 'match client idempotency is unique per player');
select ok(exists (select 1 from pg_catalog.pg_constraint where conrelid = 'public.matches'::regclass and contype = 'u' and pg_catalog.pg_get_constraintdef(oid) like 'UNIQUE (session_id)%'), 'a server session can be consumed by at most one match');
select ok((select p.prosecdef from pg_catalog.pg_proc p where p.oid = 'public.get_current_season()'::regprocedure), 'season RPC runs with a restricted definer');
select ok((select p.proconfig is not null and p.proconfig::text like '%search_path=%' from pg_catalog.pg_proc p where p.oid = 'public.get_current_season()'::regprocedure), 'season RPC pins its search_path');

select * from finish();
rollback;
