# T002 Baseline Evidence

- Date: 2026-08-02 (Asia/Shanghai)
- Worktree: `/Users/agol/repos/wb86/.worktrees/002-settings-experience`
- Branch: `codex/002-settings-experience`
- Baseline commit: `f95ee54bf6ba076d0bd7e5f5b40a45dbbd826abf`
- Hardware architecture: `arm64`
- macOS: 26.5.2 (25F84)
- Xcode: 26.6 (17F113)
- Command: `Scripts/test.sh`
- Result: PASS; `MacWubiTests` executed 108 tests with zero failures, release-contract tests passed,
  the arm64 dictionary compiler Release build succeeded, and deterministic lexicon fixture verification passed.
- Sandbox note: the first sandboxed invocation could not contact `testmanagerd`; the same command was rerun with
  the macOS test-runner permission and passed. This was an execution-environment restriction, not a product failure.
- `wb86.bin` SHA-256: `45e8132d0d0cdd9f2662a6821dd4b886cb6f7272f7e41000175abb8c6a099ab0`
- `script-conversion.bin` SHA-256: `462e134aed21f7bf7209c2c442b51c48b1d33967bb36006b4e49869bab2d3552`

No production source, resource, entitlement, signing rule, persistence snapshot, or installed input method was
changed by this baseline task.
