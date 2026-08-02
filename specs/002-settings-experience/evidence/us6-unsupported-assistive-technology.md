# US6 Unsupported Assistive-Technology Boundary Evidence

**Verdict**: PASS on 2026-08-02. VoiceOver, VoiceOver Utility/旁白实用工具,
Accessibility Inspector, and screen-reader-specific candidate speech, focus, selection,
actions, and settings navigation are explicitly unsupported. Ordinary mouse/keyboard behavior,
visible feedback, high contrast, reduced motion, scaling, and multi-display layout remain supported.

## Environment

- Hardware: Apple Silicon MacBook Air, `arm64`
- macOS: 26.5.2 (25F84)
- Xcode: 26.6 (17F113)
- Configuration: Debug tests and ad-hoc signed Release arm64 bundle
- Release executable SHA-256:
  `d0ea15ba465fde77225207acbbd65578ad322f8044bdf1e0d86ab790220c8852`

## Implementation boundary

- Deleted `AccessibilityAdapter.swift` and the specialized accessibility test/manual-scenario files.
- Replaced `AccessibleCandidatePresenter` with the ordinary `CandidatePanelPresenter`.
- Removed explicit accessibility trees, announcements, focus publication, control semantics, and
  assistive activation from InputMethod sources.
- Preserved normal candidate mouse callbacks, keyboard event handling, visible validation messages,
  screen bounds, high contrast, reduced motion, font scale, and multi-display layout.
- `UnsupportedAssistiveTechnologyTests` scans `Sources/InputMethod/*.swift` and rejects the removed
  filenames and specialized API tokens.

## Fresh validation

```text
xcodebuild test ... CandidatePanelPresenterTests SettingsWindowTests UnsupportedAssistiveTechnologyTests
PASS: 15 tests, 0 failures

xcodebuild test ... InputControllerContractTests DailyInputIntegrationTests SettingsIntegrationTests
PASS: 23 tests, 0 failures

Scripts/test.sh
PASS: 213 tests, 0 failures; deterministic lexicon fixture verification passed

Scripts/build-release.sh
PASS: Release arm64 build, ad-hoc signed with Hardened Runtime

Scripts/verify-release.sh <Release MacWubi.app>
PASS: native arm64, signed, hardened, dependency-free, non-sandboxed, offline, licensed

Scripts/privacy-audit.sh <Release MacWubi.app>
PASS: zero network capability, redacted diagnostics, bounded local data

Scripts/run-long-stress.sh <Release MacWubi.app> 3000
PASS: 30 logical days, 3,000 committed characters, 8,651,424-byte steady/maximum footprint,
maximum latency 841,875 ns, no drift
```

The 3,000-character run is a smoke regression for the already-passed 1,000,000-character monthly-volume
gate; it is not a replacement for that recorded full result. No eight-hour wall-clock stress command was
started. A final `pgrep` matched only its own inspection command, confirming no old eight-hour MacWubi
stress process remained.

No command or evidence captured raw keys, candidate/committed text, client identity, document context,
external user paths, or a reconstructable input timeline.

## Remaining release gates

- T027 ordinary physical InputMethodKit marked-text/candidate click and focus/source-switch regression.
- Physical macOS 13/current-supported-OS application and ordinary visual interaction matrices.
- Target-user studies and final Developer ID/notarization/staple/Gatekeeper operations.

VoiceOver or screen-reader acceptance is not a remaining gate.
