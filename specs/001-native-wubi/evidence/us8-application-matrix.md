# US8 Seven-Application Assistive-Technology Matrix (Historical and Superseded)

> Feature 002 T061–T063 cancelled this matrix as a release gate because VoiceOver and screen-reader-specific
> behavior are explicitly unsupported. This file remains only as historical evidence.

Status: **SKIPPED BY USER — PENDING MANUAL EXECUTION**

The automated seven-class fixture covers native editor, browser, office, code editor, terminal, system
search and Electron session isolation and focus churn. T101 additionally requires rerunning actual core
input flows in all seven application classes with VoiceOver and Full Keyboard Access enabled.

| Application class | Application/version | Input/edit/select/shortcut/focus | Accessibility delta |
|---|---|---|---|
| Native text | Pending | Pending | Pending |
| Browser | Pending | Pending | Pending |
| Office | Pending | Pending | Pending |
| Code editor | Pending | Pending | Pending |
| Terminal | Pending | Pending | Pending |
| System search | Pending | Pending | Pending |
| Electron | Pending | Pending | Pending |

No row may be marked PASS from fixture-only evidence, and no input or candidate text may be recorded.

This historical note originally left T101 open. Feature 002 T061–T063 later cancelled it because the
VoiceOver/Full Keyboard Access seven-application rerun is outside the supported scope. It was skipped by
the user on 2026-08-02 and must not be inferred from the automated fixture or the completed TextEdit checks.

## Available applications (2026-08-01)

The current machine has suitable real applications for all seven classes: TextEdit/Notes (native text),
Safari (browser), Pages and Microsoft Word (office), Xcode and Visual Studio Code (code editor), Terminal,
Spotlight (system search), and Slack/Discord (Electron). VoiceOver was not enabled during inventory, so no
application row was executed or upgraded from Pending. This avoids falsely treating app availability as
accessible-input evidence.
