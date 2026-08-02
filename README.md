# Mac Wubi 86 Native

面向 Apple Silicon Mac 的原生五笔 86 输入法。产品使用 Swift、Xcode 和 InputMethodKit，
完全本地运行，不含账户、云同步、遥测、广告或网络更新。

## 当前状态

核心输入、模式、候选、本地学习、用户词库、设置、导入导出、版本化快照、恢复和隐私功能
已经实现，并有自动化测试。设置体验增强已覆盖本地五笔拼音混输、完整模式/按键配置、
安全延迟生效、原子持久化和恢复默认。发布仍被实机 macOS 13/当前系统矩阵、
30 天实际用户替代研究、首次用户研究以及最终 Developer ID 公证门禁阻塞；30 个逻辑输入日、
100 万提交汉字的自动压力门禁已通过。仓库当前没有
可对外发布的最终安装包。

## 支持范围

| 领域 | 当前约束 |
|---|---|
| 硬件 | 仅 Apple Silicon，精确 `arm64`；不支持 Intel Mac 或 `x86_64` |
| 系统 | macOS 13.0 或更高 |
| 构建 | Xcode 工程是唯一受支持的产品构建入口 |
| 分发 | 非 Mac App Store；Developer ID + Hardened Runtime + 公证 + Gatekeeper |
| 沙箱 | InputMethodKit 直发产品不使用 App Sandbox |
| 依赖 | 核心纯 Swift，无第三方运行时或 C/C++ 动态库 |
| 隐私 | 零网络、零输入正文日志、数据仅存本地 Application Support |
| 性能 | 候选 `<2 ms`，正常输入 physical footprint `<15 MiB`；30 日/100 万提交汉字无持续增长 |
| 辅助技术 | 明确不支持 VoiceOver、旁白实用工具、Accessibility Inspector 或屏幕阅读器专用朗读、焦点、选择和设置导航 |

Intel Mac、Rosetta 2、Universal Binary、云候选/在线拼音、双拼/模糊音、五笔 98、新世纪五笔、账户、云同步、
在线词库、遥测和广告都不属于当前范围。

## 已实现功能

- 五笔 86 一至四码、简码、全码、单字、词组和稳定重码候选。
- 空格、数字、鼠标选择，分页、修码、取消、四码自动上屏和快捷键安全传递。
- 中英文、标点、全半角、简繁输出及状态菜单。
- 完全本地的五笔优先/全拼随后混输、显示文本去重、简繁转换和可关闭五笔编码提示。
- 四码唯一、五码首选、自动调频、分号/单引号候选 2/3 快捷键均可独立开关。
- Shift 等模式切换键、五组翻页键和 US/跟随系统键盘布局可配置并在保存前校验冲突。
- 本地有界学习、用户词条管理、私密模式和分域删除；私密与本地学习状态集中在高级设置页，
  不额外占用菜单栏。
- 版本化文本/产品格式导入导出、原子快照、逐版本迁移和损坏隔离。
- 候选/按键/学习/隐私设置，普通键盘焦点和多显示器布局适配。
- 系统级安装、升级、回滚、保留数据卸载和显式删除数据脚本。

“替代商业五笔”只表示覆盖熟练用户的日常工作流，不复制任何其他产品的品牌、专有实现、
私有格式、广告、遥测或在线服务。

## 构建与验证

环境需要 Apple Silicon Mac 和 Xcode。常用入口：

```bash
Scripts/test.sh
Scripts/build-release.sh
Scripts/verify-release.sh /绝对路径/MacWubi.app
Scripts/privacy-audit.sh /绝对路径/MacWubi.app
```

月度等效输入量门禁使用 `Scripts/run-long-stress.sh /绝对路径/MacWubi.app 1000000`；它模拟
30 个逻辑输入日并只统计实际提交汉字，不按墙钟时间等待。内存门禁使用
`Scripts/measure-memory.sh /绝对路径/MacWubi.app`（也接受 PID）。最终发布还必须完成
[设置增强 quickstart](specs/002-settings-experience/quickstart.md)、基础产品
[quickstart](specs/001-native-wubi/quickstart.md)和[发布清单](Docs/ReleaseChecklist.md)，不能用
自动化 fixture 替代实机应用兼容或公证验证。

安装、启用、键位、模式、个性化、迁移、私密模式、重置和卸载说明见
[用户指南](Docs/UserGuide.md)。

## 架构与数据边界

```text
macOS text client
        │
        ▼
InputMethodKit adapter (per-session state, candidate/settings UI)
        │
        ▼
Pure-Swift core (state machine, lookup, ranking, modes)
        │
        ├── signed read-only base dictionary
        ▼
versioned local snapshots (Settings / UserLexicon / Learning)
```

`Sources/Core/` 不导入 AppKit/InputMethodKit。可变数据只写入
`~/Library/Application Support/org.macwubi.inputmethod/`，目录权限 `0700`、文件权限 `0600`。
外部文件只在用户主动打开/保存期间访问，不默认保留 security-scoped bookmark。

## 词库与许可证

基础五笔词库来自固定提交的 `rime/rime-wubi`；本地全拼词库来自固定提交的
`rime/rime-pinyin-simp`。对应源、`AUTHORS`、LGPL-3.0-only/Apache-2.0 `LICENSE`、生成 manifest
和纯 Swift 可复现编译链均随资源保存。详见
[LexiconProvenance.md](Docs/LexiconProvenance.md)。项目 Swift 源代码许可证尚未确定；这不改变
第三方词库和简繁转换数据各自的许可证义务。

## 开发流程

先阅读 [AGENTS.md](AGENTS.md)、[项目宪章](.specify/memory/constitution.md)以及当前
[设置增强规格](specs/002-settings-experience/spec.md)、[计划](specs/002-settings-experience/plan.md)和
[任务](specs/002-settings-experience/tasks.md)。基础产品合同仍在 `specs/001-native-wubi/`。按任务依赖测试先行，只有 fresh validation 和证据齐全
后才能勾选任务。完成报告必须列出任务 ID、文件、行为、命令结果、宪章影响和剩余门禁。
