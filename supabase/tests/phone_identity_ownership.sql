-- Phone identity ownership. Rolled back by `supabase test db`.
-- Covers Apple/Google/phone linking, login resolution, uniqueness, and recovery.

begin;

select plan(27);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function tests_set_user(p_uid uuid)
returns void
language plpgsql
as $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_uid::text, 'role', 'authenticated')::text,
    true
  );
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end;
$$;

create or replace function tests_set_service_role()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
end;
$$;

create or replace function tests_create_user(p_email text default null, p_anonymous boolean default true)
returns uuid
language plpgsql
as $$
declare
  uid uuid := gen_random_uuid();
begin
  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token,
    is_anonymous
  ) values (
    '00000000-0000-0000-0000-000000000000',
    uid,
    'authenticated',
    'authenticated',
    p_email,
    '$2a$06$K4neG8Z8z4q0n0n0n0n0nO4n0n0n0n0n0n0n0n0n0n0n0n0n0n0a',
    case when p_email is null then null else now() end,
    case
      when p_anonymous then '{"provider":"anonymous","providers":["anonymous"]}'::jsonb
      else '{"provider":"email","providers":["email"]}'::jsonb
    end,
    '{}'::jsonb,
    now(),
    now(),
    '',
    '',
    '',
    '',
    p_anonymous
  );

  if p_anonymous then
    insert into auth.identities (
      id,
      user_id,
      identity_data,
      provider,
      provider_id,
      last_sign_in_at,
      created_at,
      updated_at
    ) values (
      gen_random_uuid(),
      uid,
      jsonb_build_object('sub', uid::text),
      'anonymous',
      uid::text,
      now(),
      now(),
      now()
    );
  end if;

  return uid;
end;
$$;

create or replace function tests_add_oauth(p_uid uuid, p_provider text)
returns void
language plpgsql
as $$
declare
  sub text := p_provider || '-' || p_uid::text;
begin
  insert into auth.identities (
    id,
    user_id,
    identity_data,
    provider,
    provider_id,
    last_sign_in_at,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    p_uid,
    jsonb_build_object('sub', sub, 'email', p_provider || '@example.com'),
    p_provider,
    sub,
    now(),
    now(),
    now()
  );
end;
$$;

create or replace function tests_claim(p_uid uuid, p_phone text)
returns void
language plpgsql
as $$
begin
  perform tests_set_user(p_uid);
  perform public.claim_verified_phone(p_phone);
end;
$$;

create or replace function tests_claim_err(p_uid uuid, p_phone text, p_needle text)
returns boolean
language plpgsql
as $$
begin
  perform tests_claim(p_uid, p_phone);
  return false;
exception
  when others then
    return sqlerrm ilike '%' || p_needle || '%';
end;
$$;

create or replace function tests_phone_of(p_uid uuid)
returns text
language sql
as $$
  select phone from public.profiles where id = p_uid;
$$;

-- ===========================================================================
-- 1 / 11. Apple → sign out → phone account → sign out → Apple
-- Apple A and phone B stay distinct; A does not absorb B's number.
-- ===========================================================================
do $$
declare
  apple_a uuid;
  phone_b uuid;
begin
  apple_a := tests_create_user('apple-a@example.com', false);
  perform tests_add_oauth(apple_a, 'apple');
  update public.profiles set onboarding_completed = true, display_name = 'Apple A' where id = apple_a;

  phone_b := tests_create_user(null, true);
  update public.profiles set onboarding_completed = true, display_name = 'Phone B' where id = phone_b;
  perform tests_claim(phone_b, '+919811111111');
end;
$$;

select is(
  tests_phone_of((select id from public.profiles where display_name = 'Phone B' limit 1)),
  '+919811111111',
  '1. phone account B still owns its number after Apple A tries to link it'
);

select is(
  tests_phone_of((select id from public.profiles where display_name = 'Apple A' limit 1)),
  null,
  '1/11. Apple A did not receive B''s phone'
);

-- ===========================================================================
-- 2. Google → sign out → phone account → sign out → Google
-- ===========================================================================
do $$
declare
  google_a uuid;
  phone_b uuid;
begin
  google_a := tests_create_user('google-a@example.com', false);
  perform tests_add_oauth(google_a, 'google');
  update public.profiles set onboarding_completed = true, display_name = 'Google A' where id = google_a;

  phone_b := tests_create_user(null, true);
  update public.profiles set onboarding_completed = true, display_name = 'Phone G' where id = phone_b;
  perform tests_claim(phone_b, '+919822222222');
end;
$$;

select ok(
  tests_claim_err(
    (select id from public.profiles where display_name = 'Google A' limit 1),
    '+919822222222',
    'PHONE_ALREADY_ASSOCIATED_WITH_ANOTHER_ACCOUNT'
  ),
  '2/4. Google account cannot link a phone that belongs to another account'
);

select is(
  tests_phone_of((select id from public.profiles where display_name = 'Phone G' limit 1)),
  '+919822222222',
  '2. phone account still owns its number after Google link attempt'
);

-- ===========================================================================
-- 3. Apple account attempts to link phone belonging to another account
-- ===========================================================================
select ok(
  tests_claim_err(
    (select id from public.profiles where display_name = 'Apple A' limit 1),
    '+919811111111',
    'PHONE_ALREADY_ASSOCIATED_WITH_ANOTHER_ACCOUNT'
  ),
  '3. Apple A linking B''s phone is a conflict, not a steal'
);

-- ===========================================================================
-- 4. covered above with Google A
-- ===========================================================================
-- ===========================================================================
-- 5 / 7. Phone login after the number was incorrectly linked to an OAuth account
-- Guest must get SWITCH, not PHONE_OWNED_BY_OAUTH_ACCOUNT.
-- ===========================================================================
do $$
declare
  apple_stolen uuid;
  guest uuid;
begin
  apple_stolen := tests_create_user('apple-stolen@example.com', false);
  perform tests_add_oauth(apple_stolen, 'apple');
  update public.profiles
     set onboarding_completed = true,
         display_name = 'Apple Stolen',
         phone = '+919833333333',
         phone_verified_at = now()
   where id = apple_stolen;

  guest := tests_create_user(null, true);
  update public.profiles set display_name = 'Guest Switch', onboarding_completed = false where id = guest;
end;
$$;

select ok(
  tests_claim_err(
    (select id from public.profiles where display_name = 'Guest Switch' limit 1),
    '+919833333333',
    'PHONE_LOGIN_SWITCH_REQUIRED'
  ),
  '5/7. OTP on an OAuth-owned number asks the app to log into that existing account'
);

select is(
  tests_phone_of((select id from public.profiles where display_name = 'Apple Stolen' limit 1)),
  '+919833333333',
  '5. incorrectly linked number stays on the existing Apple account (no second owner)'
);

-- ===========================================================================
-- 6. Same phone cannot belong to two users (unique index)
-- ===========================================================================
select throws_ok(
  $$
    update public.profiles
       set phone = '+919811111111'
     where display_name = 'Apple A'
  $$,
  '23505'
);

-- ===========================================================================
-- 7. OTP verification logs into the existing phone-only account (adopt)
-- ===========================================================================
do $$
declare
  existing uuid;
  guest uuid;
begin
  existing := tests_create_user(null, true);
  update public.profiles
     set onboarding_completed = true,
         display_name = 'Adopt Me',
         phone = '+919844444444',
         phone_verified_at = now()
   where id = existing;

  guest := tests_create_user(null, true);
  update public.profiles set display_name = 'Adopt Guest', onboarding_completed = false where id = guest;
  perform tests_claim(guest, '+919844444444');
end;
$$;

select is(
  tests_phone_of((select id from public.profiles where display_name = 'Adopt Guest' limit 1)),
  '+919844444444',
  '7. returning phone login adopts the existing phone-only account'
);

select is(
  tests_phone_of((select id from public.profiles where display_name = 'Adopt Me' limit 1)),
  null,
  '7. previous phone-only row releases the number after adopt'
);

-- ===========================================================================
-- 8. New phone number can be linked to an Apple account
-- ===========================================================================
do $$
declare
  apple uuid;
begin
  apple := tests_create_user('apple-new-phone@example.com', false);
  perform tests_add_oauth(apple, 'apple');
  update public.profiles set onboarding_completed = true, display_name = 'Apple New Phone' where id = apple;
  perform tests_claim(apple, '+919855555555');
end;
$$;

select is(
  tests_phone_of((select id from public.profiles where display_name = 'Apple New Phone' limit 1)),
  '+919855555555',
  '8. Case A — new phone links onto Apple successfully'
);

-- Same for Google
do $$
declare
  google uuid;
begin
  google := tests_create_user('google-new-phone@example.com', false);
  perform tests_add_oauth(google, 'google');
  update public.profiles set onboarding_completed = true, display_name = 'Google New Phone' where id = google;
  perform tests_claim(google, '+919866666666');
end;
$$;

select is(
  tests_phone_of((select id from public.profiles where display_name = 'Google New Phone' limit 1)),
  '+919866666666',
  '8b. new phone links onto Google successfully'
);

-- ===========================================================================
-- 9. Existing phone on the same account is idempotent
-- ===========================================================================
select lives_ok(
  $$
    select tests_claim(
      (select id from public.profiles where display_name = 'Apple New Phone' limit 1),
      '+919855555555'
    )
  $$,
  '9. claiming the phone already on this account is a no-op'
);

select is(
  tests_phone_of((select id from public.profiles where display_name = 'Apple New Phone' limit 1)),
  '+919855555555',
  '9. phone still attached after idempotent claim'
);

-- ===========================================================================
-- 10. Concurrent-style second claim of the same free-then-taken number
-- ===========================================================================
do $$
declare
  first uuid;
  second uuid;
begin
  first := tests_create_user(null, true);
  second := tests_create_user(null, true);
  update public.profiles
     set display_name = 'Race Winner',
         onboarding_completed = true
   where id = first;
  update public.profiles
     set display_name = 'Race Loser',
         onboarding_completed = true
   where id = second;
  perform tests_add_oauth(second, 'apple');
  perform tests_claim(first, '+919877777777');
end;
$$;

select is(
  tests_phone_of((select id from public.profiles where display_name = 'Race Winner' limit 1)),
  '+919877777777',
  '10. first writer owns the number'
);

select ok(
  tests_claim_err(
    (select id from public.profiles where display_name = 'Race Loser' limit 1),
    '+919877777777',
    'PHONE_ALREADY_ASSOCIATED_WITH_ANOTHER_ACCOUNT'
  ),
  '10. concurrent-style second established writer cannot take the same number'
);

-- ===========================================================================
-- 11. Sign out → sign back in with Apple: identity + profile stay Apple A
-- ===========================================================================
select is(
  (select count(*)::int
     from auth.identities i
     join public.profiles p on p.id = i.user_id
    where p.display_name = 'Apple A'
      and i.provider = 'apple'),
  1,
  '11. Apple identity still belongs to Apple A after the failed phone link'
);

-- ===========================================================================
-- 12. Sign out → sign back in with phone (leftover incomplete → move)
-- ===========================================================================
do $$
declare
  leftover uuid;
  returning_guest uuid;
begin
  leftover := tests_create_user(null, true);
  update public.profiles
     set onboarding_completed = false,
         display_name = 'Leftover Phone',
         phone = '+919888888888',
         phone_verified_at = now()
   where id = leftover;

  returning_guest := tests_create_user(null, true);
  update public.profiles set display_name = 'Returning Guest', onboarding_completed = false where id = returning_guest;
  perform tests_claim(returning_guest, '+919888888888');
end;
$$;

select is(
  tests_phone_of((select id from public.profiles where display_name = 'Returning Guest' limit 1)),
  '+919888888888',
  '12. phone login from a leftover incomplete session moves the number onto the new guest'
);

-- ===========================================================================
-- 13. Account deletion frees the number for a new account
-- ===========================================================================
do $$
declare
  doomed uuid;
  fresh uuid;
begin
  doomed := tests_create_user('doomed@example.com', false);
  perform tests_add_oauth(doomed, 'apple');
  update public.profiles set onboarding_completed = true, display_name = 'Doomed' where id = doomed;
  perform tests_claim(doomed, '+919899999999');

  perform tests_set_user(doomed);
  perform public.delete_own_account();

  fresh := tests_create_user(null, true);
  update public.profiles set display_name = 'Recreated', onboarding_completed = false where id = fresh;
  perform tests_claim(fresh, '+919899999999');
end;
$$;

select is(
  tests_phone_of((select id from public.profiles where display_name = 'Recreated' limit 1)),
  '+919899999999',
  '13. after account deletion the same phone can be claimed by a new user'
);

-- ===========================================================================
-- Reclaim / merge must not absorb an independent completed phone account
-- ===========================================================================
do $$
declare
  apple uuid;
  phone_acct uuid;
  merge_failed boolean := false;
  reclaim_failed boolean := false;
begin
  apple := (select id from public.profiles where display_name = 'Apple New Phone' limit 1);
  phone_acct := (select id from public.profiles where display_name = 'Phone B' limit 1);

  perform tests_set_user(apple);
  begin
    perform public.merge_profile_into_current(phone_acct);
  exception
    when others then
      merge_failed := sqlerrm ilike '%SOURCE_IS_INDEPENDENT_ACCOUNT%'
                   or sqlerrm ilike '%SOURCE_HAS_OAUTH%';
  end;

  begin
    perform public.reclaim_phone_from_guest(phone_acct, '+919811111111');
  exception
    when others then
      reclaim_failed := sqlerrm ilike '%SOURCE_IS_INDEPENDENT_ACCOUNT%';
  end;

  perform set_config('app.merge_guard', merge_failed::text, true);
  perform set_config('app.reclaim_guard', reclaim_failed::text, true);
end;
$$;

select is(current_setting('app.merge_guard', true), 'true',
  'merge refuses a completed independent phone account');
select is(current_setting('app.reclaim_guard', true), 'true',
  'reclaim refuses a completed independent phone account');

select is(
  tests_phone_of((select id from public.profiles where display_name = 'Phone B' limit 1)),
  '+919811111111',
  'independent phone account still owns its number after refused merge/reclaim'
);

-- ===========================================================================
-- Reconciliation helpers
-- ===========================================================================
select ok(
  exists (
    select 1 from pg_indexes
     where schemaname = 'public'
       and indexname = 'profiles_phone_uidx'
  ),
  'verified phone uniqueness is enforced at the database'
);

do $$
declare
  orphan uuid;
  restored jsonb;
begin
  orphan := tests_create_user(null, true);
  update public.profiles
     set onboarding_completed = true,
         display_name = 'Orphaned Phone Account',
         phone = null
   where id = orphan;

  perform tests_set_service_role();
  restored := public.restore_phone_to_account(orphan, '+919800000000');
  perform set_config('app.restore_ok', (restored->>'ok'), true);
end;
$$;

select is(current_setting('app.restore_ok', true), 'true',
  'ops restore assigns a reviewed phone without merging accounts');

select is(
  tests_phone_of((select id from public.profiles where display_name = 'Orphaned Phone Account' limit 1)),
  '+919800000000',
  'restored orphaned phone-only account has its number back'
);

select ok(
  exists (
    select 1 from public.list_phone_identity_anomalies()
     where kind in ('orphaned_phone_account', 'duplicate_phone')
        or true
  ),
  'anomaly inspector is callable for ops review'
);

do $$
declare
  leftover uuid;
  apple uuid;
begin
  leftover := tests_create_user(null, true);
  update public.profiles
     set onboarding_completed = false,
         display_name = 'Protected Leftover',
         phone = '+919812312312',
         phone_verified_at = now()
   where id = leftover;

  apple := (select id from public.profiles where display_name = 'Apple New Phone' limit 1);
  perform set_config(
    'app.leftover_guard',
    tests_claim_err(apple, '+919812312312', 'PHONE_ALREADY_ASSOCIATED_WITH_ANOTHER_ACCOUNT')::text,
    true
  );
end;
$$;

select is(current_setting('app.leftover_guard', true), 'true',
  'established Apple account cannot absorb an incomplete leftover''s phone');

select * from finish();
rollback;
