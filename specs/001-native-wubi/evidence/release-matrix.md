# Final Apple Silicon Release Matrix

Status: **DEFERRED / RELEASE BLOCKED**

The user explicitly deferred the physical macOS 13 and current-supported-macOS final matrix until final
release. No Intel row exists because Intel and `x86_64` are unsupported, not a pending validation target.

| Hardware | Architecture | macOS | Signed candidate | Discovery/input/upgrade/privacy | Verdict |
|---|---|---|---|---|---|
| Apple Silicon physical Mac | arm64 | 13.x | Pending | Pending | Pending |
| Apple Silicon physical Mac | arm64 | Current supported | Pending final candidate | Pending complete rerun | Pending |

Development evidence on `Mac15,12`, macOS 26.5.2 confirms an Apple Development-signed Hardened Runtime
bundle with exact `arm64` architecture can be installed and loaded, but it is not the immutable final
Developer ID candidate and cannot close T083.
