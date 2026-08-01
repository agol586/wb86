# US6 Lifecycle and Recovery Evidence

Date: 2026-08-01 (Asia/Shanghai)

Environment: Apple M3, arm64; macOS 26.5.2 (25F84); Xcode 26.6 (17F113); deployment target
`arm64-apple-macos13.0`.

## Automated scenarios

- Migrated Settings, UserLexicon and Learning through explicit schema 1 → 2 → 3 steps. Each step
  published one increasing generation; a repeated run made no write.
- Preserved an unknown schema 99 current snapshot byte-for-byte without downgrade.
- Injected interruption after previous replacement and verified current rolled back to the original
  schema, generation and payload.
- Corrupted each mutable domain independently. The coordinator quarantined only that current file,
  restored its validated previous snapshot and left the other current files byte-identical.
- With no validated previous snapshot, selected a safe default and reset active composition. A base
  dictionary/query failure returned idle and the next valid input composed normally.
- Installed and upgraded two distinct fixture bundles through the same staging/re-verify/replace
  algorithm used for `/Library/Input Methods`; no staging or backup remained after success.
- Uninstalled once with personalization preserved, then with explicit `--delete-data`; deletion was
  restricted to exact validated temporary targets during automated testing.
- Exercised seven adapter fixtures and focus/session churn; every application class used the same
  marked-text/commit contract and no session cross-committed.

## Validation commands

```sh
bash -n Scripts/install.sh Scripts/upgrade.sh Scripts/uninstall.sh Scripts/verify-release.sh
xcodebuild test -quiet -project MacWubi.xcodeproj -scheme MacWubi \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/us6-tdd \
  -only-testing:MacWubiTests/CrossApplicationCompatibilityTests \
  -only-testing:MacWubiTests/DomainRecoveryTests \
  -only-testing:MacWubiTests/DataMigratorTests \
  -only-testing:MacWubiReleaseTests/InstallationContractTests CODE_SIGNING_ALLOWED=NO
```

Result: PASS.

The final physical macOS 13/current matrix, Developer ID timestamp, notarization, staple and
Gatekeeper verdict remain explicitly deferred release gates; this evidence does not claim them.
