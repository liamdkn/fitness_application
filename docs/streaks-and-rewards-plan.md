# Streaks, stars and rewards

Design for the game layer on top of the Coach's day classification: a streak, a star chart, and self-set rewards. The engine is pure Swift (`StreakEngine.swift`); `StreakEngineTests` holds the acceptance fixture.

## Streak

- The streak is the number of consecutive on-plan days ending yesterday, plus today once it provisionally qualifies (enough logged, not over budget). Best streak is always shown beside it.
- A planned treat within budget keeps the day on plan.
- **Sick days are neutral:** they neither break the streak nor extend it.
- A **barely logged day always breaks** the streak. This keeps logging honest.

### Freezes: one slip, never two

Single slips are survivable; the second day in a row is what does the damage. Freezes encode that.

- A freeze covers one isolated off-plan day (flagged or over). The day still shows no star, but the streak survives.
- A freeze never covers an off day that follows another off day. Two in a row always break the streak.
- A freeze is only spent when there is a streak to protect.
- Earned, never free: one per perfect Monday-to-Sunday week (7 of 7 on plan, no sick days), at most two banked.

### Milestones and breaks

Streaks of 3, 7, 14, 21, 30, 45, 60 and 90 days get a full-screen moment. A break gets a calm one: no guilt copy, and never a suggestion to eat less or do extra cardio to win it back. There is no repair for past days; a freeze earned in advance is the only protection.

## Star chart

Each on-plan day earns one star on the calendar. Today shows a hollow star until the next morning's check-in confirms it. Off days have no star (grey, or a dashed outline for barely logged). A frozen day carries a snowflake. A perfect week earns a gold medal. Future days up to the phase end are empty outlines, so the stars left are visible. A newly confirmed star pulses once.

## Rewards

The user sets a prize and a behaviour goal:

| Goal | Achieved when |
|---|---|
| `stars` | Total stars this phase reach N. |
| `streak` | The best streak reaches N days. |
| `perfect_weeks` | N perfect weeks. |
| `phase_complete` | The phase has ended with at least X% of days on plan. |

- There is deliberately **no weight-based goal**: body weight swings by kilograms from water after a single large day, so it would reward luck and timing rather than behaviour.
- Progress counts confirmed days only, and an achievement is stored the moment it happens, so it can't be unlocked and then taken back.
- A missed deadline quietly clears; the reward stays active.
- An earned reward shows a full-screen moment with Claim or Later; claimed rewards move to a trophy shelf. Photos live in a private per-user storage bucket.

## Engine

One chronological pass over the finished days, recomputed from scratch on every load. Only events (milestones, freezes used or earned, breaks) are persisted, so they show once and never re-fire. Events from before yesterday are recorded silently the first time, so history doesn't replay.

## Schema

Migration `0082_streaks_rewards.sql` adds `rewards` and `streak_events` (both with row-level security scoped to `auth.uid()`) and a private `reward-photos` storage bucket with per-user object policies.

## Testing

`StreakEngineTests` replays a 65-day synthetic fixture with known on-plan runs and checks the stars, the best streak, that no freeze is earned without a perfect week, and that streaks are the same with freezes available (freezes are earned, not free). Other tests cover isolated slips with and without a banked freeze, two-in-a-row, barely logged days, the bank cap, neutral sick days, milestone dates, each reward type, and the 21:30 reminder timing.
