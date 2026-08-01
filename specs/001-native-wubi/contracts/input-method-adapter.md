# Contract: InputMethodKit Adapter

## Bundle contract

发布 bundle 必须：

- 以后台应用运行；
- bundle identifier 必须包含完整 `.inputmethod.` 段；当前稳定值为
  `org.macwubi.inputmethod.MacWubi`；
- 声明唯一且稳定的 `InputMethodConnectionName`；当前值固定为
  `org.macwubi.inputmethod.MacWubi_Connection`，与 Apple 的 Swift IMK 样例一致；
- 将 `InputMethodServerControllerClass` 指向输入控制器；
- 声明稳定的 `TISInputSourceID` 和 BCP 47 目标语言；首个版本必须作为单一、直接可选的
  系统输入源，不声明 `ComponentInputModeDict`；产品内模式由会话状态机管理；
- 声明中文字符集信息和有效图标资源；
- 不启用 App Sandbox；本机构建使用 Apple Development，分发构建使用 Developer ID
  Application、Hardened Runtime、安全时间戳与 Apple 公证；
- 分发签名不得包含网络、Apple Events、Mach 临时例外、`get-task-allow` 或 Hardened
  Runtime 弱化 entitlement；
- 主可执行文件必须恰好包含 `arm64`，不得包含 `x86_64` 或宣称 Universal Binary 支持。
- 默认安装目标为系统级 `/Library/Input Methods/MacWubi.app`，复制和替换 bundle 必须通过
  macOS 标准管理员授权；运行时可变数据仍只属于当前用户的 Application Support 目录。

## Session contract

- 每个系统输入会话拥有独立控制器和核心 `InputSession`。
- 控制器创建时状态为 idle；失活、失焦、客户端失效和销毁前必须清除 marked text 与候选。
- 适配层只把 [input-events.md](input-events.md) 定义的事件传给核心。
- 已消费事件返回成功；pass-through 事件在必要复位后返回未处理，使原客户端继续处理。
- 设置、用户词库或学习快照替换后，新查询读取一个完整新 generation；正在处理的事件不得
  看到半写入数据。

## Client text actions

- `setMarkedText` 只呈现当前编码，不提交到文档。
- `commitText` 只提交核心返回的单一候选，随后清除 marked text。
- `clearMarkedText` 必须产生空组合，不得用原编码替代。
- 取消不得直接调用会恢复 `originalString` 的系统默认取消路径；必须显式清空 marked text，
  除非契约测试已证明 `originalString` 为空且不会插入任何文本。
- 客户端不可用、抛出错误或拒绝操作时，适配层只能复位，不得重试提交。

## Candidate presentation

- 使用不夺取客户端键盘焦点的自定义可访问候选 panel 显示当前页最多九项；不得依赖
  `IMKCandidates` 的未公开内部视图或无障碍结构。
- 显示序号必须与 `select(1...9)` 一致。
- 空页、取消、提交、失活及错误均隐藏窗口。
- 鼠标选择必须转换为相同的核心选择事件，不得绕过状态机直接提交。

## Privacy and diagnostics

适配层不得记录事件字符、marked text、候选文本、提交文本、客户端内容或目标应用文档。
允许的生产诊断仅限固定类别计数，例如词库加载失败、非法事件、客户端操作失败和性能
门禁超限；诊断不得包含会话关联标识。

Apple 的公开 InputMethodKit 契约没有提供已确认的每会话安全输入状态回调。实现不得把
全局安全事件状态当作充分证明，也不得尝试监听系统级按键。学习只来源于输入法自身成功
提交的候选，必须可全局关闭并提供显式私密模式；产品不得宣称自动识别密码框。

## Failure contract

任何 Objective-C 桥接空值、客户端协议不匹配、词库错误、非法核心结果或候选窗口错误都
必须隐藏候选、清空本地状态并尽力清除客户端 marked text。故障不得跨会话传播。
