# US4 Settings Verification Evidence

Date: 2026-08-01 (Asia/Shanghai)

## Environment

- Hardware: Apple M3, arm64
- macOS: 26.5.2 (25F84)
- Xcode: 26.6 (17F113)
- Product target: arm64-apple-macos13.0

## Independent flow

`SettingsIntegrationTests.testEverySettingPersistsAppliesAndRestoresWithoutPersonalizationLoss`
executes the complete isolated flow against a temporary Application Support root:

1. Creates independently versioned UserLexicon and Learning snapshots.
2. Changes every persisted setting category: page size 9, horizontal layout, font scale 1.6,
   bracket paging keys, disabled mode shortcut, four-code auto-commit, default direct-English,
   English punctuation, full width, Traditional output, and disabled learning.
3. Confirms immediate application to idle sessions and global candidate/learning policy.
4. Reopens `SettingsStore` and confirms the full value survives process-style restart.
5. Confirms the privacy-safe preview contains only fixed example placeholders.
6. Restores defaults and byte-compares UserLexicon and Learning snapshots with their originals.

Additional contract coverage verifies deferred application while any session is composing, all three
paging-key sets, disabled mode shortcuts, automatic first-candidate commit at four codes, 5...9 page
size bounds, 0.8...2.0 font bounds, keyboard focus, accessibility labels, six setting groups, explicit
apply/restore, and domain-specific destructive confirmation text.

## Commands and results

```sh
xcodebuild test -quiet -project MacWubi.xcodeproj -scheme MacWubi \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/us4-tdd \
  -only-testing:MacWubiTests/SettingsWindowTests \
  -only-testing:MacWubiTests/SettingsIntegrationTests \
  -only-testing:MacWubiTests/SettingsStoreTests \
  -only-testing:MacWubiTests/InputModeTests \
  -only-testing:MacWubiTests/InputEngineTests CODE_SIGNING_ALLOWED=NO
```

Result: PASS.

```sh
Scripts/test.sh
```

Result: PASS — 80 product tests and 4 release-contract tests, zero failures; deterministic dictionary
compiler verification also passed.

## Privacy and recovery verdict

- Settings writes use only the Settings snapshot domain with private directory/file permissions.
- Restore Defaults does not mutate UserLexicon or Learning.
- Preview content is fixed and contains no user code, candidate, committed text, path, application, or
  timeline data.
- No dependency, network capability, telemetry, global monitor, sandbox exception, or Intel artifact
  was introduced.
