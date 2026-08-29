-- Feature flag: show Google Sign-In in onboarding and account linking.

insert into public.remote_config (key, value, description)
values (
  'google_auth_enabled',
  'false'::jsonb,
  'When true, onboarding and My Account offer Google Sign-In. When false, Google is hidden.'
)
on conflict (key) do nothing;
