# Signing and Distribution

Mac Wubi supports Apple Silicon (`arm64`) only and is distributed outside the Mac App Store as a
non-sandboxed InputMethodKit bundle. App Sandbox, Rosetta, Intel slices, network entitlements and
runtime-security exceptions are not supported.

## Local build identities

All runnable bundles are signed and use Hardened Runtime:

```sh
# Reproducible local build with ad-hoc identity
Scripts/build-release.sh

# System discovery and development testing
MACWUBI_CODE_SIGN_IDENTITY="Apple Development: Name (TEAMID)" Scripts/build-release.sh
```

Both forms must pass:

```sh
Scripts/verify-release.sh /absolute/path/to/MacWubi.app
```

The verifier requires an exact `arm64` executable, a valid strict signature, Hardened Runtime, an
empty entitlement set, InputMethodKit metadata, and system-only dynamic dependencies. It rejects
universal and `x86_64` products.

## Developer ID release

Final distribution uses a valid `Developer ID Application` identity and secure timestamp. Archive
and submit the exact verified bundle to Apple's notary service, staple the accepted ticket, then run:

```sh
MACWUBI_CODE_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" Scripts/build-release.sh
xcrun notarytool submit /absolute/path/to/MacWubi.zip --keychain-profile PROFILE --wait
xcrun stapler staple /absolute/path/to/MacWubi.app
MACWUBI_REQUIRE_DISTRIBUTION=1 Scripts/verify-release.sh /absolute/path/to/MacWubi.app
```

Distribution verification additionally requires the Developer ID authority, signature timestamp,
valid stapled ticket, and successful Gatekeeper install assessment. Credentials are never stored in
the repository. The macOS 13/current-system hardware matrix and notarization evidence are final
release gates and may not be replaced with ad-hoc or Apple Development evidence.

Installation uses `Scripts/install.sh` and standard `sudo` authorization to atomically replace
`/Library/Input Methods/MacWubi.app`. It does not disable Gatekeeper or SIP. Uninstall preserves
personalization unless the user explicitly supplies `--delete-data`.
