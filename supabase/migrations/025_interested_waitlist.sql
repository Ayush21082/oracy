-- Waitlist / RSVP emails from the marketing site.

create table if not exists public.interested (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  created_at timestamptz not null default now(),
  constraint interested_email_uidx unique (email)
);

create index if not exists interested_created_at_idx
  on public.interested (created_at desc);

alter table public.interested enable row level security;

-- Public site writes via service role API only — no anon/authenticated policies.
comment on table public.interested is
  'Marketing waitlist emails from oracy.heyayush.in; written by Vercel API with service role.';
