# FitNotes Stability Cleanup Plan

## Summary
- This note tracks the active migration and stability cleanup work after the shipped Phase 11 baseline.
- The primary blocker is a legacy on-device SwiftData/Core Data startup failure:
  - `NSCocoaErrorDomain (134504)`
  - `Cannot use staged migration with an unknown model version.`
- The recovery goal is to preserve user data first, attempt best-effort legacy recovery/import, and use reset only as a fallback when recovery truly fails.

## Confirmed Findings
- `xcodebuild build -project FitNotes.xcodeproj -scheme FitNotes -destination 'generic/platform=iOS Simulator'` succeeds.
- `xcodebuild test -project FitNotes.xcodeproj -scheme FitNotes -destination 'platform=iOS Simulator,name=iPhone 17'` succeeds.
- Current baseline is green on the `iPhone 17` simulator with 63 passing tests.
- The confirmed production issue is the pre-versioned on-device store load failure with `NSCocoaErrorDomain 134504`.
- The app now backs up detected pre-versioned stores, imports them through the original unversioned model into a fresh V3 store, and surfaces preserved-backup details when recovery fails.
- Actionable cleanup scope is limited to app-owned runtime/build/test warnings and error paths, not benign Xcode toolchain noise.

## Phase-By-Phase Plan

### Phase 12.1: Reproduce and Lock the Legacy Store Failure
- Status: complete on 2026-05-24.
- Added disk-backed regression coverage for:
  - current V3 stores
  - versioned V1/V2 migration behavior
  - pre-versioned legacy store failure behavior
- Added bootstrap-level coverage for the failing shared-store load path.
- Verified the test harness uses temporary store locations rather than the real shared app store path.

Acceptance criteria:
- The legacy store failure is reproducible in automated tests.
- Versioned-store success paths and pre-versioned failure paths are clearly separated in coverage.

### Phase 12.2: Implement Real Legacy Store Recovery and Import
- Status: complete on 2026-05-24.
- Added an explicit legacy unversioned Core Data loading path matching the original shipped store shape.
- Added backup-before-recovery handling for the failing live store and kept the preserved backup path visible in recovery messaging.
- Added import into a fresh V3 store while preserving:
  - single draft workout semantics
  - finished workout history
  - set ordering
  - normalized exercise and muscle group deduplication
  - persisted snapshot/backfill defaults
- Added regression coverage for both successful recovery and failed recovery with the backup still preserved.

Acceptance criteria:
- A legacy pre-versioned store can recover into the current schema without forced data loss.
- Failed recovery leaves the original data preserved and surfaces a clear recovery error.

### Phase 12.3: Harden Bootstrap and Recovery UX
- Status: complete on 2026-05-25.
- Distinguish between:
  - ordinary store load failure
  - legacy recovery attempted and failed
  - recovery succeeded but post-import preparation failed
- Make retry/reset behavior aware of active store files and any legacy backup files created during recovery.
- Improve startup logging and recovery messaging so the path taken is visible during diagnosis.

Acceptance criteria:
- Recovery UI accurately reflects whether preserved legacy data still exists.
- Reset/retry actions behave predictably across normal and legacy-failure states.

### Phase 12.4: Clean Up Remaining Actionable Runtime Error Handling
- Status: complete on 2026-05-25.
- Replace assertion-only persistence failure handling in user-triggered flows with visible error state where appropriate.
- Do a focused pass on runtime paths that can silently fail in release builds.
- Leave non-actionable Xcode/AppIntents metadata noise out of scope unless product direction changes.

Acceptance criteria:
- App-owned runtime persistence failures do not rely on debug-only assertions for visibility.
- No new warning-cleanup work is marked complete without a real code/test verification pass.

## Test and Verification Checklist
- [x] `xcodebuild build -project FitNotes.xcodeproj -scheme FitNotes -destination 'generic/platform=iOS Simulator'`
- [x] `xcodebuild test -project FitNotes.xcodeproj -scheme FitNotes -destination 'platform=iOS Simulator,name=iPhone 17'`
- [x] Disk-backed test for current V3 store open path.
- [x] Disk-backed test for V1/V2 to V3 migration path.
- [x] Disk-backed test for pre-versioned store failure path.
- [x] Regression test that failed recovery preserves backup store files.
- [x] Regression test that reset flow removes both active and backup store files when requested.
- [ ] Manual verification with a copied legacy store on simulator/device.

## Risks and Assumptions
- Existing uncommitted feature work should remain untouched unless directly required by the persistence fix.
- The current note set remains the historical record; this file is the active source of truth for the cleanup scope.
- “Remove warnings and errors” means actionable app-owned issues, not harmless Xcode framework/toolchain output.
- Recovery should prioritize data preservation even if that makes the implementation more involved than a reset-only path.
