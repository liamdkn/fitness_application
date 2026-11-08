# V1 release checklist

This is a release gate, not a claim that V1 has passed. Updated 2026-11-08 after source/migration review, Debug Simulator and unsigned generic iOS builds, a first-run screen visual check, and the full unit-test target. The 128 tests in 21 suites passed on an iOS 27 simulator. No live Supabase audit, signed archive, or complete physical-device smoke test was run.

## Must close before release

### Repository and secrets

- [ ] Confirm `README.md` and the docs index are the canonical setup path.
- [x] Ignore `supabase/.env.save` and other environment backups (`.env.*`, `*.env.save`). Still inspect repository history and rotate any credential that was ever exposed.
- [ ] Check repository history and rotate any service-role or other secret that was ever exposed. The iOS app must contain only the public anon/publishable key.
- [ ] Keep a clean, reviewable release diff. The current working tree has uncommitted code and documentation changes; review and commit them deliberately before cutting a release.

### Database and access control

- [ ] Use the tracked migration runner (`scripts/migrate.js`) for deployment. Prove both a blank-database install and an upgrade from a representative existing database. Back up and practice restore first.
- [ ] Review and verify migrations 0070 and 0075 against production data and policies. Confirm bounds fit real app data, account export/deletion covers every table and object, and the deployment applied successfully.
- [ ] Compare deployed schema/policies with repository migrations. Static extraction found RLS enabled on all 50 application tables. The two aggregate views use `security_invoker = true`; aggregate and reorder RPCs use `security invoker`.
- [ ] Test two accounts against every private table, child relationship, aggregate view/function, and Storage operation (select/insert/update/delete). Check grants, Auth settings, rate limits, and backup retention.
- [ ] Verify route ownership, photo ownership, signed URL expiry, upload content checks, and cleanup when a record/account is removed.

### Local data and account lifecycle

- [x] Clear local caches and queues on sign-out/account switch; meal, workout, water, supplement, and check-in queued writes now carry an owner and are sent with explicit owner IDs. A generic iOS Simulator build passed. Still prove A→B isolation and in-flight replay behavior on device and with two real test accounts.
- [x] Account export and deletion entry points exist in Settings and migrations 0075. Still verify completeness, Auth deletion behavior, storage cleanup, and backup retention against the deployed project.
- [ ] Add public account creation and password recovery (or document an intentional invite-only distribution and provide a working account-provisioning/support path). Current sign-in UI only signs in.
- [ ] Verify file protection for persisted workouts, meals, check-ins, weight, preferences, widget snapshots, and reminders. Offline SwiftData stores and the outbox now request iOS file protection; verify on device.
- [ ] Test queue idempotency after partial success, duplicate replay, sign-out with pending changes, corrupt local stores, and bounded retries.

### Progress photos: explicit ship gate

- [ ] **Do not ship progress-photo uploads to Supabase.** Before V1, either remove the photo feature or keep photo files on-device only. This is a product security requirement.
- [ ] If keeping on-device photos: store them in the app sandbox with an appropriate strong iOS Data Protection class, exclude the app-support files from device backup if "device only" is literal, partition/clear them on account change, and verify no upload, telemetry, widget, or crash-report path copies photo bytes elsewhere. Explain that a compromised/unlocked device can still expose local data.
- [ ] If removing photos: remove/disable upload and display paths and delete existing rows/objects under a reviewed retention/deletion plan. Remove the Supabase bucket/policies only after confirming no production records remain and backups/retention are handled.
- [ ] CloudKit private storage is a possible later alternative only if the product decision changes to allow iCloud storage. It is still cloud storage and requires an iCloud account, per-user quota, key-reset/recovery handling, and account-bound design; it does not meet the current "device only or no photos" release condition.

### Product behavior and release validation

- [ ] Sign and archive the Release build, review the supported iOS version, smoke-test on physical devices, and create a rollback-ready tag. Unsigned generic iOS Release and Simulator builds both compile.
- [x] Add a 1024×1024 App Store icon using the blue “1%” gym + nutrition direction. Finalize dark/tinted icon variants if desired during App Store visual review.
- [x] Align the widget deployment target with the app at iOS 26.0. State the minimum supported iOS release in the setup docs before publishing.
- [ ] Smoke-test sign-in, logging/edit/delete for training and nutrition, HealthKit granted/denied, photo upload/view, notifications, widget/Live Activity, offline write/reconnect, and date/time-zone boundaries.
- [ ] Verify input bounds in both client and database for calories, macros, quantities, weight, duration, and route data.
- [ ] Verify missing logging days are shown as unknown with explicit coverage, and suppress/qualify adherence and TDEE claims when coverage is too sparse. Do not infer or silently insert calories for absent days.
- [ ] Replace data-dependent force unwrap/crash paths and make missing configuration/local-store failures actionable.
- [ ] Publish a complete public privacy policy and add its URL in App Store Connect. An in-app “Privacy & Data Use” summary is now available in Settings, and app/widget privacy manifests declare UserDefaults access; this does not replace the public policy URL or completed App Privacy answers.
- [ ] Review privacy language and App Store privacy answers for account data, HealthKit, routes, progress photos, barcode lookups, local storage, and retention. The app currently uploads progress photos to private Supabase storage, which conflicts with the explicit photo ship gate above.
- [x] Run focused unit tests. The 128 tests cover nutrition maths, coaching, streaks, phase reports, running feedback, water/caffeine timing, notification privacy defaults, and captured kitchen-scale packets.
- [ ] Add integration coverage for migration upgrades, RLS isolation, offline queue/account behavior, and nutrition-history semantics. Avoid broad persistence refactors until these invariants are protected.

## Findings and current confidence

| Area | What source inspection found | What remains unproven |
|---|---|---|
| RLS | All 50 extracted application tables enable RLS; most user rows use `auth.uid()` policies. Two views and the reviewed aggregate/reorder RPCs explicitly use invoker security. | Deployed parity, grants, policy edge cases, and real cross-user isolation. |
| Public catalog | An older policy allowed unauthenticated OFF food inserts. Migration 0070 in the repository restricts OFF and custom inserts to `authenticated`. | Migration review/application, validation/deduplication abuse resistance. |
| Storage | Progress-photo bucket is private; object paths begin with user UUID; signed URLs are used. Migration 0070 adds limits. | Deployed bucket settings, ownership tests, route/photo retention and deletion. Cloud progress-photo uploads still violate the explicit V1 ship gate. |
| Local data | Sign-out wipes local account data; queued writes are owner-stamped and explicit-owner upserts are used. Generic simulator build succeeds. | Two-account isolation, offline launch, cancellation/in-flight flush, and file-protection behavior on device. |
| Credentials | App reads project URL and anon key from build configuration; no service-role key found in inspected source. | Git-history review and deployed secret rotation status. |

## Release decision

Mark V1 shipped only when every checkbox above that applies to the intended audience is complete and reviewed. For a personal-only release, record any deliberately deferred external-user requirements explicitly; do not describe an unverified production security review as completed.
