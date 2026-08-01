# Mac Wubi 86 Native

一个面向 macOS 的原生五笔 86 输入法，目标是用**完全本地、简洁易用、长期可靠**的产品，
替代熟练五笔用户日常依赖的商业输入法。

> **当前状态：设计与任务规划完成，应用实现尚未开始。**
>
> 仓库目前不能构建或安装输入法。`Scripts/`、Xcode 工程和 Swift 源码将在实施阶段按
> [任务清单](specs/001-native-wubi/tasks.md) 创建。

## 产品目标

Mac Wubi 86 Native 不以“能打出几个汉字”的演示为终点，而是完整覆盖长期日常使用：

- 标准五笔 86 简码、全码、单字、词组和重码候选。
- 键盘优先的候选选择、翻页、修码、取消和自动上屏。
- 中文、临时英文、中英文标点、全半角和简繁输出。
- 仅在本机工作的候选学习与用户词库。
- 可查看、编辑、清除、导入和导出的个人词库。
- 简洁的候选、键位、模式、学习和隐私设置。
- 安装、升级、迁移、回退和损坏数据隔离。
- VoiceOver、完全键盘控制、高对比度和多显示器支持。
- Apple Silicon 与 Intel Mac 原生 Universal Binary。

“替代搜狗五笔”描述的是日常功能覆盖目标。本项目与搜狗无关联，也不会复制其品牌、界面、
专有实现、私有数据格式、广告、遥测、云服务或在线内容。

## 核心承诺

### 完全本地与零网络

- 不提供账户、云同步、在线词库、遥测、广告或应用内联网更新。
- 发布 target 不包含网络 client/server entitlement。
- 输入、候选、学习、词库和设置全部在本机处理。
- 外部词库文件只能由用户通过系统打开/保存面板主动选择。

### 输入内容不进入日志

原始按键、组合文本、候选正文、提交文本、应用名称、文档上下文和可重建的输入时间线，
不会进入生产日志、崩溃诊断或导入报告。

### 可控个性化

- 学习数据和用户词条位于 App Sandbox 本地容器。
- 提供显式私密模式与学习总开关。
- 私密模式不写学习数据，已有学习结果也不参与候选排序。
- 用户可以分别删除设置、用户词库、学习数据，或删除全部个性化数据。

Apple 当前公开的 InputMethodKit API 没有可靠的每客户端密码框识别接口，因此项目不作
无法验证的“自动识别所有密码框”承诺，也绝不通过全局按键监听绕过系统安全输入机制。

## 硬性工程约束

| 领域 | 要求 |
|------|------|
| 构建 | Xcode 原生 Swift，单一受支持构建入口 |
| 架构 | Universal Binary：`arm64` + `x86_64` |
| 运行 | Apple Silicon 原生运行，不依赖 Rosetta 2 |
| 依赖 | 核心纯 Swift；无第三方重型运行时，无 C/C++ 动态库 |
| 系统集成 | InputMethodKit、App Sandbox、严格代码签名 |
| 内存 | 正常输入路径常驻内存 `< 15 MB` |
| 响应 | 可识别编码到首批候选 `< 2 ms` |
| 故障 | 非法输入或损坏数据安全复位，不崩溃、不错误上屏 |
| 隐私 | 零网络、零输入正文日志、个性化数据仅本地保存 |

完整治理规则见[项目宪章](.specify/memory/constitution.md)。

## 功能范围

### 当前完整产品范围

- 五笔 86 输入、候选、分页、鼠标/键盘选择及焦点恢复。
- 中英文、标点、全半角和简繁模式。
- 本地候选学习、衰减、清零及私密模式。
- 用户词条搜索、添加、编辑、删除和批量清除。
- 版本化 UTF-8 文本及产品格式导入导出。
- 候选数量、方向、字号、快捷键、自动上屏等设置。
- 版本化快照、原子替换、逐版本迁移和独立域恢复。
- 七类应用兼容、VoiceOver、键盘导航和多显示器验收。

### 当前不包含

- 拼音或五笔拼音混输。
- 五笔 98、新世纪五笔或移动平台。
- 账户、云同步、联网热词、在线更新、遥测或广告。
- 自动扫描、破解或逆向其他输入法的私有词库。
- `z` 键反查、表情面板、日期时间短语等非核心增强；这些可在完整基础产品稳定后另行规格化。

## 设计概览

```text
macOS text client
        │
        ▼
InputMethodKit adapter
  IMKServer / per-session controller / candidate presentation / settings
        │
        ▼
Pure-Swift core
  state machine / Wubi lookup / ranking / modes / conversion
        │
        ├──────────────► signed read-only base dictionary
        │
        ▼
Sandbox-local persistence
  settings / user lexicon / bounded learning snapshots
        │
        ▼
Explicit local import/export through system file panels
```

关键边界：

- `Sources/Core/` 不依赖 AppKit 或 InputMethodKit。
- `Sources/InputMethod/` 是唯一 macOS 输入系统与 UI 适配层。
- 设置、用户词库和学习数据是三个独立、版本化、可恢复的数据域。
- 基础词库是签名 bundle 中的只读、可复现生成资源。
- 不引入配套网络进程、后台更新守护程序或跨进程输入数据通道。

详细架构见[实施计划](specs/001-native-wubi/plan.md)和[数据模型](specs/001-native-wubi/data-model.md)。

## 规格与设计文档

| 文档 | 用途 |
|------|------|
| [Constitution](.specify/memory/constitution.md) | 不可妥协的工程、隐私和发布规则 |
| [Specification](specs/001-native-wubi/spec.md) | 8 个用户故事、31 项功能需求、13 项成功标准 |
| [Research](specs/001-native-wubi/research.md) | Apple 官方资料、技术选择与平台风险 |
| [Plan](specs/001-native-wubi/plan.md) | 技术上下文、边界和计划目录结构 |
| [Data Model](specs/001-native-wubi/data-model.md) | 输入状态、候选、词库、学习、设置和快照模型 |
| [Contracts](specs/001-native-wubi/contracts/) | 事件、词库、持久化、导入导出和无障碍契约 |
| [Tasks](specs/001-native-wubi/tasks.md) | 112 个依赖有序、测试先行的实施任务 |
| [Quickstart](specs/001-native-wubi/quickstart.md) | 最终构建、安装、验收、隐私和性能验证流程 |

## 实施路线

本项目不是 MVP 路线，而是**风险门禁优先的完整产品路线**：

1. **工程与平台门禁**：创建 Xcode 工程、签名、Universal Binary，并验证沙盒化
   InputMethodKit 能被系统发现、启用和跨应用输入。
2. **输入核心**：五笔查询、候选、分页、修码、取消、上屏与性能基线。
3. **完整日常输入**：模式、标点、全半角、简繁和快捷键传递。
4. **本地个性化**：用户词库、候选学习、快照、私密模式。
5. **设置与迁移**：设置 UI、导入导出、升级和故障恢复。
6. **隐私与无障碍**：可审计隐私边界、数据删除、VoiceOver 和键盘导航。
7. **发布门禁**：双架构、签名、沙盒、七类应用、长期压力、15 MB/2 ms 和需求追踪。

首个硬门禁是任务 `T019`。Apple 文档没有明确保证沙盒化第三方 InputMethodKit bundle 在
所有目标版本上的系统加载兼容性；该实机纵切失败时必须停止并重新评估规格或宪章，不能
通过关闭沙盒或增加宽泛例外绕过。

## 构建与运行

### 当前状态

尚未创建 `MacWubi.xcodeproj`、`Sources/` 或 `Scripts/`，因此目前没有可执行构建命令、安装
包或预览版本。

### 计划中的环境

- macOS 13.0 或更高版本。
- Xcode 15 或兼容项目 SDK 的更新版本。
- Apple Silicon Mac；发布验收另需受支持的 Intel Mac。
- 本地 ad-hoc / Apple Development 签名；正式直发版本使用适合渠道的签名与公证流程。

### 计划中的验证入口

以下命令将在对应任务完成后提供；现在仅代表交付契约：

```bash
Scripts/test.sh
Scripts/build-release.sh
Scripts/verify-release.sh /absolute/path/to/MacWubi.app
Scripts/privacy-audit.sh
```

最终发布必须完整执行 [quickstart.md](specs/001-native-wubi/quickstart.md)，并在 Apple Silicon
和 Intel 硬件上验证实际输入法 bundle。

## 词库原则

- 仅使用拥有明确再分发许可和来源记录的五笔 86 数据。
- 规范化过程、编译工具、清单、checksum 和验收语料必须可复现。
- 不导入或逆向任何商业输入法的私有、加密或未授权词库。
- 基础词库只读；用户词条和学习数据永远不会回写基础资源。

词库来源和许可证将在任务 `T014–T015` 中确定。在此之前，仓库不声称包含可分发词库。

## 参与开发

1. 阅读 [AGENTS.md](AGENTS.md) 和[项目宪章](.specify/memory/constitution.md)。
2. 阅读当前规格、计划、契约和数据模型。
3. 从 [tasks.md](specs/001-native-wubi/tasks.md) 选择下一个未阻塞任务。
4. 测试先行，完成最小实现，再运行针对性和相关集成验证。
5. 只有在验证通过并记录必要证据后才勾选任务。

提交变更时请说明：完成的任务 ID、修改文件、用户可见行为、验证命令、宪章影响和剩余风险。

## 项目状态与许可证

- 当前没有发布版本或安装包。
- 当前没有稳定 API 或数据格式兼容承诺；格式将在实现与迁移测试中版本化。
- 项目源代码许可证尚未确定。贡献代码或词库数据前必须先解决相应许可与来源问题。
