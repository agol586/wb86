# Settings Experience Quickstart Evidence

Status: **AUTOMATED QUICKSTART PASS / FINAL DISTRIBUTION GATES DEFERRED**

Execution date: 2026-08-02 (Asia/Shanghai)

## Environment

- Hardware: MacBook Air, Apple M3, 8 cores, 24 GB RAM.
- Architecture: native Apple Silicon `arm64`; Intel Mac and Rosetta are outside scope.
- macOS: 26.5.2 (25F84).
- Xcode: 26.6 (17F113).
- Build configuration: Release, macOS 13.0 deployment target, Hardened Runtime.
- Pinyin resource: MWPY schema 1, source revision
  `0c6861ef7420ee780270ca6d993d18d4101049d0`, Apache-2.0, 38,999 keys and 60,742
  candidates, maximum 64 candidates per key.

No hardware serial number, user input, composition, candidate text, application identity or document
context is retained in this evidence.

## Automated suite and deterministic fixture

```bash
Scripts/test.sh
```

Result: **PASS**. The XCTest result contains 217 passed tests, zero failures and zero skips on arm64.
The script then rebuilt the pure-Swift Release dictionary compiler and reproduced the bounded WB86
acceptance fixture successfully.

## Development-signed arm64 Release

```bash
MACWUBI_CODE_SIGN_IDENTITY='Apple Development: <configured identity>' Scripts/build-release.sh
```

Result: **PASS**. The output is a thin Mach-O arm64 executable with Hardened Runtime and the empty
product entitlement dictionary. Executable SHA-256:
`8cd9bb64a2a5132097c3da7610518de85ae25ff32c26523b007d2a14354a0c6f`.

## Release and privacy verification

```bash
Scripts/verify-release.sh \
  /Users/agol/repos/wb86/.worktrees/002-settings-experience/.build/xcode/Build/Products/Release/MacWubi.app
Scripts/privacy-audit.sh \
  /Users/agol/repos/wb86/.worktrees/002-settings-experience/.build/xcode/Build/Products/Release/MacWubi.app
```

Results: **PASS**.

- Exactly arm64; no x86_64 slice or Rosetta path.
- Valid local development signature and Hardened Runtime.
- Empty product entitlements; no sandbox, network, Apple Events, application group, Mach exception or
  get-task-allow capability.
- No embedded framework, package-manager runtime or non-system dynamic dependency.
- No network/global-input APIs or symbols.
- MWPY binary, manifest, pinned source record, AUTHORS and Apache-2.0 license are sealed resources.

## Explicitly deferred release/manual gates

Per the user's release-stage decision, Developer ID Application signing, secure timestamp, notarization,
stapling and Gatekeeper assessment are not claimed here and remain final-release gates. The previously
deferred physical InputMethodKit click/focus regression and remaining VoiceOver/settings appearance matrix
also remain manual gates; automated fixtures are not presented as substitutes.
