# Manual Accessibility Acceptance Matrix

Run against the exact signed release candidate on physical Apple Silicon. Record only PASS/FAIL,
hardware/OS/build identifiers and fixed failure categories; never record typed codes or candidate text.

Automation verifies semantics and focus contracts but cannot substitute for spoken output, visual contrast,
physical keyboard navigation or multi-display behavior. The candidate navigation rows already completed for
the previously recorded signed build remain valid; on 2026-08-02 the user explicitly deferred the remaining
VoiceOver settings and appearance rows.

| Area | Automated contract | Physical acceptance | Current status |
|---|---|---|---|
| Candidate label, value, selected order and action | `CandidateAccessibilityTests` | VoiceOver reads and activates candidates without stealing client focus | PASS on recorded candidate build |
| Candidate paging, cancel and focus recovery | Candidate snapshot and session tests | VoiceOver announces new page; stale panel disappears | PASS on recorded candidate build |
| Common/Keys/Appearance/Advanced controls | `SettingsAccessibilityTests` exact one-control labels, help, values and traversal | Full Keyboard Access and VoiceOver traverse every control once | DEFERRED BY USER |
| Save/conflict/I/O/future-schema feedback | Focus and announcement unit tests | VoiceOver speaks feedback and lands on the exact failing control | DEFERRED BY USER |
| Restore-default confirmation | Domain-naming and cancellation tests | Keyboard-only confirmation/cancel keeps focus predictable | DEFERRED BY USER |
| Light/dark/contrast/motion/scaling/displays | `CandidateAccessibilityTests` layout environment coverage | Visual and VoiceOver checks on physical displays | DEFERRED BY USER |

## VoiceOver and candidate panel

1. Enable VoiceOver using the standard macOS accessibility control.
2. In each declared application class, start composition and navigate multiple candidate pages.
3. Confirm the panel is announced as “五笔候选窗口”, current code and page state are understandable,
   and candidates are read once in visual/number order with selected state.
4. Activate a non-first candidate with VoiceOver. Confirm it follows the same commit callback as mouse
   and number-key selection, and the client retains keyboard focus.
5. Cancel, switch focus/input source, and inject a client failure. Confirm stale candidates disappear.

## Full Keyboard Access and settings

1. Enable Full Keyboard Access and open Settings from the input menu without using a pointer.
2. Traverse 常用、按键、外观、高级 and then 恢复默认、取消、保存 in visible order. Confirm no
   duplicate stop exists for 中英文切换.
3. Change every non-destructive setting, apply it, trigger a duplicate shortcut and an invalid numeric
   value, and confirm each error is announced and focus lands on the exact field. Exercise future-schema
   read-only feedback with a disposable fixture. Restore defaults and confirm focus remains predictable.
4. Open each destructive action, verify its affected domain is named, then cancel. Execute deletions
   only on a disposable profile.

## Appearance and displays

Repeat the candidate and settings flow in light, dark and increased-contrast appearances; with Reduce
Motion enabled; at 0.8, 1.0, 1.5 and 2.0 candidate font scale; in full-screen; and with anchors near
every edge of each connected display at its native backing scale. The panel must remain fully inside
the selected display, show a visible selected state, avoid animation under Reduce Motion, and never
become key or main.
