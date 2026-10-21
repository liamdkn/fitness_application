-- Streaks, stars and rewards (docs/streaks-and-rewards-plan.md).
--
-- `rewards`: prizes set for behaviour goals (stars, streak, perfect weeks, finishing a phase).
-- There is deliberately no weight-based goal: the scale swings 2-3 kg from water after one big day.
-- `streak_events`: only the moments worth remembering (milestones, freezes, breaks), so they
-- show once and never re-fire. The streak itself is recomputed from the days on every load.

create table public.rewards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  note text,
  photo_path text,
  price numeric,
  link text,
  goal_kind text not null check (goal_kind in ('stars','streak','perfect_weeks','phase_complete')),
  goal_value numeric not null,           -- stars/streak/weeks count, or % for phase_complete
  phase_started_at date,                 -- which phase it belongs to (from user_goals)
  deadline date,
  achieved_at timestamptz,
  claimed_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.streak_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  date date not null,
  kind text not null check (kind in ('milestone','freeze_earned','freeze_used','broken')),
  value int,                             -- milestone length, or streak length when broken
  created_at timestamptz not null default now(),
  unique (user_id, date, kind)
);

alter table public.rewards enable row level security;
alter table public.streak_events enable row level security;
create policy "own rows" on public.rewards for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own rows" on public.streak_events for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Reward photos: a private bucket, every object path "{user_id}/{uuid}.jpg" (same as progress photos).
insert into storage.buckets (id, name, public)
values ('reward-photos', 'reward-photos', false)
on conflict (id) do nothing;

create policy "reward_photos_storage_owner_select"
  on storage.objects for select
  using (bucket_id = 'reward-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "reward_photos_storage_owner_insert"
  on storage.objects for insert
  with check (bucket_id = 'reward-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "reward_photos_storage_owner_delete"
  on storage.objects for delete
  using (bucket_id = 'reward-photos' and (storage.foldername(name))[1] = auth.uid()::text);
