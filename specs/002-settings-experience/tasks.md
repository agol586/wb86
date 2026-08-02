# Tasks: 设置体验增强

**Input**: Design documents from `/specs/002-settings-experience/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`

**Tests**: FR-031 与 SC-012 明确要求自动化覆盖。每个实现任务必须先添加或修改目标测试并观察其
失败，再完成最小实现并让目标测试通过；不得把已知失败测试留到该任务提交之后。

**Commit and worktree policy**:

- 实际实现必须在独立 worktree `/Users/agol/repos/wb86/.worktrees/002-settings-experience/`、分支
  `codex/002-settings-experience` 中完成；主工作树只保留规格与协调工作。
- 每个产生仓库变更的任务恰好形成一个提交，提交标题以任务号开头，例如 `T014: ...`；只在该任务
  的目标验证通过后勾选并提交。T001 是无文件变更的 worktree 准备步骤，不产生提交。
- 不把多个任务压成一个提交，也不为同一任务生成多个最终提交；任务内 TDD 的临时状态在提交前整理。
- `InputEngine.swift`、`InputController.swift`、`CandidateRanker.swift`、`SettingsCoordinator.swift`、
  `SettingsWindowController.swift` 和 `MacWubi.xcodeproj/project.pbxproj` 的编辑必须串行。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可在依赖完成后并行，且不会编辑上述共享热点文件。
- **[Story]**: 对应 `spec.md` 中的用户故事。
- 所有路径均相对于独立 worktree 根目录，T001 的路径除外。

---

## Phase 1: Setup（独立 worktree 与基线）

**Purpose**: 隔离实现分支并记录实现前的可复现基线。

- [X] T001 创建并验证 `/Users/agol/repos/wb86/.worktrees/002-settings-experience/` worktree 和 `codex/002-settings-experience` 分支，确认后续命令的工作目录均为该绝对路径
- [X] T002 在独立 worktree 运行 `Scripts/test.sh`、记录 Xcode/macOS/arm64、当前资源清单和测试结果到 `specs/002-settings-experience/evidence/baseline.md`

**Checkpoint**: 独立 worktree 可构建，既有测试基线已记录；不得在主工作树实现产品代码。

---

## Phase 2: Foundational（阻塞所有用户故事）

**Purpose**: 建立完整设置值、会话快照、通用组合键和值对象，使后续故事不会共享可变全局语义。

**⚠️ CRITICAL**: 本阶段完成前不得开始任何用户故事实现。

- [X] T003 [P] 先在 `Tests/PersistenceTests/SettingsStoreTests.swift` 覆盖 schema v2 新安装默认、兼容默认及全部字段校验，再在 `Sources/Persistence/SettingsStore.swift` 定义 `InputSettings` v2、独立默认配置和字段级验证错误
- [X] T004 [P] 先在 `Tests/CoreTests/InputModeTests.swift` 覆盖结构化语言/简繁/全半角预设、五组独立翻页集合与布局枚举，再在 `Sources/Core/KeyBindingSettings.swift` 替换字符串式绑定模型并保留可验证的 legacy preset
- [X] T005 [P] 先在 `Tests/CoreTests/CoreModelTests.swift` 覆盖 1...32 位组合序列、五笔/拼音路由、候选来源和学习键身份，再在 `Sources/Core/CompositionKeySequence.swift`、`Sources/Core/Candidate.swift` 和 `Sources/Core/CompositionState.swift` 实现通用组合与候选值对象
- [X] T006 先在 `Tests/CoreTests/InputEngineTests.swift` 与 `Tests/AdapterContractTests/InputControllerContractTests.swift` 覆盖有序客户端动作的单次执行和失败中止，再在 `Sources/Core/InputEngine.swift` 与 `Sources/InputMethod/InputControllerSession.swift` 将单一 `ClientTextAction` 升级为有序复合动作批次
- [X] T007 在 `Tests/PersistenceTests/SettingsStoreTests.swift` 增加 v2 current 原子保存、读回验证、代次单调和失败不发布测试，并在 `Sources/Persistence/SettingsStore.swift` 实现可发布的 `SettingsSnapshot` 与 v2 save/load
- [X] T008 在 `Tests/IntegrationTests/SettingsIntegrationTests.swift` 先覆盖空闲立即应用、组合独立 pending、最新代次覆盖及新会话取最新值，再在 `Sources/InputMethod/SettingsCoordinator.swift` 和 `Sources/InputMethod/InputControllerSession.swift` 实现主线程串行的会话级 active/pending 快照
- [X] T009 在 `Tests/CoreTests/CandidateQueryTests.swift` 与 `Tests/IntegrationTests/PersonalizationIntegrationTests.swift` 覆盖查询、分页、排名和学习均冻结同一会话策略，再在 `Sources/Core/CandidateRanker.swift` 与 `Sources/InputMethod/PersonalizationCoordinator.swift` 移除输入路径对全局可变语义设置的依赖
- [X] T010 运行 `Scripts/test.sh` 验证基础层并将命令、通过数量和宪章五项影响记录到 `specs/002-settings-experience/evidence/foundation.md`

**Checkpoint**: v2 设置可保存，会话能冻结代次，通用组合/候选/动作模型可供所有故事使用。

---

## Phase 3: User Story 1 - 配置常用初始状态（Priority: P1）🎯 MVP

**Goal**: 用户可以配置新会话初始语言、脚本、宽度、标点和常用行为；保存不会破坏当前组合。

**Independent Test**: 修改全部初始状态，在空闲与组合期间分别保存并创建/重新激活会话；新会话采用
保存值，已有组合完整使用旧快照，中文英文标点与全半角输出确定，重启后值仍存在。

- [X] T011 [US1] 先在 `Tests/CoreTests/TextConversionTests.swift` 覆盖“先标点映射、再转换剩余 ASCII”的简繁/半全角矩阵，再在 `Sources/Core/PunctuationConverter.swift` 和 `Sources/Core/InputMode.swift` 实现确定转换规则
- [X] T012 [US1] 先在 `Tests/CoreTests/InputEngineTests.swift` 覆盖初始模式仅用于新建/重新激活且普通保存不重置临时模式，再在 `Sources/Core/InputEngine.swift` 和 `Sources/InputMethod/InputControllerSession.swift` 分离 runtime policy 应用与 mode 初始化
- [X] T013 [US1] 先在 `Tests/AccessibilityTests/SettingsWindowTests.swift` 覆盖“常用”页 saved/draft、默认值和键盘焦点，再在 `Sources/InputMethod/SettingsWindowController.swift` 构建初始状态、四码/五码、调频、混输、提示和快捷选择控件
- [X] T014 [US1] 先在 `Tests/AccessibilityTests/SettingsAccessibilityTests.swift` 覆盖 Save/Cancel 成功失败反馈、label/value/help 与焦点保持，再在 `Sources/InputMethod/SettingsWindowController.swift` 实现完整 draft 校验、显式保存和取消零写入
- [X] T015 [US1] 在 `Tests/IntegrationTests/SettingsIntegrationTests.swift` 覆盖外观立即刷新、语义设置安全延迟和持久默认不覆盖会话临时状态，并在 `Sources/InputMethod/SettingsCoordinator.swift`、`Sources/InputMethod/CandidateAppearanceController.swift` 和 `Sources/InputMethod/InputControllerSession.swift` 完成区分应用
- [X] T016 [US1] 在 `Tests/IntegrationTests/SettingsIntegrationTests.swift` 增加两个以上客户端分别组合、独立结束和重新激活的端到端测试，并在 `Sources/InputMethod/InputController.swift` 修正会话注册/失活/空闲通知次序
- [X] T017 [US1] 运行 US1 目标 XCTest 与 `Scripts/test.sh`，将默认值、空闲/组合保存和多会话结果记录到 `specs/002-settings-experience/evidence/us1-common-settings.md`

**Checkpoint**: User Story 1 可独立演示和验证，是首个可交付 MVP。

---

## Phase 4: User Story 2 - 自定义高效按键（Priority: P1）

**Goal**: 提供可验证的模式快捷键、五组候选翻页、候选 2/3 快捷选择和 US/系统键盘布局。

**Independent Test**: 在有候选、无候选、第一页、末页、目标候选缺失和系统快捷键场景逐项运行所有
绑定；配置动作准确且每事件一次，未配置/带意外修饰键事件透传，单 Shift 只切换一次。

- [X] T018 [P] [US2] 先在 `Tests/CoreTests/InputModeTests.swift` 建立合法、空值、重复、范围重叠、系统保留和布局不可用表格，再在 `Sources/Core/KeyBindingSettings.swift` 实现字段级 `KeyBindingValidator` 与冲突结果
- [X] T019 [P] [US2] 先在 `Tests/AdapterContractTests/KeyboardLayoutTranslatorTests.swift` 覆盖固定 ANSI-US、模拟 QWERTY/Dvorak、dead key、nil/多 scalar 和布局中途变化，再在 `Sources/InputMethod/KeyboardLayoutTranslator.swift` 实现 US 映射及 ASCII-capable 系统布局快照
- [X] T020 [P] [US2] 先在 `Tests/AdapterContractTests/StandaloneShiftRecognizerTests.swift` 覆盖左右 Shift、长按、双 Shift、组合键、孤立 release、reset 与代次变化，再在 `Sources/InputMethod/StandaloneShiftRecognizer.swift` 实现会话级 timestamp 状态机且不读取 flagsChanged 的 `isARepeat`
- [X] T021 [US2] 先在 `Tests/CoreTests/InputModeTests.swift` 覆盖精确 modifiers、非重复 Control-Shift-F、宽度预设和应用快捷键优先级，再在 `Sources/InputMethod/InputEventMapper.swift` 实现“模式绑定→系统快捷键透传→候选控制→普通输入”的确定映射
- [X] T022 [US2] 在 `Tests/CoreTests/InputModeTests.swift` 覆盖五组翻页的启用集合、双向、空闲、修饰键、页边界及分号/单引号缺失目标，并在 `Sources/InputMethod/InputEventMapper.swift` 和 `Sources/Core/InputEngine.swift` 实现单事件动作与活动组合边界消费
- [X] T023 [US2] 在 `Tests/AdapterContractTests/InputControllerContractTests.swift` 覆盖 flagsChanged 两端透传、release 副作用、失活和 reset，再在 `Sources/InputMethod/InputController.swift` 以 `super.recognizedEvents | flagsChanged` 接入 Shift recognizer 和布局 translator
- [X] T024 [US2] 在 `Tests/CoreTests/InputEngineTests.swift` 覆盖语言/简繁/全半角快捷键安全取消 marked text、隐藏候选且不提交原始编码，并在 `Sources/Core/InputEngine.swift` 完成当前会话模式切换语义
- [X] T025 [US2] 先在 `Tests/AccessibilityTests/SettingsWindowTests.swift` 覆盖“按键”页三个切换预设、五组复选、布局和冲突定位，再在 `Sources/InputMethod/SettingsWindowController.swift` 实现按键页及布局不可用反馈
- [X] T026 [US2] 在 `Tests/AdapterContractTests/InputControllerContractTests.swift` 和 `Tests/IntegrationTests/ModeInputIntegrationTests.swift` 增加完整事件矩阵，验证候选控制、应用快捷键、translator 快照与每事件最多一次动作
- [ ] T027 [US2] 在签名 arm64 开发构建上验证单 Shift、无卡键、点击组合区内外、候选鼠标选择、失活与跨应用透传，并将可复现步骤和结果记录到 `specs/002-settings-experience/evidence/us2-inputmethodkit-events.md`

**Checkpoint**: User Story 2 的全部键位可以独立配置，键盘和 InputMethodKit 边界已自动化并真机验证。

---

## Phase 5: User Story 3 - 控制自动上屏与本地调频（Priority: P1）

**Goal**: 四码唯一、五码首选和自动调频相互独立，无重复提交、错误提交或丢键。

**Independent Test**: 对四码零/一/多候选、五码连续键及调频/私密/禁止学习组合运行固定矩阵；每个
事件至多提交一次，第五码成为新组合首键，关闭调频后排序稳定且零学习写入。

- [X] T028 [US3] 先在 `Tests/CoreTests/InputEngineTests.swift` 覆盖四码零、唯一、多候选与过期页，再在 `Sources/Core/InputEngine.swift` 把四码自动提交修正为仅完整四码恰好一个有效候选
- [X] T029 [US3] 在 `Tests/CoreTests/InputEngineTests.swift` 覆盖五码有/无首选、双开关、下一键不丢失和每事件单提交，再在 `Sources/Core/InputEngine.swift` 实现“提交旧首选→新键 marked text→新候选”的原子复合结果
- [X] T030 [US3] 在 `Tests/AdapterContractTests/InputControllerContractTests.swift` 覆盖复合动作精确客户端调用顺序、任一步失败清理和 pending 设置只在整批结束后应用，再在 `Sources/InputMethod/InputControllerSession.swift` 完成适配器执行与恢复
- [X] T031 [P] [US3] 先在 `Tests/PersistenceTests/LearningStoreTests.swift` 与 `Tests/MigrationTests/DataMigratorTests.swift` 覆盖五笔/拼音 typed learning key、v1 包装迁移和域隔离，再在 `Sources/Persistence/LearningStore.swift` 与 `Sources/Persistence/DataMigrator.swift` 实现 Learning schema v2
- [X] T032 [US3] 在 `Tests/CoreTests/CandidateQueryTests.swift` 与 `Tests/PrivacyTests/PrivateModeTests.swift` 覆盖调频只改变同码同 tier、关闭/私密/禁止学习时既不读分也不写，再在 `Sources/Core/CandidateRanker.swift` 和 `Sources/InputMethod/PersonalizationCoordinator.swift` 实现冻结学习策略
- [X] T033 [US3] 在 `Tests/AccessibilityTests/SettingsWindowTests.swift` 和 `Tests/IntegrationTests/SettingsIntegrationTests.swift` 覆盖四码、五码、调频开关的独立保存/重启/安全延迟，并在 `Sources/InputMethod/SettingsWindowController.swift` 完成控件到 v2 快照的双向绑定
- [X] T034 [US3] 运行四码/五码/调频完整组合矩阵与 `Scripts/test.sh`，将提交次数、客户端动作顺序和学习写入隔离结果记录到 `specs/002-settings-experience/evidence/us3-auto-commit-learning.md`

**Checkpoint**: User Story 3 可独立证明无重复提交、无丢键，并满足私密/关闭学习约束。

---

## Phase 6: User Story 4 - 使用五笔拼音混输和编码提示（Priority: P2）

**Goal**: 使用固定许可资源提供完全离线的连续全拼，与五笔稳定合并、去重并显示可选编码提示。

**Independent Test**: 对仅五笔、仅拼音、双来源、转换后重复、有效前缀、长/非法串和损坏资源运行
固定 fixture；五笔始终优先，文本一次提交，提示不改变身份或排序，断网结果一致。

- [X] T035 [P] [US4] 将固定 commit 的 `pinyin_simp.dict.yaml`、LICENSE、AUTHORS 和来源说明加入 `Sources/Resources/ThirdParty/rime-pinyin-simp/`，在 `Sources/Resources/README.md` 记录 SHA-256、Apache-2.0 与仅构建期用途
- [X] T036 [US4] 先在 `Tests/DictionaryTests/PinyinDictionaryFormatTests.swift` 覆盖 MWPY header、offset/count overflow、checksum、restart/front-code 和 WB86 build ID，再在 `Sources/Core/PinyinDictionaryFormat.swift` 定义纯 Swift 版本化二进制格式与严格 envelope 验证
- [X] T037 [US4] 先在 `Tests/DictionaryTests/PinyinDictionaryCompilerTests.swift` 覆盖 NFC、连续键、非法行、权重、去重、确定排序、64 项上限和提示选择，再在 `Sources/DictionaryCompiler/PinyinDictionaryCompiler.swift` 与 `Sources/DictionaryCompiler/main.swift` 实现可复现编译
- [X] T038 [US4] 运行纯 Swift 编译器两次验证字节一致，提交 `Sources/Resources/pinyin-simp.bin`、`Sources/Resources/pinyin-simp.manifest.json` 和固定 fixture `Tests/Fixtures/Pinyin/pinyin-acceptance.tsv`
- [X] T039 [US4] 先在 `Tests/DictionaryTests/PinyinDictionaryFormatTests.swift` 覆盖截断、乱序、坏 UTF-8、坏引用和错误 WB86 ID 的原子禁用，再在 `Sources/Core/PinyinDictionaryLoader.swift` 实现只读映射、完整边界验证和脱敏结构错误
- [X] T040 [US4] 先在 `Tests/CoreTests/CandidateQueryTests.swift` 覆盖 1...32 位 prefix-exists、exact lookup、分页与每键上限，再在 `Sources/Core/PinyinDictionaryIndex.swift` 实现范围缩小、checkpoint 二分和按页解码
- [ ] T041 [US4] 在 `Tests/CoreTests/CandidateQueryTests.swift` 覆盖 user/base Wubi 优先、pinyin 随后、脚本转换后稳定去重及 tier 内学习，再在 `Sources/Core/CandidateRanker.swift` 实现有界混输合并器
- [ ] T042 [US4] 先在 `Tests/CoreTests/InputEngineTests.swift` 覆盖 `shang` 等有效拼音前缀不触发五码截断、混输关闭兼容和损坏资源复位，再在 `Sources/Core/InputEngine.swift` 接入 prefix/exact 路由与五笔优先规则
- [ ] T043 [US4] 先在 `Tests/AccessibilityTests/CandidateAccessibilityTests.swift` 覆盖提示开关、截断、字号/布局和辅助技术正文优先，再在 `Sources/InputMethod/CandidatePresenter.swift`、`Sources/InputMethod/AccessibilityAdapter.swift` 和 `Sources/InputMethod/CandidateLayoutController.swift` 展示可选五笔编码提示
- [ ] T044 [US4] 在 `Tests/IntegrationTests/DailyInputIntegrationTests.swift` 覆盖共享只读拼音索引、每会话策略和选择学习，再在 `Sources/InputMethod/InputController.swift` 与 `Sources/InputMethod/PersonalizationCoordinator.swift` 装配 MWPY loader/query 且失败时保持五笔可用
- [ ] T045 [US4] 运行离线混输、重复正文、简繁、提示、长串和资源损坏集成测试，将词典 provenance、资源大小和降级结果记录到 `specs/002-settings-experience/evidence/us4-pinyin-mixed-input.md`

**Checkpoint**: User Story 4 完全离线可用，资源许可/来源/格式可复现，损坏时仅降级混输。

---

## Phase 7: User Story 5 - 安全保存、恢复和升级设置（Priority: P2）

**Goal**: 设置在重启和升级后保留；无效、冲突、future 或损坏状态不会覆盖最后有效快照；恢复默认
只影响 Settings。

**Independent Test**: 保存完整组合并模拟重启、v1 升级、future、损坏、各写入中断、确认/取消恢复；
所有有效值保留，错误有具体反馈，future 原字节保留，UserLexicon/Learning 内容和代次不变。

- [ ] T046 [US5] 先在 `Tests/MigrationTests/DataMigratorTests.swift` 加入 golden v1 payload 的全部字段精确映射、兼容默认和幂等测试，再在 `Sources/Persistence/SettingsStore.swift` 与 `Sources/Persistence/DataMigrator.swift` 实现严格私有 `InputSettingsV1` 到 v2 原子迁移
- [ ] T047 [US5] 在 `Tests/PersistenceTests/SettingsStoreTests.swift` 覆盖 future current 字节保留、只读 Save/Restore 拒绝及 supported previous 不覆盖 future，再在 `Sources/Persistence/SettingsStore.swift` 和 `Sources/Persistence/SnapshotWriter.swift` 实现 schema 预检与只读兼容状态
- [ ] T048 [US5] 在 `Tests/MigrationTests/DataMigratorTests.swift` 和 `Tests/PersistenceTests/SnapshotWriterTests.swift` 注入 stage/write/validate/rename 各阶段中断，修正 `Sources/Persistence/DataMigrator.swift` 和 `Sources/Persistence/SnapshotWriter.swift` 使重启总能恢复最后完整快照
- [ ] T049 [US5] 在 `Tests/AccessibilityTests/SettingsWindowTests.swift` 覆盖字段级错误、最后有效 baseline、future 只读提示和焦点定位，再在 `Sources/InputMethod/SettingsWindowController.swift` 与 `Sources/InputMethod/SettingsCoordinator.swift` 实现拒绝保存及可访问反馈
- [ ] T050 [US5] 在 `Tests/PersistenceTests/SettingsStoreTests.swift` 与 `Tests/IntegrationTests/SettingsIntegrationTests.swift` 覆盖恢复确认、取消、I/O 失败和其他域字节/代次不变，再在 `Sources/InputMethod/SettingsWindowController.swift` 和 `Sources/Persistence/SettingsStore.swift` 实现仅 Settings 的原子恢复默认
- [ ] T051 [US5] 在 `Tests/IntegrationTests/SettingsIntegrationTests.swift` 和 `Tests/FailureRecoveryTests/DomainRecoveryTests.swift` 覆盖输入法重启、模拟系统重启、v1 升级、损坏 current/previous 与迁移失败隔离
- [ ] T052 [US5] 运行迁移、持久化、恢复和设置 UI 全套测试，将每个 schema/故障路径及 UserLexicon/Learning checksum 对比记录到 `specs/002-settings-experience/evidence/us5-persistence-recovery.md`

**Checkpoint**: User Story 5 的保存、升级、future 保护和恢复默认均可独立验证且不损害其他数据域。

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: 证明全部设置组合仍满足隐私、性能、无障碍、arm64 与发行约束。

- [ ] T053 [P] 在 `Tests/PrivacyTests/DiagnosticsRedactionTests.swift`、`Tests/PrivacyTests/PrivacyDataTests.swift` 和 `Scripts/privacy-audit.sh` 覆盖零网络、无 monitor/event tap、无输入/拼音/候选/路径日志及 `0700`/`0600` 权限
- [ ] T054 [P] 在 `Tests/PerformanceTests/LookupPerformanceTests.swift` 增加 Wubi-only、pinyin prefix/exact、merge/dedupe/简繁/翻页/全开设置样本，并证明每个已识别样本 `<2 ms` 而非仅 percentile
- [ ] T055 在 `Tests/PerformanceTests/ReleasePerformanceTests.swift` 与 `Scripts/measure-memory.sh` 加入 MWPY 文件大小、共享映射和全功能 Release footprint 测量，必要时调整 `Sources/DictionaryCompiler/PinyinDictionaryCompiler.swift` 的上限/压缩直到 RSS `<15 MB`
- [ ] T056 在 `Tests/PerformanceTests/LongRunStressTests.swift` 与 `Scripts/run-long-stress.sh` 加入多会话设置 churn、混输、调频和翻页负载，运行八小时并把无增长证据记录到 `specs/002-settings-experience/evidence/eight-hour-stress.md`
- [ ] T057 [P] 在 `Tests/AccessibilityTests/SettingsAccessibilityTests.swift`、`Tests/AccessibilityTests/CandidateAccessibilityTests.swift` 和 `Tests/AccessibilityTests/ManualAccessibilityScenarios.md` 完成全部新增控件、错误反馈、提示与键盘/VoiceOver 验收矩阵
- [ ] T058 [P] 在 `Tests/ReleaseContractTests/ReleaseContractTests.swift`、`Tests/ReleaseContractTests/PrivacyReleaseContractTests.swift` 和 `Scripts/verify-release.sh` 验证仅 arm64、无 Intel/Rosetta、无新包/动态库/网络权限、空最小 entitlements 及拼音许可/清单随包分发
- [ ] T059 按 `specs/002-settings-experience/quickstart.md` 运行 `Scripts/test.sh`、开发签名 arm64 build、release verification 和 privacy audit，并把命令与结果记录到 `specs/002-settings-experience/evidence/quickstart.md`；Developer ID 公证、staple 与 Gatekeeper 仍保留为最终发布门禁
- [ ] T060 更新 `README.md`、`Docs/Validation.md` 和 `specs/002-settings-experience/spec.md` 的用户设置说明、FR-001...FR-031/SC-001...SC-012 追踪与实现状态，并确认 `git diff --check` 和独立 worktree 状态干净

**Checkpoint**: 功能实现完成；只有明确标记为最终发布阶段的 Developer ID 公证/Gatekeeper 操作可延后。

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (Phase 1)**: 无代码依赖；T002 依赖 T001。
- **Foundational (Phase 2)**: 依赖 T002；T003/T004/T005 可并行，T006 依赖 T005，T007 依赖
  T003/T004，T008 依赖 T007，T009 依赖 T003/T005，T010 依赖 T003...T009。
- **User Stories**: 都依赖 T010。相同优先级按规格顺序交付；不编辑共享热点文件的任务可提前并行。
- **Polish (Phase 8)**: 依赖 T017、T027、T034、T045、T052 全部完成。

### User story dependencies

- **US1 (P1)**: T011→T012→T013→T014→T015→T016→T017；MVP，无其他故事依赖。
- **US2 (P1)**: T018/T019/T020 可并行；T021 后执行 T022，T023 依赖 T019/T020/T021，T024
  与 T023 串行编辑核心/适配器，T025 依赖 US1 设置窗口基线，最后 T026→T027。
- **US3 (P1)**: T028→T029→T030；T031 可在不编辑共享文件时并行；T032 依赖 T031，T033 依赖
  US1 设置窗口基线，最后 T034。
- **US4 (P2)**: T035 可与前置核心任务并行；T036→T037→T038→T039→T040→T041→T042→T043→
  T044→T045。编译格式、生成资源、loader 必须按此顺序保证可复现。
- **US5 (P2)**: T046→T047→T048；T049/T050 依赖 US1 设置窗口基线并串行编辑，最后 T051→T052。

### Shared-file serialization

- `Sources/Core/InputEngine.swift`: T006 → T012 → T022 → T024 → T028 → T029 → T042。
- `Sources/InputMethod/InputController.swift`: T016 → T023 → T044。
- `Sources/Core/CandidateRanker.swift`: T009 → T032 → T041。
- `Sources/InputMethod/SettingsCoordinator.swift`: T008 → T015 → T049。
- `Sources/InputMethod/SettingsWindowController.swift`: T013 → T014 → T025 → T033 → T049 → T050。

---

## Parallel Opportunities

### User Story 1

US1 主要修改共享会话和窗口文件，应串行完成；T011 的纯 Core 转换工作完成后，T013 的 UI 测试准备
可在不编辑 `InputEngine.swift` 时并行。

### User Story 2

```text
T018 KeyBindingValidator      — Core bindings/tests
T019 KeyboardLayoutTranslator — adapter new file/tests
T020 Shift recognizer         — adapter new file/tests
```

三项在 T010 后可并行，完成后再汇入 T021/T023；不得同时编辑 `InputEventMapper.swift` 或
`InputController.swift`。

### User Story 3

T031 Learning schema v2 可与 T028/T029 的 InputEngine 状态机工作并行；T032 必须等 T031，T030 必须等
T029。最终按提交顺序 rebase 后运行整套 US3 矩阵。

### User Story 4

T035 的来源/许可整理可与 T036 的格式测试准备并行；从 T037 开始资源格式、编译器、产物和 loader
形成严格流水线，不再并行修改共享格式。

### User Story 5

持久化 current/previous/future 路径共享相同文件，T046...T048 必须串行；完成后 T049 的 UI 错误反馈
与 T051 的故障 fixture 可在不同文件上准备，但合并前仍需等待 T050。

### Cross-cutting

T053、T054、T057、T058 在五个故事完成后可并行，分别编辑隐私、性能、无障碍和发行测试；T055、
T056、T059、T060 按资源优化、长压、Quickstart、文档收口顺序完成。

---

## Implementation Strategy

### MVP first

1. 完成 T001...T010，建立独立 worktree 和可复用基础层。
2. 完成 T011...T017，独立交付“常用”设置和会话安全应用。
3. 停止并验证 US1；确认每个任务各有一个通过验证的提交，再开始按键和输入状态机改动。

### Incremental delivery

1. Foundation → US1 常用设置（MVP）。
2. US2 按键配置 → 真机 InputMethodKit 事件回归。
3. US3 自动上屏/调频 → 完整提交与学习矩阵。
4. US4 混输/提示 → 许可、可复现资源和内存硬门禁。
5. US5 升级/恢复 → future 和故障注入。
6. Cross-cutting → 隐私、性能、八小时稳定、无障碍和发布契约。

### Commit verification loop

对每个 T002...T060：检查依赖 → 写目标测试并观察失败 → 实现最小变更 → 运行目标测试与受影响集成
测试 → `git diff --check` → 更新该任务 evidence/勾选状态 → 创建唯一 `Txxx: ...` 提交。若任务没有
通过，不勾选、不提交后续任务；不得用 Intel 适配、第三方运行时或未记录安全例外绕过失败。
