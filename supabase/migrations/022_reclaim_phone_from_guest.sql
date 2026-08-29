-- Explicitly move a phone from an anonymous/phone-only guest onto the current
-- (Apple/Google) account after OAuth account switch.

create or replace function public.reclaim_phone_from_guest(p_from_user_id uuid, p_phone text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  normalized text := nullif(trim(p_phone), '');
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

  select count(*) into oauth_count
    from auth.identities
   where user_id = p_from_user_id
     and provider in ('apple', 'google');
  if coalesce(oauth_count, 0) > 0 then
    raise exception 'SOURCE_HAS_OAUTH';
  end if;

  -- Free the number on the guest (and any other non-current holders of this E.164).
  update public.profiles
     set phone = null
   where phone = normalized
     and id <> uid;

  update public.profiles
     set phone = normalized
   where id = uid
     and (phone is null or phone = normalized);
end;
$$;

revoke all on function public.reclaim_phone_from_guest(uuid, text) from public;
grant execute on function public.reclaim_phone_from_guest(uuid, text) to authenticated;
