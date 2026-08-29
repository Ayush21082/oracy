-- Backend-driven referral milestone catalog (no client hardcoding).

create table if not exists public.referral_milestones (
  friends_required integer primary key check (friends_required > 0),
  reward_key text not null,
  bonus_weekly_sessions integer not null default 0 check (bonus_weekly_sessions >= 0),
  pro_days integer not null default 0 check (pro_days >= 0),
  title text not null,
  hook text not null,
  sort_order integer not null default 0,
  active boolean not null default true,
  check (bonus_weekly_sessions > 0 or pro_days > 0)
);

alter table public.referral_milestones enable row level security;

create policy "Anyone authenticated can read active milestones"
  on public.referral_milestones for select
  to authenticated
  using (active = true);

insert into public.referral_milestones (
  friends_required, reward_key, bonus_weekly_sessions, pro_days, title, hook, sort_order, active
) values
  (1,   'bonus_weekly_2',                 2,   0,   '+2 weekly speaks',      'One friend in — more practice room this week.',           10, true),
  (3,   'pro_days_7',                     0,   7,   '7 days of Pro',          'Tiny squad unlock. Taste unlimited speaking.',         20, true),
  (5,   'pro_days_30',                    0,  30,   '30 days of Pro',         'Your hero milestone. A full month on Pro.',            30, true),
  (10,  'bonus_weekly_3',                 3,   0,   '+3 weekly speaks',       'Stack more free sessions every week.',                 40, true),
  (20,  'pro_days_90',                    0,  90,   '90 days of Pro',         'Inner circle. Three months of Pro.',                   50, true),
  (50,  'pro_days_365',                   0, 365,   '1 year of Pro',          'Legendary share goal. A whole year.',                  60, true),
  (100, 'pro_days_365_bonus_weekly_5',    5, 365,   '1 year Pro + 5 speaks',  'Capstone — year of Pro plus a bigger weekly limit.',   70, true)
on conflict (friends_required) do update set
  reward_key = excluded.reward_key,
  bonus_weekly_sessions = excluded.bonus_weekly_sessions,
  pro_days = excluded.pro_days,
  title = excluded.title,
  hook = excluded.hook,
  sort_order = excluded.sort_order,
  active = excluded.active;

-- Allow any positive milestone id (validated against catalog at claim time).
alter table public.referral_reward_claims
  drop constraint if exists referral_reward_claims_milestone_check;

alter table public.referral_reward_claims
  add constraint referral_reward_claims_milestone_check
  check (milestone > 0);

-- Include catalog in reward state payload.
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
  milestones jsonb;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

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

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'friends_required', friends_required,
      'reward_key', reward_key,
      'bonus_weekly_sessions', bonus_weekly_sessions,
      'pro_days', pro_days,
      'title', title,
      'hook', hook,
      'sort_order', sort_order
    )
    order by sort_order, friends_required
  ), '[]'::jsonb)
  into milestones
  from public.referral_milestones
  where active = true;

  return jsonb_build_object(
    'count', coalesce(cnt, 0),
    'bonus_sessions', coalesce(bonus, 0),
    'pro_expires_at', pro_at,
    'claimed_milestones', to_jsonb(coalesce(claimed, '{}')),
    'referral_code', code,
    'milestones', milestones
  );
end;
$$;

-- Claim reads grants from referral_milestones (backend source of truth).
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
  is_active boolean;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  select
    m.reward_key,
    m.bonus_weekly_sessions,
    m.pro_days,
    m.active
  into reward_key, bonus_add, pro_days, is_active
  from public.referral_milestones m
  where m.friends_required = p_milestone;

  if reward_key is null or is_active is not true then
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
    referral_bonus_weekly_sessions = coalesce(current_bonus, 0) + coalesce(bonus_add, 0),
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
    'bonus_sessions', coalesce(current_bonus, 0) + coalesce(bonus_add, 0),
    'pro_expires_at', case when pro_days > 0 then new_pro else current_pro end
  );
end;
$$;

comment on table public.referral_milestones is
  'Editable referral offer ladder. Client reads via get_referral_reward_state; claims apply these grants.';
