# T045 User Story 4 Offline Pinyin Mixed-Input Evidence

- Date: 2026-08-02 (Asia/Shanghai)
- Worktree: `/Users/agol/repos/wb86/.worktrees/002-settings-experience`
- Branch: `codex/002-settings-experience`
- Validated source commit: `acd33590a2191b64ca4d2cc54c276d8f96299ac3`
- Hardware: Apple Silicon MacBook Air, `arm64`
- macOS: 26.5.2 (25F84)
- Xcode: 26.6 (17F113), Swift 5 language mode

All input strings and candidates used by these checks are deterministic test fixtures. No network
connection, real user input, committed text, application identity, document context, or external file
path was collected or logged.

## Dictionary provenance and reproducibility

| Item | Verified value |
|---|---|
| Upstream repository | `rime/rime-pinyin-simp` |
| Pinned revision | `0c6861ef7420ee780270ca6d993d18d4101049d0` |
| License | Apache-2.0; pinned LICENSE and AUTHORS are stored with the source |
| Upstream YAML SHA-256 | `e341598343a0f0f2035bb1aafc34a7f3bb7887deeecb3f60796262aaa2983e6b` |
| Generated MWPY SHA-256 | `0841a66e41e3768739b8d6370aaee14670d1c464a6c262c698f83488d12f411b` |
| Generated MWPY size | 2,856,609 bytes |
| Format / schema | MWPY / 1 |
| Key / candidate count | 38,999 / 60,742 |
| Per-key candidate limit | 64 |
| WB86 build identifier | `affd6ad3e043bec9` |
| Image checksum (FNV-1a 64) | `264a8936723d416b` |

The pure-Swift compiler was run twice from the pinned source in T038. The generated files compared
byte-for-byte equal. Compilation normalizes text to NFC, removes Pinyin syllable spaces, converts to
the product's simplified form before deduplication, applies deterministic weight/UTF-8 ordering, and
caps each key at 64 candidates. The source is a build-time input only; the signed application bundles
the generated MWPY image and its provenance manifest.

The 2.72 MiB mapped image is larger than the early design estimate. This is recorded rather than
hidden or treated as resident memory: T055 performs the required Release RSS measurement and may
change the representation if the complete input method does not remain below 15 MB.

## Offline mixed-input matrix

`Scripts/test.sh` exercised the following automated paths as part of the full repository suite:

| Requirement | Automated coverage and result |
|---|---|
| Shared, offline resource | `DailyInputIntegrationTests` loads one read-only MWPY mapping through `PersonalizationCoordinator`, shares it across sessions, and makes no network request. PASS. |
| Wubi-first mixed ranking | `CandidateQueryTests` bounds each source tier at 64, keeps user/base Wubi before Pinyin, and applies learning only within the matching typed tier. PASS. |
| Duplicate正文 and scripts | `CandidateQueryTests` converts each candidate to the selected script before stable display-text deduplication, including learned traditional display text. PASS. |
| Long viable Pinyin | `InputEngineTests` keeps valid 1...32 byte prefixes such as `shang` composing instead of applying the Wubi fifth-code policy. PASS. |
| Compatibility when disabled | `InputEngineTests` preserves the legacy Wubi-only four/five-code behavior when mixed input is off. PASS. |
| Optional WB86 hints | `CandidateAccessibilityTests` verifies hint visibility, width-first hint removal, font/layout changes, and正文-first accessibility output. PASS. |
| Selection learning | `DailyInputIntegrationTests` records a typed Pinyin learning key only when the frozen session policy permits it. PASS. |
| Paging and bounds | `CandidateQueryTests` verifies prefix/exact lookup, bounded page decoding, stable pagination, and the maximum candidate count. PASS. |

The adapter queries by the entire viable sequence, so a Pinyin continuation is neither truncated nor
replayed as a synthetic event. Candidate accessibility values expose正文 before the optional Wubi
hint, and layout pressure removes the hint before truncating正文.

## Corruption and degradation results

`PinyinDictionaryFormatTests`, `InputEngineTests`, and `DailyInputIntegrationTests` verify these
failure paths:

- Missing or invalid MWPY data disables only the Pinyin index. The already validated WB86 index stays
  available and Wubi input continues without a network or dynamic-resource fallback.
- Truncation, offset/count overflow, checksum mismatch, out-of-order keys, invalid UTF-8, invalid WB86
  references, or a mismatched WB86 build identifier rejects the whole MWPY image before publication.
- Loader errors collapse to structure-only diagnostics. They do not include dictionary text, typed
  sequences, candidates, or filesystem paths.
- A query failure atomically clears stale composition/candidates and does not commit guessed text or
  contaminate another session.
- Unknown, overlong, or invalid sequences remain bounded; no path loops, incrementally allocates an
  unbounded candidate list, or opens a network connection.

## Full verification

Command:

```sh
Scripts/test.sh
```

Result: PASS.

- XCTest result: `.build/tests/Logs/Test/Test-MacWubi-2026.08.02_15-28-58-+0800.xcresult`
- XCTest summary: 194 total, 194 passed, 0 failed, 0 skipped.
- Test destination: MacBook Air, `arm64`, macOS 26.5.2 (25F84).
- Release dictionary compiler verification: PASS for `arm64`.
- Deterministic lexicon fixture verification: PASS.
- Bundled application MWPY resource compared byte-for-byte equal with
  `Sources/Resources/pinyin-simp.bin`.

## Constitution impact

| Gate | Result | US4 evidence |
|---|---|---|
| Apple Silicon native | PASS | Tests and dictionary compiler used the Xcode project and an `arm64` destination; no Intel/Rosetta implementation was added. |
| Pure Swift and dependencies | PASS | Compiler, mapped loader, index, merge/ranking, state machine, and tests are Swift; no package or foreign runtime was added. |
| InputMethodKit boundary | PASS | Dictionary and ranking logic remain in Core; the adapter only presents Core results and client actions. |
| Failure safety and recovery | PASS | Invalid resources are rejected before publication; Pinyin failure leaves validated Wubi available and never guesses a commit. |
| Local-data privacy | PASS | The resource is bundled and read-only, lookup is offline, learning honors private/disabled policy, and diagnostics contain no content or path. |
| Performance | DEFERRED TO DEDICATED GATES | Lookup remains bounded, but every-sample latency, Release RSS, and eight-hour growth are measured by T054-T056. |

The build still emits the previously recorded Swift 6 actor-isolation migration warning for
`PrivacySessionControlling`. The project compiles in Swift 5 mode and all tests pass; the warning did
not change mixed-input behavior or resource failure isolation.
