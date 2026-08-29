-- Display name single source of truth: never seed the placeholder "Speaker".
-- UI may show "Speaker" when null; DB stays null until the user (or Apple) sets a real name.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  meta_name text := nullif(
    trim(coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', '')),
    ''
  );
begin
  insert into public.profiles (id, display_name)
  values (new.id, meta_name);
  return new;
end;
$$;

-- Clear placeholder defaults so adopted / real names can apply.
update public.profiles
   set display_name = null
 where display_name is not null
   and lower(trim(display_name)) = 'speaker';

-- Prefer a real previous name over the guest placeholder when adopting phone login.
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

  if prev.id is not null then
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
    else
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
