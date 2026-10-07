-- Phase 6: authenticated client score submission and weekly public ranking.
-- Scores remain client-authoritative in this development phase; see docs/phase6_competitive.md.

-- Existing server-issued sessions remain supported. A client-authoritative
-- submission has no server match ticket, so its match row uses NULL here.
alter table public.matches alter column session_id drop not null;

create or replace function public.submit_match_score(
    p_client_match_id uuid,
    p_game_version text,
    p_score bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_uid uuid := auth.uid();
    v_season_id uuid;
    v_season_key text;
    v_season_ends_at timestamptz;
    v_match_id uuid;
    v_best_score bigint;
    v_score_claimed bigint;
    v_duplicate boolean := false;
begin
    if v_uid is null then
        raise exception 'authentication required' using errcode = '28000';
    end if;
    if p_client_match_id is null then
        raise exception 'client match id is required' using errcode = '22023';
    end if;
    if p_game_version is null or pg_catalog.char_length(p_game_version) not between 1 and 40 then
        raise exception 'invalid game version' using errcode = '22023';
    end if;
    if p_score is null or p_score < 0 or p_score > 1000000000000 then
        raise exception 'invalid score' using errcode = '22023';
    end if;

    select s.season_id, s.season_key, s.ends_at
      into v_season_id, v_season_key, v_season_ends_at
      from public.get_current_season() as s;

    insert into public.matches (
        user_id, season_id, session_id, client_match_id,
        game_version, score_claimed, status
    ) values (
        v_uid, v_season_id, null, p_client_match_id,
        p_game_version, p_score, 'pending_review'
    )
    on conflict (user_id, client_match_id) do nothing
    returning id into v_match_id;

    if v_match_id is null then
        v_duplicate := true;
        select m.id, m.season_id, m.score_claimed, s.season_key, s.ends_at
          into v_match_id, v_season_id, v_score_claimed, v_season_key, v_season_ends_at
          from public.matches as m
          join public.seasons as s on s.id = m.season_id
         where m.user_id = v_uid
           and m.client_match_id = p_client_match_id;
    else
        insert into public.weekly_scores (
            season_id, user_id, best_score, best_match_id, achieved_at
        ) values (
            v_season_id, v_uid, p_score, v_match_id, pg_catalog.clock_timestamp()
        )
        on conflict (season_id, user_id) do update
            set best_score = excluded.best_score,
                best_match_id = excluded.best_match_id,
                achieved_at = excluded.achieved_at
          where public.weekly_scores.best_score < excluded.best_score;
    end if;

    select ws.best_score
      into v_best_score
      from public.weekly_scores as ws
     where ws.season_id = v_season_id
       and ws.user_id = v_uid;

    return pg_catalog.jsonb_build_object(
        'accepted', true,
        'duplicate', v_duplicate,
        'match_id', v_match_id,
        'season_key', v_season_key,
        'season_ends_at', v_season_ends_at,
        'score_claimed', coalesce(v_score_claimed, p_score),
        'best_score', v_best_score,
        'validation_status', 'pending_review'
    );
end;
$$;
revoke all on function public.submit_match_score(uuid, text, bigint) from public, anon, authenticated;
grant execute on function public.submit_match_score(uuid, text, bigint) to authenticated;

create or replace function public.get_weekly_leaderboard(p_limit integer default 20)
returns table (
    season_key text,
    season_ends_at timestamptz,
    position bigint,
    handle text,
    best_score bigint,
    is_me boolean
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_uid uuid := auth.uid();
    v_season_id uuid;
    v_season_key text;
    v_season_ends_at timestamptz;
    v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 25);
begin
    if v_uid is null then
        raise exception 'authentication required' using errcode = '28000';
    end if;

    select s.season_id, s.season_key, s.ends_at
      into v_season_id, v_season_key, v_season_ends_at
      from public.get_current_season() as s;

    return query
    with ranked as (
        select
            pg_catalog.row_number() over (
                order by ws.best_score desc, ws.achieved_at asc, ws.user_id asc
            ) as player_position,
            p.handle as player_handle,
            ws.best_score as player_score,
            ws.user_id as player_id
        from public.weekly_scores as ws
        join public.profiles as p on p.id = ws.user_id
        where ws.season_id = v_season_id
    )
    select
        v_season_key,
        v_season_ends_at,
        r.player_position,
        r.player_handle,
        r.player_score,
        r.player_id = v_uid
    from ranked as r
    where r.player_position <= v_limit or r.player_id = v_uid
    order by r.player_position;
end;
$$;
revoke all on function public.get_weekly_leaderboard(integer) from public, anon, authenticated;
grant execute on function public.get_weekly_leaderboard(integer) to authenticated;
