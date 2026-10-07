begin;
select plan(22);

select ok(has_function_privilege('authenticated', 'public.submit_match_score(uuid,text,bigint)', 'EXECUTE'), 'authenticated players can submit a score through the RPC');
select ok(not has_function_privilege('anon', 'public.submit_match_score(uuid,text,bigint)', 'EXECUTE'), 'anonymous players cannot submit scores');
select ok(has_function_privilege('authenticated', 'public.get_weekly_leaderboard(integer)', 'EXECUTE'), 'authenticated players can read the weekly leaderboard');
select ok(not has_function_privilege('anon', 'public.get_weekly_leaderboard(integer)', 'EXECUTE'), 'anonymous players cannot read the leaderboard');
select ok(not has_table_privilege('authenticated', 'public.matches', 'INSERT'), 'score submissions do not grant direct match writes');
select ok(not has_table_privilege('authenticated', 'public.weekly_scores', 'INSERT'), 'score submissions do not grant direct weekly-score writes');
select ok((select is_nullable = 'YES' from information_schema.columns where table_schema = 'public' and table_name = 'matches' and column_name = 'session_id'), 'client-authoritative records do not fabricate a server match session');
select ok((select not pg_catalog.pg_get_function_result('public.get_weekly_leaderboard(integer)'::regprocedure) ilike '%email%'), 'leaderboard RPC exposes no email column');

insert into auth.users (id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
    ('60000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'phase6-a@example.invalid', '', '{}', '{"name":"Competidor A"}', now(), now()),
    ('60000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'phase6-b@example.invalid', '', '{}', '{"name":"Competidor B"}', now(), now());

set local role authenticated;
set local request.jwt.claim.sub = '60000000-0000-4000-8000-000000000001';
select is((public.submit_match_score('61000000-0000-4000-8000-000000000001', '0.1.0', 1200)->>'accepted')::boolean, true, 'first authenticated score submission is accepted');
select is((select status from public.matches where user_id = auth.uid() and client_match_id = '61000000-0000-4000-8000-000000000001'), 'pending_review', 'client-declared scores remain marked for future server review');
select is((select score_claimed from public.matches where user_id = auth.uid() and client_match_id = '61000000-0000-4000-8000-000000000001'), 1200::bigint, 'match history stores the submitted score');
select is((public.submit_match_score('61000000-0000-4000-8000-000000000001', '0.1.0', 999999)->>'duplicate')::boolean, true, 'repeating a client match id is idempotent');
select is((select count(*) from public.matches where user_id = auth.uid() and client_match_id = '61000000-0000-4000-8000-000000000001'), 1::bigint, 'idempotent repeat does not create another match');
select is((select score_claimed from public.matches where user_id = auth.uid() and client_match_id = '61000000-0000-4000-8000-000000000001'), 1200::bigint, 'idempotent repeat cannot rewrite its original score');
select lives_ok($$select public.submit_match_score('61000000-0000-4000-8000-000000000002', '0.1.0', 1900)$$, 'a later higher score is accepted');
select lives_ok($$select public.submit_match_score('61000000-0000-4000-8000-000000000003', '0.1.0', 1500)$$, 'a later lower score is accepted without replacing the best');
select is((select ws.best_score from public.weekly_scores as ws where ws.user_id = auth.uid()), 1900::bigint, 'weekly score keeps the player best, not the latest score');

set local request.jwt.claim.sub = '60000000-0000-4000-8000-000000000002';
select lives_ok($$select public.submit_match_score('62000000-0000-4000-8000-000000000001', '0.1.0', 2600)$$, 'a second authenticated player can submit their own score');
select is((select ws.best_score from public.weekly_scores as ws where ws.user_id = auth.uid()), 2600::bigint, 'each authenticated identity writes only its own weekly best');

set local request.jwt.claim.sub = '60000000-0000-4000-8000-000000000001';
select is((select position from public.get_weekly_leaderboard(1) where is_me), 2::bigint, 'player outside the requested Top 1 still receives their position');
select is((select count(*) from public.get_weekly_leaderboard(1)), 2::bigint, 'leaderboard returns Top N plus the current player when outside it');
select ok((select handle ~ '^player[a-f0-9]{10}$' from public.get_weekly_leaderboard(1) where is_me), 'leaderboard identifies the player using the public handle');

reset role;
select * from finish();
rollback;
