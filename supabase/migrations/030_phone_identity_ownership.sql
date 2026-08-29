-- One verified phone number = one account identity.
--
-- Root cause (021_phone_oauth_ownership): an established Apple/Google user could
-- silently take a phone that already belonged to an independent phone-only
-- account. After that steal, phone OTP login raised PHONE_OWNED_BY_OAUTH_ACCOUNT
-- and locked the owner out.
--
-- Rules:
--   free number                              → attach
--   already on current user                  → noop
--   other owner + current is a fresh guest   → PHONE_LOGIN_SWITCH_REQUIRED
--     (app mints a session for the owner after OTP)
--   other owner + current is established     → PHONE_ALREADY_ASSOCIATED_WITH_ANOTHER_ACCOUNT
--   leftover incomplete guest + fresh guest  → move phone onto current
--   returning guest + completed phone-only   → adopt (existing returning-user path)
--
-- Never steal from a completed independent account.

-- ---------------------------------------------------------------------------
-- Source of truth: unique verified phone (already partial-unique; re-assert).
-- ---------------------------------------------------------------------------
create unique index if not exists profiles_phone_uidx
  on public.profiles (phone)
  where phone is not null;

comment on index profiles_phone_uidx is
  'One verified E.164 phone number may belong to at most one profile.';

alter table public.profiles
  add column if not exists phone_verified_at timestamptz;

comment on column public.profiles.phone_verified_at is
  'When this profile last attached a Firebase-verified phone.';

update public.profiles
   set phone_verified_at = coalesce(phone_verified_at, updated_at, created_at, now())
 where phone is not null
   and phone_verified_at is null;

-- ---------------------------------------------------------------------------
-- Audit log (ops / reconciliation). Clients have no access.
-- ---------------------------------------------------------------------------
create table if not exists public.phone_identity_events (
  id uuid primary key default gen_random_uuid(),
  phone text not null,
  action text not null,
  actor_user_id uuid,
  target_user_id uuid,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists phone_identity_events_phone_idx
  on public.phone_identity_events (phone, created_at desc);

create index if not exists phone_identity_events_target_idx
  on public.phone_identity_events (target_user_id, created_at desc);

alter table public.phone_identity_events enable row level security;

revoke all on table public.phone_identity_events from public, anon, authenticated;
grant select, insert on table public.phone_identity_events to service_role;

create or replace function public.log_phone_identity_event(
  p_phone text,
  p_action text,
  p_actor uuid,
  p_target uuid,
  p_detail jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.phone_identity_events (phone, action, actor_user_id, target_user_id, detail)
  values (p_phone, p_action, p_actor, p_target, coalesce(p_detail, '{}'::jsonb));
exception
  when others then
    null;
end;
$$;

revoke all on function public.log_phone_identity_event(text, text, uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.log_phone_identity_event(text, text, uuid, uuid, jsonb) to service_role;

create or replace function public.user_oauth_providers(p_user_id uuid)
returns text[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    array_agg(i.provider order by i.provider),
    '{}'::text[]
  )
    from auth.identities i
   where i.user_id = p_user_id
     and i.provider in ('apple', 'google');
$$;

revoke all on function public.user_oauth_providers(uuid) from public, anon, authenticated;
grant execute on function public.user_oauth_providers(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- claim_verified_phone
-- ---------------------------------------------------------------------------
create or replace function public.claim_verified_phone(p_phone text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  normalized text := nullif(trim(p_phone), '');
  prev public.profiles%rowtype;
  cur public.profiles%rowtype;
  prev_oauth text[];
  cur_oauth text[];
  cur_name text;
  prev_name text;
  chosen_name text;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  if normalized is null or length(normalized) < 8 then
    raise exception 'Invalid phone';
  end if;

  select * into cur from public.profiles where id = uid;
  if not found then
    raise exception 'Profile not found';
  end if;

  if cur.phone is not distinct from normalized then
    if cur.phone_verified_at is null then
      update public.profiles
         set phone_verified_at = now()
       where id = uid;
    end if;
    perform public.log_phone_identity_event(
      normalized, 'already_owned', uid, uid, '{}'::jsonb
    );
    return;
  end if;

  select * into prev
    from public.profiles
   where phone = normalized
     and id <> uid
   limit 1;

  if prev.id is null then
    update public.profiles
       set phone = normalized,
           phone_verified_at = now()
     where id = uid;
    perform public.log_phone_identity_event(
      normalized, 'attached', uid, uid, '{}'::jsonb
    );
    return;
  end if;

  prev_oauth := public.user_oauth_providers(prev.id);
  cur_oauth := public.user_oauth_providers(uid);

  -- Phone already belongs to another user. Never silently move it onto an
  -- established Apple/Google (or completed) account.
  if coalesce(cardinality(prev_oauth), 0) > 0 then
    if coalesce(cardinality(cur_oauth), 0) = 0 and not cur.onboarding_completed then
      perform public.log_phone_identity_event(
        normalized,
        'switch_required',
        uid,
        prev.id,
        jsonb_build_object('owner_providers', to_jsonb(prev_oauth))
      );
      raise exception 'PHONE_LOGIN_SWITCH_REQUIRED';
    end if;
    perform public.log_phone_identity_event(
      normalized,
      'conflict',
      uid,
      prev.id,
      jsonb_build_object('code', 'PHONE_ALREADY_ASSOCIATED_WITH_ANOTHER_ACCOUNT')
    );
    raise exception 'PHONE_ALREADY_ASSOCIATED_WITH_ANOTHER_ACCOUNT';
  end if;

  -- Returning phone-only user: fresh guest adopts the completed anonymous profile.
  if prev.onboarding_completed and not cur.onboarding_completed then
    update public.profiles
       set phone = null,
           phone_verified_at = null
     where id = prev.id;

    delete from public.daily_assignments d
     using public.daily_assignments o
     where d.user_id = uid
       and o.user_id = prev.id
       and d.assigned_date = o.assigned_date;

    update public.daily_assignments set user_id = uid where user_id = prev.id;
    update public.sessions set user_id = uid where user_id = prev.id;
    update public.saved_words set user_id = uid where user_id = prev.id;

    insert into public.referral_reward_claims (user_id, milestone, reward_key, claimed_at)
    select uid, c.milestone, c.reward_key, c.claimed_at
      from public.referral_reward_claims c
     where c.user_id = prev.id
    on conflict (user_id, milestone) do nothing;

    cur_name := nullif(trim(cur.display_name), '');
    if cur_name is not null and lower(cur_name) = 'speaker' then
      cur_name := null;
    end if;
    prev_name := nullif(trim(prev.display_name), '');
    if prev_name is not null and lower(prev_name) = 'speaker' then
      prev_name := null;
    end if;
    chosen_name := coalesce(cur_name, prev_name);

    update public.profiles p
       set phone = normalized,
           phone_verified_at = now(),
           onboarding_completed = true,
           display_name = chosen_name,
           goals = case when coalesce(cardinality(p.goals), 0) > 0 then p.goals else prev.goals end,
           experience_level = case
             when p.experience_level is distinct from 'beginner' then p.experience_level
             else prev.experience_level
           end,
           streak_count = greatest(p.streak_count, prev.streak_count),
           last_practice_date = case
             when p.last_practice_date is null then prev.last_practice_date
             when prev.last_practice_date is null then p.last_practice_date
             else greatest(p.last_practice_date, prev.last_practice_date)
           end,
           age = coalesce(p.age, prev.age),
           priorities = case
             when coalesce(cardinality(p.priorities), 0) > 0 then p.priorities
             else prev.priorities
           end,
           personality = case
             when coalesce(cardinality(p.personality), 0) > 0 then p.personality
             else prev.personality
           end,
           avatar_url = coalesce(p.avatar_url, prev.avatar_url),
           referral_bonus_weekly_sessions = greatest(
             p.referral_bonus_weekly_sessions,
             prev.referral_bonus_weekly_sessions
           ),
           referral_pro_expires_at = case
             when p.referral_pro_expires_at is null then prev.referral_pro_expires_at
             when prev.referral_pro_expires_at is null then p.referral_pro_expires_at
             else greatest(p.referral_pro_expires_at, prev.referral_pro_expires_at)
           end
     where p.id = uid;

    perform public.log_phone_identity_event(
      normalized,
      'adopted',
      uid,
      prev.id,
      jsonb_build_object('from', prev.id, 'into', uid)
    );
    return;
  end if;

  -- Incomplete leftover guest → only another incomplete session may take it
  -- (same person retrying phone login). Established accounts must not absorb it.
  if not prev.onboarding_completed and not cur.onboarding_completed then
    update public.profiles
       set phone = null,
           phone_verified_at = null
     where id = prev.id;

    update public.profiles
       set phone = normalized,
           phone_verified_at = now()
     where id = uid;

    perform public.log_phone_identity_event(
      normalized,
      'moved_leftover',
      uid,
      prev.id,
      jsonb_build_object('from', prev.id, 'into', uid)
    );
    return;
  end if;

  -- Completed independent phone account. Do not steal.
  perform public.log_phone_identity_event(
    normalized,
    'conflict',
    uid,
    prev.id,
    jsonb_build_object('code', 'PHONE_ALREADY_ASSOCIATED_WITH_ANOTHER_ACCOUNT')
  );
  raise exception 'PHONE_ALREADY_ASSOCIATED_WITH_ANOTHER_ACCOUNT';
end;
$$;

comment on function public.claim_verified_phone(text) is
  'Attaches a free Firebase-verified phone; adopts leftover/returning phone-only profiles; refuses to attach a number that already belongs to another established account; asks the app to switch session when a fresh guest verifies an OAuth-owned number.';

revoke all on function public.claim_verified_phone(text) from public;
grant execute on function public.claim_verified_phone(text) to authenticated;

-- ---------------------------------------------------------------------------
-- reclaim / merge: only incomplete leftovers, never independent accounts.
-- ---------------------------------------------------------------------------
create or replace function public.reclaim_phone_from_guest(p_from_user_id uuid, p_phone text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  normalized text := nullif(trim(p_phone), '');
  src public.profiles%rowtype;
  oauth_count int;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;
  if p_from_user_id is null or p_from_user_id = uid then
    return;
  end if;
  if normalized is null or length(normalized) < 8 then
    raise exception 'Invalid phone';
  end if;

  select * into src from public.profiles where id = p_from_user_id;
  if not found then
    return;
  end if;

  if src.onboarding_completed then
    raise exception 'SOURCE_IS_INDEPENDENT_ACCOUNT';
  end if;

  select count(*) into oauth_count
    from auth.identities
   where user_id = p_from_user_id
     and provider in ('apple', 'google');
  if coalesce(oauth_count, 0) > 0 then
    raise exception 'SOURCE_HAS_OAUTH';
  end if;

  if src.phone is distinct from normalized then
    return;
  end if;

  update public.profiles
     set phone = null,
         phone_verified_at = null
   where id = p_from_user_id
     and phone = normalized;

  update public.profiles
     set phone = normalized,
         phone_verified_at = now()
   where id = uid
     and (phone is null or phone = normalized);

  perform public.log_phone_identity_event(
    normalized, 'reclaimed', uid, p_from_user_id, jsonb_build_object('from', p_from_user_id)
  );
end;
$$;

revoke all on function public.reclaim_phone_from_guest(uuid, text) from public;
grant execute on function public.reclaim_phone_from_guest(uuid, text) to authenticated;

comment on function public.reclaim_phone_from_guest(uuid, text) is
  'Moves a phone from an incomplete anonymous leftover onto the current user. Refuses completed or OAuth source accounts.';

create or replace function public.merge_profile_into_current(p_from_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  src public.profiles%rowtype;
  cur public.profiles%rowtype;
  src_name text;
  cur_name text;
  chosen_name text;
  oauth_count int;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  if p_from_user_id is null or p_from_user_id = uid then
    return jsonb_build_object('merged', false, 'reason', 'noop');
  end if;

  select count(*) into oauth_count
    from auth.identities
   where user_id = p_from_user_id
     and provider in ('apple', 'google');

  if coalesce(oauth_count, 0) > 0 then
    raise exception 'SOURCE_HAS_OAUTH';
  end if;

  select * into src from public.profiles where id = p_from_user_id;
  if not found then
    return jsonb_build_object('merged', false, 'reason', 'missing_source');
  end if;

  -- Completed phone/guest accounts are independent — do not absorb them.
  if src.onboarding_completed then
    raise exception 'SOURCE_IS_INDEPENDENT_ACCOUNT';
  end if;

  select * into cur from public.profiles where id = uid;
  if not found then
    raise exception 'Profile not found';
  end if;

  delete from public.daily_assignments d
   using public.daily_assignments o
   where d.user_id = uid
     and o.user_id = p_from_user_id
     and d.assigned_date = o.assigned_date;

  update public.daily_assignments set user_id = uid where user_id = p_from_user_id;
  update public.sessions set user_id = uid where user_id = p_from_user_id;
  update public.saved_words set user_id = uid where user_id = p_from_user_id;

  insert into public.referral_reward_claims (user_id, milestone, reward_key, claimed_at)
  select uid, c.milestone, c.reward_key, c.claimed_at
    from public.referral_reward_claims c
   where c.user_id = p_from_user_id
  on conflict (user_id, milestone) do nothing;

  src_name := nullif(trim(src.display_name), '');
  if src_name is not null and lower(src_name) = 'speaker' then
    src_name := null;
  end if;
  cur_name := nullif(trim(cur.display_name), '');
  if cur_name is not null and lower(cur_name) = 'speaker' then
    cur_name := null;
  end if;
  chosen_name := coalesce(cur_name, src_name);

  -- Move phone only from this leftover, and only when current has none.
  if cur.phone is null and src.phone is not null then
    update public.profiles
       set phone = null,
           phone_verified_at = null
     where id = p_from_user_id;

    update public.profiles
       set phone = src.phone,
           phone_verified_at = now()
     where id = uid;
  end if;

  update public.profiles p
     set display_name = chosen_name,
         onboarding_completed = p.onboarding_completed or src.onboarding_completed,
         goals = case when coalesce(cardinality(p.goals), 0) > 0 then p.goals else src.goals end,
         experience_level = case
           when p.experience_level is distinct from 'beginner' then p.experience_level
           else src.experience_level
         end,
         streak_count = greatest(p.streak_count, src.streak_count),
         last_practice_date = case
           when p.last_practice_date is null then src.last_practice_date
           when src.last_practice_date is null then p.last_practice_date
           else greatest(p.last_practice_date, src.last_practice_date)
         end,
         age = coalesce(p.age, src.age),
         priorities = case
           when coalesce(cardinality(p.priorities), 0) > 0 then p.priorities
           else src.priorities
         end,
         personality = case
           when coalesce(cardinality(p.personality), 0) > 0 then p.personality
           else src.personality
         end,
         avatar_url = coalesce(p.avatar_url, src.avatar_url),
         referral_bonus_weekly_sessions = greatest(
           p.referral_bonus_weekly_sessions,
           src.referral_bonus_weekly_sessions
         ),
         referral_pro_expires_at = case
           when p.referral_pro_expires_at is null then src.referral_pro_expires_at
           when src.referral_pro_expires_at is null then p.referral_pro_expires_at
           else greatest(p.referral_pro_expires_at, src.referral_pro_expires_at)
         end
   where p.id = uid;

  return jsonb_build_object(
    'merged', true,
    'from', p_from_user_id,
    'into', uid
  );
end;
$$;

revoke all on function public.merge_profile_into_current(uuid) from public;
grant execute on function public.merge_profile_into_current(uuid) to authenticated;

comment on function public.merge_profile_into_current(uuid) is
  'Merges an incomplete anonymous leftover into the current user after OAuth switch. Refuses completed or OAuth source accounts.';

-- ---------------------------------------------------------------------------
-- Who currently owns this E.164? Used by the session-switch edge function.
-- ---------------------------------------------------------------------------
create or replace function public.lookup_phone_owner(p_phone text)
returns table (
  owner_user_id uuid,
  owner_email text,
  owner_providers text[],
  onboarding_completed boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized text := nullif(trim(p_phone), '');
begin
  if normalized is null or length(normalized) < 8 then
    return;
  end if;

  return query
  select
    p.id,
    nullif(lower(trim(coalesce(p.email, u.email))), ''),
    public.user_oauth_providers(p.id),
    p.onboarding_completed
  from public.profiles p
  left join auth.users u on u.id = p.id
  where p.phone = normalized
  limit 1;
end;
$$;

revoke all on function public.lookup_phone_owner(text) from public, anon, authenticated;
grant execute on function public.lookup_phone_owner(text) to service_role;

-- ---------------------------------------------------------------------------
-- Reconciliation: inspect split / stolen phone identities. Never auto-merge.
-- ---------------------------------------------------------------------------
create or replace function public.list_phone_identity_anomalies()
returns table (
  kind text,
  user_id uuid,
  other_user_id uuid,
  phone text,
  onboarding_completed boolean,
  oauth_providers text[],
  detail text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Same E.164 on more than one profile (unique index should prevent this).
  return query
  select
    'duplicate_phone'::text,
    p.id,
    o.id,
    p.phone,
    p.onboarding_completed,
    public.user_oauth_providers(p.id),
    'same verified phone on multiple profiles'::text
  from public.profiles p
  join public.profiles o
    on o.phone = p.phone
   and o.id > p.id
  where p.phone is not null;

  -- Completed phone-only profiles that no longer have a number — likely steal victims.
  return query
  select
    'orphaned_phone_account'::text,
    p.id,
    null::uuid,
    p.phone,
    p.onboarding_completed,
    public.user_oauth_providers(p.id),
    'completed account with no phone and no Apple/Google — review before restoring'::text
  from public.profiles p
  where p.onboarding_completed
    and p.phone is null
    and coalesce(cardinality(public.user_oauth_providers(p.id)), 0) = 0;
end;
$$;

revoke all on function public.list_phone_identity_anomalies() from public, anon, authenticated;
grant execute on function public.list_phone_identity_anomalies() to service_role;

-- Manual restore. Moves the number to the chosen account; does not delete or merge.
create or replace function public.restore_phone_to_account(p_user_id uuid, p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized text := nullif(trim(p_phone), '');
  holder uuid;
begin
  if auth.role() is distinct from 'service_role'
     and current_user not in ('postgres', 'supabase_admin') then
    raise exception 'Not authorized';
  end if;
  if p_user_id is null then
    raise exception 'Missing user';
  end if;
  if normalized is null or length(normalized) < 8 then
    raise exception 'Invalid phone';
  end if;
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'Profile not found';
  end if;

  select id into holder
    from public.profiles
   where phone = normalized
     and id <> p_user_id
   limit 1;

  update public.profiles
     set phone = null,
         phone_verified_at = null
   where phone = normalized
     and id <> p_user_id;

  update public.profiles
     set phone = normalized,
         phone_verified_at = now()
   where id = p_user_id;

  perform public.log_phone_identity_event(
    normalized,
    'restored',
    null,
    p_user_id,
    jsonb_build_object('previous_holder', holder)
  );

  return jsonb_build_object(
    'ok', true,
    'phone', normalized,
    'user_id', p_user_id,
    'previous_holder', holder
  );
end;
$$;

revoke all on function public.restore_phone_to_account(uuid, text) from public, anon, authenticated;
grant execute on function public.restore_phone_to_account(uuid, text) to service_role;

comment on function public.restore_phone_to_account(uuid, text) is
  'Ops-only: assign a verified phone to a chosen profile after review. Does not merge or delete accounts.';
