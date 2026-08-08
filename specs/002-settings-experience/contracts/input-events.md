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

- 第四码查询为零或多候选时不自动提交；恰好一个有效候选且开关开启时提交一次并清空组合。
- 第五码开关开启、已有四码首选且路由已确定为五笔时，输出有序复合动作：提交旧首选、用第五码
  建立新 marked text、查询新候选。旧首选为空或已过期时不提交错误候选。
- 混输开启且五字符序列仍为有效拼音前缀时继续拼音组合，不执行第五码截断。

## Keyboard layout

- `followSystem` 使用活动事件经系统布局解释后的字符；`us` 只对受支持的 ANSI 物理键使用固定美国
  映射，不改变系统键盘布局。
- 布局不可用或事件无法确定映射时不猜测、不缓存敏感文本，并安全透传或复位。
