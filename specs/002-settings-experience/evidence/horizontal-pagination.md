# T110 横向候选页码验证

日期：2026-09-03。环境：Apple Silicon arm64、macOS 26.5.2 (25F84)、Xcode 26.6 (17F113)。

横排页码常驻第一排候选末尾，显示 `当前页/总页数`，单页显示 `1/1`。页码预留 `99/99` 的宽度，
使用等宽数字并随字号缩放；没有独立页脚。纵向多页保留原有分隔页脚，纵向单页仍隐藏页码。
稳定性指候选内容相同、仅页码变化的情况；候选正文或数量变化仍可正常调整窗口尺寸。

修改文件：
- `Sources/InputMethod/CandidatePanelPresenter.swift`：横向/纵向分页约束和页码格式。
- `Tests/AdapterContractTests/CandidatePanelPresenterTests.swift`：单页显示和真实窗口几何回归。
- `specs/002-settings-experience/spec.md`、`contracts/settings-ui.md`、`tasks.md`：FR-039、SC-018 和 T110。
- `README.md`：用户可见行为说明。
- 本证据文件。

验证命令：

```bash
xcodebuild test -project MacWubi.xcodeproj -scheme MacWubi \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/tests \
  -only-testing:MacWubiTests/CandidatePanelPresenterTests

xcodebuild test -project MacWubi.xcodeproj -scheme MacWubi \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/tests \
  -only-testing:MacWubiTests/CandidatePanelPresenterTests \
  -only-testing:MacWubiTests/InputControllerContractTests \
  -only-testing:MacWubiTests/SettingsIntegrationTests \
  -only-testing:MacWubiTests/SettingsWindowTests

git diff --check
```

目标测试先在旧行为下失败（10 项测试、41 个断言失败），实现后 10 项全部通过；相关回归 71 项全部
通过（候选 10、输入适配 29、设置集成 8、设置窗口 24）。几何断言覆盖字号 0.8/1/2，`1/1`、
`1/10`、`10/10` 的往返切换、同排位置、页码与正文无重叠、窗口宽高稳定以及横纵切换。
`git diff --check` 通过。XCTest 最初受沙箱 testmanagerd 访问限制，获执行权限后正常运行。

宪章影响：保持 Xcode/arm64 和纯 Swift，不增加依赖；仅修改 AppKit 候选展示，未改 InputMethodKit
事件、选择、提交、签名或发行配置。恢复和隐私数据路径无改动，不增加日志、网络或持久化。
未改变引擎查询与排名算法；本次未重跑性能、全量测试或正式发行签名/公证门禁，不宣称性能或发行验收通过。
未安装到系统输入法目录，也未进行安装后真实客户端人工视觉验收。
