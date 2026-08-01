# Historical Sandboxed InputMethodKit Gate Evidence

## Verdict

**REJECTED ROUTE — retained for historical evidence.** The initial App Sandbox Mach-registration failure is resolved
by the constitution-approved exact-name temporary exception. `IMKServer` now registers without a
sandbox denial. After a full logout/login refresh, however, the input source remains absent, so
enablement and cross-application input cannot run. Rebuilding and installing with a valid Apple
Development certificate and complete Apple trust chain does not change the result: TIS still returns
zero MacWubi sources. The macOS 13 run also remains open.

## Test environment

- Date: 2026-08-01 (Asia/Shanghai)
- Hardware architecture: Apple Silicon (`arm64`)
- macOS: 26.5.2 (25F84)
- Xcode: 26.6 (17F113)
- Bundle: `/Users/agol/Library/Input Methods/MacWubi.app`
- Bundle identifier: `org.macwubi.inputmethod`
- InputMethodKit connection: `org.macwubi.inputmethod_Connection`
- Signing: valid local development signature
- Product binary: a single `arm64` Mach-O slice, matching the amended Apple Silicon-only scope
- Configured product entitlements: App Sandbox, user-selected file read/write, and the exact-name
  `mach-register.global-name` exception for `org.macwubi.inputmethod_Connection`; the local
  development build additionally carries Xcode's `get-task-allow` entitlement
- Input method icon: `MacWubi.icns`, present and named by `tsInputMethodIconFileKey`

## Procedure and observations

1. Built and signed the app using the Xcode project, then copied it to
   `~/Library/Input Methods/MacWubi.app`.
2. Verified the installed executable with `file` and verified its signature with
   `codesign --verify --deep --strict --verbose=2`.
3. Registered the installed bundle with Launch Services using `lsregister -f -R -trusted` and
   restarted `TextInputMenuAgent`.
4. Queried enabled and disabled Text Input Sources through
   `TISCreateInputSourceList(nil, true)`. No input source whose bundle identifier contained
   `macwubi` was returned.
5. Launched the original installed app directly and inspected the privacy-safe unified log. App
   Sandbox container setup succeeded, followed by these InputMethodKit failures at 17:56:26.032:

   ```text
   (InputMethodKit) could not register <private>
   (InputMethodKit) [IMKServer _createConnection]: *Failed* to register NSConnection name=<private>
   ```

The log excerpt contains no raw keys, marked text, candidates, committed text, application identity,
document context, or external file paths.

6. Added the exact connection name to
   `com.apple.security.temporary-exception.mach-register.global-name`, rebuilt, signed, verified, and
   reinstalled the arm64 bundle. Fresh launches no longer produce an InputMethodKit registration
   failure or `sandboxd` Mach-registration denial.
7. Added an explicit `TISInputSourceID`, BCP 47 language, and visible Wubi 86 input mode. Calling the
   public `TISRegisterInputSource` API for the installed bundle returns `noErr`. The source is still
   absent from `TISCreateInputSourceList(nil, true)` after restarting `TextInputMenuAgent` and the
   per-user preferences daemon.
8. The user logged out and back in. A fresh `TISCreateInputSourceList(nil, true)` query still returned
   zero MacWubi matches; a fresh `TISRegisterInputSource` call returned `noErr` but did not add a
   discoverable source.
9. `codesign -dvvv` records `Signature=adhoc` and `TeamIdentifier=not set`; `security find-identity -v
   -p codesigning` reports zero valid identities. `spctl --assess --type execute` cannot produce a
   successful trust assessment for the installed bundle. These observations identify trusted signing
   as the next test prerequisite, but do not by themselves prove that signing is the only remaining
   discovery condition.
10. An Apple Development identity with private key subsequently became visible. The first certificate-
    signed build was rejected by Xcode before compilation with `Invalid trust settings`; Xcode requires
    the Apple Development certificate to use system-default trust rather than a manual trust override.
    No newly signed bundle was produced or installed by this attempt.
11. After restoring system-default certificate trust, Xcode successfully signed the Release bundle
    with `Apple Development: luoagol@gmail.com (6XRC4PBH7N)`. The installed app verifies strictly,
    carries `TeamIdentifier=M4F29FKGK7`, and has an Apple Development → Apple Worldwide Developer
    Relations → Apple Root CA authority chain. `TISRegisterInputSource` still returns `noErr`, while a
    complete 318-source query by bundle ID, input-source ID and localized name returns zero MacWubi
    matches. Trusted development signing therefore does not resolve discovery on macOS 26.5.2.

## Gate coverage

| Required T019 check | Result |
|---|---|
| Signed sandboxed bundle launches | PASS |
| InputMethodKit server connection registers | PASS with exact-name temporary exception |
| Input source discovery | FAIL after logout/login — registration API succeeds but TIS lists zero matches |
| Input source enablement | NOT RUN — source is undiscoverable |
| Cross-application input | NOT RUN — source cannot be enabled |
| Current supported macOS | FAIL on macOS 26.5.2 (connection passes; discovery fails) |
| macOS 13 | NOT RUN — no macOS 13 validation environment is available, and the current-OS failure already triggers the hard stop |

## Superseding decision

This route was superseded on 2026-08-01 by Constitution 3.0.0 and the non-sandbox
Developer-ID/notarization distribution decision. The old bundle identifier also ended in
`.inputmethod` instead of containing the complete `.inputmethod.` segment later found necessary for
IMK/TIS discovery. The evidence below remains useful to show why the sandbox route was abandoned; it
is not the current T019 verdict.

Constitution 2.1.0 authorized only the fixed
`org.macwubi.inputmethod_Connection` Mach-registration exception supported by the recorded sandbox
denial. No wildcard, Mach lookup, network permission, non-sandboxed helper, or disabled system security
control was introduced. T019 remains unchecked: the current supported macOS does not discover the
bundle even after exact registration, logout/login, complete TIS metadata and trusted Apple
Development signing. Per the hard-stop rule, T020 and later tasks must not begin. A specification or
constitution decision is required before another workaround is attempted. A separate Apple Silicon
macOS 13 validation run also remains required by the current task contract.
