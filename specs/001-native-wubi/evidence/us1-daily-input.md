# US1 Daily Input Evidence

## Verdict

PASS for the User Story 1 development checkpoint on the current Apple Silicon development system.
This is not a final release verdict; the deferred macOS 13 and Developer ID/notarization gates remain
assigned to the final release phase.

## Environment

- Date: 2026-08-01
- Hardware architecture: Apple Silicon arm64
- macOS: 26.5.2
- Build: Release, Apple Development signed, Hardened Runtime, non-sandboxed
- Installed bundle: `/Library/Input Methods/MacWubi.app`
- Input source ID: `org.macwubi.inputmethod.MacWubi`
- Dictionary: WB86 v1, 136,233 records, build identifier `affd6ad3e043bec9`
- Upstream revision: `152a0d3f3efe40cae216d1e3b338242446848d07`
- Upstream SHA-256: `f833d86b72341fe82e069a425b6625f29ef85f1bc0f34f6fb7975fe514888b5a`

## Automated corpus

`DailyInputIntegrationTests.testDeterministicTenMinuteDailyInputTranscript` executed a deterministic
600-second virtual timeline covering one-to-four-letter codes, abbreviations, full codes, phrases,
second-candidate selection, paging, correction with backspace, cancellation, punctuation pass-through,
and continuous composition. The transcript was 880 UTF-8 bytes with FNV-1a-64 hash
`9ff0a32a41036925`; the test passed without stale final state.

The focused US1 suite executed 16 state-machine, ranking, adapter, and absolute lookup-budget tests with
zero failures. Every measured acceptance lookup completed below the two-millisecond hard assertion.

## Real InputMethodKit clients

After installing and selecting the system-level bundle, the user independently verified both TextEdit and
Notes. In each application the custom candidate window appeared and `wqvb` followed by Space committed
`你好`. This confirms marked-text composition, candidate presentation, selection, commit, session creation,
and cross-client operation through the installed InputMethodKit bundle.

Automated GUI keystroke injection was not used as evidence because macOS denied `osascript` Accessibility
permission. The manual client results above were supplied directly by the user; unified logs were used only
to confirm privacy-safe InputMethodKit action categories and contained no captured input or candidate text.

## Validation commands

```bash
xcodebuild test-without-building -project MacWubi.xcodeproj -scheme MacWubi \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /Users/agol/repos/wb86/.build/tdd-derived CODE_SIGNING_ALLOWED=NO \
  -only-testing:MacWubiTests/InputEngineTests \
  -only-testing:MacWubiTests/CandidateQueryTests \
  -only-testing:MacWubiTests/InputControllerContractTests \
  -only-testing:MacWubiTests/LookupPerformanceTests

xcodebuild test-without-building -project MacWubi.xcodeproj -scheme MacWubi \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /Users/agol/repos/wb86/.build/tdd-derived CODE_SIGNING_ALLOWED=NO \
  -only-testing:MacWubiTests/DailyInputIntegrationTests

MACWUBI_CODE_SIGN_IDENTITY='Apple Development: luoagol@gmail.com (6XRC4PBH7N)' \
  Scripts/build-release.sh
Scripts/verify-release.sh /Users/agol/repos/wb86/.build/xcode/Build/Products/Release/MacWubi.app
xcrun swift Scripts/select-input-source.swift
```

## Remaining release gaps

- macOS 13 physical runtime validation remains deferred to T081/T083/T110.
- Developer ID secure timestamp, notarization, stapling, and Gatekeeper assessment remain deferred to
  T108/T111.
- Seven-application release compatibility, ordinary interaction matrices, monthly-volume resource tests, and all
  later user stories remain open.
