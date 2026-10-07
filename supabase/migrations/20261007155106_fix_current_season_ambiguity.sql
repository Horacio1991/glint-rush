create or replace function public.get_current_season()
returns table (
    season_id uuid,
    season_key text,
    starts_at timestamptz,
    ends_at timestamptz,
    status text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_now timestamptz;
    v_week_start timestamptz;
    v_week_end timestamptz;
    v_season_key text;
begin
    if auth.uid() is null then
        raise exception 'authentication required' using errcode = '28000';
    end if;

    v_now := pg_catalog.clock_timestamp();
    v_week_start := pg_catalog.date_trunc('week', v_now at time zone 'UTC') at time zone 'UTC';
    v_week_end := v_week_start + interval '7 days';
    v_season_key := pg_catalog.to_char(v_week_start at time zone 'UTC', 'IYYY-"W"IW');

    insert into public.seasons as seasons_table (
        season_key,
        starts_at,
        ends_at,
        status
    )
    values (
        v_season_key,
        v_week_start,
        v_week_end,
        'open'
    )
    on conflict (season_key) do nothing;

    return query
    select
        s.id,
        s.season_key,
        s.starts_at,
        s.ends_at,
        s.status
    from public.seasons as s
    where s.season_key = v_season_key;
end;
$$;

revoke all on function public.get_current_season() from public, anon, authenticated;
grant execute on function public.get_current_season() to authenticated;