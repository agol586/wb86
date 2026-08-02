# T052 User Story 5 Persistence and Recovery Evidence

- Date: 2026-08-02 (Asia/Shanghai)
- Worktree: `/Users/agol/repos/wb86/.worktrees/002-settings-experience`
- Branch: `codex/002-settings-experience`
- Validated source commit: `9fc1c642068e2bda1598cd9e5ecfb110a233d632`
- Hardware: Apple Silicon MacBook Air, `arm64`
- macOS: 26.5.2 (25F84)
- Xcode: 26.6 (17F113), Swift 5 language mode

All persistence fixtures use synthetic Settings, UserLexicon, and Learning records. No real input,
candidate正文, application identity, document context, or user filesystem path was logged.

## Schema and startup matrix

| Startup state | Automated result |
|---|---|
| No Settings snapshot | New-install v2 defaults are used in memory; no file is written merely by loading. PASS. |
| Valid Settings v2 current | Every field and generation reload exactly after input-method and simulated system restart. PASS. |
| Valid Settings v1 current | A strict private v1 DTO maps every old field, maps `learningEnabled` to automatic frequency, and applies conservative values only to new v2 fields. The commit advances generation once. PASS. |
| Reopen after v1 migration | The v2 snapshot and bytes remain unchanged; migration reports current and does not advance generation again. PASS. |
| Unknown future current plus supported previous | Future current bytes remain untouched, previous does not replace it, runtime uses safe defaults, and Save/Restore are rejected in an accessible read-only state. PASS. |
| Corrupt current plus valid previous | Startup validates payload as well as the envelope, restores the complete previous snapshot, and publishes its exact settings/generation. PASS. |
| Corrupt current and corrupt previous | Runtime uses safe defaults, enters read-only recovery state, and refuses writes that could destroy the evidence. Other domains remain unchanged. PASS. |
| Valid v1 but migration commit failure | The v1 current is restored byte-for-byte, runtime uses read-only safe defaults, no v2 generation is published, and other domains remain unchanged. PASS. |

Strict v1 rejection covers unknown or missing required fields, invalid enum values, invalid nested enum
shapes, and appearance bounds. A failed direct migration leaves both the visible schema and generation
unchanged. The v1 four-code flag maps to the corrected “commit only when exactly one candidate exists”
policy; it does not retain the former multi-candidate error.

## Commit interruption matrix

Both `SnapshotWriterTests` and `DataMigratorTests` inject an error at every exposed transaction
boundary, reconstruct a fresh writer to model process restart, and load the last complete snapshot:

| Injection boundary | Recovery result |
|---|---|
| Before staging write | Original current remains current; stale staging is removed at recovery. PASS. |
| After staging write | Unpublished staging is removed; original current remains visible. PASS. |
| After staged envelope/payload validation | Staging is not published; original current remains visible. PASS. |
| After old current is renamed to previous | The previous copy restores current with `0600` permissions. PASS. |
| After staged snapshot is renamed to current | The injected error rolls back the new current and restores the previous complete snapshot. PASS. |

Every boundary was exercised for a normal snapshot replacement and for Settings v1→v2 migration.
No interrupted path published the proposed generation.

## Save, feedback, and Restore Defaults

- Full-draft validation rejects page-size, font-scale, duplicate/range-overlapping/reserved bindings,
  unsupported legacy bindings, and unavailable keyboard layouts before persistence.
- Field errors select the relevant settings tab, focus the exact control, and issue an accessibility
  announcement. Generic I/O/readback failures keep the last valid saved baseline.
- Future and failed-recovery stores expose a visible, selectable “设置状态” message, focus that status,
  disable modifying controls, and reject Save/Restore.
- Cancel discards the draft and performs zero writes.
- Restore requires explicit confirmation. Success is one normal atomic Settings save; failure leaves
  both the store's published snapshot and registered sessions unchanged.
- Restore changes only Settings. It does not disable private mode or delete/roll back UserLexicon,
  Learning, or the bundled dictionaries.

## Cross-domain checksum comparison

The full-suite `testRestoreConfirmationCancelFailureAndSuccessAreSettingsOnly` fixture captured each
domain before Cancel, injected failure, and successful Restore. UserLexicon and Learning were asserted
byte-for-byte and generation-for-generation equal after every path.

| Domain | Generation before / after | SHA-256 before | SHA-256 after | Result |
|---|---:|---|---|---|
| UserLexicon | 1 / 1 | `0ffb49d51a5a480db6e00588a650c2ea26ced904f193e3ff0056053f2a6cf5f9` | `0ffb49d51a5a480db6e00588a650c2ea26ced904f193e3ff0056053f2a6cf5f9` | unchanged |
| Learning | 1 / 1 | `61cffa7f51b82791bd8aaa2a3f963d567f6b110e322972c7c9c74554971fbf1a` | `61cffa7f51b82791bd8aaa2a3f963d567f6b110e322972c7c9c74554971fbf1a` | unchanged |

The same fixture verified Settings remained byte-identical across Cancel and injected failure, then
changed from generation 1 to generation 2 only after confirmed successful Restore.

## Full verification

Command:

```sh
Scripts/test.sh
```

Result: PASS.

- XCTest result: `.build/tests/Logs/Test/Test-MacWubi-2026.08.02_15-46-52-+0800.xcresult`
- XCTest summary: 207 total, 207 passed, 0 failed, 0 skipped.
- Main product suites: 200 passed.
- Release contract suites: 7 passed.
- Test destination: MacBook Air, `arm64`, macOS 26.5.2 (25F84).
- Release dictionary compiler: PASS for `arm64`.
- Deterministic lexicon fixture verification: PASS.

## Constitution impact

| Gate | Result | US5 evidence |
|---|---|---|
| Apple Silicon native | PASS | All tests and compiler verification used the Xcode project on an `arm64` destination; no Intel/Rosetta path was added. |
| Pure Swift and dependencies | PASS | DTO decoding, migration, snapshots, recovery, settings coordination, and tests are Swift with Foundation/AppKit only at existing boundaries; no dependency was added. |
| InputMethodKit boundary | PASS | Persistence stays outside Core and sessions receive immutable settings generations through the adapter coordinator. |
| Failure safety and recovery | PASS | Invalid/future/interrupted states never publish partial semantics, never guess input, and preserve a complete recoverable or read-only safe state. |
| Local-data privacy | PASS | Domains remain isolated, Settings restore cannot delete personalization, files retain private permissions, and diagnostics expose no payload or path. |
| Performance | NOT CHANGED | Startup work is bounded by the 16 MiB snapshot envelope. Dedicated latency, Release RSS, and stress gates remain T054-T056. |

The test build continues to emit the previously recorded Swift 6 actor-isolation migration warning
for `PrivacySessionControlling`. Swift 5 compilation and all US5 assertions pass; the warning does not
alter snapshot atomicity or recovery ordering.
