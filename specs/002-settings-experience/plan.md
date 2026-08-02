# Implementation Plan: 设置体验增强

**Branch**: `002-settings-experience` (logical feature identifier; no Git branch hook configured) | **Date**: 2026-08-02 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-settings-experience/spec.md`

**Note**: This template is filled in by the `$speckit-plan` command; its definition describes the execution workflow.

## Summary

在现有原生 macOS 五笔输入法上增加“常用”和“按键”两组可持久化设置，并把自动上屏、
本地调频、五笔拼音混输、编码提示、多组翻页键和模式切换键纳入同一套经验证的会话级策略。
实现采用纯 Swift schema v2 设置快照、显式 v1 迁移、按会话代次安全应用、状态化事件映射器，
以及构建期编译、运行期只读内存映射的本地拼音资源。输入引擎以有序复合动作处理第五码，
候选查询以五笔优先、拼音随后、按显示文本去重；设置窗口只通过协调器发布完整有效快照。

## Technical Context

**Language/Version**: Swift 5（由受版本控制的 Xcode 工程构建）

**Primary Dependencies**: Foundation；仅在适配层使用 AppKit、InputMethodKit；无第三方运行时或包管理依赖

**Storage**: `~/Library/Application Support/org.macwubi.inputmethod/` 中独立版本化、原子替换的设置与学习快照；应用包内只读词典、清单、许可及来源材料

**Testing**: XCTest 单元/契约/集成/迁移/故障恢复/隐私/无障碍/性能测试及既有 shell 发布验证脚本

**Target Platform**: macOS 13.0+，仅 Apple Silicon `arm64`；不支持 Intel Mac 或 Rosetta 2

**Project Type**: InputMethodKit 输入法应用 + 纯 Swift 构建期词典编译工具

**Performance Goals**: 每个已识别的五笔、拼音或合并查询样本到首批候选可用均 `< 2 ms`；正常输入常驻内存 `< 15 MB`；八小时压力测试无持续增长

**Constraints**: 完全离线；核心层不得导入 AppKit/InputMethodKit；不得全局监听按键；不得记录输入内容；资源损坏时有界降级；设置保存不得在输入路径执行磁盘 I/O

**Scale/Scope**: 31 项功能需求、两组设置页、约 20 个用户设置字段、5 组独立翻页键、3 类模式切换和一个本地连续全拼候选源；支持多个并发输入会话

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Design Gate

| Gate | Status | Design evidence |
|------|--------|-----------------|
| Apple Silicon 原生 | PASS | Xcode 继续以 `ARCHS=arm64`、macOS 13+ 构建；不增加 Intel/Rosetta 路径。 |
| 纯 Swift、零重型依赖 | PASS | 设置、状态机、拼音解析和构建期编译均为 Swift；运行时只用 Apple 系统框架。 |
| InputMethodKit 与签名 | PASS | 仅扩展既有 IMK 适配边界；无 App Sandbox、网络、Apple Events、Mach 或 Hardened Runtime 例外。 |
| 故障安全 | PASS | 设置、拼音资源、学习数据分别验证和降级；任何失败清理过期候选且不提交原始编码。 |
| 本地数据隐私 | PASS | 拼音为包内只读资源；设置/学习保留在批准目录；无网络、全局键盘监听或输入内容日志。 |
| 性能和发布门禁 | PASS WITH MEASUREMENT REQUIRED | 采用共享只读映射和有界查询；实现后仍必须以全功能发布构建证明 `<2 ms`、`<15 MB` 与八小时稳定。 |

### Post-Design Gate

Phase 1 数据模型和契约未引入宪章偏差。拼音数据作为经许可、固定来源、构建期转换的资源，
不是运行时依赖；状态化 Shift 检测只处理活动 IMK 会话收到的事件；未知未来设置快照保持只读，
不会被旧程序覆盖。所有 Gate 继续通过，性能项保留为实现和发布阶段的硬测量门禁。

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
├── InputMethod/         # IMK 事件、会话、候选显示、设置窗口与无障碍
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
├── AccessibilityTests/
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

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| None | N/A | N/A |
