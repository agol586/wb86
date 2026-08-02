# T017 User Story 1 Common Settings Evidence

- Date: 2026-08-02 (Asia/Shanghai)
- Worktree: `/Users/agol/repos/wb86/.worktrees/002-settings-experience`
- Branch: `codex/002-settings-experience`
- Validated commit: `55d7a407506cf4fdaa6264f0d276b4f5be808700`
- Hardware: Apple Silicon `arm64` MacBook Air
- macOS: 26.5.2 (25F84)
- Xcode: 26.6 (17F113)

## Targeted US1 verification

Command:

```sh
xcodebuild test -quiet -project MacWubi.xcodeproj -scheme MacWubi \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:MacWubiTests/TextConversionTests \
  -only-testing:MacWubiTests/InputEngineTests \
  -only-testing:MacWubiTests/SettingsWindowTests \
  -only-testing:MacWubiTests/SettingsAccessibilityTests \
  -only-testing:MacWubiTests/SettingsIntegrationTests \
  -only-testing:MacWubiTests/InputControllerContractTests
```

Result: PASS, with no test failure.

Verified behavior:

- New-install defaults populate the saved and draft settings model, and Cancel performs no write.
- Punctuation mapping runs before remaining ASCII full-width conversion across script modes.
- An idle session adopts a persisted generation immediately; a composing session keeps its frozen
  semantic generation until its own client action reaches idle.
- Candidate layout and font scale refresh immediately without resetting a session's temporary mode.
- Persisted initial mode affects new and reactivated sessions, but an ordinary save does not overwrite
  a current session's temporary language, script, punctuation, or width mode.
- Two composing clients finish independently: the first can adopt and reactivate on the new generation
  while the second remains on its old active generation with the latest pending snapshot.
- Invalid client senders do not fall back to a stale proxy, and deactivation publishes the idle boundary
  only after marked text and candidates have been cleared.

## Full repository verification

- Command: `Scripts/test.sh`
- Result: PASS.
- XCTest result: `.build/tests/Logs/Test/Test-MacWubi-2026.08.02_13-29-49-+0800.xcresult`
- XCTest summary: 130 total, 130 passed, 0 failed, 0 skipped.
- Release dictionary compiler: PASS for `arm64`.
- Deterministic lexicon fixture verification: PASS.
- `wb86.bin` SHA-256:
  `45e8132d0d0cdd9f2662a6821dd4b886cb6f7272f7e41000175abb8c6a099ab0`
- `script-conversion.bin` SHA-256:
  `462e134aed21f7bf7209c2c442b51c48b1d33967bb36006b4e49869bab2d3552`

## Constitution impact

| Gate | Result | US1 evidence |
|---|---|---|
| Apple Silicon native | PASS | Targeted and full tests used the Xcode project with an `arm64` destination; no Intel or Rosetta path was added. |
| Pure Swift and dependencies | PASS | Settings, mode conversion, immutable generations and lifecycle ordering are Swift; no dependency was added. |
| InputMethodKit and signing boundary | PASS | Core remains free of AppKit/InputMethodKit; lifecycle integration remains in `Sources/InputMethod`, and release-contract signing tests pass. |
| Failure safety and recovery | PASS | Invalid settings preserve the last valid snapshot; stale client proxies are rejected; deactivation clears composition before publishing idle. |
| Local-data privacy | PASS | Settings use the existing private snapshot store; no network, global monitor, telemetry, text logging or new user-content persistence was introduced. |
| Performance and release gates | PASS WITH LATER MEASUREMENT | Full regression includes the existing lookup budget test. Feature-wide memory, latency and monthly-volume evidence remains assigned to T054-T056 and subsequently passed. |

The build continues to emit an existing Swift 6 actor-isolation migration warning for
`PrivacySessionControlling`; the project compiles in Swift 5 mode and all tests pass. The warning is not
caused by a new runtime dependency or an InputMethodKit boundary violation and remains a later static
quality cleanup item.
