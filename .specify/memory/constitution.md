<!--
Sync Impact Report
- Version change: 2.1.0 -> 3.0.0
- Modified principles:
  - III. InputMethodKit 合规与严格签名（改为 Developer ID、Hardened Runtime 与公证分发）
  - V. 本地数据隐私（由沙盒强制隔离改为明确路径、权限与代码边界）
- Added sections: none
- Removed sections: none
- Follow-up TODOs: none
-->
# Mac Wubi Input Method (Native) Constitution

## Core Principles

### I. Apple Silicon 原生优先
项目必须使用 Xcode 和纯 Swift 为 Apple Silicon 原生编译，并产出 `arm64` 架构的发布
候选。产品不支持 Intel Mac，运行时不得依赖 Rosetta 2。发布候选产物必须通过架构检查，
并在 Apple Silicon 设备上验证原生加载。正常输入路径的常驻内存必须小于 15 MB，首字
响应时间必须小于 2 ms；性能结论必须由可重复的基准测试支持。

理由：明确聚焦 Apple Silicon 可减少不再需要的架构、签名和硬件验证成本，同时保持原生
性能与可复现构建；资源预算可防止输入法这一常驻系统组件侵占用户资源。

### II. 核心引擎纯 Swift 与零重型依赖
编码解析、候选生成、词库检索和输入状态管理等核心引擎必须以纯 Swift 实现。核心引擎
不得链接 C/C++ 动态库，也不得引入外部重型运行时或框架。新增第三方依赖必须证明无法
由 Swift 标准库或 Apple 系统框架合理替代，并在变更评审中记录体积、性能、安全与维护
成本；任何进入核心引擎的外部重型依赖均视为违反本原则。

理由：减少二进制、ABI 和供应链风险，确保目标架构可由 Xcode 原生、可复现地构建。

### III. InputMethodKit 合规与严格签名
输入法实现必须遵循 macOS InputMethodKit 及 `IMKServer` 协议约定。产品不采用 App
Sandbox，也不以 Mac App Store 为分发渠道；正式发行必须使用 Developer ID Application
签名、Hardened Runtime、安全时间戳和 Apple 公证，并验证 stapled ticket 与 Gatekeeper
评估。开发环境可使用 Apple Development 签名；ad-hoc 仅限不进入系统输入源门禁的纯构建
检查。不得申请网络、Apple Events、Mach 注册/查找临时例外或 Hardened Runtime 弱化例外，
除非先修订宪章。不得关闭 Gatekeeper、SIP 或其他系统安全机制来使输入法加载。

理由：macOS 会拒绝身份、权限或签名不一致的输入法组件，合规流程是可靠安装与运行的
前提。

### IV. 故障安全与优雅降级
词库读取或检索失败、非法编码、损坏数据以及无法识别的输入状态不得导致崩溃、死循环
或残留候选。引擎必须捕获此类失败，清空组合输入缓冲区和相关候选状态，并安全返回可
继续输入的空闲状态。所有这些失败路径必须有自动化回归测试，且不得记录原始用户输入。

理由：输入法运行在所有应用的关键交互路径中，局部数据错误不得扩散为宿主应用或输入
会话故障。

### V. 本地数据隐私
用户按键、组合文本、候选选择、用户词频及其他可推断输入内容的数据必须仅在本机处理；
持久化只能位于 `~/Library/Application Support/org.macwubi.inputmethod/`，目录权限必须为
`0700`，数据文件权限必须为 `0600`。项目不得上传、遥测、同步或向其他进程披露此类数据，也不得
在日志、崩溃信息或调试产物中写入原始输入内容。持久化数据必须限定为实现输入法功能
所必需的最小集合，并遵循明确的删除与重置路径。

理由：输入法可接触高度敏感内容，本地隔离和数据最小化是不可妥协的信任边界。

## 工程与性能约束

- 支持的构建入口必须是受版本控制的 Xcode 工程或工作区，发布 Swift 编译设置必须仅包含
  原生 `arm64` 架构。
- 核心运行路径只能使用 Swift 标准库与 Apple 原生系统框架；不得依赖 Rosetta 2 或
  C/C++ 动态库。
- 性能基准必须定义测试机型、macOS 版本、构建配置、词库规模、样本量及统计口径。
  内存小于 15 MB 和首字响应小于 2 ms 的门禁必须在发布候选构建上测量。
- 产品签名 entitlements 必须为空或仅包含经宪章批准的 Hardened Runtime 能力；禁止 App
  Sandbox、网络、Apple Events、Mach 临时例外和 `get-task-allow` 出现在分发构建中。
- 日志必须采用不包含用户原始输入的结构化事件；生产构建不得启用可泄露输入内容的
  调试日志。

## 开发流程与质量门禁

- 每项变更必须说明其对 Apple Silicon 原生构建、核心依赖、InputMethodKit 合规、故障恢复、隐私和
  性能预算的影响；不适用项也必须明确标记。
- 合并前必须运行与变更相关的单元测试和集成测试。涉及词库或解析的变更必须覆盖无效
  编码、损坏词库、检索失败与缓冲区复位场景。
- 发布候选必须验证主可执行文件仅包含 `arm64` 架构、Developer ID 签名、Hardened
  Runtime、最小 entitlements、公证票据、Gatekeeper 评估以及在 Apple Silicon 上的原生加载；
  同时必须执行内存和首字响应基准。
- 评审发现违反任一 Iron Rule 时不得合并。确需改变规则时，必须先通过宪章修订流程，
  不得以临时例外、隐藏开关或未记录豁免绕过。
- 验证证据必须可复现，并随变更记录测试命令、关键结果和已知风险。

## Governance

本宪章是项目工程决策的最高约束；规范、计划、任务和实现与其冲突时，必须以本宪章为准。
修订必须以书面变更提出，列明动机、受影响原则、兼容性影响、迁移方案和验证证据，并在
实施依赖该修订的代码前完成评审与批准。

宪章版本遵循语义化版本：删除原则、削弱不可协商约束或不兼容地重定义治理规则使用
MAJOR；新增原则、章节或实质扩展治理要求使用 MINOR；不改变含义的澄清和文字修正使用
PATCH。每次修订必须同步更新顶部 Sync Impact Report、版本和 Last Amended 日期。

所有规格与变更评审必须逐项检查五项核心原则及质量门禁。复杂性、权限扩展、依赖引入和
性能预算偏差必须有明确依据；若无法证明合规，变更必须停止。维护者应在每个发布候选上
复核构建架构、签名、公证、Hardened Runtime、故障恢复、隐私和性能证据。

**Version**: 3.0.0 | **Ratified**: 2026-08-01 | **Last Amended**: 2026-08-01
