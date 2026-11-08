# 1% Fitness

An iOS app for strength training, running, nutrition and body-composition tracking, built around one idea: **close the loop between what you log and what your body does**. It estimates energy expenditure from your food log and weight trend, flags when a plan isn't working, and turns your own history into coaching.

Built with SwiftUI, a Supabase (Postgres) backend, HealthKit, CoreBluetooth and a watchOS companion. About 45k lines of Swift, 80+ database migrations, and 128 passing unit tests across the calculation engines, privacy defaults and captured scale protocol.

> I use this daily, so it is shaped by real use rather than a tutorial spec. The backend is yours to provision (see [Setup](#setup)); no credentials are in this repository.

> **Status:** active portfolio project and personal prototype. It is not an App Store release. Public account registration and recovery, production backend verification, privacy-policy publication, and release-device validation are still open work.

## What it does

**Training**
- Routines on a weekly schedule, live session logging, supersets, set history and progressive-overload suggestions, deload advice.
- Running plans with distance-based warm-up/cool-down and paces picked from menus. A weekly review suggests progress, hold or back-off from effort ratings and pace trends. The next run is scheduled onto the Apple Watch.
- Live Activities and widgets for workouts and supplements.

**Nutrition**
- Food search (including Open Food Facts), barcode and nutrition-label scanning, recipes and meal prep, saved meals and days.
- Bluetooth kitchen-scale integration: live weights, tare, and unit switching to ml for liquids. The device protocol was reverse-engineered with a probe script (`scripts/scale_probe.py`).
- Planned treats with calorie banking across the week; NFC tags (via Shortcuts) that open the next meal.

**Insight**
- Smoothed (EWMA) trend weight and an **adaptive TDEE estimate** that back-calculates expenditure from intake and weight change, ignoring days that can't be trusted (off-plan, sick, not tracked).
- **Phase report**: progress against the plan, a projected end weight range, what off-plan days cost, lift changes and weekly activity.
- **Coach**: classifies each day, learns your weak spots from your own data (for example, "after an off day you go off again 71% of the time") and picks one message a day. Streaks, stars and self-set rewards sit on top of it.

**Reliability**
- Offline-first writes: check-ins, meals, workouts and water are queued on the device and replayed when the connection returns.
- Row-level security on user data, with private per-user storage buckets for photos.

## How it is built

```
ios/FitnessTracker/
  FitnessTracker/        App: Models, Services (repositories + pure engines), ViewModels, Views
  FitnessTrackerWatch/   watchOS companion (run sessions)
  FitnessTrackerWidgets/ Widgets and Live Activities
  FitnessTrackerTests/   Swift Testing unit tests
supabase/migrations/     Ordered SQL migrations (schema, RLS, storage)
scripts/                 Migration runner, test-data seeder, Bluetooth scale probe
docs/                    Maintained product notes and design specifications
```

- **Feature-oriented SwiftUI with repositories.** Views and view models use focused services for Supabase, HealthKit, Bluetooth and offline queues. Backend queries and destructive account operations stay behind repository boundaries.
- **Pure calculation engines.** The interesting maths (`AdaptiveTDEEEngine`, `PhaseReportCalculator`, `CoachEngine`, `StreakEngine`, run feedback, calorie banking) are plain Swift taking arrays and returning values, with no Supabase or HealthKit inside. That keeps them testable; the tests replay realistic fixtures, including one shaped like 65 days of real history.
- **Design decisions are written down.** [`docs/coach-plan.md`](docs/coach-plan.md) and [`docs/streaks-and-rewards-plan.md`](docs/streaks-and-rewards-plan.md) hold the specs the engines were built against, with the reasoning.
- **Honest about its limits.** [`docs/V1_RELEASE_CHECKLIST.md`](docs/V1_RELEASE_CHECKLIST.md) lists what is verified and what is still open.

## Setup

Requires Xcode 26 (iOS 26 SDK) and a Supabase project.

1. Create a Supabase project and apply the migrations in order:
   ```bash
   cd scripts && npm install
   # put DATABASE_URL in supabase/.env (git-ignored)
   node migrate.js up
   ```
2. Copy `ios/FitnessTracker/Config.xcconfig.example` to `ios/FitnessTracker/Config.xcconfig` and set your project URL and anon (publishable) key. Never put a service-role key in the app.
3. Open `ios/FitnessTracker/FitnessTracker.xcodeproj`, choose your own signing team, and run on a simulator or device. HealthKit, Bluetooth and NFC features need a real device.
4. The current app has sign-in but no public registration screen. Create a development user in Supabase Auth before signing in. For UI testing, `node scripts/seed-test-data.js` fills only the `test@test.com` account with deterministic sample history; it resets that account's transactional data, so never point it at a production project.

A free Apple account can run local device builds, but the full capability set and TestFlight/App Store distribution require an Apple Developer Program team.

Run the tests from Xcode, or:

```bash
xcodebuild test -scheme FitnessTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=latest' \
  -only-testing:FitnessTrackerTests
```

## Documentation

Start at [`docs/README.md`](docs/README.md).

## License

MIT, see [LICENSE](LICENSE).
