-- User identity lookup for ops / analytics: resolve auth user_id from phone, email,
-- referral code, or UUID. Email is mirrored onto profiles for easier joins.

alter table public.profiles
  add column if not exists email text;

comment on column public.profiles.email is
  'Primary email from auth.users (Apple/Google). Synced for lookup; not client-writable.';

create unique index if not exists profiles_email_uidx
  on public.profiles (lower(email))
  where email is not null and length(trim(email)) > 0;

-- Backfill from auth.users.
update public.profiles p
   set email = nullif(lower(trim(u.email)), '')
  from auth.users u
 where u.id = p.id
   and u.email is not null
   and nullif(trim(u.email), '') is not null
   and (p.email is null or p.email is distinct from lower(trim(u.email)));

-- Keep profiles.email in sync when auth.users.email changes.
create or replace function public.sync_profile_email_from_auth()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
     set email = nullif(lower(trim(new.email)), ''),
         updated_at = now()
   where id = new.id;
  return new;
end;
$$;

drop trigger if exists on_auth_user_email_sync on auth.users;
create trigger on_auth_user_email_sync
  after insert or update of email on auth.users
  for each row
  execute function public.sync_profile_email_from_auth();

-- Clients must not overwrite email via normal profile updates.
create or replace function public.prevent_client_email_overwrite()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE'
     and new.email is distinct from old.email
     and auth.role() = 'authenticated'
  then
    new.email := old.email;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_protect_email on public.profiles;
create trigger profiles_protect_email
  before update on public.profiles
  for each row
  execute function public.prevent_client_email_overwrite();

-- ---------------------------------------------------------------------------
-- Resolve a user_id from phone / email / referral code / UUID.
-- Service role (SQL editor / dashboards) only — not exposed to app clients.
-- ---------------------------------------------------------------------------
create or replace function public.resolve_user_id(p_query text)
returns table (
  user_id uuid,
  matched_by text,
  phone text,
  email text,
  display_name text,
  referral_code text,
  onboarding_completed boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  q text := nullif(trim(p_query), '');
  digits text;
  e164 text;
begin
  if q is null then
    return;
  end if;

  -- Exact UUID
  if q ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return query
    select
      p.id,
      'user_id'::text,
      p.phone,
      p.email,
      p.display_name,
      p.referral_code,
      p.onboarding_completed
    from public.profiles p
    where p.id = q::uuid;
    if found then
      return;
    end if;
  end if;

  -- Referral code (6–10 alnum)
  if length(q) between 6 and 10 and q ~* '^[a-z0-9]+$' then
    return query
    select
      p.id,
      'referral_code'::text,
      p.phone,
      p.email,
      p.display_name,
      p.referral_code,
      p.onboarding_completed
    from public.profiles p
    where upper(p.referral_code) = upper(q)
    limit 5;
    if found then
      return;
    end if;
  end if;

  -- Email
  if position('@' in q) > 1 then
    return query
    select
      p.id,
      'email'::text,
      p.phone,
      p.email,
      p.display_name,
      p.referral_code,
      p.onboarding_completed
    from public.profiles p
    where p.email = lower(q)
       or exists (
            select 1 from auth.users u
             where u.id = p.id and lower(trim(u.email)) = lower(q)
          )
    limit 5;
    if found then
      return;
    end if;
  end if;

  -- Phone: E.164 or last 10 digits (default +91 for 10-digit India numbers)
  digits := regexp_replace(q, '[^0-9+]', '', 'g');
  if digits like '+%' then
    e164 := digits;
  elsif length(regexp_replace(digits, '\D', '', 'g')) = 10 then
    e164 := '+91' || regexp_replace(digits, '\D', '', 'g');
  elsif length(regexp_replace(digits, '\D', '', 'g')) >= 10 then
    e164 := '+' || regexp_replace(digits, '\D', '', 'g');
  else
    e164 := null;
  end if;

  if e164 is not null then
    return query
    select
      p.id,
      'phone'::text,
      p.phone,
      p.email,
      p.display_name,
      p.referral_code,
      p.onboarding_completed
    from public.profiles p
    where p.phone = e164
       or right(regexp_replace(coalesce(p.phone, ''), '\D', '', 'g'), 10)
          = right(regexp_replace(e164, '\D', '', 'g'), 10)
    limit 5;
    if found then
      return;
    end if;
  end if;

  -- Display name (exact, case-insensitive) — last resort
  return query
  select
    p.id,
    'display_name'::text,
    p.phone,
    p.email,
    p.display_name,
    p.referral_code,
    p.onboarding_completed
  from public.profiles p
  where lower(trim(p.display_name)) = lower(q)
  limit 10;
end;
$$;

revoke all on function public.resolve_user_id(text) from public;
grant execute on function public.resolve_user_id(text) to service_role;

comment on function public.resolve_user_id(text) is
  'Ops lookup: find profiles by UUID, phone, email, referral code, or display name. Service role only.';

-- Convenience: analytics rows for an identity query.
create or replace function public.analytics_for_identity(p_query text, p_limit integer default 100)
returns table (
  event_id uuid,
  user_id uuid,
  name text,
  properties jsonb,
  created_at timestamptz,
  matched_by text,
  phone text,
  email text,
  display_name text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select
    e.id,
    e.user_id,
    e.name,
    e.properties,
    e.created_at,
    r.matched_by,
    r.phone,
    r.email,
    r.display_name
  from public.resolve_user_id(p_query) r
  join public.analytics_events e on e.user_id = r.user_id
  order by e.created_at desc
  limit greatest(1, least(coalesce(p_limit, 100), 1000));
end;
$$;

revoke all on function public.analytics_for_identity(text, integer) from public;
grant execute on function public.analytics_for_identity(text, integer) to service_role;

comment on function public.analytics_for_identity(text, integer) is
  'Ops: latest analytics events for a user resolved by phone/email/code/UUID.';

-- Directory view for SQL editor (service role). Joins profile + auth email + providers.
create or replace view public.user_directory
with (security_invoker = false)
as
select
  p.id as user_id,
  p.display_name,
  p.phone,
  coalesce(p.email, nullif(lower(trim(u.email)), '')) as email,
  p.referral_code,
  p.onboarding_completed,
  p.streak_count,
  p.created_at as profile_created_at,
  u.created_at as auth_created_at,
  u.last_sign_in_at,
  (
    select coalesce(array_agg(distinct i.provider order by i.provider), '{}')
    from auth.identities i
    where i.user_id = p.id
  ) as auth_providers
from public.profiles p
left join auth.users u on u.id = p.id;

comment on view public.user_directory is
  'Ops directory of users with phone, email, referral code, and auth providers.';

revoke all on public.user_directory from public;
grant select on public.user_directory to service_role;
