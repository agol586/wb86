# US7 Privacy Audit Evidence

Date: 2026-08-01 (Asia/Shanghai)

Environment: Apple M3, arm64; macOS 26.5.2 (25F84); Xcode 26.6 (17F113).

## Evidence

- Privacy inventory returned only Settings, UserLexicon and Learning, with fixed purposes, logical
  relative locations, schema versions and byte counts. It exposed no entry text or absolute path.
- Per-domain deletion removed only its selected snapshot directory. Delete-all continued after an
  injected domain failure and returned a truthful result for every domain. Base dictionary input
  remained available.
- Adversarial raw code, candidate, path, application identity and timestamp/timeline strings were
  passed through the diagnostic test boundary; output remained the fixed line
  `client_operation_failure=5` and contained none of those samples.
- Release tests found no network client/server entitlement, CFNetwork, Network.framework, WebKit,
  libcurl, URLSession or NWConnection product dependency/API.
- The exact ad-hoc Hardened Runtime Release bundle passed strict arm64/signature/entitlement and
  static privacy audits.
- The currently installed Apple Development input-method process (PID recorded transiently for the
  command only) passed live `lsof` network observation with zero TCP/UDP connection.
- Existing deterministic tests cover normal input, injected failures, 10,000-record import, migration,
  upgrade contracts and 10,000 private-mode submissions with no learning or filesystem changes.

## Commands

```sh
Scripts/build-release.sh
Scripts/verify-release.sh /Users/agol/repos/wb86/.build/xcode/Build/Products/Release/MacWubi.app
Scripts/privacy-audit.sh /Users/agol/repos/wb86/.build/xcode/Build/Products/Release/MacWubi.app
Scripts/privacy-audit.sh '/Library/Input Methods/MacWubi.app' --pid 52418
```

Result: PASS — exact arm64, valid signature, Hardened Runtime, empty entitlements, system-only dynamic
dependencies, no prohibited network framework/symbol, and no live network connection.

The process identifier is operational evidence only and is not stored by the product. Final Developer
ID/notarized candidate observation remains part of the explicitly deferred final release gate.
