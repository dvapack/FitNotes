# FitNotes Progress

## Shipped Baseline
- [x] Notes system created in `docs/notes`.
- [x] SwiftData models for muscle groups, exercises, workouts, and workout sets.
- [x] Seeded default English catalog.
- [x] Store-based draft workout lifecycle with single active draft behavior.
- [x] Home, History, and CSV Import flows.
- [x] Statistics tab with progression and personal record summaries.
- [x] Workout builder with custom categories/exercises, validated set entry, deletion, and finish/discard flows.
- [x] Richer workout metadata: workout comment, editable date, set comments, set editing, set reordering, copy-most-recent workout, and share text.
- [x] Exercise library management: favorites, notes, muscle group color metadata, search, add/edit/delete for muscle groups and exercises, rest defaults, and type/unit metadata.
- [x] Regression coverage expanded to 27 tests.

## Phase 5 Checklist: Migration Safety and Data Compatibility
- [x] Add real migration coverage for older on-device stores.
- [x] Replace destructive recovery assumptions for production store loading.
- [x] Define backfill defaults for schema-expanded fields.
- [x] Verify richer schema compatibility with CSV import and seeding.

## Phase 6 Checklist: Workout Flow Depth and Navigation Polish
- [x] Add visible exercise reordering UI in active workouts.
- [x] Improve in-workout navigation and training-session layout.
- [x] Add visible rest timer UX.
- [x] Add clearer duration and finish-time editing UX.

## Phase 7 Checklist: Exercise Insights and Goals
- [x] Add exercise overview screens.
- [x] Add per-exercise history screens.
- [x] Add richer PR presentation and goal tracking.
- [x] Link library items into exercise insights.

## Phase 8 Checklist: Calendar and Training Review
- [x] Add month calendar view.
- [x] Add list view and filtering.
- [x] Reuse category colors and workout summaries in calendar UI.
- [x] Add workout-detail and exercise-detail drill-ins from the calendar.

## Phase 9 Checklist: Settings and App Behavior Controls
- [x] Add persisted app settings model/service.
- [x] Add unit system and increment settings.
- [x] Add calendar, PR, set-complete, next-set, and wake-lock settings.
- [x] Add home screen display preferences.

## Phase 10 Checklist: Data Portability and Backup
- [x] Add full-app export.
- [x] Add restore flow.
- [x] Add spreadsheet export.
- [x] Add destructive reset flows with explicit confirmations.

## Phase 11 Checklist: Body Tracker
- [x] Add configurable body measurements.
- [x] Add custom measurement units and enable/disable behavior.
- [x] Add body history and graphing.
- [x] Add body-goal support.

## Phase 12 Checklist: Stability Cleanup and Legacy Store Recovery
- [x] Reproduce and lock the failing legacy-store path.
- [x] Implement real legacy-store recovery/import.
- [x] Harden bootstrap/recovery UX.
- [x] Clean up remaining actionable runtime error handling.
- [x] Add disk-backed migration regression coverage.

## Work Log
- 2026-05-23: Added the notes system and wrote the original roadmap, progress tracker, and decision log.
- 2026-05-23: Replaced the starter hardcoded exercise flow with SwiftData models and English seed data.
- 2026-05-23: Added store-based draft workout handling and a minimal tab-based app shell.
- 2026-05-23: Added automated tests for seeding, workout draft lifecycle, and duplicate exercise handling.
- 2026-05-23: Replaced the draft placeholder with a real workout builder for muscle group selection, exercise selection, custom exercises, and set entry.
- 2026-05-23: Added workout history detail and expanded automated coverage for set ordering and finished workout history.
- 2026-05-23: Fixed builder edge-case crashes, prevented blank custom exercises, and moved set validation into the store layer.
- 2026-05-23: Added custom muscle group creation in the workout builder, including validation and regression tests.
- 2026-05-23: Added FitNotes CSV preview/import flow with skipped-row handling and importer regression tests.
- 2026-05-23: Added discard and empty-finish confirmations, keyboard flow polish, overview stats, and draft deletion test coverage.
- 2026-05-23: Switched the workout builder to reactive SwiftData queries so saved workouts, sets, muscle groups, and exercises stay visible immediately.
- 2026-05-23: Added deletion support for saved sets during a workout and for completed workouts from History, with regression tests.
- 2026-05-23: Added the first FitNotes adaptation slice: richer workout/exercise/set metadata, routine models and flows, a library tab, additional tabs in the shell, and expanded regression coverage.
- 2026-05-23: Rebased the notes to show the new shipped baseline and split the remaining work into Phases 5-11.
- 2026-05-23: Simplified the workout builder so saved sets are treated as completed immediately and exercise selection no longer uses an in-builder search field.
- 2026-05-24: Removed routine templates from the app and expanded the library into full muscle group and exercise management with add, edit, and delete flows.
- 2026-05-24: Removed workout tools from the workout builder so the logging flow stays centered on direct set entry.
- 2026-05-24: Replaced the silent shared-store reset with an explicit recovery screen and reset action, and added regression coverage for the reset helper.
- 2026-05-24: Added a legacy-data backfill pass at startup to persist defaults and repair ordering/snapshot fields for richer workout and exercise metadata, with regression tests.
- 2026-05-24: Introduced a versioned SwiftData schema baseline, added migration-plan coverage, verified seeding/import defaults against the richer model, and clarified the explicit recovery path for pre-versioned stores.
- 2026-05-24: Finished Phase 6 by adding in-workout exercise reordering, a session flow jump menu, a visible rest timer tied to exercise defaults, and editable finish-time/duration handling with regression coverage for workout time normalization.
- 2026-05-24: Finished Phase 7 by adding exercise insight screens with progression, PR highlights, persisted goals, workout-history drill-ins, library deep-links, and goal backfill coverage.
- 2026-05-24: Finished Phase 8 by turning History into a calendar-and-list training review flow with category and exercise filters, streak and weekly summary stats, day drill-ins, and direct links into workout details and exercise insights.
- 2026-05-24: Finished Phase 9 by adding a persisted app-settings model with migration/backfill coverage, a dedicated Settings tab, global unit and increment controls, calendar week-start and PR display behavior, configurable set-complete and next-set defaults, workout wake-lock control, and home dashboard visibility preferences.
- 2026-05-24: Finished Phase 10 by adding versioned full-backup export and restore, spreadsheet-friendly workout CSV export, explicit workouts-only and full-app reset flows in Settings, and regression coverage for backup round-trips and reset behavior.
- 2026-05-24: Finished Phase 11 by adding a standalone body-tracking module with configurable measurements, custom units, enabled/disabled metrics, trend charts, directional goals, backup/reset integration, schema migration coverage, and new regression tests.
- 2026-05-24: Completed a stability audit, confirmed the app currently builds cleanly and passes 56 tests on the `iPhone 17` simulator, and identified pre-versioned on-device store recovery for `NSCocoaErrorDomain 134504` as the active blocker for the next phase.
- 2026-05-24: Finished Phase 12.1 by adding disk-backed migration regression coverage for current V3 stores, versioned V1/V2 migration, and pre-versioned legacy-store failure reproduction via a temporary Core Data store harness; startup now keeps legacy unversioned stores on the explicit recovery path instead of reopening them with the latest schema shape, and the suite now passes 61 tests on the `iPhone 17` simulator.
- 2026-05-24: Finished Phase 12.2 by adding a real legacy-store recovery/import path that backs up pre-versioned stores, loads them through the original Core Data model, imports them into a fresh V3 store with set ordering and snapshot defaults preserved, surfaces preserved-backup details in recovery errors/UI, and now passes 63 tests on the `iPhone 17` simulator.
- 2026-05-25: Finished Phase 12.3 by distinguishing ordinary load, failed legacy recovery, and post-recovery startup failures in bootstrap state; recovery UI now shows preserved-backup presence and offers explicit current-store-only versus delete-both reset actions, startup logging records the path taken, and regression coverage now locks the post-recovery failure and backup-aware reset flows.
- 2026-05-25: Finished Phase 12.4 by replacing assertion-only body-tracking persistence failures with visible alerts, making settings changes restore the prior saved value when persistence fails instead of silently drifting in memory, and adding regression coverage for save-success and save-failure rollback behavior; the suite now passes 69 tests on the `iPhone 17` simulator.
