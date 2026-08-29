-- Invite tracking for waitlist / RSVP emails.

alter table public.interested
  add column if not exists invite_status text not null default 'not_sent'
    check (invite_status in ('not_sent', 'sent')),
  add column if not exists invite_sent_at timestamptz;

create index if not exists interested_invite_status_idx
  on public.interested (invite_status);

comment on column public.interested.invite_status is
  'not_sent | sent — admin invite email state';
comment on column public.interested.invite_sent_at is
  'When the invite email was last sent successfully';
