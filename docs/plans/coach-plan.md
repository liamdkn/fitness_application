# Coach: pattern-driven adherence coaching

Design for the Coach feature: an engine that classifies every day, learns where the user tends to slip from their own history, and steps in at those moments. The engine is pure Swift (`CoachEngine.swift`); the acceptance fixture lives in `CoachEngineTests`.

## Principles

- Everything is derived from data the app already holds. No extra data entry.
- Blunt, numbers-first copy that quotes the user's own rates. No shaming, and fixed templates (no generated text).
- Only model what the data supports. Sleep and steps were tested against off-plan days and showed no signal, so they are deliberately not conditions. Don't add them back without new evidence.

## Day classification

A finished day is one of four statuses, with precedence `flagged`, then `blank`, then `over`:

| Status | Rule |
|---|---|
| `on` | Logged calories at least 80% of the target, not flagged, and no more than target + 150 + that day's planned-treat calories. |
| `flagged` | The next morning's check-in said yesterday was off plan. |
| `blank` | Under 80% of the target logged. Incomplete logging hides damage, so it counts as off. |
| `over` | Above target + 150 + planned treats. |

- The target is the goal row in force on that date (a mid-phase change adds a row).
- A day is final once the next day's check-in exists, or from 04:00 the next morning without one. Today is never classified.
- A planned treat within its budget is on plan and must never read as failure.
- Sick days still count as off in the totals but are marked `isSick` and left out of pattern learning.

## Learning weak spots

For each condition the engine counts how often the day went off plan, against all the other days:

- after an off day (`afterSlip`),
- no session that day (`noTraining`),
- each weekday,
- a high hunger rating (4 or 5) from the next morning's check-in.

A condition is a **weakness** when it has at least 8 days and runs 15 percentage points above the rest. It is compared with the *other days* rather than the overall rate, because the overall rate includes the condition's own days and understates a condition that is most of the problem. Weaknesses are sorted by `(rate - restRate) * sqrt(n)`.

The set is recomputed on every load, so a pattern that stops being true stops being reported.

## Today's message

One message, chosen by priority: a long off-plan stretch, after a slip, a barely logged yesterday, no session yet (once the usual gym time plus two hours has passed), a learned weak weekday, a planned treat, then the plain status.

Hard rules:

- Never suggest eating below target, extra cardio or skipping meals to "make up" for an off day. After a slip the message is always "back to the normal plan".
- Never call a planned treat a slip.
- An off-plan stretch of 5 or more days gets one calm line and no extra numbers.

## Surfaces

- **Dashboard card:** the message, one action button, this week's seven day slots and the current streak.
- **Star chart:** a phase-long Monday-to-Sunday calendar, a chart of off-plan rate by condition with the overall rate as a dashed line, and the lengths of off-plan stretches over time.
- **Nudges (planned):** local notifications at risky moments, capped at two a day, never on a sick day, with each one logged so the feedback loop can be measured.

## Testing

`CoachEngineTests` builds a 65-day synthetic fixture with known counts for each status, known off-plan run lengths and known before/after rates, and asserts that exactly the expected weaknesses are found. Further tests cover precedence, the 80% and budget boundaries, the target changing mid-phase, the 04:00 close, duplicate workout rows, sick-day exclusion, and the wording rules above.
