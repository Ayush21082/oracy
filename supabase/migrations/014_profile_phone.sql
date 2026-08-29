-- Phone numbers verified via Firebase Auth (not Supabase SMS).
-- Stored on profiles so Account / Settings can display and gate "linked" state.

alter table public.profiles
  add column if not exists phone text;

comment on column public.profiles.phone is
  'E.164 mobile verified with Firebase Phone Auth (e.g. +9198XXXXXXXX).';

create unique index if not exists profiles_phone_uidx
  on public.profiles (phone)
  where phone is not null;
