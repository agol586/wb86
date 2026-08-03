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
prefix-exists、exact-key lookup 和有界 prefix prediction；有效未完成前缀继续 marked text，精确键
优先展示自身候选，无精确候选时才从最多 24 个后续完整键预测最多 24 项。1...4 位可同时查询两个来源，五笔
tier 永远在拼音 tier 前，脚本转换后按显示文本稳定去重。混输开启且第五码仍构成有效拼音前缀时
不执行五笔第五码截断。

学习键升级为带来源种类的 v2；学习只改变同一查询键和来源 tier 内次序，不能把拼音提升到五笔之前。
关闭调频、私密模式或禁止学习时不读取分数也不写入。

**Rationale**: 不扩大五笔值对象可以保持旧不变量；prefix 查询避免在 `shang` 第五码误上屏；有界
预测让 `shenm` 等未完成连续全拼在五笔为空时仍可提前显示 `什么`，固定 24 键扫描和 24 项结果上限
使查询、合并、简繁转换和去重有界。

**Alternatives considered**: 第五码无条件提交四码首选（截断连续全拼）；拼音覆盖五笔排名（破坏熟练
用户路径）；只允许单字拼音（不满足连续全拼）。

## 6. 独立修饰键单击和事件识别

**Decision**: 每个 `IMKInputController` 旁增加会话级 `StandaloneModifierRecognizer`，让
`recognizedEvents` 返回精确的 `keyDown | flagsChanged`，不继承客户端特定的额外事件位。语言切换可选择左/右 Shift、左/右 Control、
Caps Lock 或禁用；只在配置的修饰键独立完成、无其他事件/修饰键且未超长按阈值时切换一次。
任何普通按键、同类左右键交错、设置代次变化或显式 reset 使待定手势失效。modifier observation
必须发生在 client proxy 解析之前：`sender` 为 nil 或不能转换为 `IMKTextInput` 时，仍观察活动 IMK
会话已经交付的 edge，而不是提前 reset。正常 press/release 保持未处理并透传，识别成功只产生一次
内部会话模式副作用；不得在 `flagsChanged` 上读取 `isARepeat`，长按用可注入时钟和事件 timestamp
判定。Caps Lock 按系统 toggle 型 flagsChanged 语义去重，不安装监听或 event tap。
若活动 IMK 客户端已交付 `flagsChanged` 但给出 `keyCode=0` 或其他非修饰键值，只在前后聚合
modifier flags 显示唯一目标修饰键变化时推断配置键；无变化、多变化或客户端根本未交付事件时不推测。

**Rationale**: 单独修饰键产生 flagsChanged 而非普通 keyDown；会话级状态可避免修饰键+字母、系统
快捷键、遗留 release 和跨客户端串线。Squirrel 在 client cast 失败时仍先更新 modifier transition，
并让正常 `flagsChanged` 透传；MacWubi 先要求 client proxy、失败即 reset 的顺序更可能丢失
Chromium/Electron 的 edge。T076“消费候选 press 以换取 release”的假设与该实现不符，也已被
Codex、VS Code、Chrome 的物理测试证伪。后续 Chrome 固定序列证明客户端实际交付了 edge：旧实现
在 Command-L 后第一次 Shift 失败、第二次成功。根因是非目标 modifier 把 recognizer 留在粘滞的
`disqualified` 状态；非目标 flag 已完全松开时必须恢复 idle，精确目标 press 可在当前无其他 modifier
时安全排除历史 stale flags。这一恢复规则不放宽真实组合键、重复 edge 或模糊 keyCode 的拒绝条件。

**Alternatives considered**: keyDown-only（无法识别独立修饰键）；轮询 modifier flags（无法证明配对）；
global monitor/event tap（违反会话与隐私边界）；消费 press/release（实测失败且可能改变客户端 modifier
语义）；把 `keyCode=0` 推断作为 Chromium 主修复（Squirrel 对应改动服务于远程桌面异常事件，不证明
Chromium 根因）；按应用身份特判（脆弱且扩大隐私面）。

### R12 — 输入法进程需要 agent 应用语义才能显示设置窗口

**Decision**: 输入法 bundle 使用 `LSUIElement=true`，不得使用 `LSBackgroundOnly=true`。前者保持
输入法不出现在 Dock，同时允许同一 InputMethodKit 进程按用户点击“设置…”显示标准 AppKit 窗口；
后者声明进程只能在后台运行，与产品必须提供设置窗口的合同冲突。显示设置时显式采用 accessory
activation policy、置前并激活应用，不增加独立常驻进程。

**Rationale**: Apple 将 `LSBackgroundOnly` 定义为只在后台运行，将 `LSUIElement` 定义为不显示在
Dock 的 agent 应用。设置入口是用户主动操作，因此 agent 窗口符合现有隐私和进程边界。

**Validation evidence (2026-08-02)**: 签名 arm64 build 6 覆盖安装到
`/Library/Input Methods/MacWubi.app` 后，用户从系统输入菜单点击“设置…”确认同进程设置窗口成功显示。
自动化测试同时验证程序化窗口实际创建、标题正确并进入可见状态；实现必须检查 `window == nil`，不能
依赖 `NSWindowController(window: nil)` 的 `isWindowLoaded`，后者可能在窗口仍为空时返回 true。

**Alternatives rejected**: 保留 background-only 并尝试强制 order-front（进程类型与窗口需求冲突）；
增加设置 helper（扩大签名、进程和 IPC 范围）。

### R13 — 系统输入菜单命令必须由当前 IMKInputController 接收

**Decision**: `menu()` 返回项只携带 action selector 和稳定整数 tag，不把普通 AppKit target/closure
当作执行路径。selector 必须由 `InputController` 实现，并从 InputMethodKit 传入的命令字典
`kIMKCommandMenuItemName` 取回菜单项后路由模式切换或设置窗口。

**Rationale**: InputMethodKit 在用户选择文本输入菜单命令时调用 `doCommand(by:command:)`；默认实现
检查当前 input controller 是否响应 selector，并将命令字典作为参数调用。把 action 只实现到另一个
`NSObject` target 会在系统输入菜单中被静默忽略，虽然同一进程的自建 `NSStatusItem` 菜单可以工作。

**Alternatives rejected**: 依赖 `NSMenuItem.target` 或闭包（不符合 IMK 命令转发合同）；恢复独立
状态栏项目（重复系统状态且违反 FR-033/FR-034）。

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

## 11. VoiceOver 与屏幕阅读器支持边界

**Decision**: 产品明确不支持 VoiceOver、旁白实用工具、Accessibility Inspector 或其他屏幕阅读器
专用候选朗读、辅助选择、辅助焦点与设置导航。删除自定义辅助候选快照、元素树、公告、焦点发布和
专用控件语义；候选面板继续提供普通显示、鼠标选择、键盘选择、分页、定位和视觉环境适配。设置窗口
继续维护普通键盘焦点顺序与可见错误信息，但不发布专用辅助公告。开启系统辅助技术不得导致崩溃或
错误提交，但不构成支持承诺。

**Rationale**: 物理验收已经表明屏幕阅读器导航依赖复杂容器交互，剩余支持无法稳定证明。删除专用
适配并明确边界可避免误导用户，也减少辅助焦点抢占文本客户端焦点的风险，同时不影响主输入路径。

**Alternatives considered**: 保留未完成代码并标记实验性（仍会暗示支持且扩大维护面）；继续把手工
验收作为发布门禁（用户明确移出范围）；主动禁用系统辅助技术（越权且不可接受）；删除整个自绘候选
面板（会破坏鼠标选择、外观和多显示器功能）。

## 12. 私密与学习状态入口

**Decision**: 私密模式与本地学习作为高级设置页中的即时运行时控制，由同一策略控制器原子发布到
所有活动输入会话；重新打开设置页时读取控制器的当前状态。两项控制不创建独立 `NSStatusItem`，
也不在菜单栏显示“`五·学`”或“`五·私`”。私密模式继续独立于 Settings 快照，恢复默认设置不会
关闭它；本地学习运行时总开关与持久化的自动调频策略共同决定是否读取和写入学习数据。

**Rationale**: 独立状态栏项目与系统输入菜单重复、占用菜单栏空间，并把学习状态和主要设置入口
分散到两个位置。集中到高级页可在不增加全局事件、权限或持久化耦合的情况下保留即时控制。

**Alternatives considered**: 保留精简状态图标（仍占用状态栏）；把控制塞进系统输入菜单（仍分散
设置体验）；将私密模式持久化为普通设置（会改变恢复默认和临时隐私语义）。

## 13. 五笔短码后的本地词组联想

**Decision**: 二码或三码存在精确五笔候选时，在同一个两字母前缀范围内有界扫描基础词库，追加
正文以精确候选开头的长编码词组。二分定位首条匹配记录后最多解码 256 条，精确候选独立成更高
tier，重复正文保留精确身份；联想候选仍以
本次输入码作为查询/学习键，以完整词组码作为展示元数据，界面只显示未输入后缀。一码不联想以避免
扫描和展示过宽，四码没有后续五笔码空间。

**Rationale**: 固定 WB86 资源已经包含 `机会(smwf)`、`机构(smsq)`、`机场(smfn)`、`机器(smkk)`
和 `机遇(smjm)`，现有 exact-only 路由才是 `sm` 只显示 `机` 的原因。复用映射资源和现有两字母
prefix range 不增加依赖、网络、持久化或词库副本，并保持查询有界。

**Alternatives considered**: 在线联想（违反隐私）；运行时解析上游 YAML（违反只读二进制边界）；
一码全前缀联想（候选噪声和扫描范围过大）；把联想正文直接硬编码进产品（破坏词库来源契约）。
