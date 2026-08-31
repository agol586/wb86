# Data Model: 设置体验增强

## 1. SettingsSnapshot v3

`SettingsSnapshot` 是设置域唯一可发布单元：

| Field | Type / values | Validation |
|-------|---------------|------------|
| schemaVersion | UInt32 = 3 | 仅支持 3；未来版本只读保留 |
| generation | UInt64 | 成功替换时单调递增 |
| initialMode | language, script, width, punctuation | 每个枚举必须为已知值 |
| autoCommit | uniqueAtFour, firstAtFive | Bool |
| ranking | automaticFrequency | Bool；私密/禁止学习为更严格覆盖 |
| assistance | mixedPinyin, codeHint, candidate2And3 | Bool |
| characterSet | extendedCJK | Bool；默认 false，关闭时使用固定 Rime 扩展 CJK 范围过滤 |
| bindings | language, script, width | 结构化预设，范围冲突时拒绝 |
| pageKeyGroups | Set<PageKeyGroup> | 五个已知组的任意集合 |
| keyboardLayout | followSystem / us | 保存时必须可用 |
| appearance | 既有页大小、布局、字号缩放 | 延续既有边界 |

全新安装或“恢复默认”使用规格中的 `newInstallDefault`；v1/v2 升级使用单独的
`migrationCompatibilityDefault`，新增 `extendedCJK` 一律为 false，绝不以新安装默认覆盖旧习惯。

## 2. SessionSettingsState

每个输入会话保存：

- `activeSnapshot`: 当前组合完整使用的不可变设置快照。
- `pendingSnapshot`: 组合期间收到的最新快照；只保留最高代次。
- `sessionMode`: 当前会话语言、脚本、宽度和标点临时状态，不因普通设置保存而重置。
- `directInput`: 中文空闲态由首个大写字母开启的短期原样组合；保存有界原文和单一候选，不改变
  `sessionMode`。字母、数字和符号更新组合；空格、回车或选择提交，回车由输入法消费且不插入换行，
  Escape 取消。
- `compositionGeneration`: 组合开始时捕获的代次；组合结束前查询、排序、按键和学习决策均使用它。

状态转换：空闲会话立即采纳最新语义快照；组合会话将其置为 pending，并在提交、取消或故障
复位完成后独立采纳。新会话获得最新快照。外观字段可立即刷新，但不得改变组合语义。

## 3. KeyBinding

`KeyBinding` 由 `physicalKey`、精确 `modifiers`、`triggerPhase` 和 `preset` 构成，不存任意用户字符串。
语言绑定限定为 Shift、Control、Caps Lock 或禁用；简繁和全半角分别选择其文档化预设或禁用；
翻页是五个独立组的集合。独立修饰键由会话级 `ModifierTapState` 跟踪：
`resyncing/idle → eligible → completed/disqualified`。状态包含 `lastModifierFlags`、目标 modifier 类别、
可选物理 keyCode、开始 timestamp、设置代次和歧义标记；不保存 client、应用身份或输入文本。

`flagsChanged` 先更新该状态，随后才解析 client proxy。聚合 flags 的唯一目标 transition 是必要证据；
精确 keyCode 只增强左右键与交错判定。aggregate flags 未变化的重复 edge 是幂等重放并保持当前状态；
其他键、多 flag 同变、超时、设置代次改变或不完整配对均进入 `disqualified/resyncing`。普通 activation/deactivation 不制造完成事件；首次可证明的 flags
快照只用于同步，孤立 release 不得切换。

完成状态只输出一次 `ModifierModeIntent`，与原始事件是否 handled 分离。intent 应用规则为：client
可用时先原样提交当前编码并切换语言；client 不可用且会话空闲时只更新会话模式；client 不可用且
正在组合时丢弃 intent 并安全复位，不盲目提交原始编码。

## 4. CompositionKeySequence and Route

- `CompositionKeySequence`: 1...32 个归一化 ASCII `a...z`；不保存到磁盘。
- `wubiCode`: 当长度 1...4 且全部位于 `a...y` 时可构造。
- `pinyinState`: `invalid / viablePrefix / exactMatch`，由只读拼音索引给出。
- `route`: `wubiOnly / pinyinOnly / mixed`，由设置、编码范围和拼音可行性确定。

混输开启时，有效拼音前缀优先继续组合；第五码首选上屏只在路由已确定为五笔时触发。
序列非法、超过 32 字节或资源损坏时有界复位，不提交原始输入。

当前拼音串无精确候选但仍为有效前缀时，候选查询从后续完整键中有界生成前缀预测；精确候选存在时
不混入预测。预测候选仍以当前组合串作为 `queryKey`，选择后可按同一前缀学习排序。

## 5. Candidate and CandidatePage

候选包含 `text`、`source`（baseWubi/userWubi/localPinyin）、`queryKey`、基础次序、可选
`wubiHint`。合并器按“五笔候选、拼音候选”顺序稳定拼接，再以最终脚本转换后的显示文本去重；
第一个来源保留。编码提示是展示元数据，不参与身份、排序、选择或提交。

二码/三码五笔联想候选的 `queryKey` 仍是用户实际输入码，`wubiHint` 保存词组完整码；展示层只呈现
完整码减去输入前缀后的后续码。精确候选与联想候选分层，重复正文保留精确候选。

分页在完整合并结果上执行。选择事件产生至多一个提交和一个允许的学习增量。

## 6. LearningKey v2

学习键是 `kind + normalizedCode + candidateIdentity`。v1 五笔记录迁移为 `kind=wubi`；拼音选择可用
`kind=pinyin` 记录同码排序。关闭自动调频、私密模式或禁止学习时，既不读取分数参与排名也不写入。
记录继续有界衰减、可按学习域独立清除，且不含应用、文档、时间线或上下文。

## 7. ResourceManifest

拼音资源清单记录格式版本、固定上游来源与提交、许可、规范化规则、条目数、源文件校验和和
编译产物校验和。运行时只映射已通过 magic/version/长度/边界/校验验证的包内只读资源；失败时
禁用拼音来源并保持五笔可用，绝不尝试联网恢复。

## 8. Persistence invariants

- 设置和学习分别迁移、验证、暂存、原子替换并最多保留一个已验证 previous。
- 未知未来设置版本保留原始 current，进入只读兼容状态，Save/Restore 均拒绝。
- 保存或恢复失败不改变内存中的有效代次。
- 恢复默认只替换 Settings；UserLexicon、Learning、Base Dictionary 的内容和代次不变。
- 所有可变文件保持目录 `0700`、文件 `0600`。

## 9. MonthlyVolumeWorkload

月度等效压力负载是仅用于测试的确定性状态，不持久化用户内容：

- `logicalDay`: `1...30`；每个边界销毁并重建全部输入会话。
- `targetCommittedCharacters`: 发布门禁至少 `1_000_000`。
- `committedCharacters`: 只累加 `commitText` 客户端动作中的中文字符；marked text、取消、ASCII、
  失败和未提交候选均不计数。
- `sessionCount`: 同时覆盖至少 8 个独立会话，并在每个逻辑日重新创建。
- `metrics`: 只记录逻辑日、提交字符数、迭代数、学习增量数，以及首尾窗口延迟和 physical
  footprint；不得记录编码、候选或提交正文。

每个逻辑日运行到累计量达到按比例分配的日末阈值，确保所有 30 个边界都执行；最终允许因一个候选
含多个汉字而略高于目标，但不得低于目标。

## 10. UnsupportedAssistiveTechnologyBoundary

该边界不产生持久化实体或用户设置。产品能力清单固定记录 VoiceOver、旁白实用工具、Accessibility
Inspector 和其他屏幕阅读器专用候选朗读、辅助选择、辅助焦点与设置导航为“不支持”。普通候选页、
鼠标/键盘选择、视觉布局和设置错误信息继续使用既有模型；不得新增“实验性辅助功能”开关或隐藏
状态，也不得把系统已开启辅助技术记录到磁盘或诊断中。

## 11. RuntimePrivacyPolicy

该状态属于当前输入法进程，不是 Settings 快照的一部分：

- `privateMode`: 启用时排除既有学习分数并禁止所有学习写入。
- `learningEnabled`: 本地学习总开关；关闭时排除既有学习分数并禁止学习写入。
- `effectiveLearning`: 仅当 `!privateMode && learningEnabled && automaticFrequency` 时为真。

高级设置页读取并即时修改前两项，控制器将同一状态原子应用到所有活动会话；重新打开页面必须
回显当前值。该状态不得拥有独立状态栏表示，恢复 Settings 默认值也不得改变 `privateMode`。
