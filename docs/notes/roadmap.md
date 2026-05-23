# FitNotes Roadmap

## Phase 1: Foundation, Notes, and Persistence
- Create the repository notes system in English.
- Introduce SwiftData models for muscle groups, exercises, workouts, and workout sets.
- Seed the default catalog once on first launch.
- Add workout and exercise stores.
- Support one active draft workout that survives relaunch.
- Replace the starter screens with a minimal shell for Home, History, and Import.
- Add tests for seeding, draft persistence, and exercise deduplication.

Exit criteria:
- Notes are present and maintained in English.
- Hardcoded exercise arrays are removed from the app flow.
- SwiftData models persist across launches.
- Default data seeds exactly once.
- Only one active draft workout exists at a time.
- Phase 1 progress is tracked in `progress.md`.

## Phase 2: Core Workout Flow
- Build the full workout builder.
- Add muscle group and exercise selection.
- Add custom exercise creation and set entry.
- Show current sets while building a workout.
- Finish workouts and show workout details in history.

Exit criteria:
- A user can start or resume a workout draft from Home.
- A user can pick a muscle group and exercise, create a custom exercise, and save sets with validation.
- The current exercise sets and full workout summary are visible while building a workout.
- Finishing a workout removes it from draft state and makes it visible in History.
- History shows workout detail grouped by exercise.

## Phase 3: FitNotes CSV Import
- Add a document picker import flow.
- Parse FitNotes CSV exports.
- Normalize, validate, and persist imported workouts.
- Show an import summary with skipped rows.

Exit criteria:
- A user can choose a CSV file from the Import tab and preview the import before saving.
- Invalid or unsupported rows are skipped without crashing the app.
- Imported workouts appear in History immediately after import.
- Automated tests cover preview validation and persisted import results.

## Phase 4: UX Polish and Hardening
- Improve navigation and interaction details.
- Add stronger validation and recovery paths.
- Improve accessibility.
- Expand automated coverage for primary flows.

Exit criteria:
- Users can safely discard an in-progress workout or finish an empty one with confirmation.
- The main screens surface useful summary information instead of only raw lists.
- Core controls have basic accessibility improvements and smoother keyboard flow.
- Automated tests cover the added lifecycle recovery paths.
