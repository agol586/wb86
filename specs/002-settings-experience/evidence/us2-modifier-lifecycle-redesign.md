# T077–T081 Modifier Lifecycle Redesign Evidence

**Date**: 2026-08-03
**Host**: macOS 26.5.2 (25F84), Apple Silicon arm64
**Toolchain**: Xcode 26.6 (17F113)
**Release executable SHA-256**: `252f5fb7a023a8fa889b12bda72f5589fa4a1dc6b9ef4a5cb8d902ca71bf1f6c`

## Design result

- T076 的 modifier press/release consume 语义已回滚；正常 `flagsChanged` 始终透传。
- `InputControllerEventProcessor` 先让会话 recognizer 观察事件，再解析当前 client proxy。
- nil 或不可转换 sender 不会重置当前 modifier edge；空闲无 client 可应用模式 intent。
- recognizer 依据聚合 modifier flag delta/category 配对；精确 keyCode 只增强左右键歧义判定，
  `keyCode=0` 只在唯一 flag transition 时使用。
- 普通 activate/deactivate 使跨边界待定 tap 失效但保留 flag resync；controller 关闭才完全 reset。
- 组合中 client 不可用时丢弃完成 intent、清理本地组合，不切换模式且不提交文本。

## Test-first evidence

新增测试先观察到预期失败：

- `InputControllerEventProcessor` 尚不存在时，client-independent routing 契约编译失败。
- exact/invalid keyCode 跨端 category pairing 在旧物理 key set 模型下出现 2 个断言失败。
- lifecycle suspension API 尚不存在时，生命周期契约编译失败。

最小实现完成后的目标命令：

```bash
xcodebuild test -project MacWubi.xcodeproj -scheme MacWubi \
  -destination platform=macOS,arch=arm64 -derivedDataPath .build/tests \
  -only-testing:MacWubiTests/InputControllerContractTests \
  -only-testing:MacWubiTests/StandaloneShiftRecognizerTests
```

结果：29 tests，0 failures。

完整回归：

```bash
Scripts/test.sh
```

结果：主测试 target 232 tests、Release contract target 9 tests，合计 241 tests，0 failures；
确定性词典 fixture 校验通过。沙箱内首次运行因系统 `testmanagerd` 访问受限失败，使用相同命令在
获准的 macOS 测试环境重新运行后通过，失败与产品逻辑无关。

## Release and privacy gates

```bash
MACWUBI_CODE_SIGN_IDENTITY='Apple Development: luoagol@gmail.com (6XRC4PBH7N)' \
  Scripts/build-release.sh
Scripts/verify-release.sh \
  /Users/agol/.codex/worktrees/92ba/wb86/.build/xcode/Build/Products/Release/MacWubi.app
Scripts/privacy-audit.sh \
  /Users/agol/.codex/worktrees/92ba/wb86/.build/xcode/Build/Products/Release/MacWubi.app
```

结果：Release build 成功；可执行文件仅 arm64；Apple Development 签名、Hardened Runtime、空最小
entitlements、系统动态依赖、本地资源许可和离线隐私审计全部通过。

源码审计未发现 global/local event monitor、CGEventTap、全局 modifier flags 轮询、前台应用查询或
按目标应用身份分支。`AppDelegate.swift` 中 `Bundle.main.bundleIdentifier` 仅用于注册本输入法自己的
IMK server connection，不读取宿主应用身份。

## Failed physical gate

T082 于 2026-08-03 使用上述 SHA-256 的已安装包执行，TextEdit、iTerm、Codex、VS Code、Chrome
全部报告单 Shift 切换失败。因此 T077–T081 的自动化结果不能证明 FR-014，且
client-independent routing / aggregate-delta 方案作为完整修复已被实机证伪。

安装后核验确认 `/Library/Input Methods/MacWubi.app` 与构建产物 SHA-256 完全一致，设置快照中的
`languageSwitch` 仍为 `standaloneShift`；系统日志确认新进程从该安装路径启动且普通组词、marked text
和提交路径工作。失败不是旧包、未启动或设置回退造成。

对 `rime/squirrel` 主干 `7b4a314a05c465e99bc98bcf38006c07c3b7b901` 的源码复核发现：Squirrel
同样只声明 `keyDown | flagsChanged`，但不会在普通 `activateServer` / `deactivateServer` 中废弃
modifier 配对状态。MacWubi 的 `suspend()` 以及严格单一 delta 要求仍是尚未经过物理验证的差异。
下一轮只能验证这一项生命周期差异；若仍失败，按计划停止 Shift 代码绕行并回到产品规格决策。

## Phase 14 reproducible diagnosis and fix

辅助功能授权仅用于向临时输入面合成固定测试串；MacWubi 本身未获得或使用辅助功能权限。旧安装包在
同一会话内得到：

- TextEdit：`你好 → wqvb → 你好`。
- iTerm：`你好 → wqvb → 你好`。
- Chrome 新临时窗口地址栏（先执行 Command-L）：`你好 → 你好 → wqvb`。

因此 Chromium 会交付足以让第二次 Shift 生效的事件，问题不是“没有 flagsChanged”，而是 Command
事件让 recognizer 的 `disqualified` 状态粘滞。新增两个测试先在旧实现观察到 3 个断言失败：完整
Command gesture 后状态不是 idle，下一次 Shift 不触发；缺失 Command release 的 stale baseline 后
Shift 也不触发。

最小实现只修改 `StandaloneModifierRecognizer`：目标 flag 已不存在时，非目标 modifier edge 恢复
idle；当前 flags 恰为目标 modifier、目标 keyCode 精确且历史未按下目标时，允许安全重同步 stale
flags。目标仍按下、组合键、多义 invalid keyCode、重复 edge、长按和左右交错继续拒绝。

验证结果：

- modifier/controller 目标套件：31 tests，0 failures。
- `Scripts/test.sh`：完整 XCTest、Release contract 和确定性词典 fixture 全部通过。
- `Scripts/verify-release.sh`：arm64、ad-hoc 本地签名、Hardened Runtime、依赖与资源门禁通过。
- `Scripts/privacy-audit.sh`：零网络能力、诊断脱敏和本地数据边界通过。
- 正式包已确认不包含临时 `MWMOD` / `MODIFIER_DIAGNOSTICS` 代码。
- 已安装正式本地测试包 SHA-256：
  `a642f8af4704ad277dc82b963aa13682d51cf53887e95c0e87488b660a3d6237`。
- 完全退出并重开 Chrome 后，同一序列变为 `你好 → wqvb → 你好`，首次 Shift 自动化物理回归通过。

本机 Apple Development 证书在本轮中途变为 `0 valid identities`，因此最终物理测试包按项目合同改用
ad-hoc 本地签名；这不满足 Developer ID 分发门禁，但不影响本机 InputMethodKit 行为验证。T087 仍需
用户使用实体键盘在 TextEdit、iTerm、Codex、VS Code、Chrome 完成最终矩阵。

### T087 VS Code follow-up

用户随后报告 VS Code 实体键盘仍未生效，故 T087 保持失败/未完成。在当前已安装正式包和当前 VS Code
进程中，使用临时未保存编辑器分别合成左 Shift 与右 Shift（keyCode 60），两次固定序列均得到
`你好 → wqvb → 你好`；临时内容已清空、窗口已关闭且剪贴板已恢复。现有证据说明 VS Code 的
InputMethodKit 路径和左右 Shift 自动化可用，但实体键盘事件形态仍有未解释差异。未取得实体事件证据前
不得通过增加时长阈值、吞键、应用特判或全局监听做猜测性修改。

### Calibrated physical VS Code evidence

第二轮诊断先用 VS Code 自动 Shift 校准日志通道：每端一个 edge，两次均完成
`idle → eligible → idle/triggered=true`。用户随后操作实体左右 Shift，日志稳定显示每次 press 与
release 各交付两个相同 aggregate-flags edge；重复 press 把 eligible 变为 disqualified，重复 release
又把 idle 变为 disqualified，所有 triggered 均为 false。根因由此确定为零 delta 重放处理错误，而非
事件缺失、左右键、时长阈值或 client proxy。

日志流已停止，诊断包已替换为无日志包，诊断源码已移除。新增测试在旧实现观察到 4 个失败断言；零
delta 幂等实现后 modifier/controller 目标套件 33 tests、0 failures。完整发布与新包实体门禁待
T090/T091。

T090 完成：`Scripts/test.sh`、ad-hoc Release build、`Scripts/verify-release.sh` 和
`Scripts/privacy-audit.sh` 全部通过；源码扫描无 `MWMOD`、`MODIFIER_DIAGNOSTICS` 或诊断 subsystem，
`git diff --check` 通过。待安装的无日志可执行文件 SHA-256 为
`13975f488f3181dbd7e7ac010ef6f63bb2eb7402f4ff8f68131f27a3ea5ee663`。

### T091 VS Code result

用户完全重开 VS Code 并使用实体键盘验证后确认“可以了”。因此 SHA-256
`13975f488f3181dbd7e7ac010ef6f63bb2eb7402f4ff8f68131f27a3ea5ee663` 的无日志安装包已通过
VS Code 实体 Shift 门禁。TextEdit、iTerm、Codex、Chrome 在该最终哈希上的回归尚未由用户共同确认，
故当时尚未勾选 T082/T087/T091；后续最终结果见下节。

### Final five-client physical gate

用户随后确认 TextEdit、iTerm、Codex、VS Code、Chrome 在同一最终安装包上“都可以了”。因此
T082、T087、T091 于 2026-08-03 完成，FR-014 的本机五类客户端实体 Shift 门禁通过。最终可执行文件
SHA-256 为 `13975f488f3181dbd7e7ac010ef6f63bb2eb7402f4ff8f68131f27a3ea5ee663`；包为
arm64、ad-hoc 本地签名、Hardened Runtime，发布校验与隐私审计均通过，且不包含临时诊断代码。
