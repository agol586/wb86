# Contract: Input Event State Machine

## Event vocabulary

- `letter(a...y)`：大小写归一化后的有效编码字母。
- `select(1...9)`：选择当前页对应序号；空位选择无效。
- `selectFirst`：空格，等价于选择当前页第一项。
- `pagePrevious`：`-`。
- `pageNext`：`=`。
- `backspace`：删除末位编码。
- `cancel`：Escape、会话失活、失焦或输入源切换。
- `switchLanguage`、`switchPunctuation`、`switchWidth`、`switchScript`：切换对应输入模式。
- `passThrough`：其他字符、系统命令或含 Command/Control/Option 的快捷键。

## Processing result

核心每次只接收一个事件，并原子返回：

- 新的 `CompositionState`；
- 零或一个客户端动作：`setMarkedText`、`commitText`、`clearMarkedText` 或 `none`；
- 候选窗口动作：`show(page)`、`hide` 或 `none`；
- 该事件是否已消费。
- 零或一个学习增量；仅成功候选提交且非安全输入时允许存在。

核心不得直接访问系统客户端、窗口、磁盘、网络或日志。

## Deterministic rules

完整转换表以 [data-model.md](../data-model.md#state-transitions) 为准，并满足：

1. 任一查询后，候选必须与返回状态中的完整 code 和 pageIndex 相符。
2. 无候选时空格和数字选择不得提交文本。
3. 第一页的上一页、最后一页的下一页是已消费的无状态变化事件。
4. 空闲态的选择、翻页、退格和取消不产生副作用，可交由客户端处理。
5. composing 状态收到 `passThrough` 时，先清除组合和候选，再把原事件交还客户端；不得
   提交编码字母或候选。
6. 任一错误只返回 idle、`clearMarkedText`、`hide` 和已消费；不得返回部分新状态。
7. 每次提交最多一个候选，提交后状态必须为 idle。
8. DirectEnglish 模式中的字母和普通符号直接传递，不查询、不显示候选、不学习。
9. 模式切换必须先按设置原子提交或取消当前组合，再变更模式；不得同时产生两次提交。
10. 安全输入状态下所有结果的学习增量必须为空。

## Ordering

适配层必须先应用客户端文本动作，再更新候选窗口。客户端动作失败时，不得继续显示新
候选；必须执行本地复位，并在不含输入内容的诊断计数中记录错误类别。
