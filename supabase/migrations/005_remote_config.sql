-- Remote config flags (readable by authenticated clients)

create table if not exists public.remote_config (
  key text primary key,
  value jsonb not null default 'false'::jsonb,
  description text,
  updated_at timestamptz not null default now()
);

create or replace function public.touch_remote_config_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists remote_config_updated_at on public.remote_config;
create trigger remote_config_updated_at
  before update on public.remote_config
  for each row execute function public.touch_remote_config_updated_at();

alter table public.remote_config enable row level security;

-- Clients may read flags; only service role / dashboard writes.
drop policy if exists "Authenticated users can read remote_config" on public.remote_config;
create policy "Authenticated users can read remote_config"
  on public.remote_config for select to authenticated using (true);

-- Membership / RevenueCat paywall — OFF by default.
insert into public.remote_config (key, value, description)
values (
  'membership_plan_enabled',
  'false'::jsonb,
  'When true, Oracy Plus (RevenueCat) paywall, quota, and membership UI are enabled.'
)
on conflict (key) do nothing;
