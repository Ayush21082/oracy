-- After OAuth sign-in switches away from a guest session, pull that guest's
-- phone + practice data onto the surviving account (one identity graph).

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

  -- Only absorb anonymous / phone-only leftovers — never steal an OAuth account.
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

  select * into cur from public.profiles where id = uid;
  if not found then
    raise exception 'Profile not found';
  end if;

  -- Move practice rows (resolve daily assignment date conflicts).
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

  -- Move phone only when current has none (avoid unique collisions).
  if cur.phone is null and src.phone is not null then
    update public.profiles
       set phone = null
     where id = p_from_user_id;

    update public.profiles
       set phone = src.phone
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
  'Merges an abandoned anonymous/phone-only profile into the current user after OAuth account switch.';
