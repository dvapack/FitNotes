# FitNotes Decisions

## 2026-05-23
- Phase 1 implementation uses English-only copy for notes and app content.
- Persistence uses SwiftData with one shared on-device store and no backend in v1.
- The app supports exactly one active draft workout during Phase 1.
- Phase 1 ships a placeholder shell for Home, History, and Import so persistence can land before the full workout builder.
