# Release Checklist

任一必需项未通过都禁止发布。命令输出不得包含用户输入正文或应用上下文。

## 构建与平台

- [ ] 候选构建由 Xcode Release 配置产生，部署目标为 macOS 13.0 或更高。
- [ ] `lipo -archs` 的精确结果只有 `arm64`；产物、文档和依赖均无 `x86_64`/Universal 声明。
- [ ] 无第三方运行时、C/C++ 动态库、网络 entitlement、全局键盘监听或 App Sandbox entitlement。
- [ ] Hardened Runtime、Info.plist、资源清单和代码签名分别通过验证。

## 直发签名（最终发布时执行）

- [ ] 使用 Developer ID Application 身份签名所有可执行代码，启用 secure timestamp。
- [ ] 向 Apple 公证成功，ticket 已 staple，`stapler validate` 通过。
- [ ] `spctl --assess --type execute --verbose=4` 通过 Gatekeeper。
- [ ] `MACWUBI_REQUIRE_DISTRIBUTION=1 Scripts/verify-release.sh /绝对路径/MacWubi.app` 通过。

## 功能、恢复与隐私

- [ ] `Scripts/test.sh` 全部通过，包含单元、契约、集成、迁移、恢复、隐私和发布契约测试。
- [ ] 安装、升级、失败回滚、保留数据卸载及显式删除数据场景通过。
- [ ] 设置、用户词库、学习三个域的兼容迁移、中断恢复、损坏隔离和未来版本保留通过。
- [ ] `Scripts/privacy-audit.sh` 对最终候选和正常/失败/导入/升级/私密模式流程通过。
- [ ] 运行进程零网络连接，日志、导出和 Application Support diff 无输入内容或时间线。

## 无障碍、兼容性与性能

- [ ] VoiceOver、Accessibility Inspector、完全键盘控制、深浅色、高对比度、缩放、多显示器通过。
- [ ] 开启无障碍功能后七类应用矩阵无回归。
- [x] Release 查询报告的全部样本 `< 2 ms`，并记录硬件、OS、Xcode、配置、语料、热身和百分位。
- [x] `Scripts/measure-memory.sh /绝对路径/MacWubi.app` 在正常输入稳态下报告 physical footprint `< 15 MiB`。
- [x] `Scripts/run-long-stress.sh /绝对路径/MacWubi.app 1000000` 完成 30 个逻辑输入日、至少
  100 万实际提交汉字、多会话设置 churn、混输、调频和翻页，且无持续内存或延迟趋势。
- [ ] Apple Silicon 实机 macOS 13 与当前支持 macOS 的完整 quickstart、七类应用和隐私矩阵通过。

## 可追踪性

- [ ] `FR-001…FR-031` 与 `SC-001…SC-013` 均有 PASS 证据；30 天实际用户替代研究与首次用户研究已完成。
- [ ] 词库来源、许可证、对应源、manifest、checksum 和双次可复现编译均通过。
- [ ] 最终候选摘要、产物哈希、签名身份、公证结果和所有未决项记录在 evidence 文档中。
