# Tasks: 隐私优先的原生五笔 86 输入法

**Input**: Design documents from `/specs/001-native-wubi/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: 宪章要求自动化回归、集成、性能、签名与沙盒验证。本任务表采用测试先行：每个
用户故事先提交可失败的契约/验收测试，再实现至通过。

**Organization**: 任务按用户故事分组；这是一份完整产品计划，不将任何单一故事视为可发布 MVP。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可在前置阶段完成后与同组其他不同文件任务并行。
- **[Story]**: 映射到 spec.md 中的用户故事。
- 所有任务均给出需要创建或修改的精确文件路径。

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: 建立唯一 Xcode 原生构建入口、目录、测试入口和发布验证骨架。

- [ ] T001 Create the macOS Xcode project, product target, test targets, and shared scheme in `MacWubi.xcodeproj/project.pbxproj` and `MacWubi.xcodeproj/xcshareddata/xcschemes/MacWubi.xcscheme`
- [ ] T002 Configure Swift 5 language mode, macOS 13 deployment target, Standard Architectures, Release universal build, and zero package dependencies in `MacWubi.xcodeproj/project.pbxproj`
- [ ] T003 [P] Create the background input-method metadata skeleton in `Sources/Supporting/Info.plist`
- [ ] T004 [P] Create the minimal sandbox and user-selected-file entitlement set with no network capability in `Sources/Supporting/MacWubi.entitlements`
- [ ] T005 Create deterministic debug/release build entry points in `Scripts/build-debug.sh` and `Scripts/build-release.sh`
- [ ] T006 Create architecture, signature, entitlement, bundle-metadata, and dependency verification entry point in `Scripts/verify-release.sh`
- [ ] T007 Create the test target directory map and fixture policy in `Tests/README.md` and `Tests/Fixtures/README.md`

**Checkpoint**: Xcode can build an empty signed Universal Binary product and invoke all declared test targets.

---

## Phase 2: Foundational (Blocking Platform and Core Prerequisites)

**Purpose**: Prove the two undocumented platform boundaries, establish pure-Swift contracts, and create the base dictionary path required by every story.

**⚠️ CRITICAL**: T019 is a hard stop. If sandboxed InputMethodKit loading fails, do not start any user-story implementation or weaken the constitution.

- [ ] T008 [P] Write failing release-contract tests for dual architecture, signing, entitlements, and required Info.plist keys in `Tests/ReleaseContractTests/ReleaseContractTests.swift`
- [ ] T009 [P] Write failing value and invariant tests for InputCode, InputEvent, InputMode, CompositionState, Candidate, and CandidatePage in `Tests/CoreTests/CoreModelTests.swift`
- [ ] T010 [P] Write failing dictionary v1 known-vector, corruption, bounds, ordering, and UTF-8 tests in `Tests/DictionaryTests/DictionaryFormatTests.swift`
- [ ] T011 Implement InputCode, InputEvent, InputMode, CompositionState, Candidate, and CandidatePage value types in `Sources/Core/InputCode.swift`, `Sources/Core/InputEvent.swift`, `Sources/Core/InputMode.swift`, `Sources/Core/CompositionState.swift`, and `Sources/Core/Candidate.swift`
- [ ] T012 [P] Implement dictionary v1 envelope, packed-code, prefix-range, entry-record, and checksum types in `Sources/Core/DictionaryFormat.swift`
- [ ] T013 [P] Implement the build-time pure-Swift dictionary compiler and deterministic manifest output in `Sources/DictionaryCompiler/main.swift`
- [ ] T014 Establish redistributable Wubi 86 lexicon provenance, license evidence, normalization rules, and acceptance corpus policy in `Docs/LexiconProvenance.md` and `Tests/Fixtures/Lexicon/README.md`
- [ ] T015 Generate the normalized source lexicon fixture and expected known vectors in `Tests/Fixtures/Lexicon/wb86-acceptance.tsv` and `Tests/Fixtures/Lexicon/known-vectors.json`
- [ ] T016 Implement validated read-only mapped dictionary loading and prefix-bounded lookup in `Sources/Core/DictionaryLoader.swift` and `Sources/Core/DictionaryIndex.swift`
- [ ] T017 [P] Implement privacy-safe fixed-category diagnostics with no input-bearing fields in `Sources/Core/Diagnostics.swift`
- [ ] T018 Implement the IMKServer entry point, per-session controller skeleton, and candidate presenter abstraction in `Sources/InputMethod/AppDelegate.swift`, `Sources/InputMethod/InputController.swift`, and `Sources/InputMethod/CandidatePresenter.swift`
- [ ] T019 Build, sign, install, and record the sandboxed InputMethodKit discovery/enablement/cross-app vertical-slice verdict on macOS 13 and the current supported macOS in `specs/001-native-wubi/evidence/sandbox-imk-gate.md`
- [ ] T020 Probe IMKCandidates keyboard, VoiceOver, Accessibility Inspector, focus, and multi-display behavior and record the system-wrapper-versus-custom-presenter decision in `specs/001-native-wubi/evidence/candidate-accessibility-gate.md`
- [ ] T021 Implement the candidate presenter selected by T020 as either a verified IMKCandidates wrapper or accessible custom panel in `Sources/InputMethod/SystemCandidatePresenter.swift` or `Sources/InputMethod/AccessibleCandidatePresenter.swift`
- [ ] T022 Create the single local verification entry point that runs unit, integration, release-contract, and fixture checks in `Scripts/test.sh`

**Checkpoint**: Constitution platform gates pass, core value contracts are green, and candidate presentation architecture is fixed by evidence.

---

## Phase 3: User Story 1 - 完成高频五笔输入 (Priority: P1)

**Goal**: Deliver complete, fast Wubi 86 composition, candidate, paging, correction, mouse selection, and commit behavior across a standard text client.

**Independent Test**: Use the standard one-to-four-code, abbreviation, full-code, word, collision, punctuation, and continuous-input corpus for a ten-minute typing run with correct output and no stale state.

### Tests for User Story 1

- [ ] T023 [P] [US1] Write failing state-transition and edge-case tests from `contracts/input-events.md` in `Tests/CoreTests/InputEngineTests.swift`
- [ ] T024 [P] [US1] Write failing base-ranking, paging, empty-result, and deterministic-order tests in `Tests/CoreTests/CandidateQueryTests.swift`
- [ ] T025 [P] [US1] Write failing marked-text, commit, cancel-without-original-string, shortcut pass-through, focus-change, and mouse-selection adapter tests in `Tests/AdapterContractTests/InputControllerContractTests.swift`
- [ ] T026 [P] [US1] Write failing absolute two-millisecond lookup assertions over the acceptance corpus in `Tests/PerformanceTests/LookupPerformanceTests.swift`

### Implementation for User Story 1

- [ ] T027 [US1] Implement the deterministic composition state machine and atomic event results in `Sources/Core/InputEngine.swift`
- [ ] T028 [P] [US1] Implement base candidate ordering, page slicing, selection validation, and empty-result behavior in `Sources/Core/CandidateRanker.swift`
- [ ] T029 [P] [US1] Implement system candidate rendering, explicit update/show/hide, mouse callback mapping, and visible-screen positioning in `Sources/InputMethod/SystemCandidatePresenter.swift` or `Sources/InputMethod/AccessibleCandidatePresenter.swift` as selected by T021
- [ ] T030 [US1] Map NSEvent input, client marked text, commit, cancel, pass-through, focus, and session lifecycle to the core engine in `Sources/InputMethod/InputController.swift`
- [ ] T031 [US1] Compile the licensed normalized base lexicon into the signed bundle resource in `Sources/Resources/wb86.bin` and record its manifest in `Sources/Resources/wb86.manifest.json`
- [ ] T032 [US1] Add the ten-minute deterministic daily-input integration scenario and expected transcript hashes in `Tests/IntegrationTests/DailyInputIntegrationTests.swift`
- [ ] T033 [US1] Execute and record the independent US1 corpus and cross-client result in `specs/001-native-wubi/evidence/us1-daily-input.md`

**Checkpoint**: US1 is independently functional and passes correctness plus initial 2 ms query checks; it is not yet a complete product release.

---

## Phase 4: User Story 2 - 自然切换输入模式 (Priority: P1)

**Goal**: Add predictable Chinese/direct-English, punctuation, width, simplified/traditional, and shortcut behavior with visible state.

**Independent Test**: Type a scripted Chinese sentence, English identifier, numbers, paired punctuation, full-width sample, and simplified/traditional sample using only documented keys.

### Tests for User Story 2

- [ ] T034 [P] [US2] Write failing mode-transition, composition-resolution, shortcut-conflict, and pass-through tests in `Tests/CoreTests/InputModeTests.swift`
- [ ] T035 [P] [US2] Write failing Chinese/English punctuation, half/full-width, and simplified/traditional known-vector tests in `Tests/CoreTests/TextConversionTests.swift`

### Implementation for User Story 2

- [ ] T036 [P] [US2] Implement bounded punctuation and width conversion tables in `Sources/Core/PunctuationConverter.swift`
- [ ] T037 [P] [US2] Implement the build-time simplified/traditional conversion resource compiler in `Sources/DictionaryCompiler/ScriptConversionCompiler.swift`
- [ ] T038 [US2] Implement read-only simplified/traditional candidate conversion in `Sources/Core/ScriptConverter.swift` and generate `Sources/Resources/script-conversion.bin`
- [ ] T039 [US2] Extend core mode switching, temporary English, composition resolution, and shortcut handling in `Sources/Core/InputEngine.swift`
- [ ] T040 [US2] Add input-menu actions and a non-input-bearing visible mode indicator in `Sources/InputMethod/InputModeController.swift`
- [ ] T041 [US2] Execute and record the independent mixed-language and mode-switch acceptance flow in `specs/001-native-wubi/evidence/us2-input-modes.md`

**Checkpoint**: US2 independently supports mixed daily text and mode recovery without changing US1 candidate semantics.

---

## Phase 5: User Story 3 - 本地学习与管理用户词库 (Priority: P1)

**Goal**: Add bounded local learning, editable user entries, persistent independent snapshots, and a deterministic private mode.

**Independent Test**: Promote a candidate after three selections, persist a custom entry across restart, remove/reset both effects, and prove private mode performs no input-related writes.

### Tests for User Story 3

- [ ] T042 [P] [US3] Write failing snapshot envelope, replacement, retained-backup, interrupted-write, and per-domain recovery tests in `Tests/PersistenceTests/SnapshotWriterTests.swift`
- [ ] T043 [P] [US3] Write failing user-entry validation, duplicate merge, search, edit, delete, and restart tests in `Tests/PersistenceTests/UserLexiconStoreTests.swift`
- [ ] T044 [P] [US3] Write failing three-selection promotion, cap, decay, pruning, disable, clear, and stable-order tests in `Tests/PersistenceTests/LearningStoreTests.swift`
- [ ] T045 [P] [US3] Write failing private-mode no-write and no-learned-ranking tests in `Tests/PrivacyTests/PrivateModeTests.swift`

### Implementation for User Story 3

- [ ] T046 [P] [US3] Implement versioned DataSnapshot envelopes and checksum validation in `Sources/Persistence/DataSnapshot.swift`
- [ ] T047 [US3] Implement staged validation, FileManager replacement, one-backup retention, and startup recovery in `Sources/Persistence/SnapshotWriter.swift`
- [ ] T048 [P] [US3] Implement validated UserLexiconEntry storage, indexing, and immutable generations in `Sources/Persistence/UserLexiconStore.swift`
- [ ] T049 [P] [US3] Implement bounded LearningRecord aggregation, decay epochs, caps, pruning, disable, and clear in `Sources/Persistence/LearningStore.swift`
- [ ] T050 [US3] Merge base, user, fixed-rank, and learned candidates deterministically in `Sources/Core/CandidateRanker.swift`
- [ ] T051 [US3] Implement user-entry add/edit/delete/search services and privacy-safe result types in `Sources/Core/UserLexiconService.swift`
- [ ] T052 [US3] Implement visible private-mode and learning-toggle commands that atomically affect every active session in `Sources/InputMethod/PrivacyModeController.swift`
- [ ] T053 [US3] Add restart, concurrent-session generation, and domain-isolation integration coverage in `Tests/IntegrationTests/PersonalizationIntegrationTests.swift`
- [ ] T054 [US3] Execute and record the independent learning, user lexicon, reset, and 10,000-submit private-mode flow in `specs/001-native-wubi/evidence/us3-personalization.md`

**Checkpoint**: US3 provides controllable personalization without network, input history, cross-session state leakage, or unsafe writes.

---

## Phase 6: User Story 4 - 配置简洁一致的输入体验 (Priority: P2)

**Goal**: Provide a focused settings window for behavior, keys, candidates, learning, privacy, and safe default restoration.

**Independent Test**: Change every setting group, verify preview/live effect and restart persistence, then restore defaults without deleting user lexicon or learning.

### Tests for User Story 4

- [ ] T055 [P] [US4] Write failing settings validation, schema, default, key-conflict, and restore-without-data-loss tests in `Tests/PersistenceTests/SettingsStoreTests.swift`
- [ ] T056 [P] [US4] Write failing keyboard navigation, control labeling, preview, apply, and destructive-confirmation UI tests in `Tests/AccessibilityTests/SettingsWindowTests.swift`

### Implementation for User Story 4

- [ ] T057 [US4] Implement versioned InputSettings validation and immutable generation storage in `Sources/Persistence/SettingsStore.swift`
- [ ] T058 [US4] Implement the on-demand settings window and Input, Keys, Candidates, Learning, User Lexicon, and Privacy groups in `Sources/InputMethod/SettingsWindowController.swift`
- [ ] T059 [P] [US4] Implement key-binding conflict detection and documented default mappings in `Sources/Core/KeyBindingSettings.swift`
- [ ] T060 [P] [US4] Implement candidate page size, layout, font scale, appearance, and safe live-preview application in `Sources/InputMethod/CandidateAppearanceController.swift`
- [ ] T061 [US4] Implement settings apply-at-idle and restore-default semantics without touching UserLexicon or Learning in `Sources/InputMethod/SettingsCoordinator.swift`
- [ ] T062 [US4] Execute and record the independent settings, persistence, appearance, and restore-default flow in `specs/001-native-wubi/evidence/us4-settings.md`

**Checkpoint**: US4 is independently configurable, keyboard navigable, and preserves unrelated personalized data.

---

## Phase 7: User Story 5 - 导入、导出和迁移个人词库 (Priority: P2)

**Goal**: Migrate user vocabulary through explicit local files with bounded validation, deterministic merge, atomic commit, and privacy-safe reporting.

**Independent Test**: Import a 10,000-record mixed-validity fixture, verify counts and atomicity, export both formats, then restore equivalent data in a clean profile.

### Tests for User Story 5

- [ ] T063 [P] [US5] Write failing UTF-8 text and product-archive parse, bound, duplicate, invalid-Unicode, and unknown-version tests in `Tests/ImportExportTests/LexiconImporterTests.swift`
- [ ] T064 [P] [US5] Write failing deterministic export, checksum, optional-learning, privacy-field exclusion, and round-trip tests in `Tests/ImportExportTests/LexiconExporterTests.swift`
- [ ] T065 [P] [US5] Write failing user-cancel, scoped-access-release, and existing-destination preservation panel tests in `Tests/ImportExportTests/FilePanelContractTests.swift`

### Implementation for User Story 5

- [ ] T066 [P] [US5] Implement versioned Mac Wubi archive and documented UTF-8 text codecs in `Sources/ImportExport/LexiconArchiveCodec.swift` and `Sources/ImportExport/LexiconTextCodec.swift`
- [ ] T067 [US5] Implement bounded streaming validation, merge planning, ImportReport counts, and atomic user-lexicon commit in `Sources/ImportExport/LexiconImporter.swift`
- [ ] T068 [US5] Implement deterministic export staging, validation, and destination replacement in `Sources/ImportExport/LexiconExporter.swift`
- [ ] T069 [US5] Implement one-shot NSOpenPanel/NSSavePanel access without persistent bookmarks in `Sources/InputMethod/ImportExportPanelController.swift`
- [ ] T070 [US5] Implement privacy-safe import preview and count-only result UI in `Sources/InputMethod/ImportReportViewController.swift`
- [ ] T071 [US5] Add 10,000-record five-second and interrupted-import integration assertions in `Tests/PerformanceTests/ImportPerformanceTests.swift`
- [ ] T072 [US5] Execute and record the independent import/export/round-trip/privacy result in `specs/001-native-wubi/evidence/us5-import-export.md`

**Checkpoint**: US5 enables migration without automatic scanning, retained external authority, partial writes, or exported input history.

---

## Phase 8: User Story 6 - 安装、升级和可靠恢复 (Priority: P2)

**Goal**: Deliver secure installation, versioned upgrades, per-domain migration, rollback, and corruption isolation across supported systems.

**Independent Test**: Upgrade every supported fixture version, interrupt each replacement stage, corrupt each domain independently, and verify installation plus recovery without weakening macOS security.

### Tests for User Story 6

- [ ] T073 [P] [US6] Write failing sequential-schema, unknown-future-version, idempotency, interruption, and rollback tests in `Tests/MigrationTests/DataMigratorTests.swift`
- [ ] T074 [P] [US6] Write failing base/settings/user/learning corruption-isolation and next-input recovery tests in `Tests/FailureRecoveryTests/DomainRecoveryTests.swift`
- [ ] T075 [P] [US6] Write failing install, upgrade, uninstall-preserve, uninstall-delete, and bundle-replacement shell contract tests in `Tests/ReleaseContractTests/InstallationContractTests.swift`

### Implementation for User Story 6

- [ ] T076 [US6] Implement explicit sequential migrations and unknown-version preservation for all three data domains in `Sources/Persistence/DataMigrator.swift`
- [ ] T077 [US6] Implement per-domain quarantine, validated previous recovery, safe defaults, and current-session reset in `Sources/Persistence/DomainRecoveryCoordinator.swift`
- [ ] T078 [P] [US6] Implement user-level install, upgrade, and uninstall scripts without security bypasses in `Scripts/install.sh`, `Scripts/upgrade.sh`, and `Scripts/uninstall.sh`
- [ ] T079 [P] [US6] Add local ad-hoc, Apple Development, and Developer ID release configuration documentation and strict verification in `Docs/SigningAndDistribution.md` and `Scripts/verify-release.sh`
- [ ] T080 [US6] Add seven-application compatibility fixtures and focus/session scenarios in `Tests/IntegrationTests/CrossApplicationCompatibilityTests.swift`
- [ ] T081 [US6] Add macOS 13/current plus Apple Silicon/Intel release-matrix procedure in `Docs/ReleaseMatrix.md`
- [ ] T082 [US6] Execute interrupted migration, corruption, install, upgrade, uninstall, and rollback scenarios in `specs/001-native-wubi/evidence/us6-lifecycle-recovery.md`
- [ ] T083 [US6] Record the signed hardware/OS compatibility matrix verdict in `specs/001-native-wubi/evidence/release-matrix.md`

**Checkpoint**: US6 supports long-term upgrades and domain recovery with no destructive downgrade or security bypass.

---

## Phase 9: User Story 7 - 验证完全隐私 (Priority: P2)

**Goal**: Make zero network, local data boundaries, private mode, diagnostics redaction, data inventory, and complete deletion independently auditable.

**Independent Test**: Observe network and filesystem behavior through every product flow, compare the documented inventory, then delete each domain and all personalization while preserving base input.

### Tests for User Story 7

- [ ] T084 [P] [US7] Write failing PrivacyStatus inventory, byte-count, domain-delete, delete-all, and base-input-preservation tests in `Tests/PrivacyTests/PrivacyDataTests.swift`
- [ ] T085 [P] [US7] Write failing diagnostics redaction tests with adversarial input, candidate, path, application, and timeline samples in `Tests/PrivacyTests/DiagnosticsRedactionTests.swift`
- [ ] T086 [P] [US7] Write failing zero-network-entitlement and prohibited-framework/symbol release checks in `Tests/ReleaseContractTests/PrivacyReleaseContractTests.swift`

### Implementation for User Story 7

- [ ] T087 [P] [US7] Implement the derived, non-content-bearing privacy inventory in `Sources/Persistence/PrivacyStatus.swift`
- [ ] T088 [US7] Implement per-domain and delete-all coordination with truthful partial-failure reporting in `Sources/Persistence/PrivacyDeletionCoordinator.swift`
- [ ] T089 [US7] Implement the Privacy settings view with purpose, logical location, size, private-mode, and deletion controls in `Sources/InputMethod/PrivacyViewController.swift`
- [ ] T090 [US7] Harden all production diagnostics through fixed event categories and redacted payload-free formatting in `Sources/Core/Diagnostics.swift`
- [ ] T091 [US7] Implement entitlement inspection, process network observation, container diff, log scan, and export scan automation in `Scripts/privacy-audit.sh`
- [ ] T092 [US7] Execute the complete normal/failure/import/upgrade/private-mode privacy audit and record evidence in `specs/001-native-wubi/evidence/us7-privacy-audit.md`
- [ ] T093 [US7] Publish the exact local-data and zero-network product commitment in `Docs/Privacy.md`

**Checkpoint**: US7 turns “完全隐私” into repeatable evidence without collecting production input telemetry.

---

## Phase 10: User Story 8 - 无障碍与键盘优先操作 (Priority: P3)

**Goal**: Make candidate selection and all major settings perceivable and operable with VoiceOver, keyboard navigation, high contrast, scaling, and multiple displays.

**Independent Test**: With VoiceOver and Full Keyboard Access, complete candidate navigation/selection and every major settings change across appearance and display variants.

### Tests for User Story 8

- [ ] T094 [P] [US8] Write failing candidate role, label, value, selected-state, order, action, and focus accessibility tests in `Tests/AccessibilityTests/CandidateAccessibilityTests.swift`
- [ ] T095 [P] [US8] Write failing keyboard-only settings traversal, error-announcement, destructive-confirmation, and focus-order tests in `Tests/AccessibilityTests/SettingsAccessibilityTests.swift`

### Implementation for User Story 8

- [ ] T096 [US8] Implement or complete the candidate accessibility representation selected by T020 in `Sources/InputMethod/AccessibilityAdapter.swift` and the presenter file selected by T021
- [ ] T097 [P] [US8] Implement candidate screen-bounds, scaling, full-screen, multi-display, reduced-motion, and high-contrast behavior in `Sources/InputMethod/CandidateLayoutController.swift`
- [ ] T098 [P] [US8] Complete settings labels, values, focus order, keyboard actions, and announced validation errors in `Sources/InputMethod/SettingsWindowController.swift`
- [ ] T099 [US8] Add VoiceOver and Full Keyboard Access manual scenario definitions without input-text logging in `Tests/AccessibilityTests/ManualAccessibilityScenarios.md`
- [ ] T100 [US8] Execute VoiceOver, Accessibility Inspector, keyboard, appearance, scaling, and multi-display acceptance and record evidence in `specs/001-native-wubi/evidence/us8-accessibility.md`
- [ ] T101 [US8] Re-run the seven-application core input matrix with accessibility features enabled and record deltas in `specs/001-native-wubi/evidence/us8-application-matrix.md`

**Checkpoint**: US8 completes the simple, keyboard-first product experience for assistive-technology users.

---

## Phase 11: Polish & Cross-Cutting Release Gates

**Purpose**: Satisfy constitution-wide quality, performance, documentation, and final release evidence after every desired story is complete.

- [ ] T102 [P] Add absolute wall-clock, percentile reporting, warm-up, corpus metadata, and machine metadata to `Tests/PerformanceTests/ReleasePerformanceTests.swift`
- [ ] T103 [P] Add eight-hour rapid-input, application-switch, session-churn, and memory-trend stress harness in `Tests/PerformanceTests/LongRunStressTests.swift`
- [ ] T104 Optimize query working set and candidate decoding until all release lookup samples meet 2 ms in `Sources/Core/DictionaryIndex.swift` and document before/after evidence in `specs/001-native-wubi/evidence/performance.md`
- [ ] T105 Optimize process allocations, mapped resource residency, user indexes, and learning caches until normal-input RSS stays below 15 MB in `Sources/Core/DictionaryLoader.swift` and document evidence in `specs/001-native-wubi/evidence/memory.md`
- [ ] T106 [P] Finalize Wubi 86 coverage corpus, lexicon manifest, license notices, and reproducible compiler output in `Sources/Resources/wb86.manifest.json`, `Docs/LexiconProvenance.md`, and `Tests/Fixtures/Lexicon/wb86-acceptance.tsv`
- [ ] T107 [P] Write installation, enablement, daily input, modes, settings, personalization, migration, private mode, reset, and uninstall guidance in `Docs/UserGuide.md`
- [ ] T108 [P] Create the constitution-aligned release checklist with architecture, signature, sandbox, privacy, recovery, migration, accessibility, and performance gates in `Docs/ReleaseChecklist.md`
- [ ] T109 Run `Scripts/test.sh` and record the complete automated result in `specs/001-native-wubi/evidence/automated-tests.md`
- [ ] T110 Execute every scenario in `specs/001-native-wubi/quickstart.md` on the declared release matrix and record the final verdict in `specs/001-native-wubi/evidence/quickstart-validation.md`
- [ ] T111 Run `Scripts/build-release.sh`, `Scripts/verify-release.sh`, and `Scripts/privacy-audit.sh` against the final candidate and record immutable command/output summaries in `specs/001-native-wubi/evidence/final-release.md`
- [ ] T112 Review every FR-001...FR-031 and SC-001...SC-013 against evidence, document gaps or PASS, and prohibit release on any gap in `specs/001-native-wubi/evidence/requirements-traceability.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Starts immediately.
- **Foundational (Phase 2)**: Depends on Setup and blocks every story. T019 is a hard stop; T021 depends on T020.
- **US1 (Phase 3)**: Depends on Foundational and establishes complete core input.
- **US2 (Phase 4)**: Depends on US1 state machine and candidate pipeline.
- **US3 (Phase 5)**: Depends on US1; can proceed in parallel with US2 after core input stabilizes.
- **US4 (Phase 6)**: Depends on US2 settings semantics and US3 persistence generations.
- **US5 (Phase 7)**: Depends on US3 user lexicon and snapshot writer; can proceed in parallel with US4.
- **US6 (Phase 8)**: Depends on US3 persistence plus US5 archive/schema contracts.
- **US7 (Phase 9)**: Depends on US3 privacy mode, US4 privacy/settings entry, US5 file boundary, and US6 lifecycle behavior.
- **US8 (Phase 10)**: Depends on US1 candidate presentation and US4 settings UI; may proceed in parallel with US5/US6 after those prerequisites.
- **Polish (Phase 11)**: Depends on all eight stories selected for the complete product release.

### User Story Dependency Graph

```text
Setup -> Foundational -> US1 -> US2 -> US4 -> US7 -> Polish
                         |      |             ^
                         |      +-----------> US8 --+
                         +-> US3 -> US5 -> US6 ------+
                               +-----------> US7
```

### Within Each User Story

- Write the listed tests first and confirm they fail for the intended missing behavior.
- Implement data/value contracts before stores or services.
- Implement stores/services before InputMethodKit or settings UI integration.
- Complete automated tests before generating the story evidence file.
- Re-run prior story suites before marking the current story complete.

## Parallel Opportunities

- **Setup**: T003 and T004 can run in parallel after T001; documentation-free build scripts follow project creation.
- **Foundational**: T008, T009, and T010 can run in parallel; T012, T013, and T017 can run in parallel after models are fixed.
- **US1**: T023...T026 are parallel failing-test lanes; T028 and T029 can run in parallel after T027 contracts stabilize.
- **US2**: T034 and T035 are parallel tests; T036 and T037 are independent conversion implementations.
- **US3**: T042...T045 are parallel tests; T046, T048, and T049 can proceed in separate files after snapshot contracts settle.
- **US4**: T055 and T056 are parallel; T059 and T060 are independent after settings schema is known.
- **US5**: T063...T065 are parallel tests; archive/text codecs can be split within T066 if different owners coordinate the shared test vectors.
- **US6**: T073...T075 are parallel tests; T078 and T079 are parallel release-tooling lanes.
- **US7**: T084...T086 are parallel tests; T087 can proceed independently of diagnostics hardening once the data-domain schema is fixed.
- **US8**: T094 and T095 are parallel; T097 and T098 modify separate UI concerns.
- **Polish**: T102, T103, T106, T107, and T108 are parallel once product behavior is frozen.

## Parallel Examples by User Story

```text
US1: T023 InputEngine tests | T024 query tests | T025 adapter tests | T026 performance tests
US2: T034 mode tests | T035 conversion tests; then T036 punctuation | T037 script compiler
US3: T042 snapshot tests | T043 user lexicon tests | T044 learning tests | T045 private-mode tests
US4: T055 settings storage tests | T056 settings accessibility tests
US5: T063 importer tests | T064 exporter tests | T065 file-panel tests
US6: T073 migration tests | T074 recovery tests | T075 installation tests
US7: T084 data tests | T085 diagnostics tests | T086 release privacy tests
US8: T094 candidate accessibility tests | T095 settings accessibility tests
```

## Implementation Strategy

### Risk-Gated Full Product

1. Complete Setup.
2. Complete Foundational and pass T019; if it fails, stop and revise governance/scope.
3. Complete US1 as the first executable technical slice, but do not market or release it as an MVP.
4. Complete all P1 stories: US1, US2, and US3.
5. Complete P2 stories in dependency order, using allowed parallel lanes.
6. Complete US8 and every cross-cutting release gate.
7. Release only when requirements traceability reports every required FR and SC as PASS.

### Incremental Internal Validation

1. Core input slice -> validate US1 without calling it a product release.
2. Mode and personalization slices -> validate long-form daily input.
3. Settings, migration, lifecycle, and privacy slices -> validate long-term replacement readiness.
4. Accessibility and final performance/release gates -> validate complete product readiness.

### Multi-Lane Execution

After Foundational and US1 stabilize, separate owners can work on US2/US3, then US4/US5/US8, while
US6 and US7 integrate the stable persistence and UI contracts. Shared-file owners must serialize edits to
`InputEngine.swift`, `InputController.swift`, `CandidateRanker.swift`, and `SettingsWindowController.swift`.

## Notes

- `[P]` only marks work in different files without an incomplete dependency.
- Story labels map directly to the eight user stories in spec.md.
- Evidence tasks are part of completion, not optional documentation.
- No new dependency may be added without an explicit constitution-compliant decision.
- Failed architecture, signature, sandbox, privacy, recovery, accessibility, or performance gates block release.
