-- When someone enters a friend's code, they get a welcome speaking grant too.
-- Size matches the 1-friend inviter milestone (+2 weekly speaks) when present.

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
  bonus_add int := 2;
  current_bonus int;
  new_bonus int;
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
  where upper(regexp_replace(coalesce(referral_code, ''), '[^A-Za-z0-9]', '', 'g')) = normalized
  limit 1;

  if inviter is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  if inviter = uid then
    return jsonb_build_object('ok', false, 'error', 'self_redeem');
  end if;

  select m.bonus_weekly_sessions into bonus_add
  from public.referral_milestones m
  where m.friends_required = 1 and m.active is true
  limit 1;
  bonus_add := coalesce(bonus_add, 2);

  select coalesce(referral_bonus_weekly_sessions, 0) into current_bonus
  from public.profiles
  where id = uid;
  new_bonus := coalesce(current_bonus, 0) + bonus_add;

  insert into public.referral_redemptions (invitee_id, inviter_id, code)
  values (uid, inviter, normalized);

  update public.profiles
  set
    referred_by = coalesce(referred_by, inviter),
    referral_bonus_weekly_sessions = new_bonus
  where id = uid;

  return jsonb_build_object(
    'ok', true,
    'inviter_id', inviter,
    'bonus_sessions', new_bonus,
    'welcome_bonus_sessions', bonus_add
  );
end;
$$;

revoke all on function public.redeem_referral_code(text) from public;
grant execute on function public.redeem_referral_code(text) to authenticated;

comment on function public.redeem_referral_code(text) is
  'Attributes the caller to the inviter and grants the invitee a welcome weekly-speak bonus.';
