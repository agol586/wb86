# Implementation Plan: 隐私优先的原生五笔 86 输入法

**Branch**: `001-native-wubi` | **Date**: 2026-08-01 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-native-wubi/spec.md`

## Summary

构建一个可长期替代商业五笔产品的原生 macOS 五笔 86 输入法：InputMethodKit 适配层负责
系统输入会话，纯 Swift 核心状态机统一处理编码、模式、候选、分页和故障复位，内存映射
基础词库与分层用户数据提供稳定候选、本地学习、自定义词条、简繁输出和迁移。输入法自身
提供轻量设置窗口与显式本地导入导出，不引入配套常驻进程或网络能力。发布构建同时包含
`arm64` 与 `x86_64`，启用最小 App Sandbox 权限并严格签名；分层验证覆盖长期输入、升级、
无障碍、15 MB/2 ms 门禁和零输入数据外传。

## Technical Context

**Language/Version**: Swift 5 language mode；使用支持所选 macOS SDK 的 Xcode 15 或更新版本

**Primary Dependencies**: Swift 标准库及 Apple 原生 Foundation、AppKit、InputMethodKit、
XCTest；无第三方运行时或库

**Storage**: bundle 内只读、版本化紧凑基础词库；沙盒容器内分别保存设置、用户词库和
有界学习快照；导入导出仅访问用户显式选择的本地文件

**Testing**: XCTest 单元/集成/迁移/故障/性能测试，伪造文本客户端的适配层契约测试，
设置与导入导出 UI 测试，发布 bundle 签名与架构检查，以及七类应用和辅助技术实机验收

**Target Platform**: macOS 13.0 及以上；Universal Binary (`arm64` + `x86_64`)，Apple
Silicon 必须原生运行

**Project Type**: 带设置窗口的后台 macOS 输入法应用 bundle，附不随产品运行的纯 Swift
词库编译与数据检查工具

**Performance Goals**: 预热后的候选查询 p99 小于 2 ms；正常输入路径总常驻内存小于
15 MB；10,000 条导入在 5 秒内完成；八小时压力运行无持续内存或延迟增长

**Constraints**: 纯 Swift 核心；无 C/C++ 动态库和 Rosetta 2；无网络 entitlement；App
Sandbox 只允许容器存储和用户选择文件；生产日志不含输入内容；持久化必须原子、版本化、
可回退；任一数据或状态异常只能隔离所属数据域并复位当前会话

**Scale/Scope**: 单一 macOS 用户、多个彼此隔离的应用会话；一至四位 `a...y` 编码；每页
5...9 项候选；基础词库以覆盖验收而非固定条目数为准，运行时查询工作集目标小于 4 MB；
最多 100,000 个用户词条和 50,000 条有界学习记录；支持设置、迁移、简繁和无障碍，不含
拼音混输、账户、云同步、广告或在线更新

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Gate | Pre-research | Post-design evidence |
|------|--------------|----------------------|
| Apple Silicon 与 Universal Binary | PASS：计划使用标准双架构 Release 构建 | PASS：quickstart 包含 `lipo` 检查及两类硬件验收；无 Rosetta 运行依赖 |
| 纯 Swift 与零重型依赖 | PASS：仅 Swift 与 Apple 系统框架 | PASS：核心、词库编译器和测试均无第三方依赖；词库格式自有且版本化 |
| InputMethodKit、沙盒与签名 | PASS BY DESIGN：使用公开 InputMethodKit 契约并强制最小沙盒权限 | PASS BY DESIGN：适配契约、bundle 元数据、entitlements 与 `codesign` 验证均已纳入；实际加载是首个阻断性实机门禁 |
| 故障安全 | PASS：错误统一转为空闲态 | PASS：状态模型和契约明确词库、编码、客户端错误的原子复位及回归测试 |
| 数据隐私 | PASS：所有个性化仅在容器内，外部文件必须由用户显式选择 | PASS：无网络 entitlement、无输入历史、分域删除和私密模式禁写均有契约与验收 |
| 性能门禁 | PASS：基础词库内存映射、用户数据有界、候选按需解码 | PASS：查询工作集、学习上限、长时压力和绝对指标共同验证 15 MB/2 ms 硬门禁 |

Apple 官方资料未明确承诺沙盒化第三方 InputMethodKit bundle 的系统加载兼容性，因此
该组合目前是“设计合规、运行证据待首个纵切验证”，而不是已证明的平台能力。首个可运行
纵切必须在 macOS 13 及当前支持版本上验证发现、启用、`IMKServer` 连接和跨应用输入；
若最小沙盒 entitlement 无法工作，必须停止后续实现并修订宪章或产品范围，不得静默关闭
沙盒、添加宽泛临时例外或宣称具备 Mac App Store 资格。

## Project Structure

### Documentation (this feature)

```text
specs/001-native-wubi/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── dictionary-format.md
│   ├── input-events.md
│   ├── input-method-adapter.md
│   ├── persistence.md
│   ├── import-export.md
│   └── settings-accessibility.md
└── tasks.md
```

### Source Code (repository root)

```text
MacWubi.xcodeproj/
Sources/
├── InputMethod/
│   ├── AppDelegate.swift
│   ├── InputController.swift
│   ├── CandidatePresenter.swift
│   ├── SettingsWindowController.swift
│   └── AccessibilityAdapter.swift
├── Core/
│   ├── InputEngine.swift
│   ├── CompositionState.swift
│   ├── InputEvent.swift
│   ├── Candidate.swift
│   ├── DictionaryIndex.swift
│   ├── DictionaryLoader.swift
│   ├── CandidateRanker.swift
│   ├── ScriptConverter.swift
│   └── InputSettings.swift
├── Persistence/
│   ├── UserLexiconStore.swift
│   ├── LearningStore.swift
│   ├── SettingsStore.swift
│   ├── SnapshotWriter.swift
│   └── DataMigrator.swift
├── ImportExport/
│   ├── LexiconImporter.swift
│   └── LexiconExporter.swift
├── DictionaryCompiler/
│   └── main.swift
├── Resources/
│   ├── wb86.bin
│   └── script-conversion.bin
└── Supporting/
    ├── Info.plist
    └── MacWubi.entitlements

Tests/
├── CoreTests/
├── AdapterContractTests/
├── DictionaryTests/
├── FailureRecoveryTests/
├── PersistenceTests/
├── MigrationTests/
├── ImportExportTests/
├── AccessibilityTests/
└── PerformanceTests/

Scripts/
├── build-release.sh
└── verify-release.sh
```

**Structure Decision**: 采用单一 Xcode 工程和一个输入法产品 target；设置窗口由输入法进程
按需显示，避免额外常驻组件、App Group 和跨进程用户数据通道。`Core` 不导入 AppKit 或
InputMethodKit；`Persistence` 只处理版本化本地快照；`InputMethod` 是唯一系统框架和 UI
适配边界；构建期工具不进入发布 bundle。测试按风险分组但共享同一工程，避免包管理和
第三方运行时。

## Complexity Tracking

无宪章违规，无需例外或复杂性豁免。
