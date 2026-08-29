-- Phone ownership rules for a single identity graph:
-- 1) Free number → attach to current user
-- 2) Owned by Apple/Google account → refuse (sign in with that provider)
-- 3) Owned by anonymous/phone-only completed profile + current incomplete → adopt
-- 4) Owned by anonymous leftover + current already established → move phone onto current

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
  prev_oauth int;
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
    return;
  end if;

  select * into prev
    from public.profiles
   where phone = normalized
     and id <> uid
   limit 1;

  if prev.id is null then
    update public.profiles
       set phone = normalized
     where id = uid;
    return;
  end if;

  select count(*) into prev_oauth
    from auth.identities
   where user_id = prev.id
     and provider in ('apple', 'google');

  if coalesce(prev_oauth, 0) > 0 then
    raise exception 'PHONE_OWNED_BY_OAUTH_ACCOUNT';
  end if;

  -- Returning phone-only user (fresh guest) adopts completed anonymous profile.
  if prev.onboarding_completed and not cur.onboarding_completed then
    update public.profiles
       set phone = null
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
    return;
  end if;

  -- Established current user claiming a number left on an anonymous leftover.
  update public.profiles
     set phone = null
   where id = prev.id;

  update public.profiles
     set phone = normalized
   where id = uid;
end;
$$;

comment on function public.claim_verified_phone(text) is
  'Attaches phone to current user; refuses numbers owned by Apple/Google accounts; adopts or moves from anonymous leftovers only.';
