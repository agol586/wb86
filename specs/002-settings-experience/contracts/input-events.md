# Contract: 输入事件与候选控制

## Event boundary

- 只处理活动 InputMethodKit 会话交付的 `keyDown`、必要的 modifier-change 和候选鼠标事件；不得安装
  全局 monitor、event tap 或绕过 Secure Event Input。
- `flagsChanged` 必须在 client proxy 获取/类型转换之前交给会话 recognizer；nil 或不可转换的
  `sender` 不得导致当前 modifier edge 被丢弃或 recognizer 被无条件 reset。
- 连续收到聚合 modifier flags 完全相同的 `flagsChanged` 时，后一个事件必须作为客户端重放幂等忽略；
  不得触发第二次模式动作，也不得把 eligible/idle 改成 disqualified。只有实际 flag delta 才推进状态。
- 带 Command、Control、Option 等非预期修饰键的应用/系统快捷键默认透传，并在需要时先安全取消组合。
- 每个物理事件最多产生一个核心事件；每个核心事件最多产生一次候选提交。

## Mode switches

- Shift 或 Control 预设只在一次无其他键/修饰键的按下—释放序列完成时切换一次；相同 aggregate flags
  的客户端重复 edge 不算新的物理 transition；
  Caps Lock 按系统 toggle 型修饰事件去重并只切换一次。禁用时所有对应事件均不产生模式副作用。
- 正常 modifier press/release 必须透传；模式 intent 与原始事件的 handled 返回值分离，不得通过消费
  press 来要求客户端继续交付 release。
- 组合期间触发中英文切换时，先原子提交当前原始编码一次并隐藏候选，再切换语言；简繁、全半角等
  其他模式切换仍安全取消 marked text，不提交原始编码。
- client 可用时 intent 走正常输入会话路径；client 不可用且会话空闲时可只更新当前会话模式；client
  不可用且组合未结束时必须丢弃 intent、安全复位且不提交文本。
- 简繁和全半角切换只改变当前会话状态，不写持久化默认。
- 中文空闲态首个大写 ASCII 字母开启单次原样组合，不改变语言状态；后续本段字符不查询、
  不转换、不学习，以 marked text 和单一候选显示。空格只提交原文并由输入法消费，不向应用插入空格；
  适配器同时消费原始 keyDown 与 InputMethodKit `inputText:client:` 文本回调路径；
  回车提交原文并由输入法消费，
  不向应用插入换行；适配器同时消费原始 keyDown 与 InputMethodKit `insertNewline:` 命令路径。
  候选首项提交原文；退格修正，Escape 取消。直接输入组合期间候选快捷键和翻页键不得截获原文符号。

## Modifier lifecycle

- recognizer 依据聚合 modifier flags 的 transition/category 维护 `lastModifierFlags`；keyCode 无效时仅在
  flag delta 唯一指向目标 modifier 时作有界推断。
- controller 首次同步、普通 activation/deactivation、设置代次变化及 client 暂时缺失均不得把孤立
  release 解释为点击；非 modifier 键、超时、多 flag edge 和左右键歧义必须使待定点击失效。
- controller 关闭、确定的会话废弃或不可恢复歧义必须清空状态。不得跨 controller、跨会话共享
  modifier 状态。

## Candidate page and direct selection keys

- 启用组可并存：`,`/`.`、`-`/`=`、`[`/`]`、Shift-Tab/Tab、Up/Down；前键上一页，后键下一页。
- 仅在候选存在且目标页有效时消费。无组合、设置关闭、越界或修饰键不匹配时透传。
- 开启快捷选择时，`;` 选择当前页第二项，`'` 选择第三项；目标不存在时保持组合与候选不变，
  不降级选择其他项。
- 同一事件即使匹配多个抽象规则也只执行优先级最高的一个已验证规则。

## Auto commit

- 任一有效组合的第一页查询为零候选时，合成一个正文等于当前原码、来源为 `directInput` 的唯一候选并显示；
  空格或数字选择提交原码但不产生学习增量。继续输入字母时在同一组合末尾追加并显示完整原码，超过
  四码也不得分段、提交或清空；只有查询重新产生词库候选或用户显式提交才离开该原码候选状态。
  该兜底候选不满足“四码唯一”或“第五码首选”自动提交条件。
- 普通五笔或拼音组合的 Return/Enter keyDown、`insertNewline:` 系列命令或等价换行文本回调必须提交
  当前原码、隐藏候选并由输入法消费；不得选择候选、学习、清屏或向应用插入换行。Escape 仍只清屏。
- 第四码查询为多候选时不自动提交；恰好一个有效词库候选且开关开启时提交一次并清空组合。
- 第五码开关开启、已有四码首选且路由已确定为五笔时，输出有序复合动作：提交旧首选、用第五码
  建立新 marked text、查询新候选。原码兜底候选必须绕过此路径并继续同一组合；旧词典首选已过期时
  提交四码原文而不提交错误候选，然后用第五码建立新 marked text；取消和故障恢复仍清空组合。
- 混输开启且五字符序列仍为有效拼音前缀时继续拼音组合，不执行第五码截断。
- 当前首项为原码兜底候选时，无论第五码开关状态如何，后续字母都追加到同一原码组合；不得自动提交
  前缀或另起组合。

## Candidate positioning

- 适配层必须从 `attributes(forCharacterIndex: 0, lineHeightRectangle:)` 取得当前 inline session 的完整
  输入行矩形，不得只传递单个锚点而丢失行高。
- 候选窗口默认位于输入行下方并保留至少 4 点间距；下方可见空间不足时翻转到输入行上方。多显示器
  边界夹取和窗口缩放不得使候选窗口与输入行相交或覆盖 marked text。

## Keyboard layout

- `followSystem` 使用活动事件经系统布局解释后的字符；`us` 只对受支持的 ANSI 物理键使用固定美国
  映射，不改变系统键盘布局。
- 布局不可用或事件无法确定映射时不猜测、不缓存敏感文本，并安全透传或复位。
