-- Profile photo URL + public avatars bucket.

alter table public.profiles
  add column if not exists avatar_url text;

comment on column public.profiles.avatar_url is 'Public URL of the user profile photo in storage.avatars';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars',
  'avatars',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Users can upload own avatar" on storage.objects;
drop policy if exists "Users can update own avatar" on storage.objects;
drop policy if exists "Users can delete own avatar" on storage.objects;
drop policy if exists "Anyone can read avatars" on storage.objects;

create policy "Users can upload own avatar"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );

create policy "Users can update own avatar"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'avatars'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  )
  with check (
    bucket_id = 'avatars'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );

create policy "Users can delete own avatar"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );

create policy "Anyone can read avatars"
  on storage.objects for select
  using (bucket_id = 'avatars');
