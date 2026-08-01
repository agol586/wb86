# US2 Input Modes Evidence

## Verdict

PASS for the User Story 2 development checkpoint. Automated, installed-bundle, and real-client keyboard
checks all passed. This is not a final release verdict; the deferred macOS 13 and Developer ID/notarization
gates remain assigned to the final release phase.

## Environment

- Date: 2026-08-01
- Hardware architecture: Apple Silicon arm64
- macOS: 26.5.2
- Build: Release, Apple Development signed, Hardened Runtime, non-sandboxed
- Installed bundle: `/Library/Input Methods/MacWubi.app`
- Input source ID: `org.macwubi.inputmethod.MacWubi`
- Script resource: MWSC v1, 53,256 records, FNV-1a-64 `87f109dfee9b7849`
- OpenCC data revision: `2f569603954f1cddfdef7b648e71e1aa0d1f47a3`

## Automated acceptance

`ModeInputIntegrationTests.testDocumentedMixedLanguageModeFlowProducesExpectedTranscript` exercised
Chinese candidate commits, direct-English pass-through, half/full-width digits, paired Chinese quotes,
Chinese punctuation, and simplified/traditional candidate output. It produced exactly
`你好，macwubi42“测试”？１２中國`, ended idle, and retained the expected independent mode fields.

The focused mode/conversion suites executed 14 tests with zero failures. They additionally covered exact
shortcut interception versus system shortcut pass-through, cancellation of active composition before a
mode change, menu check states, the non-input-bearing indicator label, corrupt resource rejection, and
longest-phrase conversion. The full local verification entry point executed 57 tests with zero failures.

Recompiling the OpenCC inputs at the pinned revision produced byte-identical `script-conversion.bin` and
manifest files. Runtime lookup retains the validated read-only image and performs bounded binary searches;
it does not retain a 53,256-entry Swift object dictionary.

## Installed-bundle checks

The new release executable SHA-256 is
`5fc702dd1ae201eee0f1481b10bb03b368ee64a5ce8462b897ec3ce7b1b5463`; the build and installed copies
match. Strict code-signature validation passed, and TIS enumerated exactly one selected source with ID
`org.macwubi.inputmethod.MacWubi`.

## Real-client keyboard flow

The user independently completed the documented TextEdit flow against the installed bundle and confirmed
the expected transcript `你好，macwubi42“测试”？１２中國`. The same observation confirmed the visible
mode indicator, its four mode-menu actions, all four documented mode transitions, and that
`Control-Space` remained available to macOS for system input-source switching.

Automated GUI keystroke injection was not used as evidence because the development terminal did not have
Accessibility authorization. The manual result above was supplied directly by the user and contains only
the fixed acceptance transcript, not private document content or a production input timeline.

## Validation commands

```bash
Scripts/test.sh
Scripts/compile-script-conversion.sh
MACWUBI_CODE_SIGN_IDENTITY='Apple Development: luoagol@gmail.com (6XRC4PBH7N)' Scripts/build-release.sh
Scripts/verify-release.sh /Users/agol/repos/wb86/.build/xcode/Build/Products/Release/MacWubi.app
xcrun swift Scripts/select-input-source.swift
```

## Remaining release gaps

- macOS 13 physical runtime validation remains deferred to T081/T083/T110.
- Developer ID secure timestamp, notarization, stapling, and Gatekeeper assessment remain deferred to
  T108/T111.
