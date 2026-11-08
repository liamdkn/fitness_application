# Feedback loop: wearable, scales, waist and food

How the app's inputs are meant to combine into a tight feedback loop.

## Inputs

| Input | State |
|---|---|
| Food log and Bluetooth kitchen scale | Done. |
| Body weight (manual and Bluetooth) | Done. A smart body scale is planned. |
| Waist | Daily check-in field, one reading a day in `body_measurements`. |
| Smart ring | Optional future integration. Its data contract, permissions, retention, and user value must be validated before implementation. |
| Continuous glucose monitor | NFC reader in progress. |
| Guessed calories for an overfeed | Planned, below. |

## Ring integration

No smart-ring API is part of the maintained app. Any future integration must use a documented, supported API; keep credentials in the Keychain; make data sharing optional; and define retention and deletion before release.

## Guessed calories for an overfeed

An off-plan day is usually under-logged, so the TDEE engine currently leaves it out. Instead, store the guess:

- A day gets an unlogged range (low and high kcal) on top of what was logged.
- The midpoint feeds the engines; the width says how far to trust it, so a narrow range counts for more than a wide one.
- The Phase Report's cost of off-plan days uses it.

## The loop

1. Intake (logged plus any guessed range) and the weight trend give the TDEE estimate.
2. Waist says whether a weight change is fat or water.
3. Ring metrics (HRV, resting heart rate, sleep, temperature) say whether the deficit is being recovered from.
4. Glucose response to meals, once the reader is done.
5. The output is always a suggestion the user confirms, never an automatic change to targets.
