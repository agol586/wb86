# Quickstart: 设置体验增强验证

本文件是功能实现完成后的端到端验证合同。所有命令从仓库根目录执行，使用 Apple Silicon 真机；
不得把任何真实用户输入写入证据。

## 1. Automated suite

```bash
Scripts/test.sh
```

必须通过 Core、AdapterContract、Dictionary、Persistence、Migration、FailureRecovery、Privacy、
Performance、ReleaseContract 和 Integration 测试。重点确认：

- Settings v1→v2 golden migration、future-schema 只读、中断和 previous 恢复。
- 新安装默认与升级兼容默认不同且都精确匹配。
- 4 码零/一/多候选、五码复合动作、拼音前缀优先和每事件至多一次提交。
- 五组翻页键全部组合、候选 2/3、精确 modifiers、边界消费和空闲透传。
- 左/右 Shift、长按、双 Shift、Shift+字母、孤立 release、失活和设置代次改变。
- 两个以上会话独立切换代次；一个组合内仅观察一个快照。
- 混输 merge/dedupe/简繁/提示、资源损坏降级、学习开关/私密覆盖。
- Restore Default 的确认/取消/故障只改变 Settings 域。

## 2. Reproducible resources

```bash
xcodebuild -project MacWubi.xcodeproj -target MacWubiDictionaryCompiler -configuration Release ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
Scripts/test.sh
git diff --exit-code -- Sources/Resources
```

确认编译器对固定源产生相同 `MWPY` 与 manifest，源/产物 checksum、commit、license、WB86 build ID
和每键 64 项上限均由测试验证。若资源更新是本变更的预期内容，应先审核 diff，再在干净检出重复构建。

## 3. Signed arm64 release

```bash
Scripts/build-release.sh
Scripts/verify-release.sh /absolute/path/to/MacWubi.app
Scripts/privacy-audit.sh
```

验证主可执行文件仅 `arm64`、Developer ID、Hardened Runtime、timestamp、公证/staple/Gatekeeper（发布
阶段）、无 App Sandbox/网络/Apple Events/Mach/get-task-allow entitlement，且包内拼音资源和许可存在。

## 4. Settings UI acceptance

1. 确认设置窗口使用始终可见、不可自定义的“常用 / 按键 / 外观 / 高级”工具栏，当前项明确选中，
   窗口标题随面板同步；四页均显示标题、简短说明和清晰分组。确认 Return 保存、Escape 取消，恢复
   默认不是默认按钮。
2. 打开“常用”，确认全新安装默认：中文/简体/半角/英文标点；四码唯一开；五码和调频关；
   混输与提示开；分号/单引号关。
3. 打开“按键”，确认中英文切换依次提供 Shift、Control、Caps Lock、禁用且默认 Shift；
   简繁为 Control-Shift-F、宽度禁用；四个默认翻页组开启、方向键关闭；US 布局。
4. 只用普通键盘逐项修改、保存、取消，并检查冲突错误将键盘焦点定位到对应控件。
5. 保存非法冲突，确认零写入；取消 draft，确认运行值不变。
6. 执行并取消一次 Restore Default；确认取消零写入，确认后用户词库/学习文件 checksum 与 generation 不变。
7. 打开“高级”，确认运行状态、用户词库和本地数据为三个独立区域；“私密模式”和“本地学习”
   回显当前运行状态，逐项切换后立即影响所有活动
   会话，关闭并重新打开设置仍显示当前值，普通“取消”和“恢复默认”不改变它们。
8. 确认菜单栏只显示系统输入菜单中的 Mac Wubi 86，不存在“`五·学`”“`五·私`”或其他由产品
   额外创建的常驻状态栏项目。

## 4.1 Unsupported assistive-technology contract

1. README、用户指南和发布清单必须明确说明 VoiceOver、旁白实用工具、Accessibility Inspector 与
   屏幕阅读器专用功能不受支持。
2. 产品源代码不得包含自定义辅助候选树、朗读公告、辅助按压动作或辅助焦点发布。
3. 删除专用适配后，普通鼠标候选选择、键盘候选选择、候选翻页、设置保存/取消和可见错误反馈
   必须继续通过自动化回归。

## 5. Input behavior matrix

使用 Release 签名 arm64 产物，在 TextEdit、iTerm、Codex、VS Code、Chrome 中分别验证。每次重新安装
输入法后必须完全退出并重开这些应用，避免旧 IMK client/controller 继续驻留：

- 分别选择 Shift、Control、Caps Lock 后单独操作只切一次；Shift+字母、Command+Shift、长按、重复、
  左右键交错时不误切换且不出现卡键；选择禁用后不切换。
- 组合中用语言快捷键切换时当前原始编码上屏且候选隐藏；Control-Shift-F 和选定宽度快捷键仍按
  安全取消规则工作，应用快捷键继续到达客户端。
- 中文空闲态以大写字母开始输入 `MacWubi_86`，确认 marked text 与候选框同步显示完整原文、状态
  仍为中文；按空格后只将整段上屏且不附加空格，下一小写字母重新进入五笔组合。另测 Backspace、Escape、
  Enter 和鼠标选择首项。
- 分别检查纵向与横向候选布局：纵向每行的悬停和点击底色铺满内容宽度；首选同时显示强调底色与
  左侧短条；横向候选间距清晰。多页显示带分隔线的右对齐“第 n / m 页”页脚，单页不保留空页脚；
  整个候选窗不得抢走当前文本焦点。
- 每组翻页键在候选存在时双向翻页；第一页/末页不循环；关闭或空闲时按键正常透传。
- 分号/单引号只选当前页第二/第三项，目标缺失保持组合不变。
- 四码唯一仅唯一时上屏；五码路径提交旧首选并保留新键；`shang` 等有效拼音前缀不中途截断。
- 混输为五笔优先、拼音随后、转换后去重；输入 `shenm` 时通过本地前缀预测出现 `什么`，继续到
  `shenme` 时切换为精确候选；提示开关不改变候选/提交；断网结果完全一致。
- 输入 `sm` 时首项为 `机`，并可翻页找到 `机会`、`机构`、`机场`、`机器`、`机遇`；开启提示时
  联想词只显示 `wf`、`sq`、`fn`、`kk`、`jm` 等尚未输入的后续码。
- 中文/英文标点与半/全角遵循“先标点映射，再转换仍为 ASCII 的字符”。

## 6. InputMethodKit physical regression

扩展 `recognizedEvents` 后必须真机执行：组合中点击 marked text 内外、点击候选、切换窗口、切换应用、
停用/重启输入源。确认 marked text 和候选总能安全清理、鼠标选择不回归、无原始编码提交。若默认
点击外部取消失效，修复 `IMKMouseHandling` 后重复本节，不能把它标记为自动通过。

独立 modifier 的通过条件是 TextEdit、iTerm、Codex、VS Code、Chrome 五类客户端全部通过上述矩阵；
不得用 TextEdit/iTerm 成功替代 Chromium/Electron 结果。只记录构建标识、系统版本和每项 pass/fail，
产品运行时不得记录按键、应用身份、文本或可重建输入时间线。若重构后 Chromium/Electron 仍未交付
可配对 `flagsChanged`，记录平台门禁失败并停止实现，不得增加 global monitor、event tap 或轮询。

## 7. Performance and stability

```bash
Scripts/measure-memory.sh /absolute/path/to/MacWubi.app
Scripts/run-long-stress.sh /absolute/path/to/MacWubi.app 1000000
```

使用 Release 签名 arm64 产物记录硬件、macOS/Xcode、资源 manifest、warm-up、样本数、p50/p95/max。
五笔-only、`sm` 短码联想、拼音 prefix/exact、合并/去重/简繁、翻页和全部开关开启的每个已识别样本必须 `<2 ms`；
正常 resident memory `<15 MB`；月度等效负载必须完成 30 个逻辑输入日、累计实际提交至少
1,000,000 个中文字符，并且无持续内存或延迟增长。运行时长仅作信息记录，不作为通过条件。任一失败
都阻止完成对应任务和发布。
