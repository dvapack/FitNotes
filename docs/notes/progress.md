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
- [ ] Add exercise overview screens.
- [ ] Add per-exercise history screens.
- [ ] Add richer PR presentation and goal tracking.
- [ ] Link library items into exercise insights.

## Phase 8 Checklist: Calendar and Training Review
- [ ] Add month calendar view.
- [ ] Add list view and filtering.
- [ ] Reuse category colors and workout summaries in calendar UI.
- [ ] Add workout-detail and exercise-detail drill-ins from the calendar.

## Phase 9 Checklist: Settings and App Behavior Controls
- [ ] Add persisted app settings model/service.
- [ ] Add unit system and increment settings.
- [ ] Add calendar, PR, set-complete, next-set, and wake-lock settings.
- [ ] Add home screen display preferences.

## Phase 10 Checklist: Data Portability and Backup
- [ ] Add full-app export.
- [ ] Add restore flow.
- [ ] Add spreadsheet export.
- [ ] Add destructive reset flows with explicit confirmations.

## Phase 11 Checklist: Body Tracker
- [ ] Add configurable body measurements.
- [ ] Add custom measurement units and enable/disable behavior.
- [ ] Add body history and graphing.
- [ ] Add body-goal support.

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
