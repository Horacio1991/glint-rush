-- GLINT RUSH online foundation. No score-submission RPC is intentionally added.
-- Apply only after reviewing this migration in the target Supabase project.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table public.profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    handle text not null,
    display_name text not null,
    avatar_key text,
    created_at timestamptz not null default pg_catalog.clock_timestamp(),
    updated_at timestamptz not null default pg_catalog.clock_timestamp(),
    last_seen_at timestamptz,
    constraint profiles_handle_normalized check (handle = pg_catalog.lower(handle)),
    constraint profiles_handle_format check (handle ~ '^[a-z0-9]{3,16}$'),
    constraint profiles_display_name_length check (pg_catalog.char_length(display_name) between 1 and 24),
    constraint profiles_avatar_key_length check (avatar_key is null or pg_catalog.char_length(avatar_key) <= 80)
);

create table public.seasons (
    id uuid primary key default pg_catalog.gen_random_uuid(),
    season_key text not null unique,
    starts_at timestamptz not null,
    ends_at timestamptz not null,
    status text not null default 'open',
    closed_at timestamptz,
    constraint seasons_key_format check (season_key ~ '^[0-9]{4}-W(0[1-9]|[1-4][0-9]|5[0-3])$'),
    constraint seasons_start_monday_utc check (
        starts_at = pg_catalog.date_trunc('week', starts_at at time zone 'UTC') at time zone 'UTC'
    ),
    constraint seasons_window_length check (ends_at = starts_at + interval '7 days'),
    constraint seasons_status check (status in ('open', 'closed')),
    constraint seasons_closed_at_consistency check ((status = 'open' and closed_at is null) or (status = 'closed' and closed_at is not null))
);

create table public.friendships (
    user_low uuid not null references public.profiles (id) on delete cascade,
    user_high uuid not null references public.profiles (id) on delete cascade,
    requested_by uuid not null references public.profiles (id) on delete cascade,
    status text not null default 'pending',
    created_at timestamptz not null default pg_catalog.clock_timestamp(),
    responded_at timestamptz,
    constraint friendships_pair_pk primary key (user_low, user_high),
    constraint friendships_ordered_pair check (user_low < user_high),
    constraint friendships_requester_in_pair check (requested_by = user_low or requested_by = user_high),
    constraint friendships_status check (status in ('pending', 'accepted', 'rejected')),
    constraint friendships_response_time check (
        (status = 'pending' and responded_at is null)
        or (status in ('accepted', 'rejected') and responded_at is not null)
    )
);

create table public.match_sessions (
    id uuid primary key default pg_catalog.gen_random_uuid(),
    user_id uuid not null references public.profiles (id) on delete cascade,
    season_id uuid not null references public.seasons (id) on delete restrict,
    seed bigint not null,
    game_version text not null,
    started_at timestamptz not null default pg_catalog.clock_timestamp(),
    expires_at timestamptz not null,
    consumed_at timestamptz,
    constraint match_sessions_expiry check (expires_at > started_at),
    constraint match_sessions_game_version check (pg_catalog.char_length(game_version) between 1 and 40)
);

create table public.matches (
    id uuid primary key default pg_catalog.gen_random_uuid(),
    user_id uuid not null references public.profiles (id) on delete cascade,
    season_id uuid not null references public.seasons (id) on delete restrict,
    session_id uuid not null unique references public.match_sessions (id) on delete cascade,
    client_match_id uuid not null,
    game_version text not null,
    score_claimed bigint not null,
    score_verified bigint,
    status text not null default 'received',
    received_at timestamptz not null default pg_catalog.clock_timestamp(),
    replay_version integer,
    replay jsonb,
    constraint matches_client_idempotency unique (user_id, client_match_id),
    constraint matches_score_claimed_nonnegative check (score_claimed >= 0),
    constraint matches_score_verified_nonnegative check (score_verified is null or score_verified >= 0),
    constraint matches_status check (status in ('received', 'pending_review', 'verified', 'rejected')),
    constraint matches_game_version check (pg_catalog.char_length(game_version) between 1 and 40),
    constraint matches_replay_version check (replay_version is null or replay_version > 0)
);

create table public.weekly_scores (
    season_id uuid not null references public.seasons (id) on delete restrict,
    user_id uuid not null references public.profiles (id) on delete cascade,
    best_score bigint not null,
    best_match_id uuid not null references public.matches (id) on delete cascade,
    achieved_at timestamptz not null,
    primary key (season_id, user_id),
    constraint weekly_scores_nonnegative check (best_score >= 0),
    constraint weekly_scores_best_match_unique unique (best_match_id)
);

create table public.season_awards (
    season_id uuid not null references public.seasons (id) on delete restrict,
    rank smallint not null,
    user_id uuid references public.profiles (id) on delete set null,
    final_score bigint not null,
    achieved_at timestamptz not null,
    display_name_snapshot text not null,
    primary key (season_id, rank),
    constraint season_awards_rank check (rank between 1 and 3),
    constraint season_awards_score_nonnegative check (final_score >= 0),
    constraint season_awards_name_length check (pg_catalog.char_length(display_name_snapshot) between 1 and 40),
    constraint season_awards_one_award_per_user unique (season_id, user_id)
);

create index friendships_low_status_created_idx on public.friendships (user_low, status, created_at desc);
create index friendships_high_status_created_idx on public.friendships (user_high, status, created_at desc);
create index match_sessions_user_started_idx on public.match_sessions (user_id, started_at desc);
create index match_sessions_season_expiry_idx on public.match_sessions (season_id, expires_at);
create index matches_user_received_idx on public.matches (user_id, received_at desc);
create index matches_season_claimed_score_idx on public.matches (season_id, score_claimed desc);
create index weekly_scores_leaderboard_idx on public.weekly_scores (season_id, best_score desc, achieved_at asc, user_id asc);
create function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at := pg_catalog.clock_timestamp();
    return new;
end;
$$;
revoke all on function private.touch_updated_at() from public, anon, authenticated;
create trigger profiles_touch_updated_at
before update on public.profiles
for each row execute function private.touch_updated_at();

alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.seasons enable row level security;
alter table public.match_sessions enable row level security;
alter table public.matches enable row level security;
alter table public.weekly_scores enable row level security;
alter table public.season_awards enable row level security;

-- Remove inherited/default API table privileges first. Re-grant only intended access.
revoke all on table public.profiles, public.friendships, public.seasons,
    public.match_sessions, public.matches, public.weekly_scores, public.season_awards
from public, anon, authenticated;

grant select (id, handle, display_name, avatar_key) on table public.profiles to authenticated;
grant select on table public.friendships, public.seasons,
    public.match_sessions, public.matches, public.season_awards to authenticated;
grant select (season_id, user_id, best_score, achieved_at) on table public.weekly_scores to authenticated;
-- The permanent handle and identity key are not client-editable.
grant update (display_name, avatar_key) on table public.profiles to authenticated;

grant usage on schema public to authenticated;

create policy profiles_read_authenticated
on public.profiles for select to authenticated
using (true);
create policy profiles_update_own_public_fields
on public.profiles for update to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

create policy friendships_read_participants
on public.friendships for select to authenticated
using ((select auth.uid()) = user_low or (select auth.uid()) = user_high);

create policy seasons_read_authenticated
on public.seasons for select to authenticated
using (true);

create policy match_sessions_read_owner
on public.match_sessions for select to authenticated
using ((select auth.uid()) = user_id);

create policy matches_read_owner
on public.matches for select to authenticated
using ((select auth.uid()) = user_id);

create policy weekly_scores_read_authenticated
on public.weekly_scores for select to authenticated
using (true);

create policy season_awards_read_authenticated
on public.season_awards for select to authenticated
using (true);

-- Only authenticated users can ask for the current ISO-8601 UTC season.
-- The function creates the season idempotently; old seasons are not closed here.
create function public.get_current_season()
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

    insert into public.seasons (season_key, starts_at, ends_at, status)
    values (v_season_key, v_week_start, v_week_end, 'open')
    on conflict (season_key) do nothing;

    return query
    select s.id, s.season_key, s.starts_at, s.ends_at, s.status
    from public.seasons as s
    where s.season_key = v_season_key;
end;
$$;
revoke all on function public.get_current_season() from public, anon, authenticated;
grant execute on function public.get_current_season() to authenticated;
