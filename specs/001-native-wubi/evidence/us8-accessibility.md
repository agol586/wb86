# US8 Accessibility Evidence

Status: **AUTOMATED PASS / REMAINING MANUAL GATE SKIPPED BY USER**

Automated contract coverage on 2026-08-01 verifies candidate role, label, code, value, selected state,
order, action and non-stealing focus; settings focus order, values, keyboard focus, announced validation
errors and destructive confirmations; and candidate screen clamping for scaling, full-screen,
multi-display, reduced-motion and high-contrast inputs.

Command:

```bash
xcodebuild test -quiet -project MacWubi.xcodeproj -scheme MacWubi \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/us8-tdd \
  -only-testing:MacWubiTests/CandidateAccessibilityTests \
  -only-testing:MacWubiTests/SettingsAccessibilityTests \
  -only-testing:MacWubiTests/SettingsWindowTests CODE_SIGNING_ALLOWED=NO
```

Result: PASS. No input text was logged.

T100 remains open until a human executes every scenario in
`Tests/AccessibilityTests/ManualAccessibilityScenarios.md` with VoiceOver and Accessibility Inspector
on physical hardware and records the observed spoken order, keyboard completion, appearance, scaling and
multi-display verdict. Automated semantic snapshots do not substitute for this gate.

## Current physical environment audit (2026-08-01)

The installed candidate is exact hash
`8237827cdf536400d9f41c673e299e12aceb42d8c4c6414715ea511e568ca048`. AppKit reports one physical screen,
1710×1068 logical points, 1661×1038 visible frame and 2.0 backing scale. VoiceOver and Accessibility
Inspector were not running; Increase Contrast, Reduce Motion and Differentiate Without Color were false.
Consequently no spoken/visual result was inferred, and the required physical multi-display portion cannot
be executed in the current one-display configuration. T100 remains open.

## First VoiceOver execution (2026-08-02)

Two physical displays were available (1470×956 and 1920×1080 logical points, both 2.0 backing scale),
VoiceOver was running, and Accessibility Inspector was open. The user reported that VoiceOver candidate
navigation, Inspector candidate inspection and VoiceOver activation of a non-first candidate did not work.
This is recorded as a real FAIL, not operator error. T096 and T109 were reopened. The remediation explicitly
exposes the non-activating panel content/list/buttons, separates candidate label/value/selected state, routes
the accessibility press through the normal button action, and publishes layout/focused-element notifications
without allowing the panel to become key or main. A rebuilt candidate must be retested before T100 can pass.

## Accessibility remediation candidate (2026-08-02)

The focused candidate/settings accessibility suites and the complete 115-test suite pass after remediation.
An Apple Development signed, Hardened Runtime, exact-arm64, non-sandboxed and offline candidate was built
and independently verified. Its executable SHA-256 is
`105d6c81eb34dba0c6ff94fdbb4eaf87c40bbe93850820ca84fbb5a0adbb339e`.
The system-installed copy was atomically upgraded and independently verified at the same hash, and the
old input-method process was terminated so the next session loads this candidate. It is ready for physical
VoiceOver retesting; no manual PASS is inferred from automation.

The subsequent no-speech observation was invalidated before being recorded as a product failure: process
inspection showed that only VoiceOver Utility was running, while the VoiceOver screen reader itself was not.
The installed candidate still awaits a retest with VoiceOver verifiably enabled.

With the VoiceOver screen-reader process verified as running, the candidate content was spoken and could be
reached, but only after interacting downward through several accessibility containers. This is a partial
result, not a PASS: the effect-view and stack/list wrappers make the candidate hierarchy unnecessarily deep.
T096 and T109 were reopened to flatten candidates to direct window children and add one deduplicated,
high-priority candidate summary announcement.

The remediation passed the focused accessibility test and the complete 115-test suite. A new verified
Apple Development/Hardened Runtime exact-arm64 candidate was installed at executable SHA-256
`cfae20172041567d93136fdbdba6404927af936ca651dbdd1ae0a15e9989ad7f`; VoiceOver remained verifiably
running after the old input-method process was terminated. Physical retest remains pending.

Physical VoiceOver retest on that exact installed hash passed the core candidate path in TextEdit: the first
candidate was announced directly without descending through wrapper containers; `VO+Right Arrow` announced
the second candidate; `VO+Space` activated it through the normal selection callback; and the client retained
text-input focus. Multi-page, cancellation/focus-loss, settings and appearance/display scenarios remain open.

The multi-page VoiceOver path also passed: a production dictionary code with more than one page was entered,
the next-page key caused updated page/candidate speech, `VO+Right Arrow` moved in order, and `VO+Space`
committed the chosen candidate. No typed code or candidate content is retained in this evidence.

Cancellation and application-focus recovery passed with VoiceOver enabled: Escape hid the candidate window
without committing either the code or a candidate; switching applications hid stale candidates; returning to
the original client showed no residual composition and allowed a fresh session. Global
`AppleKeyboardUIMode=2` confirms all-controls keyboard navigation is enabled for the settings phase.

## Deferred continuation

On 2026-08-02 the user explicitly skipped the remaining VoiceOver work. T100 stays open. Resume at the
keyboard-only settings-entry scenario, followed by settings traversal/error/confirmation, appearance and
display coverage. The completed candidate navigation, activation, paging, cancellation and focus-recovery
observations above remain valid for the recorded candidate hash.
