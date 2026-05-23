# FitNotes Agent Guide

## Project Snapshot
- `FitNotes` is a native iOS app built with SwiftUI and SwiftData.
- The app tracks workouts, workout sets, exercise catalogs, and FitNotes CSV imports.
- The current product is farther along than the original Phase 1 notes: workout building, history, deletion flows, and CSV import are already implemented.

## Repository Layout
- `FitNotes/FitNotesApp.swift`: app entry point, creates the shared SwiftData container, seeds default data on launch.
- `FitNotes/Models`: SwiftData models: `MuscleGroup`, `Exercise`, `Workout`, `WorkoutSet`.
- `FitNotes/Services`: persistence and business logic:
  - `ModelContainerFactory.swift`: shared and in-memory containers.
  - `SeedDataService.swift`: seeds the default English catalog once.
  - `ExerciseStore.swift`: muscle group and exercise fetch/create logic with deduplication.
  - `WorkoutStore.swift`: draft workout lifecycle, finish/delete flows, set creation/deletion.
  - `FitNotesCSVImporter.swift`: CSV preview and import pipeline.
- `FitNotes/Features/Home`: home dashboard and workout builder UI.
- `FitNotes/Features/History`: workout history and detail screens.
- `FitNotes/Features/Import`: CSV import UI.
- `FitNotes/Shared`: small shared helpers for normalization and workout presentation.
- `FitNotesTests/FitNotesTests.swift`: the main regression suite.
- `docs/notes`: roadmap, progress, and decision notes. Treat these as historical notes, not as the current source of truth for shipped functionality.

## App Architecture
- UI is SwiftUI-first and uses `@Environment(\.modelContext)` plus `@Query` for reactive data updates.
- Mutations go through store/service types instead of being spread directly through views.
- Persistence is fully local via one shared SwiftData store. There is no backend.
- Tests use `ModelContainerFactory.makeInMemoryContainer()` and exercise stores/importers directly.

## Important Domain Rules
- There should be only one active draft workout at a time. A workout is a draft when `finishedAt == nil`.
- `Workout.finishedAt != nil` means the workout belongs in history.
- `WorkoutSet.setOrder` is per workout and per exercise, starting at `1` and incrementing by insertion order.
- Exercise and muscle group creation deduplicate on normalized names, not raw strings.
- Blank exercise names and blank muscle group names must be rejected.
- Weight and reps must both be greater than zero.
- CSV import currently accepts only kilogram units normalized to `kg` or `kgs`.
- Imported workouts are created as already-finished workouts, grouped by day.

## Existing UX Behavior To Preserve
- `HomeView` shows overview stats, recent workouts, and resume/new workout actions.
- `WorkoutBuilderView` supports:
  - selecting or creating a muscle group
  - selecting or creating an exercise
  - adding validated sets
  - deleting saved sets
  - discarding a draft workout
  - finishing a workout, with a confirmation for empty workouts
- `HistoryView` lists finished workouts and supports deleting them.
- `ImportView` validates a CSV first, then imports from the preview object.

## Testing Expectations
- If you change store logic, importer behavior, model relationships, or workout lifecycle rules, update or add tests in `FitNotesTests/FitNotesTests.swift`.
- Prefer in-memory SwiftData tests over UI-heavy testing for business rules.
- Existing tests already cover:
  - one-time seeding
  - single active draft behavior
  - draft persistence across store instances
  - finishing and deleting workouts
  - deleting sets
  - exercise and muscle group deduplication
  - set ordering
  - invalid input rejection
  - CSV preview and import persistence

## Working Conventions
- Keep user-facing copy in English unless the product direction explicitly changes.
- Favor small service-layer fixes over pushing more persistence logic into views.
- Preserve SwiftData relationship delete behavior:
  - deleting a `Workout` cascades to its `WorkoutSet`s
  - deleting a `MuscleGroup` cascades to its `Exercise`s
  - deleting an `Exercise` nullifies `WorkoutSet.exercise`
- When adding catalog-style matching, use the existing normalization helpers in `FitNotes/Shared/StringNormalization.swift`.
- When adding list or summary displays for sets, prefer the shared grouping helper in `FitNotes/Shared/WorkoutPresentation.swift`.

## Notes About Current Repo State
- `readme.md` is very sparse and should not be treated as reliable technical documentation.
- `docs/notes/progress.md` marks all phases complete; verify code behavior against the app itself before trusting the roadmap language.
- There are existing uncommitted changes in:
  - `FitNotes.xcodeproj/project.pbxproj`
  - `readme.md`
  Do not overwrite or revert them unless the user asks.

## Useful Commands
- List files: `rg --files`
- Run tests: `xcodebuild test -project FitNotes.xcodeproj -scheme FitNotes -destination 'platform=iOS Simulator,name=iPhone 16'`
  - If that simulator name is unavailable on this machine, switch to an installed simulator rather than changing project code first.

## When In Doubt
- Trust the code and tests over the old planning notes.
- Preserve the single-draft-workout invariant.
- Add or adjust regression tests when changing importer or persistence behavior.
