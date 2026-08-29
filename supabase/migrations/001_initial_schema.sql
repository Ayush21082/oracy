-- OneWord Phase 1 MVP Schema

-- Profiles (extends auth.users)
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  goals text[] default '{}',
  experience_level text not null default 'beginner'
    check (experience_level in ('beginner', 'intermediate', 'advanced', 'expert')),
  streak_count integer not null default 0,
  last_practice_date date,
  timezone text not null default 'UTC',
  onboarding_completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Challenge bank
create table public.challenges (
  id uuid primary key default gen_random_uuid(),
  prompt text not null,
  category text not null
    check (category in ('everyday', 'opinion', 'storytelling', 'imagine', 'work', 'debate', 'interview')),
  difficulty text not null
    check (difficulty in ('beginner', 'intermediate', 'advanced', 'expert')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- One challenge per user per day
create table public.daily_assignments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  challenge_id uuid not null references public.challenges(id),
  assigned_date date not null,
  created_at timestamptz not null default now(),
  unique (user_id, assigned_date)
);

-- Speaking sessions
create table public.sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  challenge_id uuid not null references public.challenges(id),
  audio_path text,
  transcript text,
  duration_seconds numeric,
  word_count integer,
  words_per_minute numeric,
  filler_count integer,
  feedback_json jsonb,
  overall_score integer,
  attempt_number integer not null default 1,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'failed')),
  created_at timestamptz not null default now()
);

-- Saved vocabulary (schema for Phase 2)
create table public.saved_words (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  word text not null,
  definition text,
  example text,
  session_id uuid references public.sessions(id) on delete set null,
  created_at timestamptz not null default now()
);

-- Indexes
create index idx_sessions_user_created on public.sessions(user_id, created_at desc);
create index idx_daily_assignments_user_date on public.daily_assignments(user_id, assigned_date desc);
create index idx_challenges_difficulty on public.challenges(difficulty) where active = true;

-- Updated_at trigger
create or replace function public.handle_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger profiles_updated_at
  before update on public.profiles
  for each row execute function public.handle_updated_at();

-- Auto-create profile on signup
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', 'Speaker')
  );
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Assign daily challenge function
create or replace function public.assign_daily_challenge(p_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date;
  v_tz text;
  v_level text;
  v_goals text[];
  v_existing uuid;
  v_challenge_id uuid;
  v_recent_ids uuid[];
begin
  select timezone, experience_level, goals
  into v_tz, v_level, v_goals
  from public.profiles
  where id = p_user_id;

  v_today := (now() at time zone coalesce(v_tz, 'UTC'))::date;

  select challenge_id into v_existing
  from public.daily_assignments
  where user_id = p_user_id and assigned_date = v_today;

  if v_existing is not null then
    return v_existing;
  end if;

  select array_agg(challenge_id) into v_recent_ids
  from public.daily_assignments
  where user_id = p_user_id
    and assigned_date >= v_today - interval '14 days';

  select c.id into v_challenge_id
  from public.challenges c
  where c.active = true
    and c.difficulty = coalesce(v_level, 'intermediate')
    and (v_recent_ids is null or c.id != all(v_recent_ids))
  order by random()
  limit 1;

  if v_challenge_id is null then
    select c.id into v_challenge_id
    from public.challenges c
    where c.active = true
      and (v_recent_ids is null or c.id != all(v_recent_ids))
    order by random()
    limit 1;
  end if;

  if v_challenge_id is null then
    raise exception 'No active challenges available';
  end if;

  insert into public.daily_assignments (user_id, challenge_id, assigned_date)
  values (p_user_id, v_challenge_id, v_today);

  return v_challenge_id;
end;
$$;

-- Update streak function
create or replace function public.update_streak(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date;
  v_tz text;
  v_last date;
  v_streak integer;
begin
  select timezone, last_practice_date, streak_count
  into v_tz, v_last, v_streak
  from public.profiles
  where id = p_user_id;

  v_today := (now() at time zone coalesce(v_tz, 'UTC'))::date;

  if v_last = v_today then
    return v_streak;
  elsif v_last = v_today - 1 then
    v_streak := v_streak + 1;
  else
    v_streak := 1;
  end if;

  update public.profiles
  set streak_count = v_streak, last_practice_date = v_today
  where id = p_user_id;

  return v_streak;
end;
$$;

-- RLS
alter table public.profiles enable row level security;
alter table public.challenges enable row level security;
alter table public.daily_assignments enable row level security;
alter table public.sessions enable row level security;
alter table public.saved_words enable row level security;

-- Profiles policies
create policy "Users can view own profile"
  on public.profiles for select using (auth.uid() = id);
create policy "Users can update own profile"
  on public.profiles for update using (auth.uid() = id);

-- Challenges are readable by all authenticated users
create policy "Authenticated users can read challenges"
  on public.challenges for select to authenticated using (true);

-- Daily assignments
create policy "Users can view own assignments"
  on public.daily_assignments for select using (auth.uid() = user_id);
create policy "Users can insert own assignments"
  on public.daily_assignments for insert with check (auth.uid() = user_id);
create policy "Users can update own assignments"
  on public.daily_assignments for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Sessions
create policy "Users can view own sessions"
  on public.sessions for select using (auth.uid() = user_id);
create policy "Users can insert own sessions"
  on public.sessions for insert with check (auth.uid() = user_id);
create policy "Users can update own sessions"
  on public.sessions for update using (auth.uid() = user_id);
create policy "Users can delete own sessions"
  on public.sessions for delete using (auth.uid() = user_id);

-- Saved words
create policy "Users can manage own saved words"
  on public.saved_words for all using (auth.uid() = user_id);

-- Storage bucket (run via dashboard or storage migration)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'session-audio',
  'session-audio',
  false,
  10485760,
  array['audio/m4a', 'audio/mp4', 'audio/mpeg', 'audio/wav', 'audio/x-m4a']
) on conflict (id) do nothing;

-- Storage RLS
create policy "Users can upload own audio"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'session-audio'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );

create policy "Users can update own audio"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'session-audio'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  )
  with check (
    bucket_id = 'session-audio'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );

create policy "Users can read own audio"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'session-audio'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );

create policy "Users can delete own audio"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'session-audio'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );

-- Service role can read all audio (for edge functions)
create policy "Service role can read all audio"
  on storage.objects for select to service_role
  using (bucket_id = 'session-audio');
