# FitNotes Progress

## Phase 1 Checklist
- [x] Create the notes system in `docs/notes`.
- [x] Restructure the app into `Models`, `Features`, `Services`, and `Shared`.
- [x] Add SwiftData model types for muscle groups, exercises, workouts, and workout sets.
- [x] Seed the default English catalog once on first launch.
- [x] Add workout and exercise store layers.
- [x] Support a single active draft workout with resume behavior.
- [x] Replace the starter UI with a minimal shell for Home, History, and Import.
- [x] Add tests for seeding, draft persistence, and exercise deduplication.

## Phase 2 Checklist
- [x] Build the workout builder on top of the Phase 1 draft workout flow.
- [x] Add muscle group and exercise selection.
- [x] Add custom exercise creation.
- [x] Add validated set entry with automatic set ordering.
- [x] Show current exercise sets and a full workout summary while building.
- [x] Finish workouts and remove them from active draft state.
- [x] Show workout detail from History.
- [x] Add tests for set ordering and finished workout history.

## Phase 3 Checklist
- [x] Add a document picker import flow.
- [x] Parse FitNotes CSV exports.
- [x] Normalize, validate, and persist imported workouts.
- [x] Show an import summary with skipped rows.

## Phase 4 Checklist
- [x] Improve navigation and interaction details.
- [x] Add stronger validation and recovery paths.
- [x] Improve accessibility.
- [x] Expand automated coverage for primary flows.

## Work Log
- 2026-05-23: Added the notes system and wrote the Phase 1 roadmap, progress tracker, and decision log.
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
