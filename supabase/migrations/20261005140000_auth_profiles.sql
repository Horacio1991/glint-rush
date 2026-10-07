-- Google Auth profile lifecycle for GLINT RUSH. Does not add match/ranking RPCs.
create unique index if not exists profiles_handle_unique on public.profiles (handle);

create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_candidate text;
    v_display_name text;
    v_attempt integer := 0;
begin
    if exists (select 1 from public.profiles p where p.id = new.id) then
        return new;
    end if;

    v_display_name := nullif(
        pg_catalog.left(
            pg_catalog.btrim(
                pg_catalog.regexp_replace(
                    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', ''),
                    '[[:cntrl:]]', '', 'g'
                )
            ), 24
        ), ''
    );
    if v_display_name is null then
        v_display_name := 'Jugador';
    end if;

    loop
        v_attempt := v_attempt + 1;
        if v_attempt > 10 then
            raise exception 'could not allocate a unique profile handle';
        end if;
        v_candidate := 'player' || pg_catalog.substr(pg_catalog.replace(pg_catalog.gen_random_uuid()::text, '-', ''), 1, 10);
        begin
            insert into public.profiles (id, handle, display_name, avatar_key, last_seen_at)
            values (new.id, v_candidate, v_display_name, null, pg_catalog.clock_timestamp())
            on conflict (id) do nothing;
            if exists (select 1 from public.profiles p where p.id = new.id) then
                return new;
            end if;
        exception when unique_violation then
            -- A random handle collided; generate a new one and retry.
        end;
    end loop;
end;
$$;
revoke all on function private.handle_new_auth_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created_glint_profile on auth.users;
create trigger on_auth_user_created_glint_profile
after insert on auth.users
for each row execute function private.handle_new_auth_user();

create or replace function public.touch_current_profile_last_seen()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_uid uuid := auth.uid();
begin
    if v_uid is null then
        raise exception 'authentication required' using errcode = '28000';
    end if;
    update public.profiles p
       set last_seen_at = pg_catalog.clock_timestamp()
     where p.id = v_uid
       and (p.last_seen_at is null or p.last_seen_at < pg_catalog.clock_timestamp() - interval '15 minutes');
end;
$$;
revoke all on function public.touch_current_profile_last_seen() from public, anon, authenticated;
grant execute on function public.touch_current_profile_last_seen() to authenticated;
