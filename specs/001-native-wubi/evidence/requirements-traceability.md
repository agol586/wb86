# Requirements Traceability Review

Reviewed 2026-08-01 after T109. **Release is prohibited while any row is PARTIAL or PENDING.** Automated
tests passed 114/114, but automated evidence is not substituted for physical OS, assistive-technology,
long-duration, study or final distribution gates.

## Functional requirements

| Requirement | Status | Primary evidence / gap |
|---|---|---|
| FR-001 | PARTIAL | Development discovery and lifecycle evidence in `inputmethod-distribution-gate.md` and `us6-lifecycle-recovery.md`; final Developer ID/notary/Gatekeeper is T111. |
| FR-002 | PASS | `us1-daily-input.md`, dictionary/core/integration tests. |
| FR-003 | PASS | 136,233-record manifest and reproducibility in `Docs/LexiconProvenance.md`. |
| FR-004 | PASS | `us1-daily-input.md`, event/presenter contract tests. |
| FR-005 | PASS | `us1-daily-input.md`, cancellation/failure tests. |
| FR-006 | PASS | `us2-input-modes.md`, mode integration tests. |
| FR-007 | PASS | `us2-input-modes.md`, mapper/session contract tests. |
| FR-008 | PASS | `us2-input-modes.md`, conversion compiler/vector tests. |
| FR-009 | PARTIAL | Candidate appearance/layout automated tests pass; human appearance acceptance is T100. |
| FR-010 | PARTIAL | Bounds/scaling/full-screen/multi-display logic tests pass; physical multi-display acceptance is T100. |
| FR-011 | PASS | `us3-personalization.md`, ranking/learning tests. |
| FR-012 | PASS | Three-selection promotion, cap and decay tests in `us3-personalization.md`. |
| FR-013 | PASS | User lexicon service/store/settings contracts in `us3-personalization.md`. |
| FR-014 | PASS | Explicit panel boundary and import/export evidence in `us5-import-export.md`. |
| FR-015 | PASS | Bounded atomic text/archive importer tests and `us5-import-export.md`. |
| FR-016 | PASS | Deterministic export/redaction tests and `us5-import-export.md`. |
| FR-017 | PASS | Settings model/window/integration tests and `us4-settings.md`. |
| FR-018 | PASS | Snapshot/restart/migration/lifecycle tests in `us4-settings.md` and `us6-lifecycle-recovery.md`. |
| FR-019 | PASS | Domain deletion tests and `us7-privacy-audit.md`. |
| FR-020 | PASS | Private-mode ranking/write suppression tests and `us3-personalization.md`. |
| FR-021 | PASS | Entitlement/dependency/source/live-process audit in `us7-privacy-audit.md`. |
| FR-022 | PASS | Adversarial diagnostics and export scans in `us7-privacy-audit.md`. |
| FR-023 | PASS | InputMethodKit session boundary and no-monitor source/release audits. |
| FR-024 | PASS | Privacy inventory/UI tests and `Docs/Privacy.md`. |
| FR-025 | PASS | Failure recovery suites and `us6-lifecycle-recovery.md`. |
| FR-026 | PASS | Independent domain quarantine/restore/default tests in `us6-lifecycle-recovery.md`. |
| FR-027 | PARTIAL | Current candidates verify exact arm64; final two-OS matrix is T083/T110. Intel is explicitly excluded. |
| FR-028 | PASS for current development matrix | `<2 ms` report, `<15 MiB` normal footprint and amended 30-day/1,000,000-character stability gate pass; final two-OS release matrix remains under FR-027/SC-013. |
| FR-029 | PARTIAL | Seven-class fixtures pass; actual seven-application final and accessibility matrices are T083/T101/T110. |
| FR-030 | PARTIAL | Automated semantics/focus/layout pass; VoiceOver/Inspector/keyboard/appearance acceptance is T100. |
| FR-031 | PASS | Supported migrations, interruption rollback and future-version preservation in `us6-lifecycle-recovery.md`. |

## Success criteria

| Criterion | Status | Primary evidence / gap |
|---|---|---|
| SC-001 | PASS | Acceptance corpus lookup/commit tests pass 100%. |
| SC-002 | PENDING | Required 30-day skilled-user replacement study has not been executed. |
| SC-003 | PENDING | Required first-user timed study and 90% result have not been executed. |
| SC-004 | PASS for amended automated gate | 1,800/1,800 lookup samples, normal footprint and 30-day/1,000,000-character stability workload pass. |
| SC-005 | PASS | Promotion/disable/clear samples pass 100%. |
| SC-006 | PASS | 10,000-record import completes under 5 seconds with exact counts and atomicity. |
| SC-007 | PASS | Supported domain migration and interrupted migration matrices pass 100%. |
| SC-008 | PASS | Defined corruption/input/client failure tests pass without crash, commit or cross-session loss. |
| SC-009 | PARTIAL | Fixture matrix passes; actual seven-application physical matrix is pending T083/T101/T110. |
| SC-010 | PASS | Current complete privacy audit reports zero network and no sensitive-content artifacts. |
| SC-011 | PASS | 10,000 private/learning-disabled submissions preserve learning generation/content. |
| SC-012 | PENDING | Automated accessibility contracts pass, but required human VoiceOver/FKA/appearance flow is T100/T101. |
| SC-013 | PENDING | Final Apple Silicon macOS 13/current matrix and immutable candidate are T083/T110/T111. |

## Open release blockers

- T083: final signed physical Apple Silicon macOS 13/current compatibility matrix (explicitly deferred).
- T100–T101: human VoiceOver/Accessibility Inspector/FKA acceptance and accessible seven-app rerun.
- The active feature amendment's monthly-volume stability gate passed; it is not an open release blocker.
- SC-002 30-day replacement study and SC-003 first-user timed study.
- T110: complete quickstart on macOS 13 and current supported macOS (explicitly deferred).
- T111: Developer ID timestamp, notarization, staple and Gatekeeper final candidate (explicitly deferred).

This review completes T112 because every FR/SC has an evidence status and every gap blocks release; it does
not declare the product or release complete.
