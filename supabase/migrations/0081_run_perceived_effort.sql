-- How a run felt, on Apple's own 1-10 effort scale (the "Rate Your Effort" prompt
-- the Watch shows after a workout, stored in Health). Nullable: older workouts, and
-- runs where the prompt was dismissed, have no rating.
alter table cardio_tracking_sessions
  add column perceived_effort smallint check (perceived_effort between 1 and 10);
