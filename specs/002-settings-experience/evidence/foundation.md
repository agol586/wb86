# T010 Foundation Evidence

- Date: 2026-08-02 (Asia/Shanghai)
- Worktree: `/Users/agol/repos/wb86/.worktrees/002-settings-experience`
- Branch: `codex/002-settings-experience`
- Validated commit: `9175ffbc93c02bc4675e3d2fa72dccad9c37f742`
- Hardware: Apple Silicon `arm64` MacBook Air
- macOS: 26.5.2 (25F84)
- Xcode: 26.6 (17F113)
- Command: `Scripts/test.sh`
- Result: PASS. The XCTest result contains 123 tests, 123 passed, 0 failed, 0 skipped.
  Release-contract tests passed, the Release dictionary compiler built for arm64, and deterministic
  lexicon fixture verification passed.
- XCTest result:
  `.build/tests/Logs/Test/Test-MacWubi-2026.08.02_13-13-25-+0800.xcresult`
- Result inspection command:
  `xcrun xcresulttool get test-results summary --path <xcresult>`
- `wb86.bin` SHA-256:
  `45e8132d0d0cdd9f2662a6821dd4b886cb6f7272f7e41000175abb8c6a099ab0`
- `script-conversion.bin` SHA-256:
  `462e134aed21f7bf7209c2c442b51c48b1d33967bb36006b4e49869bab2d3552`

## Constitution impact

| Gate | Result | Foundation evidence |
|---|---|---|
| Apple Silicon native | PASS | All commands used the Xcode project on arm64; no Intel or Rosetta path was introduced. |
| Pure Swift and dependencies | PASS | Composition, action batches, snapshots and ranking policy are Swift; no package, C/C++ library or runtime dependency was added. |
| InputMethodKit and signing boundary | PASS | Core remains free of AppKit/InputMethodKit. Adapter work stays under `Sources/InputMethod`; entitlements and distribution policy are unchanged. |
| Failure safety and recovery | PASS | Failed client batches stop in order and reset atomically; failed settings writes do not publish; stale candidates and marked text are cleared. |
| Local-data privacy | PASS | Settings remain in private versioned snapshots; no network, monitor, event tap, text logging or new persisted input content was added. |
| Performance and release gates | PASS WITH LATER MEASUREMENT | Policies and composition values are bounded and snapshots are immutable. Full `<2 ms`, `<15 MB`, and monthly-volume Release measurements remain assigned to T054-T056 and subsequently passed. |

The foundational layer now supplies schema-v2 settings, structured key bindings, generalized composition
and candidate identities, ordered client actions, validated settings generations, independent per-session
active/pending snapshots, and explicit frozen ranking policies. No release-signing or installation state was
changed by T003-T010.
