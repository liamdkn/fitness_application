-- A day the owner has marked as unreliable for calculations: sick, or not
-- tracked accurately. Flagged days stay visible in history but are left out
-- of the adaptive calorie estimate. One row per date; no row means a normal day.
create table day_flags (
  user_id uuid not null references auth.users(id),
  date date not null,
  status text not null check (status in ('sick', 'not_tracked')),
  created_at timestamptz not null default now(),
  primary key (user_id, date)
);

alter table day_flags enable row level security;

create policy "day_flags_owner_all"
  on day_flags for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- How many flagged days an estimate left out, so the recommendation can say so.
alter table tdee_estimates
  add column excluded_flagged_days integer not null default 0;
