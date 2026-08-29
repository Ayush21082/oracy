-- Referral codes, redemptions, milestone claims, and profile grant fields.

alter table public.profiles
  add column if not exists referral_code text,
  add column if not exists referred_by uuid references public.profiles(id) on delete set null,
  add column if not exists referral_bonus_weekly_sessions integer not null default 0,
  add column if not exists referral_pro_expires_at timestamptz;

create unique index if not exists profiles_referral_code_uidx
  on public.profiles (referral_code)
  where referral_code is not null;

create table if not exists public.referral_redemptions (
  invitee_id uuid primary key references public.profiles(id) on delete cascade,
  inviter_id uuid not null references public.profiles(id) on delete cascade,
  code text not null,
  created_at timestamptz not null default now(),
  check (invitee_id <> inviter_id)
);

create index if not exists referral_redemptions_inviter_idx
  on public.referral_redemptions (inviter_id);

create table if not exists public.referral_reward_claims (
  user_id uuid not null references public.profiles(id) on delete cascade,
  milestone integer not null
    check (milestone in (1, 3, 5, 10, 20, 50, 100)),
  reward_key text not null,
  claimed_at timestamptz not null default now(),
  primary key (user_id, milestone)
);

alter table public.referral_redemptions enable row level security;
alter table public.referral_reward_claims enable row level security;

create policy "Users read own redemptions as invitee or inviter"
  on public.referral_redemptions for select
  using (auth.uid() = invitee_id or auth.uid() = inviter_id);

create policy "Users read own reward claims"
  on public.referral_reward_claims for select
  using (auth.uid() = user_id);

-- Generate a short readable code (same alphabet as the iOS client).
create or replace function public._generate_referral_code(seed text)
returns text
language plpgsql
immutable
as $$
declare
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  hash bigint := 5381;
  i int;
  value numeric;
  idx int;
  out_code text := '';
  b int;
begin
  for i in 1..length(seed) loop
    b := ascii(substr(seed, i, 1));
    hash := ((hash << 5) + hash + b) % 9223372036854775807;
  end loop;
  if hash = 0 then
    hash := 1;
  end if;
  value := hash;
  for i in 1..8 loop
    idx := (value::bigint % length(alphabet))::int;
    out_code := out_code || substr(alphabet, idx + 1, 1);
    value := trunc(value / length(alphabet));
    value := (value::bigint # ((value::bigint << 7) % 9223372036854775807))::numeric;
    if value < 0 then
      value := -value;
    end if;
  end loop;
  return out_code;
end;
$$;

create or replace function public.ensure_my_referral_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  existing text;
  candidate text;
  attempt int := 0;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  select referral_code into existing from public.profiles where id = uid;
  if existing is not null and length(existing) >= 6 then
    return existing;
  end if;

  loop
    attempt := attempt + 1;
    candidate := public._generate_referral_code(uid::text || '-' || attempt::text);
    begin
      update public.profiles
      set referral_code = candidate
      where id = uid
        and (referral_code is null or length(referral_code) < 6);
      select referral_code into existing from public.profiles where id = uid;
      if existing is not null then
        return existing;
      end if;
    exception when unique_violation then
      -- try again with a different salt
      null;
    end;
    if attempt > 12 then
      raise exception 'Could not allocate referral code';
    end if;
  end loop;
end;
$$;

create or replace function public.redeem_referral_code(raw_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  normalized text;
  inviter uuid;
  already uuid;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  normalized := upper(regexp_replace(coalesce(raw_code, ''), '[^A-Za-z0-9]', '', 'g'));
  if length(normalized) < 6 or length(normalized) > 10 then
    return jsonb_build_object('ok', false, 'error', 'invalid_code');
  end if;

  select invitee_id into already from public.referral_redemptions where invitee_id = uid;
  if already is not null then
    return jsonb_build_object('ok', false, 'error', 'already_redeemed');
  end if;

  select id into inviter
  from public.profiles
  where referral_code = normalized
  limit 1;

  if inviter is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  if inviter = uid then
    return jsonb_build_object('ok', false, 'error', 'self_redeem');
  end if;

  insert into public.referral_redemptions (invitee_id, inviter_id, code)
  values (uid, inviter, normalized);

  update public.profiles
  set referred_by = inviter
  where id = uid and referred_by is null;

  return jsonb_build_object('ok', true, 'inviter_id', inviter);
end;
$$;

create or replace function public.get_referral_reward_state()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  cnt int;
  bonus int;
  pro_at timestamptz;
  claimed int[];
  code text;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  -- Ensure code exists so share UI always has one.
  code := public.ensure_my_referral_code();

  select count(*)::int into cnt
  from public.referral_redemptions
  where inviter_id = uid;

  select referral_bonus_weekly_sessions, referral_pro_expires_at
  into bonus, pro_at
  from public.profiles
  where id = uid;

  select coalesce(array_agg(milestone order by milestone), '{}')
  into claimed
  from public.referral_reward_claims
  where user_id = uid;

  return jsonb_build_object(
    'count', coalesce(cnt, 0),
    'bonus_sessions', coalesce(bonus, 0),
    'pro_expires_at', pro_at,
    'claimed_milestones', to_jsonb(coalesce(claimed, '{}')),
    'referral_code', code
  );
end;
$$;

create or replace function public.claim_referral_milestone(p_milestone integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  cnt int;
  reward_key text;
  bonus_add int := 0;
  pro_days int := 0;
  current_bonus int;
  current_pro timestamptz;
  base_ts timestamptz;
  new_pro timestamptz;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  if p_milestone not in (1, 3, 5, 10, 20, 50, 100) then
    return jsonb_build_object('ok', false, 'error', 'invalid_milestone');
  end if;

  select count(*)::int into cnt
  from public.referral_redemptions
  where inviter_id = uid;

  if coalesce(cnt, 0) < p_milestone then
    return jsonb_build_object('ok', false, 'error', 'not_unlocked');
  end if;

  if exists (
    select 1 from public.referral_reward_claims
    where user_id = uid and milestone = p_milestone
  ) then
    return jsonb_build_object('ok', false, 'error', 'already_claimed');
  end if;

  case p_milestone
    when 1 then
      reward_key := 'bonus_weekly_2';
      bonus_add := 2;
    when 3 then
      reward_key := 'pro_days_7';
      pro_days := 7;
    when 5 then
      reward_key := 'pro_days_30';
      pro_days := 30;
    when 10 then
      reward_key := 'bonus_weekly_3';
      bonus_add := 3;
    when 20 then
      reward_key := 'pro_days_90';
      pro_days := 90;
    when 50 then
      reward_key := 'pro_days_365';
      pro_days := 365;
    when 100 then
      reward_key := 'pro_days_365_bonus_weekly_5';
      pro_days := 365;
      bonus_add := 5;
  end case;

  select referral_bonus_weekly_sessions, referral_pro_expires_at
  into current_bonus, current_pro
  from public.profiles
  where id = uid
  for update;

  new_pro := current_pro;
  if pro_days > 0 then
    base_ts := greatest(coalesce(current_pro, now()), now());
    new_pro := base_ts + make_interval(days => pro_days);
  end if;

  update public.profiles
  set
    referral_bonus_weekly_sessions = coalesce(current_bonus, 0) + bonus_add,
    referral_pro_expires_at = case
      when pro_days > 0 then new_pro
      else current_pro
    end
  where id = uid;

  insert into public.referral_reward_claims (user_id, milestone, reward_key)
  values (uid, p_milestone, reward_key);

  return jsonb_build_object(
    'ok', true,
    'milestone', p_milestone,
    'reward_key', reward_key,
    'bonus_sessions', coalesce(current_bonus, 0) + bonus_add,
    'pro_expires_at', case when pro_days > 0 then new_pro else current_pro end
  );
end;
$$;

revoke all on function public.ensure_my_referral_code() from public;
revoke all on function public.redeem_referral_code(text) from public;
revoke all on function public.get_referral_reward_state() from public;
revoke all on function public.claim_referral_milestone(integer) from public;

grant execute on function public.ensure_my_referral_code() to authenticated;
grant execute on function public.redeem_referral_code(text) to authenticated;
grant execute on function public.get_referral_reward_state() to authenticated;
grant execute on function public.claim_referral_milestone(integer) to authenticated;

comment on function public.ensure_my_referral_code() is
  'Allocates a stable referral_code on the caller profile if missing.';
comment on function public.redeem_referral_code(text) is
  'Links the caller as invitee to an inviter code (once).';
comment on function public.get_referral_reward_state() is
  'Returns referral count, grants, claimed milestones, and code for the caller.';
comment on function public.claim_referral_milestone(integer) is
  'Claims a milestone reward when referral count is high enough.';
