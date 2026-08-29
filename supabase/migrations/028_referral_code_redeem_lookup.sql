-- Make redeem match codes case-insensitively, and let the app persist a
-- locally shown code so friends can redeem what they were actually given.

drop function if exists public.ensure_my_referral_code();

create or replace function public.ensure_my_referral_code(preferred text default null)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  existing text;
  candidate text;
  normalized text;
  attempt int := 0;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  select referral_code into existing from public.profiles where id = uid;
  if existing is not null and length(existing) >= 6 then
    return existing;
  end if;

  normalized := upper(regexp_replace(coalesce(preferred, ''), '[^A-Za-z0-9]', '', 'g'));
  if length(normalized) >= 6 and length(normalized) <= 10 then
    if not exists (
      select 1
      from public.profiles
      where id <> uid
        and upper(regexp_replace(coalesce(referral_code, ''), '[^A-Za-z0-9]', '', 'g')) = normalized
    ) then
      update public.profiles
      set referral_code = normalized
      where id = uid
        and (referral_code is null or length(referral_code) < 6);
      select referral_code into existing from public.profiles where id = uid;
      if existing is not null and length(existing) >= 6 then
        return existing;
      end if;
    end if;
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
  where upper(regexp_replace(coalesce(referral_code, ''), '[^A-Za-z0-9]', '', 'g')) = normalized
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

revoke all on function public.ensure_my_referral_code(text) from public;
revoke all on function public.redeem_referral_code(text) from public;
grant execute on function public.ensure_my_referral_code(text) to authenticated;
grant execute on function public.redeem_referral_code(text) to authenticated;

comment on function public.ensure_my_referral_code(text) is
  'Allocates a stable referral_code. Uses preferred when the profile has none and the code is free.';
comment on function public.redeem_referral_code(text) is
  'Attributes the caller to the inviter who owns this code (case-insensitive).';
