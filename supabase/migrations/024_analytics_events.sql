-- Client analytics event log (product tracking).

create table if not exists public.analytics_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  client_event_id uuid not null default gen_random_uuid(),
  name text not null,
  properties jsonb not null default '{}'::jsonb,
  platform text not null default 'ios',
  app_version text,
  install_id text,
  session_id text,
  created_at timestamptz not null default now(),
  unique (user_id, client_event_id)
);

create index if not exists idx_analytics_events_user_created
  on public.analytics_events (user_id, created_at desc);

create index if not exists idx_analytics_events_name_created
  on public.analytics_events (name, created_at desc);

alter table public.analytics_events enable row level security;

-- Clients may insert their own rows only.
drop policy if exists "Users can insert own analytics_events" on public.analytics_events;
create policy "Users can insert own analytics_events"
  on public.analytics_events
  for insert
  to authenticated
  with check (auth.uid() = user_id);

-- Optional read of own events (debug / support). Service role for dashboards.
drop policy if exists "Users can read own analytics_events" on public.analytics_events;
create policy "Users can read own analytics_events"
  on public.analytics_events
  for select
  to authenticated
  using (auth.uid() = user_id);

-- Batch insert: forces user_id = auth.uid(), ignores client-supplied user ids.
create or replace function public.track_analytics_events(events jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  inserted integer := 0;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  if events is null or jsonb_typeof(events) <> 'array' then
    return 0;
  end if;

  insert into public.analytics_events (
    user_id,
    client_event_id,
    name,
    properties,
    platform,
    app_version,
    install_id,
    session_id,
    created_at
  )
  select
    uid,
    coalesce((e->>'client_event_id')::uuid, gen_random_uuid()),
    trim(e->>'name'),
    coalesce(e->'properties', '{}'::jsonb),
    coalesce(nullif(trim(e->>'platform'), ''), 'ios'),
    nullif(trim(e->>'app_version'), ''),
    nullif(trim(e->>'install_id'), ''),
    nullif(trim(e->>'session_id'), ''),
    coalesce((e->>'created_at')::timestamptz, now())
  from jsonb_array_elements(events) as e
  where coalesce(trim(e->>'name'), '') <> ''
  on conflict (user_id, client_event_id) do nothing;

  get diagnostics inserted = row_count;
  return inserted;
end;
$$;

grant execute on function public.track_analytics_events(jsonb) to authenticated;

comment on table public.analytics_events is
  'Product analytics events from the Oracy iOS client.';
comment on function public.track_analytics_events(jsonb) is
  'Batch-insert analytics events for the authenticated user.';
