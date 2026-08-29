-- Allow users to shuffle today's challenge (update assignment row).
create policy "Users can update own assignments"
  on public.daily_assignments
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
