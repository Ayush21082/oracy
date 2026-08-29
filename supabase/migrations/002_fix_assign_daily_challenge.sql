-- Fix assign_daily_challenge: first SELECT wrongly mapped timezone (text) into a date variable.
create or replace function public.assign_daily_challenge(p_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date;
  v_tz text;
  v_level text;
  v_goals text[];
  v_existing uuid;
  v_challenge_id uuid;
  v_recent_ids uuid[];
begin
  select timezone, experience_level, goals
  into v_tz, v_level, v_goals
  from public.profiles
  where id = p_user_id;

  v_today := (now() at time zone coalesce(v_tz, 'UTC'))::date;

  select challenge_id into v_existing
  from public.daily_assignments
  where user_id = p_user_id and assigned_date = v_today;

  if v_existing is not null then
    return v_existing;
  end if;

  select array_agg(challenge_id) into v_recent_ids
  from public.daily_assignments
  where user_id = p_user_id
    and assigned_date >= v_today - interval '14 days';

  select c.id into v_challenge_id
  from public.challenges c
  where c.active = true
    and c.difficulty = coalesce(v_level, 'intermediate')
    and (v_recent_ids is null or c.id != all(v_recent_ids))
  order by random()
  limit 1;

  if v_challenge_id is null then
    select c.id into v_challenge_id
    from public.challenges c
    where c.active = true
      and (v_recent_ids is null or c.id != all(v_recent_ids))
    order by random()
    limit 1;
  end if;

  if v_challenge_id is null then
    raise exception 'No active challenges available';
  end if;

  insert into public.daily_assignments (user_id, challenge_id, assigned_date)
  values (p_user_id, v_challenge_id, v_today);

  return v_challenge_id;
end;
$$;
