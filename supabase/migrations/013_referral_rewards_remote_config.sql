-- Referral rewards master switch (Profile, Settings redeem, onboarding optional code).

insert into public.remote_config (key, value, description)
values (
  'referral_rewards_enabled',
  'true'::jsonb,
  'When true, show the referral reward system: Profile share/milestones, Settings code entry, and optional onboarding referral-code step. Independent of invite_only_enabled.'
)
on conflict (key) do update
set
  value = excluded.value,
  description = excluded.description,
  updated_at = now();

-- Drop the short-lived duplicate flag if it was ever applied.
delete from public.remote_config
where key = 'onboarding_referral_code_enabled';
