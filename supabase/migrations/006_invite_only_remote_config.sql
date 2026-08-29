-- Invite-only gate (readable via remote_config)

insert into public.remote_config (key, value, description)
values (
  'invite_only_enabled',
  'false'::jsonb,
  'When true, new devices must redeem an invite / referral code before using Oracy.'
)
on conflict (key) do nothing;
