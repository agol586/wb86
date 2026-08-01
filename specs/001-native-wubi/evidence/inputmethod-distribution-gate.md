# T019 InputMethodKit Distribution Gate Evidence

## Verdict

**PASS — local implementation gate is open.** The current-system Apple Development vertical slice
passes discovery, enablement, selection, launch, and InputMethodKit client connection on Apple
Silicon macOS 26.5.2. The deterministic installation route is the system-level
`/Library/Input Methods/MacWubi.app`; the user-level location was discoverable through TIS but was
not offered by System Settings for enablement on this system.

By explicit product decision on 2026-08-01, macOS 13 runtime coverage and the Developer ID Application,
notarization, staple, and Gatekeeper checks remain mandatory but move to the final-release gates. This
gate opens T020 and later implementation without claiming distribution readiness.

## Test environment

- Date: 2026-08-01 (Asia/Shanghai)
- Hardware architecture: Apple Silicon (`arm64`)
- macOS: 26.5.2 (25F84)
- Xcode: 26.6 (17F113), macOS 26.5 SDK, deployment target macOS 13.0
- Installed bundle: `/Library/Input Methods/MacWubi.app`, version `0.1.0` build `4`
- Bundle identifier and source ID: `org.macwubi.inputmethod.MacWubi`
- Connection name: `org.macwubi.inputmethod.MacWubi_Connection`
- Local gate signing: Apple Development, Team ID `M4F29FKGK7`
- Formal distribution requirement: Developer ID Application, Hardened Runtime, secure timestamp,
  notarization ticket, and Gatekeeper assessment

## Current-system observations

1. The initial sandboxed design remained absent from TIS enumeration after signing and temporary
   Mach registration experiments. The approved design is therefore the non-sandbox Developer ID
   route; no sandbox or Hardened Runtime weakening exception remains.
2. The old identifier `org.macwubi.inputmethod` registered with `noErr` but enumerated no source.
   Changing it to `org.macwubi.inputmethod.MacWubi`, with a complete `.inputmethod.` segment, made
   the source immediately discoverable.
3. A parent plus `ComponentInputModeDict` child produced an enabled child behind a disabled,
   non-addable parent. Registering one direct source without `ComponentInputModeDict` yielded one
   enabled, select-capable source.
4. The same Apple Development bundle in `~/Library/Input Methods/` was queryable through TIS but did
   not appear in System Settings. Installing it through the standard administrator prompt at
   `/Library/Input Methods/MacWubi.app` made it enableable and selectable. The user copy was moved,
   not deleted, to `~/Library/Input Methods/MacWubi.app.user-backup` to isolate duplicate registration.
5. After system registration, the public TIS calls returned one matching source,
   `TISEnableInputSource=0`, `TISSelectInputSource=0`, and current source ID
   `org.macwubi.inputmethod.MacWubi`.
6. Activating TextEdit launched PID 39746 from the system path. Unified logs recorded the input method
   connecting to `com.apple.inputmethodkit.setxpcendpoint`, imklaunchagent receiving the peer endpoint,
   and InputMethodKit `Activate Server`. This proves a real client-to-server connection rather than
   only bundle enumeration.
7. macOS 26.5.2 also logs a legacy `InputMethodConnectionName` refusal and occasional
   `LaunchInputMethod() Error, status=-50` before or alongside the successful XPC endpoint path.
   Replacing the official sample-style connection name with `MacWubi_Connection`, bumping the bundle
   build, unregistering development paths, and refreshing TIS did not remove the warning; endpoint
   registration and server activation still succeeded. Apple documentation requires a connection
   name but does not document this modern XPC fallback warning, so the product retains the official
   sample convention and records the warning without claiming an unsupported character restriction.

## Automated and release checks

| Check | Result |
|---|---|
| Metadata release-contract test | PASS after an intentional failing assertion during diagnosis |
| Release architecture | PASS — thin `arm64`, no `x86_64` |
| Strict code signature | PASS — Apple Development identity |
| Hardened Runtime | PASS |
| Entitlements | PASS — empty; no sandbox, network, Apple Events, Mach, or runtime weakening |
| Dynamic dependencies | PASS — Apple system libraries only |
| Discovery on macOS 26.5.2 | PASS — exactly one direct source |
| Enablement and selection | PASS — both APIs returned `noErr`; current ID matches |
| TextEdit IMK connection | PASS — system-path process, XPC endpoint, `Activate Server` |
| macOS 13 runtime | DEFERRED — mandatory final-release matrix in T081/T083/T110 |
| Developer ID notarized artifact | DEFERRED — mandatory final-release gate in T108/T111 |

## Security and privacy impact

No Gatekeeper or SIP control was disabled. The product has no App Sandbox, network, Apple Events,
Mach temporary-exception, `get-task-allow`, or Hardened Runtime weakening entitlement. The system-level
directory contains only the immutable signed bundle; mutable data remains restricted to the current
user's Application Support directory. Evidence contains no raw keys, marked text, candidates,
committed text, application document content, or reconstructable input timeline.

## Deferred final-release actions

1. Repeat the complete install, discovery, enablement, selection, launch, and client-input procedure on
   an Apple Silicon Mac running macOS 13.
2. Repeat it with a Developer ID Application signed, securely timestamped, notarized and stapled bundle,
   including `spctl` Gatekeeper assessment.
3. Record complete privacy-safe native-editor and browser input flows under US1 and the final
   compatibility matrix. T019 proves the client/server platform boundary; event semantics belong to
   T025/T030/T033 and must not be claimed as implemented by this gate.
