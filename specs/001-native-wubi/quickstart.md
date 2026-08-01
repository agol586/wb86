# Quickstart Validation: 隐私优先的原生五笔 86 输入法

本指南定义完整产品实现后的可重复验证入口。当前仓库尚未实现 Xcode 工程；以下命令和
验收方案是后续任务必须提供并保持可运行的交付契约。

## Prerequisites

- 安装支持项目 SDK 的 Xcode 15 或更新版本，并接受许可。
- 一台 Apple Silicon Mac；发布验收另需一台受支持的 Intel Mac。
- 用户级 `~/Library/Input Methods/` 可写。
- 准备标准五笔 86 语料、七类应用、VoiceOver、损坏快照和 10,000 条导入样本。
- 仓库根目录为当前工作目录。

每次发布验证记录 Mac 型号、CPU、macOS、Xcode、构建配置、词库清单、测试数据版本和
性能样本量；不得记录验收人员实际输入正文。

## 1. Run automated tests

```bash
xcodebuild test \
  -project MacWubi.xcodeproj \
  -scheme MacWubi \
  -destination 'platform=macOS'
```

预期：核心状态、模式、排序、简繁、词库、设置、用户词条、学习、导入导出、迁移、损坏
恢复、适配器、无障碍和性能测试全部通过；测试日志不打印输入或候选正文。

## 2. Build and verify a signed universal release

```bash
Scripts/build-release.sh
Scripts/verify-release.sh /absolute/path/to/MacWubi.app
```

构建必须使用 Release、`ARCHS="arm64 x86_64"` 和 `ONLY_ACTIVE_ARCH=NO`，不得下载依赖。
验证脚本必须至少执行等价检查：

```bash
lipo -archs /absolute/path/to/MacWubi.app/Contents/MacOS/MacWubi
codesign --verify --deep --strict --verbose=2 /absolute/path/to/MacWubi.app
codesign --display --entitlements :- /absolute/path/to/MacWubi.app
plutil -lint /absolute/path/to/MacWubi.app/Contents/Info.plist
```

预期：主可执行文件恰好包含 `arm64` 和 `x86_64`；两个 slice 及 bundle 签名有效；
entitlements 只包含 App Sandbox 和用户选择文件所需权限，不含网络、Apple Events 或 App
Group；InputMethodKit 元数据一致。`codesign --deep` 只用于验证，不用于签名。

## 3. Pass the sandboxed InputMethodKit blocking gate

将已验证 bundle 安装到用户级 Input Methods 目录，通过系统设置添加输入源；必要时按文档
注销并重新登录。不得关闭 Gatekeeper、SIP、App Sandbox 或其他系统安全功能。

在 macOS 13 和当前支持版本分别验证：发现、启用、输入源切换、`IMKServer` 连接、组合
文本、候选显示、设置打开，以及原生文本应用和浏览器中的提交。

预期：无签名、entitlement 或沙盒拒绝。此门禁失败时立即停止后续产品实现并回到宪章/
范围决策；不得通过宽泛临时例外或非沙盒辅助进程绕过。

## 4. Validate complete daily input

在原生编辑器、浏览器、办公软件、代码编辑器、终端、系统搜索和 Electron 应用执行：

1. 覆盖一级至三级简码、全码、单字、词组、重码和连续输入。
2. 用空格、`1...9`、鼠标/触控板选择，测试三组可配置翻页键。
3. 退格修码、Escape 取消、四码自动上屏；确认取消不会插入 original string。
4. 切换中文、临时英文、中英文标点、全半角和简繁输出。
5. 验证 Command、Control、Option 快捷键和普通 pass-through 事件。
6. 在组合中切换焦点、应用、显示器和输入源。

预期：输出和状态符合 [input-events.md](contracts/input-events.md)，七类应用无漏字、重复
提交、快捷键拦截、错误目标提交或会话串线。

## 5. Validate learning, user lexicon, and private mode

对同码非首位候选连续选择三次，确认下一次前移；关闭学习或清零后确认恢复稳定排序。
添加、编辑、搜索、删除用户词条并重启，确认数据按预期保留。

启用私密模式后执行 10,000 次候选提交，前后比较三个数据域和文件清单。

预期：学习行为有界且确定；私密模式不产生学习增量或其他输入相关写入，已有学习不参与
排序。输入法没有全局按键监听，也不尝试绕过 Secure Event Input。

## 6. Validate settings and accessibility

修改候选数量、布局、字号、翻页键、模式键、自动上屏、简繁和学习开关，重启验证保留；
恢复默认设置并确认 UserLexicon 与 Learning 未被删除。

使用 VoiceOver、完全键盘控制、Accessibility Inspector、浅色、深色、高对比度、多显示器
和不同缩放完成核心输入与设置流程。

预期：候选序号、视觉顺序、选择顺序和朗读顺序一致；候选窗口不夺取文本焦点且保持可见；
所有设置可键盘操作。若 `IMKCandidates` 无法通过，候选展示实现不得进入发布路径。

## 7. Validate import, export, migration, and rollback

使用包含合法、重复、非法、超长和未知版本记录的 10,000 条样本执行导入；导出产品格式
和 UTF-8 文本，再在干净数据域恢复。只允许通过系统打开/保存面板选择文件。

对 Settings、UserLexicon 和 Learning 分别测试：当前版本加载、所有支持旧版本逐级升级、
未知未来版本、checksum 错误、磁盘空间不足及替换各阶段中断。

预期：导入 5 秒内完成且计数完全正确；失败不改变原数据；导出不包含输入历史或上下文；
每个域只提交完整 generation，失败时恢复 current 或 previous，其他域不受影响。

## 8. Validate fault recovery

注入错误 magic、未知版本、越界偏移、无效 Unicode、错误 checksum、查询失败、客户端失效、
候选窗口失败和并发快照替换。每次错误后立即输入已知有效编码。

预期：当前组合与候选安全清除，无崩溃、错误提交、死循环或跨会话污染；仅损坏域隔离，
下一次有效输入恢复。生产诊断只包含固定错误类别。

## 9. Performance and privacy release gates

在 Release bundle 和发布数据上先预热，再覆盖一至四位编码、基础/用户/学习合并、简繁和
首中末范围查询。报告 p50、p95、p99、最大值和 RSS；执行八小时连续输入与应用切换压力。

同时观察输入法及其组件的网络活动，扫描签名 entitlements、容器、生产日志、崩溃产物和
导出文件。

预期：所有可识别编码在 2 ms 内提供首批候选，正常输入 RSS 始终低于 15 MB，八小时无
持续增长；零网络连接、零网络 entitlement，且不存在原始输入历史、应用上下文或可重建
输入时间线。

任何架构、签名、沙盒加载、输入正确性、隐私、恢复、迁移、无障碍或性能门禁失败都阻止
发布，不得以关闭安全约束或跳过失败测试解决。
