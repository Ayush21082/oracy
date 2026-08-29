-- Feature flag: show phone OTP auth in onboarding (and related surfaces).

insert into public.remote_config (key, value, description)
values (
  'phone_auth_enabled',
  'true'::jsonb,
  'When true, onboarding offers phone number OTP login. When false, phone is hidden.'
)
on conflict (key) do nothing;
