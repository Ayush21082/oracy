-- After Firebase Phone Auth proves ownership of a number, attach it to the
-- current profile. Clears the same phone from any other profile first so
-- re-linking (new guest / account) does not hit profiles_phone_uidx.

create or replace function public.claim_verified_phone(p_phone text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  normalized text := nullif(trim(p_phone), '');
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  if normalized is null or length(normalized) < 8 then
    raise exception 'Invalid phone';
  end if;

  update public.profiles
     set phone = null
   where phone = normalized
     and id <> uid;

  update public.profiles
     set phone = normalized
   where id = uid;
end;
$$;

revoke all on function public.claim_verified_phone(text) from public;
grant execute on function public.claim_verified_phone(text) to authenticated;

comment on function public.claim_verified_phone(text) is
  'Attaches a Firebase-verified E.164 phone to the current user, releasing it from other profiles.';
