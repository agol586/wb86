# T034 User Story 3 Auto-Commit and Learning Evidence

- Date: 2026-08-02 (Asia/Shanghai)
- Worktree: `/Users/agol/repos/wb86/.worktrees/002-settings-experience`
- Branch: `codex/002-settings-experience`
- Validated source commit: `8bc73e5fbfbe5cb71f0b276f9586cc5eb3980b33`
- Hardware: Apple M3 MacBook Air, 24 GB, `arm64`
- macOS: 26.5.2 (25F84)
- Xcode: 26.6 (17F113), Swift 5 language mode

No real user input, committed text, application identity, or document context was collected. All
results below come from deterministic synthetic fixtures.

## Targeted US3 matrix

Command:

```sh
xcodebuild test -quiet -project MacWubi.xcodeproj -scheme MacWubi \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/tests \
  -only-testing:MacWubiTests/InputEngineTests \
  -only-testing:MacWubiTests/InputControllerContractTests \
  -only-testing:MacWubiTests/LearningStoreTests \
  -only-testing:MacWubiTests/DataMigratorTests \
  -only-testing:MacWubiTests/CandidateQueryTests \
  -only-testing:MacWubiTests/PrivateModeTests \
  -only-testing:MacWubiTests/SettingsWindowTests \
  -only-testing:MacWubiTests/SettingsIntegrationTests \
  -only-testing:MacWubiTests/PersonalizationIntegrationTests
```

Result: PASS, 61 passed, 0 failed, 0 skipped.

Result bundle:
`.build/tests/Logs/Test/Test-MacWubi-2026.08.02_14-27-20-+0800.xcresult`

### Commit count and next-key matrix

| Path | Fixture condition | Commit count for event | Client action/state result |
|---|---|---:|---|
| Four-code | zero candidates | 0 | Keep the complete marked code; no learning delta. |
| Four-code | one current candidate | 1 | Commit once, hide candidates, and become idle. |
| Four-code | multiple candidates | 0 | Keep the complete marked code; no learning delta. |
| Four-code | one visible item but total count greater than one | 0 | Reject the stale partial-page uniqueness claim. |
| Fifth-code | stable current first candidate | 1 | `commit(first) -> mark(next-key)`; the next key begins a new composition. |
| Fifth-code | no current candidate | 0 | `mark(next-key)` only; never commit empty text. |
| Fifth-code | first candidate changed before commit | 0 | `mark(next-key)` only; never commit either stale value. |
| Both auto-commit switches | unique candidate commits at four | 1 at four, 0 at next key | The next event only marks its key; the old candidate is not committed twice. |

Every tested input event emitted at most one commit. When the fifth-code policy consumed a continuation
key, the same atomic result established that key as the next marked composition; no adapter replay or
synthetic key injection was used.

### Adapter order and failure isolation

- The successful fifth-code batch called the client exactly in
  `commit(first) -> setMarkedText(next-key)` order.
- A failure on action 1 attempted recovery clear only. A failure on action 2 preserved the already
  completed first commit, stopped the remaining batch, then cleared stale marked text and candidates.
- Neither failure path published a learning write.
- A settings snapshot staged reentrantly after action 1 remained pending through action 2. Both client
  callbacks observed the old generation; the new generation became active only after the full batch
  reached the idle boundary.

### Learning read/write isolation

| Policy | Existing score affects order | Selection write | Verified invariant |
|---|---:|---:|---|
| Automatic frequency on, normal mode, learning allowed | Yes, exact typed key and same source tier only | Yes | A score cannot cross code, query kind, or source tier. |
| Automatic frequency off in frozen snapshot | No | No | Ranking remains deterministic and the in-memory learning snapshot is unchanged. |
| Private mode on | No | No | Existing scores are excluded and the learning snapshot is unchanged. |
| Global learning disabled | No | No | Existing scores are excluded and the learning snapshot is unchanged. |

Learning schema v2 also passed typed Wubi/Pinyin key round trips, v1 wrapping migration, and
cross-domain isolation: migrating or writing Learning did not alter Settings or UserLexicon snapshots.

### Settings persistence and safe delay

The four-code, fifth-code, and automatic-frequency checkboxes independently updated the draft v2
settings model and their accessibility values. Saving preserved all three values across a fresh
`SettingsStore` and settings-window construction. A composing session retained its old semantic
snapshot while the new snapshot was pending, then atomically adopted all three values after Cancel
reached idle.

## Full repository verification

- Command: `Scripts/test.sh`
- Result: PASS.
- XCTest result: `.build/tests/Logs/Test/Test-MacWubi-2026.08.02_14-27-45-+0800.xcresult`
- XCTest summary: 164 total, 164 passed, 0 failed, 0 skipped.
- Release dictionary compiler: PASS for `arm64`.
- Deterministic lexicon fixture verification: PASS.
- `wb86.bin` SHA-256:
  `45e8132d0d0cdd9f2662a6821dd4b886cb6f7272f7e41000175abb8c6a099ab0`
- `script-conversion.bin` SHA-256:
  `462e134aed21f7bf7209c2c442b51c48b1d33967bb36006b4e49869bab2d3552`

## Constitution impact

| Gate | Result | US3 evidence |
|---|---|---|
| Apple Silicon native | PASS | Targeted and full tests used the Xcode project with an `arm64` destination; no Intel or Rosetta path exists. |
| Pure Swift and dependencies | PASS | State, ranking, typed learning persistence, and tests are Swift; no dependency was added. |
| InputMethodKit boundary | PASS | Core emits value-semantic ordered actions; only the adapter calls AppKit/InputMethodKit clients. |
| Failure safety and recovery | PASS | Stale/empty candidates do not commit, each event commits at most once, and action failure clears stale state without continuing the batch. |
| Local-data privacy | PASS | Disabled/private/frozen-off policies neither read scores into ranking nor write Learning; no network, telemetry, or content logging was added. |
| Performance | PASS WITH LATER FEATURE-WIDE MEASUREMENT | The full suite includes the existing lookup budget test. Dedicated memory, latency, and long-stress evidence remains assigned to T054-T056. |

The build continues to emit the pre-existing Swift 6 actor-isolation migration warning for
`PrivacySessionControlling`. The project compiles in Swift 5 mode and all tests pass; this warning did
not alter US3 action ordering or snapshot isolation.
