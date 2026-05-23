# FitNotes Decisions

## 2026-05-23
- Phase 1 implementation uses English-only copy for notes and app content.
- Persistence uses SwiftData with one shared on-device store and no backend in v1.
- The app supports exactly one active draft workout during Phase 1.
- Phase 1 ships a placeholder shell for Home, History, and Import so persistence can land before the full workout builder.
- The first FitNotes adaptation slice expands the core schema before adding calendar/settings/body tracking.
- Exercise deletion keeps workout history readable by storing exercise/category snapshot values on `WorkoutSet`.
- Routines, workout tools, and library management ship before calendar/settings/body tracking because they build directly on the current workout model.
- Automated tests run the app with an in-memory container under XCTest to avoid shared-store migration crashes during test execution.
- Remaining roadmap work is now split into Phases 5-11, with production-grade schema migration treated as the next highest priority.
- Saved workout sets are treated as completed as soon as they are logged, so the active workout flow does not expose a separate completion toggle.
