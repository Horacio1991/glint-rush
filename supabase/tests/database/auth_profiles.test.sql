begin;
select plan(15);

insert into auth.users (id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
    ('10000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'phase4-a@example.invalid', '', '{}', '{"full_name":"  Ada   Vela "}', now(), now()),
    ('10000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'phase4-b@example.invalid', '', '{}', '{"name":"Jugador Dos"}', now(), now());

select is((select id from public.profiles where id = '10000000-0000-4000-8000-000000000001'), '10000000-0000-4000-8000-000000000001'::uuid, 'new auth user receives an id-matched profile');
select is((select display_name from public.profiles where id = '10000000-0000-4000-8000-000000000001'), 'Ada   Vela', 'public name is trimmed and copied from provider metadata');
select ok((select handle ~ '^player[a-f0-9]{10}$' from public.profiles where id = '10000000-0000-4000-8000-000000000001'), 'generated handle uses the constrained public format');
select is((select count(*) from public.profiles where id in ('10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002')), 2::bigint, 'two users receive profiles');
select is((select count(distinct handle) from public.profiles where id in ('10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002')), 2::bigint, 'handles are unique');
select ok(not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name = 'email'), 'profile does not store an email address');
select ok(has_function_privilege('authenticated', 'public.touch_current_profile_last_seen()', 'EXECUTE'), 'authenticated users can call the bounded activity RPC');
select ok(not has_function_privilege('anon', 'public.touch_current_profile_last_seen()', 'EXECUTE'), 'anonymous users cannot call the activity RPC');
select ok(not has_column_privilege('authenticated', 'public.profiles', 'handle', 'UPDATE'), 'clients cannot update their permanent handle');
select ok(exists (select 1 from pg_catalog.pg_indexes where schemaname = 'public' and tablename = 'profiles' and indexname = 'profiles_handle_unique' and indexdef like '%UNIQUE%'), 'profile handle has a unique index');

set local role authenticated;
set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
update public.profiles set display_name = 'Ada V.', avatar_key = 'avatar-crystal-blue' where id = '10000000-0000-4000-8000-000000000001';
select is((select display_name from public.profiles where id = '10000000-0000-4000-8000-000000000001'), 'Ada V.', 'owner may update an approved public field');
select is((select avatar_key from public.profiles where id = '10000000-0000-4000-8000-000000000001'), 'avatar-crystal-blue', 'owner may update the approved avatar key');
update public.profiles set display_name = 'forbidden' where id = '10000000-0000-4000-8000-000000000002';
select is((select display_name from public.profiles where id = '10000000-0000-4000-8000-000000000002'), 'Jugador Dos', 'RLS prevents one user from changing another profile');
select lives_ok('select public.touch_current_profile_last_seen()', 'authenticated owner can touch their activity timestamp');
reset role;

set local role anon;
select ok(not has_table_privilege('anon', 'public.profiles', 'SELECT'), 'anonymous role cannot read profiles');
reset role;

select * from finish();
rollback;
