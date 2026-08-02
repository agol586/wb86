# Complete Automated Test Evidence (Historical Run)

> Specialized accessibility claims in this historical run were superseded on 2026-08-02. Feature 002
> T061–T063 removed that code and replaced it with ordinary interaction regression tests plus an explicit
> unsupported-assistive-technology source boundary. See the feature 002 US6 evidence for current results.

Status: **PASS**

Final run: 2026-08-02 on Apple M3 (`Mac15,12`), arm64, macOS 26.5.2 (25F84), Xcode 26.6
(17F113).

```bash
Scripts/test.sh
```

Result: exit 0. The final XCTest result bundle reports 115/115 passed, 0 failed, 0 skipped, on arm64.
The command then built the pure-Swift dictionary compiler in Release,
validated the fixture format and known vectors, compiled the fixture, and ended with
`test verification passed: XCTest suites and deterministic lexicon fixtures`.

This final run includes the remediation for the physical VoiceOver failure: explicit candidate list/button
semantics, accessible label/value/selection state, executable accessibility press actions, and layout/focus
notifications. The result bundle is
`.build/tests/Logs/Test/Test-MacWubi-2026.08.02_00-46-33-+0800.xcresult`.

The latest run additionally verifies a flattened top-level candidate hierarchy and the complete candidate
summary used by the deduplicated high-priority VoiceOver announcement.

An immediately preceding run found two test-environment issues: Xcode's hosted test copy carried
testmanager Mach entitlements, and native AppKit controls lacked explicit accessibility values. The privacy
contract now separately checks the empty checked-in product entitlements while allowing only Xcode-hosted
test injection, and settings controls now expose explicit popup/stepper/slider values. Focused regression
tests passed before the clean full run above.

The default full suite includes a bounded 30-logical-day monthly-volume harness. The full Release gate is
executed separately with at least 1,000,000 committed Chinese characters and passed under T056. XCTest
against the current Xcode SDK warns that its test libraries require macOS 14 while
the product deployment target is macOS 13; this is a test-host SDK warning and reinforces the separate
physical macOS 13 gate in T110.

Fresh-process measurement exposed retained startup validation allocations. `DictionaryLoader` now validates
the mapped image without materializing records or candidate strings; the 115-test final run includes mapped
layout, UTF-8, ordering, lookup and performance regression coverage.
