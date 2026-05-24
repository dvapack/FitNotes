# FitNotes Decisions

## 2026-05-23
- Phase 1 implementation uses English-only copy for notes and app content.
- Persistence uses SwiftData with one shared on-device store and no backend in v1.
- The app supports exactly one active draft workout during Phase 1.
- Phase 1 ships a placeholder shell for Home, History, and Import so persistence can land before the full workout builder.
- The first FitNotes adaptation slice expands the core schema before adding calendar/settings/body tracking.
- Exercise deletion keeps workout history readable by storing exercise/category snapshot values on `WorkoutSet`.
- Explicit library management ships before calendar/settings/body tracking because it builds directly on the current workout model.
- Automated tests run the app with an in-memory container under XCTest to avoid shared-store migration crashes during test execution.
- Remaining roadmap work is now split into Phases 5-11, with production-grade schema migration treated as the next highest priority.
- Saved workout sets are treated as completed as soon as they are logged, so the active workout flow does not expose a separate completion toggle.

## 2026-05-24
- Routines are no longer part of the product direction; workout creation stays centered on the single draft workout flow plus manual set logging.
- The Library tab is the canonical place to manage muscle groups and exercises, including add, edit, and delete actions for both.
- Workout tools are no longer part of the product direction; workout logging stays focused on direct set entry inside the workout builder.
- Shared-store bootstrap no longer silently deletes the on-device SwiftData files after a load failure; recovery must be explicit and user-triggered.
- Legacy or partially populated rows should be repaired in-place at startup so richer exercise and workout metadata has persisted defaults before later schema versioning work begins.
- Pre-versioned SwiftData stores are treated as an explicit unsupported migration case: the app preserves those files, explains the limitation, and lets the user choose whether to reset local data.
