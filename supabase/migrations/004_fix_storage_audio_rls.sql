-- Storage RLS: match folder to auth.uid() case-insensitively (Swift UUID strings are uppercase).
-- Also allow UPDATE so upsert uploads work.

drop policy if exists "Users can upload own audio" on storage.objects;
drop policy if exists "Users can read own audio" on storage.objects;
drop policy if exists "Users can delete own audio" on storage.objects;
drop policy if exists "Users can update own audio" on storage.objects;

create policy "Users can upload own audio"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'session-audio'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );

create policy "Users can update own audio"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'session-audio'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  )
  with check (
    bucket_id = 'session-audio'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );

create policy "Users can read own audio"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'session-audio'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );

create policy "Users can delete own audio"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'session-audio'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );
