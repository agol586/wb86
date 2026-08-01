# Apple Silicon Release Matrix

Intel Macs and `x86_64` binaries are outside product support and release validation. Every matrix
entry must use physical Apple Silicon hardware, an exact-arm64 product, standard macOS security
settings, and the same notarized final candidate.

## Required systems

| System | Hardware | Required coverage | Release state |
|---|---|---|---|
| macOS 13 latest update | Physical Apple Silicon Mac | Full quickstart, seven application classes, VoiceOver, install/upgrade/uninstall | Pending final hardware run |
| Current supported macOS | Physical Apple Silicon Mac | Same full matrix | Pending final candidate run |

If the current supported version is macOS 13, add the newest later supported macOS before release so
the matrix still covers two distinct system generations. Virtual machines may supplement but cannot
replace either physical-hardware row.

## Per-row procedure

1. Record Mac model, chip, memory, macOS build, Xcode build, release configuration, exact bundle
   checksum, dictionary manifest checksum and fixture version. Do not record input content.
2. Confirm `uname -m` is `arm64`; run `lipo -archs` and require exactly `arm64` with no `x86_64`.
3. Run `Scripts/test.sh`, build with Developer ID and secure timestamp, notarize, staple, then run
   `MACWUBI_REQUIRE_DISTRIBUTION=1 Scripts/verify-release.sh` and `Scripts/privacy-audit.sh`.
4. Install through `Scripts/install.sh`; verify discovery, enablement, connection and input in native
   editor, browser, office suite, code editor, terminal, system search and Electron application.
5. Execute every quickstart input, settings, personalization, import/export, migration, recovery,
   privacy, accessibility and performance scenario.
6. Upgrade in place and confirm data preservation; uninstall once preserving personalization and once
   explicitly deleting it. Never disable Gatekeeper, SIP, Secure Event Input or other protections.

Any missing row or failed architecture, signing, InputMethodKit, privacy, recovery, accessibility or
performance gate blocks release. Results belong in `specs/001-native-wubi/evidence/release-matrix.md`.
