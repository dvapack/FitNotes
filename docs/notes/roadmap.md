# FitNotes Roadmap

## Current Baseline
- The app now ships a local SwiftData workout tracker with Home, History, Statistics, Library, and Import tabs.
- Workout logging supports one active draft workout, workout comments/date editing, set comments, set editing, set reordering, copy-from-last-workout, and workout sharing.
- The exercise library supports muscle group colors, favorites, notes, rest defaults, exercise type metadata, search, and add/edit/delete flows for muscle groups and exercises.
- Tests currently cover the main service layer and pass on the `iPhone 17` simulator.

## Remaining Work Overview
- The app has the first adaptation slice implemented, but several roadmap areas are still incomplete.
- The highest remaining risk is production data migration for older on-device stores after schema expansion.
- The next phases focus on stabilizing migration, deepening workout UX, then adding advanced insights, calendar, settings, and portability.

## Phase 5: Migration Safety and Data Compatibility
- Introduce a versioned schema baseline and attach an explicit migration plan for future releases.
- Repair older or partially populated rows in-place so richer `Exercise`, `Workout`, and `WorkoutSet` metadata has stable persisted defaults.
- Cover migration and recovery behavior with regression tests, including the explicit pre-versioned-store recovery path.
- Preserve existing store files on load failure and surface user-facing recovery instead of destructive automatic reset.
- Audit CSV import and seeded catalog creation against the richer exercise metadata model.

Exit criteria:
- Versioned stores from this release forward have an explicit migration baseline.
- Legacy unversioned stores are preserved and handled with explicit user-facing recovery instead of silent data loss.
- Backfill, import, seeding, and recovery behavior are covered by automated tests.
- No production path silently deletes the main store to recover from schema mismatch.

## Phase 6: Workout Flow Depth and Navigation Polish
- Rework the workout builder into a more focused training-session UX with clearer exercise-level navigation.
- Add in-workout exercise reordering UI on top of the new `exerciseOrder` model support.
- Improve set editing ergonomics, including inline editing and copy previous values.
- Add a visible rest timer experience directly in the workout flow.
- Add workout duration display and editable finish time behavior.

Exit criteria:
- Exercise order can be changed visually during a workout.
- The active workout screen feels training-centric rather than form-centric.
- Copied workouts and normal logging fit naturally into the draft workflow.

## Phase 7: Exercise Insights and Goals
- Expand the current statistics tab into richer exercise overview flows.
- Add per-exercise history screens with record highlights, progression summaries, and workout history drill-ins.
- Add estimated and actual PR concepts where the data model supports both.
- Add exercise goals and progress status for a chosen metric.
- Let the exercise library deep-link into each exercise’s stats and history.

Exit criteria:
- A user can open an exercise and understand recent history, progression, and current records from one place.
- Goals exist as first-class persisted data and appear in exercise insights.

## Phase 8: Calendar and Training Review
- Add a calendar module with month and list views.
- Reuse workout summaries and category colors in the calendar UI.
- Add category and exercise filters for calendar browsing.
- Support drill-in from calendar to workout detail and exercise overview.
- Add lightweight training review summaries such as workouts per week and streak-style indicators if they fit the current UX.

Exit criteria:
- A user can browse completed training sessions by date and filter them meaningfully.
- Calendar drill-in routes cleanly into existing workout and exercise detail screens.

## Phase 9: Settings and App Behavior Controls
- Add settings for unit system, default increment, calendar week start, PR behavior, set-complete behavior, next-set behavior, keep-screen-awake, and home screen display preferences.
- Move any hardcoded behavior defaults that now affect multiple features into a persisted settings model/service.
- Integrate those settings into workout builder, statistics, and future calendar behavior.

Exit criteria:
- App behavior defaults can be changed without code edits.
- Workout and stats flows read from one consistent settings source.

## Phase 10: Data Portability and Backup
- Add full-app export and restore.
- Add spreadsheet-friendly export for workouts and history.
- Add destructive reset flows with confirmation and clear copy.
- Define what settings and future goals/calendar data look like in export payloads.

Exit criteria:
- A user can export and restore the full app state locally.
- Export/restore round-trip behavior is verified with automated tests.

## Phase 11: Body Tracker
- Add configurable body measurements, enable/disable behavior, custom measurements, and unit support.
- Add body measurement history and graphing.
- Add optional goals or directional targets for body metrics.
- Keep this module separate from workout tracking so it can evolve without destabilizing the core training model.

Exit criteria:
- Body tracking works as a coherent standalone module tied into the existing statistics/navigation model.
- Workout tracking remains stable if body tracking is absent or unused.
