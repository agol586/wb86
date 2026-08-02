# Phase 0 Research: 设置体验增强

## 1. 设置版本与全新安装默认值

**Decision**: Settings 升级到 schema v2，使用与当前 Codable 形状完全匹配的私有 v1 DTO 严格
解码、验证和显式映射。`newInstallDefault` 与 `migrationCompatibilityDefault` 分离；旧值保留语义，
新增字段采用保守兼容默认。v1 四码开关映射到已修正的“四码唯一”语义。

**Rationale**: 当前 `.default` 同时承担全新安装、恢复和回退，若给新增非可选字段直接使用新默认，
升级会改变用户按键和混输行为。显式 DTO 也能让缺失、非法和未来字段的处理可测试。

**Alternatives considered**: `decodeIfPresent` 后填新默认（会静默改变旧用户行为）；保留多候选四码
误提交（违反 FR-005）；删除旧设置重建（破坏升级契约）。

## 2. 未知未来版本与原子恢复

**Decision**: schema 大于 2 时保留 current 原始字节，进入设置只读兼容状态，拒绝 Save/Restore；
不得调用会以 supported previous 覆盖 future current 的普通损坏恢复路径。损坏的受支持版本可从完整
previous 恢复，迁移或写入失败则保留旧 current/previous 并使用安全内存回退。

**Rationale**: future 数据不是 corruption；旧程序覆盖它会造成不可逆降级。设置、学习和用户词库
继续作为独立事务域。

**Alternatives considered**: 把 future 当作损坏（数据丢失）；先发布运行时再写盘（保存失败会产生
假生效状态）。

## 3. 多会话安全应用

**Decision**: 协调器发布带单调代次的不可变设置快照。每个会话独立持有 active/pending；空闲会话
立即采纳，组合会话在自己的客户端动作结束且转为空闲后采纳最新 pending。查询、排名、分页和学习
接收会话冻结策略，不再读取全局可变语义设置。保存策略与“初始化/重新激活默认模式”分离。

**Rationale**: 当前实现会因一个长组合阻塞所有会话，并可能让引擎使用旧开关却让共享 ranker 使用
新学习策略。按会话快照可证明一个组合只观察一个代次，且保存不会抹掉临时模式切换。

**Alternatives considered**: 等全部会话空闲后统一切换（无关会话被阻塞）；查询前临时交换全局设置
（跨会话竞态）；每次保存重置 mode（破坏会话内状态）。

## 4. 本地连续全拼资源

**Decision**: 固定 `rime/rime-pinyin-simp` 的 `pinyin_simp.dict.yaml` commit
`0c6861ef7420ee780270ca6d993d18d4101049d0` 作为构建输入，随附 Apache-2.0 LICENSE、AUTHORS、
源 SHA-256 `e341598343a0f0f2035bb1aafc34a7f3bb7887deeecb3f60796262aaa2983e6b` 和来源清单。
构建期用纯 Swift 归一化为连续键（`ni hao → nihao`）、按最终简体文本去重、确定排序，并将每个键
限制为 64 项；运行时只读 `MWPY` 二进制，不引入 librime 或运行时 YAML 解析。

源数据约 65,125 条、38,999 个连续键。格式使用版本头、首/次字母范围、每 32 键重启的前缀压缩
键表、候选区和 UTF-8 blob；可复用现有 WB86 字符串/记录索引并直接提供五笔提示。预估生成资源
约 1.25–1.4 MiB，但这不是性能通过证据；若 Release 常驻内存超过 `<15 MB`，必须减小候选上限或
进一步压缩资源，不得放宽宪章门禁。

**Rationale**: 该固定语料包含有权重的单字和多音节短语，许可宽松，能以现有映射二进制架构保持
离线、可复现和有界查询。已有约 45,181 条记录正文可复用 WB86，减少重复字符串与反向索引内存。

**Alternatives considered**: Unihan `kMandarin`（许可合适但缺少短语与上下文频率）；rime-essay
（LGPL、体积和维护复杂度不必要）；SQLite/librime（新增运行时边界）；Swift Dictionary/trie 或运行时
YAML（内存/启动不可控）；云端拼音（违反隐私）。

**Primary sources**:

- [Rime Pinyin Simplified repository](https://github.com/rime/rime-pinyin-simp)
- [Apache-2.0 license in the repository](https://github.com/rime/rime-pinyin-simp/blob/master/LICENSE)
- [Pinned dictionary source](https://raw.githubusercontent.com/rime/rime-pinyin-simp/0c6861ef7420ee780270ca6d993d18d4101049d0/pinyin_simp.dict.yaml)
- [Unicode UAX #38: Unihan database](https://www.unicode.org/reports/tr38/)
- [Unicode License v3](https://www.unicode.org/license.txt)

## 5. 拼音路由、合并与学习

**Decision**: 保留 1...4 位五笔 `InputCode`，新增 1...32 位 ASCII `PinyinCode`/组合序列。索引支持
prefix-exists 和 exact-key lookup；有效未完成前缀继续 marked text，exact 才展示拼音候选。1...4 位
可同时查询两个来源，五笔 tier 永远在拼音 tier 前，脚本转换后按显示文本稳定去重。混输开启且第五码
仍构成有效拼音前缀时不执行五笔第五码截断。

学习键升级为带来源种类的 v2；学习只改变同一查询键和来源 tier 内次序，不能把拼音提升到五笔之前。
关闭调频、私密模式或禁止学习时不读取分数也不写入。

**Rationale**: 不扩大五笔值对象可以保持旧不变量；prefix 查询避免在 `shang` 第五码误上屏；每键
64 项上限使合并、简繁转换和去重有界。

**Alternatives considered**: 第五码无条件提交四码首选（截断连续全拼）；拼音覆盖五笔排名（破坏熟练
用户路径）；只允许单字拼音（不满足连续全拼）。

## 6. Shift 单击和事件识别

**Decision**: 每个 `IMKInputController` 旁增加 `StandaloneShiftRecognizer`，把 `recognizedEvents`
扩展为 `super | flagsChanged`。只对配对的左/右 Shift press/release、无重复语义、无其他事件/修饰键、
未超长按阈值的会话内手势切换一次；任何按键、第二个 Shift、会话切换、设置代次变化或 reset 使手势
失效。press/release 均透传，release 只产生会话内副作用。不得在 `flagsChanged` 上读取 `isARepeat`，
长按用可注入时钟和事件 timestamp 判定。

**Rationale**: 单独修饰键产生 flagsChanged 而非普通 keyDown；会话级配对可避免 Shift+字母、系统
快捷键、遗留 release 和跨客户端串线，同时不采用隐私违规的全局监听。

**Alternatives considered**: keyDown-only（无法识别单 Shift）；轮询 modifier flags（无法证明配对）；
global monitor/event tap（违反会话与隐私边界）；消费 release（可能让客户端认为 Shift 卡住）。

**Platform caveat**: Apple SDK 说明，默认“点击组合区外”处理只在默认 recognizedEvents 恰为 keyDown
时有保证。扩展 mask 后必须在真机回归点击外部、失活和鼠标选择；若失效，显式实现/转发
`IMKMouseHandling` 或安全取消，不得只凭单元测试假设。

**Primary sources**:

- [IMKInputController](https://developer.apple.com/documentation/inputmethodkit/imkinputcontroller)
- [IMKStateSetting recognizedEvents](https://developer.apple.com/documentation/inputmethodkit/imkstatesetting/recognizedevents(_:))
- [NSEvent flagsChanged mask](https://developer.apple.com/documentation/appkit/nsevent/eventtypemask/flagschanged)
- [NSEvent isARepeat](https://developer.apple.com/documentation/appkit/nsevent/isarepeat)
- [characters(byApplyingModifiers:)](https://developer.apple.com/documentation/appkit/nsevent/characters(byapplyingmodifiers:))

## 7. 快捷键优先级与边界消费

**Decision**: keyDown 映射顺序固定为：使待定 Shift 手势失效；精确匹配非重复模式快捷键；其余
Command/Control/Option 安全透传；组合中匹配快捷选择、翻页、数字/空格；最后处理字母和普通文本。
翻页组为独立 Set。启用的候选控制键在第一页/末页或第二/第三候选缺失时被消费但保持组合不变；
空闲、关闭或修饰键不符时透传。

**Rationale**: 精确 modifiers 防止抢占应用快捷键；边界时把已配置控制键漏到文档会在 marked text
期间改变正文，反而破坏组合契约。

**Alternatives considered**: modifiers 子集匹配（抢快捷键）；边界一律透传（破坏活动组合）；缺失目标
时选择最近候选（规格明确禁止）。

## 8. 美国布局与跟随系统

**Decision**: `.us` 使用内建不可变 ANSI-US 虚拟键码表，不要求用户启用系统 US input source；
`.followSystem` 在适配层通过 `TISCopyCurrentASCIICapableKeyboardLayoutInputSource` 取得 Unicode layout
data，并在组合开始时固定 translator 快照。即时重解释可用 `characters(byApplyingModifiers: [])`；需要
固定布局时只在适配层使用 `UCKeyTranslate`、零 dead-key state 和 no-dead-keys，拒绝 nil、多 scalar、
非 ASCII 或歧义输出。运行中不可用时保留最后有效 translator、明确反馈并透传无法解释的事件，
不能静默切成 US。

**Rationale**: 当前 input source 会返回 MacWubi 本身；Apple 专门提供 ASCII-capable layout 给输入法。
组合级快照避免系统布局中途改变导致半段输入含义变化。

**Alternatives considered**: 永远信任 event.characters（不能提供固定 US）；永远按 keyCode（不能跟随
系统）；切换系统 US source（不必要的外部状态变更）；静默 fallback（违反 FR-019）。

## 9. 有序第五码客户端动作

**Decision**: 核心结果从单一 `ClientTextAction` 扩展为有序、不可重复执行的复合动作列表。第五码
路径明确为“提交旧候选 → 用第五码建立新 marked text → 展示新候选”；适配器完成整个列表后才通知
设置协调器进入空闲/新组合边界。

**Rationale**: 当前单动作无法表达提交旧候选后不丢第五码，且过早应用 pending 设置会让一个物理
事件混用两个代次。

**Alternatives considered**: 适配器私自补发键（核心和客户端状态可分叉）；提交后丢弃第五码（违反
FR-006）；把两个动作分成两个事件（可能插入设置切换和会话竞态）。

## 10. 性能与验证

**Decision**: 基准覆盖五笔-only、拼音 exact/prefix、合并/去重/简繁、翻页、提示和全部设置开启；
记录真实生成资源大小及 Release 进程物理 footprint。长期稳定性不再依赖八小时墙钟等待，而使用
可复现的月度等效工作量：顺序模拟 30 个逻辑输入日，每日结束销毁并重建多个会话，累计只按客户端
动作实际提交的中文字符计数，至少达到 1,000,000 字。工作量必须包含设置 churn、五笔/拼音混输、
调频和翻页，并比较预热后首尾窗口的内存与延迟；取消、marked text 和错误路径不计入提交量。
映射资源只创建一次，页面按需解码，输入路径不得读取设置文件或完整物化词典/学习快照。真机还要
验证 flagsChanged 交付、按键透传、点击外部取消、候选鼠标行为和多应用会话。

**Rationale**: 当前实测距 15 MB 上限余量有限，资源大小估计不能替代发布进程证据；以提交量和
逻辑日边界定义强度可在分钟级重复完整月度输入规模，又不会把机器速度或空闲等待误当作覆盖度。
InputMethodKit 部分行为仍无法由纯单元测试证明。

**Alternatives considered**: 仅报告 p50/p95（宪章要求每个样本 `<2 ms`）；以文件大小推断 RSS；
固定八小时墙钟运行（覆盖量随硬件差异且大部分时间价值低）；连续等待一个自然月（不可重复）；把
真机行为当作 SDK 保证。
