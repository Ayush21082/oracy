-- Onboarding fields that were previously device-local only.
-- Guests (anon auth) and linked accounts share the same profiles.id,
-- so these persist across guest → Apple/Google link when identity is linked.

alter table public.profiles
  add column if not exists age integer
    check (age is null or (age >= 13 and age <= 120)),
  add column if not exists priorities text[] not null default '{}',
  add column if not exists personality text[] not null default '{}';

comment on column public.profiles.age is 'User-reported age from onboarding / account settings';
comment on column public.profiles.priorities is 'Onboarding priority tags (confidence, clarity, …)';
comment on column public.profiles.personality is 'Onboarding personality tags (technology, creative, …)';
