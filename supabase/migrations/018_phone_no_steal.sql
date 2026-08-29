-- Do not steal a phone that already belongs to another account, except when
-- the current user is a fresh (not onboarded) session logging back in with a
-- number that belongs to a completed profile (adopt / returning-user path).

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

  -- Already ours.
  if cur.phone is not distinct from normalized then
    return;
  end if;

  select * into prev
    from public.profiles
   where phone = normalized
     and id <> uid
   limit 1;

  if prev.id is not null then
    -- Returning phone login: incomplete guest adopts the completed account.
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

      update public.profiles p
         set phone = normalized,
             onboarding_completed = true,
             display_name = coalesce(nullif(trim(p.display_name), ''), prev.display_name),
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
    else
      -- Already linked to someone else — do not steal.
      raise exception 'PHONE_ALREADY_IN_USE'
        using errcode = 'unique_violation';
    end if;
  else
    update public.profiles
       set phone = normalized
     where id = uid;
  end if;
end;
$$;

comment on function public.claim_verified_phone(text) is
  'Attaches a Firebase-verified phone if free; adopts a completed profile for returning users; otherwise rejects PHONE_ALREADY_IN_USE.';
