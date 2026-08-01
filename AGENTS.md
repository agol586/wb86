<!-- AUTONOMY DIRECTIVE — DO NOT REMOVE -->
YOU ARE AN AUTONOMOUS CODING AGENT. EXECUTE SCOPED, REVERSIBLE WORK TO COMPLETION.
DO NOT ASK FOR CONFIRMATION ON OBVIOUS LOCAL EDIT–TEST–VERIFY STEPS.
ASK ONLY FOR DESTRUCTIVE, CREDENTIAL-GATED, EXTERNAL-PRODUCTION, OR MATERIALLY
SCOPE-CHANGING ACTIONS.
<!-- END AUTONOMY DIRECTIVE -->

# AGENTS.md — Mac Wubi 86 Native

This file is the repository-level operating contract for coding agents. It applies to the entire
repository. More specific `AGENTS.md` files may add rules for subdirectories but must not weaken
this contract or the project constitution.

## 1. Source of Truth and Precedence

When instructions conflict, follow this order:

1. Safety, platform, and user instructions from the active session.
2. [Project constitution](.specify/memory/constitution.md).
3. Active feature documents referenced by `.specify/feature.json`.
4. This file.
5. Existing code patterns and local conventions.

For the current product, read these files before implementation:

- `specs/001-native-wubi/spec.md` — user-visible requirements and success criteria.
- `specs/001-native-wubi/plan.md` — architecture and technology decisions.
- `specs/001-native-wubi/research.md` — Apple-platform evidence and unresolved platform risks.
- `specs/001-native-wubi/data-model.md` — states, entities, and persistence invariants.
- `specs/001-native-wubi/contracts/` — input, dictionary, persistence, import/export, and UI contracts.
- `specs/001-native-wubi/tasks.md` — dependency-ordered implementation work.
- `specs/001-native-wubi/quickstart.md` — final end-to-end verification contract.

Do not silently change a requirement in code. Amend the appropriate Spec Kit artifact first when
new evidence changes scope, behavior, or a constitutional constraint.

## 2. Current Repository State

The repository is currently **design-complete but implementation-not-started**:

- Constitution, specification, research, plan, contracts, data model, validation guide, and tasks exist.
- The Xcode project and Swift sources described in the plan do not exist yet.
- Commands under `Scripts/` and build instructions in `quickstart.md` are delivery contracts, not
  currently runnable features.

Never claim that the input method builds, installs, or passes performance gates until fresh evidence
from a macOS/Xcode environment proves it.

## 3. Product Goal

Build a native macOS Wubi 86 input method that can replace a commercial Wubi input method for daily
use while remaining private, simple, fast, and maintainable.

“Replace” means supporting complete daily Wubi workflows, local personalization, settings, migration,
long-term upgrades, privacy controls, and accessibility. It does not mean copying another product's
branding, proprietary implementation, private data format, advertising, telemetry, or online services.

## 4. Non-Negotiable Engineering Rules

### 4.1 Native and Universal

- Use an Xcode project as the only supported product build entry.
- Product code MUST be Swift and compile into a Universal Binary containing `arm64` and `x86_64`.
- Do not require Rosetta 2 for normal execution.
- Target macOS 13.0 or later unless the specification is formally amended.

### 4.2 No Heavy or Foreign Runtime Dependencies

- The input engine, dictionary lookup, ranking, state machine, persistence, and migration logic MUST
  be implemented in Swift.
- Apple system frameworks are allowed at explicit boundaries.
- Do not add third-party packages or link C/C++ dynamic libraries without an approved constitution
  amendment and a documented dependency review.

### 4.3 InputMethodKit Boundary

- `Sources/Core/` MUST NOT import AppKit or InputMethodKit.
- `Sources/InputMethod/` is the system adapter boundary for `IMKServer`, `IMKInputController`, client
  text operations, candidate presentation, settings windows, and accessibility.
- Every input session owns independent composition state.
- Cancel must clear marked text without inserting `originalString` or committing the current code.
- Unhandled system/application shortcuts must pass through after any required safe reset.

### 4.4 Failure Safety

- Invalid input, corrupt dictionaries, failed migrations, unavailable clients, and candidate-window
  failures MUST NOT crash, loop, submit incorrect text, or contaminate another session.
- Recover atomically to an idle session and hide stale candidates.
- Isolate corruption by domain: base dictionary, settings, user lexicon, and learning data.
- Never log invalid bytes or user text while reporting an error.

## 5. Privacy Contract

- The shipped input method and all companion code MUST have no network client/server entitlement and
  MUST NOT create network connections, telemetry, accounts, cloud sync, ads, or online update checks.
- Process only events delivered by the active InputMethodKit session. Never install global key
  monitors or bypass Secure Event Input.
- Raw keys, marked text, candidate text, committed text, application identity, document context, file
  paths, and reconstructable input timelines MUST NOT appear in production logs or crash diagnostics.
- Mutable product data belongs in the input method's App Sandbox Application Support container.
- External files are accessible only through an explicit user-driven open/save panel and only for the
  duration of that import/export operation. Do not retain security-scoped bookmarks by default.
- Private mode and disabled learning MUST produce no learning writes and MUST exclude existing learning
  scores from ranking.
- User-facing deletion must support each data domain and all personalization without damaging the base
  input method.

Apple does not document a reliable per-client secure-field callback for InputMethodKit. Do not claim
automatic password-field detection or treat a global secure-event flag as sufficient evidence.

## 6. Persistence and Data Rules

- Store Settings, UserLexicon, and Learning as independently versioned snapshots.
- Stage and validate a complete replacement before atomically replacing the current snapshot.
- Retain at most one validated previous snapshot per domain for recovery.
- Unknown future schema versions must be preserved without destructive downgrade.
- Import must be bounded, deterministic, fully validated, and atomic.
- UserDefaults is not an approved store for user terms or learning data.
- The base Wubi dictionary is a signed, read-only bundle resource with reproducible provenance,
  normalization, format, checksum, and license evidence.

## 7. Performance Budgets

These are hard release gates, not aspirational targets:

- Normal input-path resident memory: `< 15 MB`.
- Recognized-code to first-candidate availability: `< 2 ms` for every release benchmark sample.
- No sustained memory or latency growth during the eight-hour stress scenario.

Performance evidence must record hardware, architecture, macOS, Xcode, build configuration, dictionary
manifest, fixture version, warm-up, sample count, percentiles, and maximum. Optimize only after a
repeatable failing measurement exists.

## 8. Signing, Sandbox, and Platform Gates

- Build and sign every runnable input-method bundle; local development may use ad-hoc or Apple
  Development signing.
- Verify Info.plist keys, entitlements, both architecture slices, and code signatures separately.
- Do not disable Gatekeeper, SIP, App Sandbox, or other macOS security controls to make the product load.
- `T019` in `tasks.md` is a hard stop: prove sandboxed InputMethodKit discovery, enablement, connection,
  and cross-app input on macOS 13 and the current supported macOS before broader implementation.
- `T020` decides whether the system candidate window meets keyboard, VoiceOver, focus, and display
  requirements. Use the recorded verdict; do not assume undocumented behavior.

If either platform assumption fails, stop and report the evidence. The next action is a specification
or constitution decision, not an undocumented entitlement or non-sandboxed workaround.

## 9. Repository Layout

The planned source layout is authoritative:

```text
MacWubi.xcodeproj/
Sources/
├── InputMethod/         # InputMethodKit and AppKit adapters only
├── Core/                # Pure-Swift input engine and immutable domain values
├── Persistence/         # Versioned snapshots, migration, and recovery
├── ImportExport/        # Explicit local file interchange
├── DictionaryCompiler/  # Build-time pure-Swift tooling
├── Resources/           # Signed generated dictionaries and manifests
└── Supporting/          # Info.plist and entitlements
Tests/
├── CoreTests/
├── AdapterContractTests/
├── DictionaryTests/
├── PersistenceTests/
├── MigrationTests/
├── ImportExportTests/
├── FailureRecoveryTests/
├── PrivacyTests/
├── AccessibilityTests/
├── PerformanceTests/
├── ReleaseContractTests/
└── IntegrationTests/
Scripts/
Docs/
specs/001-native-wubi/
```

Do not invent alternate top-level source trees, package managers, helper services, or daemons unless the
plan is formally amended.

## 10. Execution Workflow

1. Read the constitution and active feature artifacts.
2. Select the next unblocked task in `specs/001-native-wubi/tasks.md`.
3. Confirm its prerequisite task and platform gates have passed.
4. Write the specified failing test first when the task list includes one.
5. Implement the smallest change that satisfies the task and existing contracts.
6. Run targeted tests, then affected integration/contract tests.
7. Run lint/static/build checks available for the current stage.
8. Record required evidence without user input content.
9. Mark a task complete only after fresh validation passes.

Follow task IDs in dependency order. Parallel work is allowed only for tasks marked `[P]`, on distinct
files, after shared prerequisites are complete. Serialize edits to known shared files such as
`InputEngine.swift`, `InputController.swift`, `CandidateRanker.swift`, and
`SettingsWindowController.swift`.

## 11. Testing and Verification

Planned canonical commands:

```bash
Scripts/test.sh
Scripts/build-release.sh
Scripts/verify-release.sh /absolute/path/to/MacWubi.app
Scripts/privacy-audit.sh
```

Until those scripts are implemented, run the smallest available checks and state the validation gap.
After implementation, a release requires:

- Unit, contract, integration, migration, recovery, privacy, accessibility, and performance tests.
- A signed Universal Binary on Apple Silicon and Intel validation hardware.
- The complete `specs/001-native-wubi/quickstart.md` procedure.
- Traceability for FR-001 through FR-031 and SC-001 through SC-013.

Do not use production telemetry to validate reliability. Use deterministic tests, local stress harnesses,
manual accessibility checks, and privacy-safe user studies.

## 12. Change Discipline

- Prefer small, reviewable, reversible diffs and existing utilities.
- Do not add dependencies without explicit approval and constitutional review.
- Do not modify generated dictionary binaries without also updating their source, compiler, manifest,
  checksum tests, provenance, and license evidence.
- Do not overwrite user-authored changes, perform destructive Git operations, or commit/push unless the
  active user request explicitly includes them.
- Keep documentation honest: distinguish implemented behavior, planned behavior, and unverified platform
  assumptions.
- Update README, contracts, tests, and evidence when user-visible behavior changes.

## 13. Completion Report

Every coding completion report must include:

- Task IDs completed.
- Files changed.
- User-visible behavior delivered.
- Exact validation commands and concise results.
- Constitution gate impact: architecture, dependencies, InputMethodKit/sandbox/signing, recovery, privacy,
  and performance.
- Remaining risks or validation gaps.

Never claim the product, a story, or a release is complete while required tasks or gates remain open.
