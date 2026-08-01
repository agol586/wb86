# US5 Import/Export Verification Evidence

Date: 2026-08-01 (Asia/Shanghai)

## Environment

- Hardware: Apple M3, arm64
- macOS: 26.5.2 (25F84)
- Xcode: 26.6 (17F113)
- Product target: arm64-apple-macos13.0

## Independent flow and verdict

- Parsed a bounded 10,000-record UTF-8 v1 fixture, validated every line, created one merge plan,
  and published exactly one UserLexicon generation in less than the five-second hard assertion.
- Rejected invalid UTF-8, oversized files/lines, invalid codes/ranks/text, unknown text/archive
  versions, invalid archive flags/lengths, corrupt payloads, and checksum mismatches.
- Merged duplicate `(code, text)` values deterministically, keeping the highest user priority.
- Exported deterministic UTF-8 and versioned archive forms. Archive payloads have independent
  UserLexicon/Learning lengths and checksums; Learning is omitted unless explicitly selected.
- Imported the archive into a clean profile and recovered equivalent UserLexicon and Learning data.
- Injected interruption after staged snapshot validation; the prior current snapshot and in-memory
  generation remained unchanged.
- Cancelled file selection created no scoped access. Selected access was released exactly once.
  Failed export validation preserved the existing destination bytes.
- Settings exposes explicit system open/save panel actions. Results contain counts and fixed error
  categories only, with no path, entry body, application, document, session, or timeline history.

## Commands and results

```sh
xcodebuild test -quiet -project MacWubi.xcodeproj -scheme MacWubi \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/us5-tdd \
  -only-testing:MacWubiTests/LexiconImporterTests \
  -only-testing:MacWubiTests/LexiconExporterTests \
  -only-testing:MacWubiTests/FilePanelContractTests \
  -only-testing:MacWubiTests/ImportPerformanceTests CODE_SIGNING_ALLOWED=NO
```

Result: PASS.

```sh
Scripts/test.sh
```

Result: PASS — 88 product tests and 4 release-contract tests, zero failures; deterministic dictionary
compiler verification passed.

## Constitution impact

- Architecture remains exact arm64 with macOS 13 deployment target.
- Implementation is Swift plus Foundation/AppKit system panels; no package or foreign runtime added.
- External-file authority is one-shot and user-driven; no bookmark or path is persisted.
- All mutable product data remains under the private Application Support root and uses staged,
  validated snapshot replacement.
- No network entitlement, connection, telemetry, global monitor, user-text logging, or Intel support
  was introduced.
