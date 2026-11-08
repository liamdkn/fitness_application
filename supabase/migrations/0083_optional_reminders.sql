-- Permission-backed reminders are opt-in. Existing accounts keep their
-- current step/caffeine choices; new accounts start with no reminders.
alter table public.user_preferences
  add column if not exists daily_checkin_reminders_enabled boolean not null default false;

alter table public.user_preferences
  alter column step_reminders_enabled set default false,
  alter column caffeine_reminders_enabled set default false;
