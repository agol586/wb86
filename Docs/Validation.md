# Settings Experience Validation and Traceability

This document records the implementation state of `specs/002-settings-experience/spec.md`. A `PASS`
means the requirement has fresh deterministic automated evidence. `PARTIAL` or `DEFERRED` is a release
gate and must not be inferred as passed from fixtures.

## Canonical validation

```bash
Scripts/test.sh
Scripts/build-release.sh
Scripts/verify-release.sh /absolute/path/to/MacWubi.app
Scripts/privacy-audit.sh /absolute/path/to/MacWubi.app
Scripts/measure-memory.sh /absolute/path/to/MacWubi.app
Scripts/run-long-stress.sh /absolute/path/to/MacWubi.app 1000000
```

The 2026-08-31 extended-character filtering run passed 264/264 main XCTest cases and 9/9 Release XCTest
cases (273/273 total) plus deterministic dictionary compilation. The measured full-feature lookup samples
remained below 2 ms; exact environment, sample maxima, commands and release-candidate hashes are recorded
in `specs/002-settings-experience/evidence/v1.4-release.md`.
The prior development-signed native arm64 Release build, release verification, privacy audit and 15 MiB
steady-footprint evidence remain in `specs/002-settings-experience/evidence/`; the 30-logical-day,
one-million-committed-character verdict is in `evidence/monthly-volume-stress.md`.

## Functional requirements

| Requirement | Status | Primary automated evidence |
|---|---|---|
| FR-001 | PASS automated; ordinary physical settings flow remains in final matrix | `SettingsWindowTests`, settings integration |
| FR-002 | PASS | `InputModeTests`, `SettingsWindowTests`, `SettingsIntegrationTests` |
| FR-003 | PASS | `TextConversionTests` punctuation-before-width matrix |
| FR-004 | PASS | `InputControllerContractTests`, `SettingsIntegrationTests` session reactivation |
| FR-005 | PASS | `InputEngineTests` zero/one/many four-code matrix |
| FR-006 | PASS | `InputEngineTests`, `InputControllerContractTests` ordered fifth-code action batch |
| FR-007 | PASS | `PrivateModeTests`, `LearningStoreTests`, settings integration |
| FR-008 | PASS | `CandidateQueryTests`, `PersonalizationIntegrationTests` bounded same-key learning |
| FR-009 | PASS | `PinyinDictionaryFormatTests`, `DailyInputIntegrationTests`, privacy audit |
| FR-010 | PASS | `CandidateQueryTests` Wubi-first merge, conversion, dedupe, paging and learning |
| FR-011 | PASS | `CandidatePanelPresenterTests` hint on/off invariance |
| FR-012 | PASS automated; visual matrix deferred | Candidate row/layout ordinary-interaction tests |
| FR-013 | PASS | `InputModeTests` second/third candidate shortcut boundaries |
| FR-014 | PASS | `StandaloneShiftRecognizerTests`, adapter contract tests |
| FR-015 | PASS | `InputModeTests`, settings key-binding tests |
| FR-016 | PASS | `InputModeTests`, reserved/conflict validation tests |
| FR-017 | PASS | All five `CandidatePageKeyGroup` cases in core and UI tests |
| FR-018 | PASS automated; physical click/focus regression deferred | `InputModeTests`, `ModeInputIntegrationTests`; T027 remains manual |
| FR-019 | PASS | `KeyboardLayoutTranslatorTests`, unavailable-layout UI error test |
| FR-020 | PASS | `KeyBindingValidator` range, duplicate, reserved, legacy and layout tests |
| FR-021 | PASS | Draft/save/cancel/I/O and visible feedback tests |
| FR-022 | PASS | Appearance-immediate and semantic-safe-boundary integration test |
| FR-023 | PASS | Multi-client generation, reentrant batch and focus-churn tests |
| FR-024 | PASS | Settings v3 snapshots, restart and atomic replacement tests |
| FR-025 | PASS | Strict v1→v2→v3 golden migration, future preservation and recovery injection |
| FR-026 | PASS | Confirm/cancel/failure restore tests with cross-domain checksums |
| FR-027 | PASS | Migration, snapshot, domain and client failure-recovery suites |
| FR-028 | PASS | Diagnostics redaction, source/binary privacy audit and private permissions |
| FR-029 | PASS | Thin arm64, no package/foreign runtime, empty-entitlement release contracts |
| FR-030 | PASS | T054 every-sample lookup, T055 footprint and T056 30-day/1,000,000-character stability gates pass |
| FR-031 | PASS | 264-test main suite covers defaults, validation, migration, recovery, sessions and input states |
| FR-032 | PASS | Documentation boundary plus `UnsupportedAssistiveTechnologyTests`; no specialized screen-reader source remains |
| FR-040 | PASS | Rime extended A–J/compatibility boundaries, default `wqvb` filtering, setting persistence and UI tests |

## Success criteria

| Criterion | Status | Evidence or remaining gate |
|---|---|---|
| SC-001 | PASS automated | Complete settings integration and input-event matrices; at most one commit per event |
| SC-002 | DEFERRED | Timed target-user usability study has not been executed |
| SC-003 | PASS automated | Exact modifiers, all paging groups, idle/boundary pass-through; T027 physical regression remains |
| SC-004 | PASS | Four/fifth-code zero/one/many/stale/double-commit matrices |
| SC-005 | PASS | Pinned offline corpus, Wubi-first merge and display-text dedupe |
| SC-006 | PASS automated | Restart reconstruction, v1 upgrade, future/corrupt/interruption recovery |
| SC-007 | PASS | Concurrent sessions freeze one immutable generation through each composition |
| SC-008 | PASS | UserLexicon/Learning bytes and generations unchanged for every restore path |
| SC-009 | PASS automated | Ordinary keyboard focus, visible errors, candidate mouse/keyboard selection and screen layout pass; physical matrix remains a release gate |
| SC-010 | PASS | Every lookup sample `<2 ms`; normal footprint 8,258,208 bytes; T056 peak 8,487,584 bytes with no sustained drift after 1,000,000 committed characters |
| SC-011 | PASS | Zero network capability/connections/APIs and content-free diagnostics/persistence audit |
| SC-012 | PASS automated | 264/264 main and 9/9 Release tests plus deterministic resources, privacy and release contracts |
| SC-013 | PASS | README, user guide, specs and release checklist explicitly mark screen-reader-specific functionality unsupported |
| SC-019 | PASS | `wqvb` defaults to `你好`/`您好`; enabling extended characters restores `𠛈` as candidate 3 |

## Release blockers not hidden by automation

- T027: physical InputMethodKit marked-text click/candidate/focus/source-switch regression was explicitly
  deferred and remains open.
- Developer ID Application signing, secure timestamp, notarization, staple and Gatekeeper are final-release
  operations and were intentionally deferred.
- macOS 13/current-supported-OS physical matrices, the target-user usability study and the broader product
  replacement studies remain release validation rather than unimplemented settings behavior.

No validation artifact may contain raw keys, composition/candidate/committed text, client identity, document
context, user paths or a reconstructable input timeline.
