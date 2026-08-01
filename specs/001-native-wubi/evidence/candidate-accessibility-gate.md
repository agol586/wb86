# T020 Candidate Accessibility Gate Evidence

## Verdict

**PASS — select the accessible custom presenter.** `IMKCandidates` is rejected as the release
candidate presenter because its public API cannot prove the candidate-level VoiceOver, selected-state,
focus, configurable typography, and accessibility-order contracts. T021 must implement a non-activating
custom AppKit panel using public accessibility properties and actions.

## Probe environment

- Date: 2026-08-01 (Asia/Shanghai)
- Hardware: Apple Silicon (`arm64`)
- macOS: 26.5.2 (25F84)
- Xcode: 26.6 (17F113)
- SDK header inspected: macOS 26.5 `InputMethodKit.framework/Headers/IMKCandidates.h`
- Runtime class inspected: system `IMKCandidates`

No candidate text or user input was recorded during this probe.

## Capability matrix

| Requirement | Publicly verifiable result | Verdict |
|---|---|---|
| Number-key selection | `setSelectionKeys` controls displayed keys and page size | PASS |
| Event routing | `IMKCandidatesSendServerKeyEventFirst` can route controller first | PASS |
| Horizontal/vertical layout | Three fixed panel types exist | PARTIAL — not the full product layout contract |
| Candidate font scaling | `NSFontAttributeName` changes candidate font | PARTIAL — header says selection-key font is unaffected |
| Visible-screen placement | location hints promise a fully visible display; frame getter/setter exists | PARTIAL — no public screen-change or scaling policy |
| Client focus retention | event order is configurable | UNPROVEN — no public key-window/focus policy API |
| Candidate role/label/value | No candidate-level public accessibility API | FAIL |
| Selected state and order | No public mapping for accessibility selected children/order | FAIL |
| VoiceOver action | No public per-candidate accessibility action | FAIL |
| Accessibility Inspector stability | Internal candidate views are private and cannot form a supported contract | FAIL |

## Runtime inspection

Runtime introspection reported superclass `NSResponder`. Generic selectors such as
`accessibilityRole`, `accessibilityChildren`, and `accessibilityPerformPress` are inherited, but the
class does not publicly conform to an `NSAccessibility` protocol and exposes no supported API that
maps candidate identifiers to accessibility elements. The presence of inherited selectors therefore
does not prove candidate semantics.

## Decision consequences

The selected implementation uses a borderless, non-activating `NSPanel` and standard AppKit controls
with explicit labels, values, selected state, ordering, and press actions. It must:

1. never become key or main and never steal the text client's focus;
2. expose candidates in the same visual, numeric, and accessibility order;
3. send mouse and accessibility activation through the same selection callback;
4. clamp its frame to the visible frame of the screen containing the composition anchor;
5. respond to appearance, contrast, font scale, screen, and backing-scale changes;
6. hide atomically on empty pages, cancellation, commit, focus loss, or error.

T021 establishes this presenter boundary. Detailed layout, mouse callback, screen positioning, and
full VoiceOver acceptance remain assigned to T029, T094, T096, T097, and T100.
