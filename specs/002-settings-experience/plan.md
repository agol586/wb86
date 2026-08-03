# Implementation Plan: 设置体验增强

**Branch**: `002-settings-experience` (logical feature identifier; no Git branch hook configured) | **Date**: 2026-08-03 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-settings-experience/spec.md`

**Note**: This template is filled in by the `$speckit-plan` command; its definition describes the execution workflow.

## Summary

在现有原生 macOS 五笔输入法上增加“常用”和“按键”两组可持久化设置，并把自动上屏、
本地调频、五笔拼音混输、编码提示、多组翻页键和模式切换键纳入同一套经验证的会话级策略。
实现采用纯 Swift schema v2 设置快照、显式 v1 迁移、按会话代次安全应用、状态化事件映射器，
会话内独立修饰键状态机，以及构建期编译、运行期只读内存映射的本地拼音资源。输入引擎以有序复合动作处理第五码，
候选查询以五笔优先、拼音随后、按显示文本去重；设置窗口只通过协调器发布完整有效快照，
二码/三码五笔查询复用 WB86 两字母 prefix range 追加以精确候选开头的本地词组，精确候选保持优先，
并在高级页集中提供私密模式与本地学习运行时控制，不创建额外状态栏项目。

针对独立 Shift 在 Codex、VS Code、Chrome 等 Chromium/Electron 客户端不生效的问题，废弃
“消费 modifier press 以换取 release 交付”的 T076 路径。新设计以 Squirrel 的适配边界为参照：
先于客户端代理解析观察活动 IMK 会话交付的 `flagsChanged`，以聚合 modifier flags 的会话级变化
识别独立点击，普通 modifier edge 保持透传。客户端对象暂时不可用时不得丢弃或重置该 edge；只有
在具备安全文本操作条件时才取消组合并切换模式。该方向必须先用契约测试证明，再由 TextEdit、iTerm、
Codex、VS Code 和 Chrome 的签名构建实测共同验收。

## Technical Context

**Language/Version**: Swift 5（由受版本控制的 Xcode 工程构建）

**Primary Dependencies**: Foundation；仅在适配层使用 AppKit、InputMethodKit；无第三方运行时或包管理依赖

**Storage**: `~/Library/Application Support/org.macwubi.inputmethod/` 中独立版本化、原子替换的设置与学习快照；应用包内只读词典、清单、许可及来源材料

**Testing**: XCTest 单元/契约/集成/迁移/故障恢复/隐私/性能测试及既有 shell 发布验证脚本；增加源码契约证明不存在屏幕阅读器专用适配

**Target Platform**: macOS 13.0+，仅 Apple Silicon `arm64`；不支持 Intel Mac 或 Rosetta 2

**Project Type**: InputMethodKit 输入法应用 + 纯 Swift 构建期词典编译工具

**Performance Goals**: 每个已识别的五笔、拼音或合并查询样本到首批候选可用均 `< 2 ms`；正常输入常驻内存 `< 15 MB`；模拟 30 个逻辑输入日并累计提交至少 1,000,000 个中文字符的压力负载无持续内存或延迟增长

**Constraints**: 完全离线；核心层不得导入 AppKit/InputMethodKit；modifier edge 必须先于客户端代理解析且普通 edge 透传；不得全局监听按键、轮询系统 modifier 状态或按应用身份分支；不得记录输入内容、应用身份或可重建时间线；资源损坏时有界降级；设置保存不得在输入路径执行磁盘 I/O；明确不支持且不实现 VoiceOver/屏幕阅读器专用候选树、公告或焦点

**Scale/Scope**: 34 项功能需求、四组设置页、约 20 个用户设置字段、2 个运行时隐私控制、5 组独立翻页键、3 类模式切换和一个本地连续全拼候选源；支持多个并发输入会话

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Design Gate

| Gate | Status | Design evidence |
|------|--------|-----------------|
| Apple Silicon 原生 | PASS | Xcode 继续以 `ARCHS=arm64`、macOS 13+ 构建；不增加 Intel/Rosetta 路径。 |
| 纯 Swift、零重型依赖 | PASS | 设置、状态机、拼音解析和构建期编译均为 Swift；运行时只用 Apple 系统框架。 |
| InputMethodKit 与签名 | PASS WITH PHYSICAL GATE | IMK 适配边界先观察会话已交付的 modifier edge，再解析客户端代理；普通 edge 透传。签名构建仍须在 TextEdit、iTerm、Codex、VS Code、Chrome 实测，不以单一客户端或单元测试代替。 |
| 故障安全 | PASS | 设置、拼音资源、学习数据分别验证和降级；任何失败清理过期候选且不提交原始编码。 |
| 本地数据隐私 | PASS | 拼音为包内只读资源；设置/学习保留在批准目录；无网络、全局键盘监听或输入内容日志。 |
| 性能和发布门禁 | PASS WITH MEASUREMENT REQUIRED | 采用共享只读映射和有界查询；实现后仍必须以全功能发布构建证明 `<2 ms`、`<15 MB`，并在 30 个逻辑输入日、至少 1,000,000 个已提交中文字符的确定性负载中证明稳定。 |

### Post-Design Gate

Phase 1 数据模型和契约未引入宪章偏差。拼音数据作为经许可、固定来源、构建期转换的资源，
不是运行时依赖；状态化 Shift/Control/Caps Lock 检测只处理活动 IMK 会话收到的事件，并且不依赖
`sender` 必须能转换为 `IMKTextInput` 才观察 modifier edge；未知未来设置快照保持只读，不会被旧程序
覆盖。InputMethodKit 项保持 `PASS WITH PHYSICAL GATE`，在五类目标客户端全部完成真机矩阵前不得宣称
跨应用修复完成；性能项保留为实现和发布阶段的硬测量门禁。

## Project Structure

### Documentation (this feature)

```text
specs/002-settings-experience/
├── plan.md              # This file ($speckit-plan command output)
├── research.md          # Phase 0 output ($speckit-plan command)
├── data-model.md        # Phase 1 output ($speckit-plan command)
├── quickstart.md        # Phase 1 output ($speckit-plan command)
├── contracts/           # Phase 1 output ($speckit-plan command)
└── tasks.md             # Phase 2 output ($speckit-tasks command - NOT created by $speckit-plan)
```

### Source Code (repository root)

```text
MacWubi.xcodeproj/
Sources/
├── Core/                # 设置值、组合路由、候选合并、输入状态机；不导入 UI 框架
├── Persistence/         # Settings/Learning schema 迁移、快照、恢复和权限
├── DictionaryCompiler/  # 固定来源拼音数据的纯 Swift 编译与清单生成
├── InputMethod/         # IMK 事件、会话、普通候选显示与设置窗口；无屏幕阅读器专用适配
├── Resources/           # 只读五笔/拼音二进制、清单、来源和许可
└── Supporting/          # Info.plist 与无新增权限的 entitlements
Tests/
├── CoreTests/
├── AdapterContractTests/
├── DictionaryTests/
├── PersistenceTests/
├── MigrationTests/
├── FailureRecoveryTests/
├── PrivacyTests/
├── PerformanceTests/
├── ReleaseContractTests/
└── IntegrationTests/
Scripts/
Docs/
```

**Structure Decision**: 保留既有单一 Xcode 工程和分层目录。纯业务模型、混输和状态机进入
`Sources/Core/`；文件格式与迁移进入 `Sources/Persistence/`；AppKit/InputMethodKit 事件与设置
窗口只进入 `Sources/InputMethod/`；资源转换复用 `Sources/DictionaryCompiler/`，不引入新服务、
守护进程、包管理器或备用构建入口。

## Chromium/Electron Modifier Lifecycle Redesign

### 已证伪方向

- T076 的“配置 modifier press 和成功 release 返回 handled”与 Squirrel 的正常 `flagsChanged`
  透传行为不一致，并已在 Codex、VS Code、Chrome 的实测中失败。实现阶段第一步必须回滚这组返回语义，
  相关测试改为断言普通 press/release 透传。
- `keyCode=0` 的唯一 flag-delta 推断仅保留为远程桌面/异常客户端兼容，不再被视为 Chromium 修复。
- 不采用 global monitor、event tap、modifier 轮询、应用 bundle ID 特判或生产键盘日志。

### 目标事件路径

1. `InputController.handle` 收到活动 IMK 会话事件后，先把 `flagsChanged` 的 keyCode、聚合 flags、
   timestamp 和设置代次交给会话级 recognizer；此步骤不得依赖 `sender` 可转换为 `IMKTextInput`。
2. recognizer 以 flag delta 和目标 modifier 类别维护 `lastModifierFlags`、待定开始时间和歧义状态；
   精确 keyCode 只用于增强左右键/交错判定，不作为观察 release 的前置条件。
3. 普通 modifier press/release 返回未处理。只有完成一个有效独立点击时产生一次内部模式动作；该动作
   与 adapter 是否消费原始 `flagsChanged` 分离。
4. 随后才解析或复用当前 client proxy。client 可用时沿既有输入会话路径安全取消组合并切换；client
   不可用且会话空闲时允许只改变会话模式；client 不可用且存在 marked composition 时失败关闭：清除
   recognizer 待定状态，不提交文本、不盲目切换。
5. 普通 activation/deactivation 不得无条件擦除刚收到的 modifier edge。首次事件、设置代次变化、
   controller 关闭、非 modifier 键、超时、多 flag 同变或无法证明配对时执行显式 resync/失效，确保
   孤立 release 永远不会触发切换。

### 实施与验证阶段

1. **回滚与测试基线**：撤销 T076 handled 语义，并把这次失败记录为已证伪实验；不删除仍有独立价值的
   `keyCode=0` 有界推断。
2. **适配边界重构**：先写契约测试，再把 modifier observation 移到 client proxy guard 之前；覆盖
   press/release 两端分别为有效、nil、不可转换 sender 的全部组合。
3. **状态机替换**：改用 Squirrel/librime 风格的聚合 flag transition/category 模型，覆盖左右键交错、
   重复、长按、组合键、重复 edge、多 flag 同变和孤立 release。
4. **生命周期与故障安全**：测试 activation/deactivation 穿插于两端、设置代次变化、空闲无 client、
   组合中无 client；任何不确定状态均不切换、不提交文本。
5. **自动化门禁**：运行目标 adapter/core 测试、完整 `Scripts/test.sh`、Release 构建与
   `Scripts/verify-release.sh`；静态隐私检查确认无 monitor、tap、轮询、app-specific 分支和敏感日志。
6. **物理门禁**：重新安装签名 arm64 包，完全退出并重开 TextEdit、iTerm、Codex、VS Code、Chrome，
   逐项验证单 Shift、Shift+字母、Command+Shift、长按、重复、左右交错及应用切换。五类应用全部通过
   后才能关闭问题。

### 停止条件

若 client-independent routing 完成后，Chromium/Electron 仍未向当前 IMK controller 交付可配对的
`flagsChanged`，立即停止代码绕行。不得扩大权限或增加全局输入观察；应将 FR-014 的跨客户端物理门禁
记录为失败，并回到规格决策，选择 Caps Lock、显式组合键或限定支持范围。

### T082 失败后的限定实验

2026-08-03 的 T082 在 TextEdit、iTerm、Codex、VS Code、Chrome 全部失败。安装包哈希、装载路径和
`standaloneShift` 设置快照均已核对，因此不能再把失败归因于旧包或客户端代理。

复核 Squirrel 主干 `7b4a314a05c465e99bc98bcf38006c07c3b7b901` 后，保留最后一个限定假设。
Chrome 固定序列进一步证明根因不是 activate/deactivate 本身，而是 MacWubi 把 Command press/release
作为“错误 modifier”后永久停留在 `disqualified`，导致 Command-Tab、Command-L 后第一次 Shift 只能
清除坏状态。Phase 14 只允许让已完整松开的非目标 modifier 恢复 idle，并允许当前仅有目标 modifier
且 keyCode 精确时排除历史 stale flags；维持 controller close、设置变化、组合键、非 modifier key 和
故障复位的拒绝边界。不得引入 monitor、event tap、轮询、宿主应用识别或额外权限；再次物理失败即
执行上述停止条件。

### VS Code physical duplicate-edge evidence

经自动 Shift 校准的临时分类诊断包证明，VS Code 对实体左右 Shift 的每个 press/release 连续交付两次
相同 aggregate flags。旧 recognizer 把重复 press 从 eligible 改为 disqualified，又把重复 release
从 idle 改为 disqualified，因此永远不触发。Squirrel 对 `lastModifiers == modifiers` 有显式幂等分支。
MacWubi 同样必须把零 flag-delta edge 当作重放忽略，只允许非零 delta 推进状态；不消费原事件，也不
放宽多 flag、组合键、长按或孤立 release 的拒绝边界。

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| None | N/A | N/A |
