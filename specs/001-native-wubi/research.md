# Phase 0 Research: 隐私优先的原生五笔 86 输入法

## InputMethodKit 接入方式

**Decision**: 在后台输入法应用入口创建一个 `IMKServer`，由系统为每个输入会话实例化
`IMKInputController` 子类。适配层采用 `handle(_:client:)` 接收完整按键事件，通过
`IMKTextInput` 客户端更新 marked text 和提交文本，并使用 `IMKCandidates` 呈现当前页。
取消操作不得直接依赖 `IMKInputController.cancelComposition()`，因为该方法会把
`originalString` 插入客户端；适配层应显式清除 marked text 和本地状态，确保 FR-005 的
“取消但不提交”语义。

**Rationale**: Apple 将 `IMKServer` 定义为客户端连接管理者，每个会话对应一个
`IMKInputController`；`IMKServerInput` 明确支持完整事件、文本数据和键绑定三种路径。
完整事件路径能在一个边界内区分字母、数字、翻页键、修饰键和命令键，同时把核心状态机
保持为平台无关的值类型。`IMKCandidates.update()` 只刷新数据，不负责可见性，因此适配层
必须显式执行显示和隐藏。

**Alternatives considered**:

- `inputText`/key binding：样板更少，但数字选择、分页和修饰键转发规则更分散。
- 自绘候选窗口：控制力更强，但增加可访问性、定位和窗口生命周期风险；先验证系统候选
  窗口能否满足布局和 VoiceOver 契约，失败时才采用自绘且必须通过无障碍门禁。

**Sources**: [InputMethodKit overview](https://developer.apple.com/documentation/inputmethodkit),
[IMKServerInput](https://developer.apple.com/documentation/inputmethodkit/imkserverinput),
[IMKCandidates](https://developer.apple.com/documentation/inputmethodkit/imkcandidates),
[cancelComposition](https://developer.apple.com/documentation/inputmethodkit/imkinputcontroller/cancelcomposition%28%29),
[IMKServer initialization](https://developer.apple.com/documentation/inputmethodkit/imkserver/init%28name%3Abundleidentifier%3A%29)

## Bundle 元数据与生命周期

**Decision**: 输入法作为 `LSBackgroundOnly` 应用 bundle。bundle identifier 固定为
`org.macwubi.inputmethod.MacWubi`，必须包含 IMK/TIS 实际识别所需的完整
`.inputmethod.` 段。`Info.plist` 至少声明唯一的
`InputMethodConnectionName`、`InputMethodServerControllerClass`、稳定 `TISInputSourceID`、
BCP 47 目标语言、图标和中文字符集信息；首个版本只注册一个直接可选择的系统输入源，
不声明 `ComponentInputModeDict`。产品内部的中文/英文、标点、宽度和字形切换仍由每个
输入会话的纯 Swift 状态机管理，不映射为多个 TIS input mode；
入口持有 `IMKServer` 并运行应用事件循环。连接名固定为 Apple Swift IMK 样例采用的
`org.macwubi.inputmethod.MacWubi_Connection`。默认安装目标为系统级
`/Library/Input Methods/MacWubi.app`，复制或升级时使用 macOS 标准管理员授权。

**Rationale**: `IMKServer` 的 bundle 初始化器会读取这些键，加载控制器类并按连接名注册
客户端通信。Text Input Sources 将带 `ComponentInputModeDict` 的输入法建模为不可直接
选择的 mode-enabled 父项；输入模式只有在父输入法已经启用时才能选择。2026-08-01 的实机
证据显示，单一五笔模式配置形成了“子模式默认启用、父项仍禁用”的不可添加状态，而 Apple
的 Swift IMK 样例使用单一无子模式输入法。当前产品只有一个系统级入口，采用直接可选模型
避免没有用户价值的父子启用依赖。旧标识
`org.macwubi.inputmethod` 虽包含单词但以 `.inputmethod` 结尾，实机表现为注册返回
`noErr` 而 TIS 枚举为零；改用带完整 `.inputmethod.` 段的标识是 T019 的最小修正。2026-08-01
实机还显示，用户级 bundle 虽可被 TIS 枚举，却不出现在系统设置的可添加列表；同一签名
bundle 安装到系统级目录后可启用、选择并由 TextEdit 连接。因此系统级目录是当前确定性
安装路径，管理员授权只用于 bundle 生命周期，不扩大运行时数据权限。Apple 对第三方输入法
安装路径的专门说明已归档，因此当前系统行为仍必须逐个受支持系统实机验证。当前系统日志
会在 XPC endpoint 建立前报告一次旧式连接名拒绝；把连接名改为不含句点的值后警告仍存在，
随后 endpoint 注册和 `Activate Server` 均成功，故不能把该警告归因于连接名字符集。

**Alternatives considered**:

- 用户级 `~/Library/Input Methods/`：不需要管理员权限，但在当前 macOS 实机上无法通过系统
  设置完成添加和启用，不作为受支持安装路径。
- 额外设置应用：当前没有必须独立配置的功能，增加 target 和签名面没有用户价值。

**Sources**: [IMKServer bundle initializer and Info.plist keys](https://developer.apple.com/documentation/inputmethodkit/imkserver/init%28name%3Abundleidentifier%3A%29),
[QA1810: third-party input method management](https://developer.apple.com/library/archive/qa/qa1810/_index.html),
[inputMethodsDirectory](https://developer.apple.com/documentation/foundation/filemanager/searchpathdirectory/inputmethodsdirectory),
[Text Input Source Services reference](https://leopard-adc.pepas.com/documentation/TextFonts/Reference/TextInputSourcesReference/TextInputSourcesReference.pdf),
[Swift InputMethodKit sample](https://github.com/ensan-hcl/macOS_IMKitSample_2021)

## 系统集成与分发安全策略

**Decision**: 输入法 target 不启用 `com.apple.security.app-sandbox`，不申请网络、Apple
Events、Mach 或 Hardened Runtime 弱化权限。正式发行使用 Developer ID Application、
Hardened Runtime、安全时间戳和 Apple 公证；本机系统集成验证可使用 Apple Development。
基础词库从 bundle 读取，个性化数据只写入固定 Application Support 目录。

**Rationale**: Apple 将 App Sandbox 明确列为 Mac App Store 分发要求，而站外分发使用
Developer ID 与公证。2026-08-01 实机证明沙箱化输入法在补齐 Mach 注册例外、TIS 元数据、
登录刷新和 Apple Development 签名后仍不进入 TIS 枚举；继续扩展沙箱例外没有官方契约
依据。Hardened Runtime、公证、无网络实现与严格本地路径权限共同形成新的安全边界。

**Alternatives considered**:

- 继续增加沙箱临时例外：没有端到端发现证据，且扩大不可维护权限面，拒绝。
- 关闭 Gatekeeper/SIP：破坏系统安全，拒绝。
- App Group 或固定外部词库目录：单一进程设置窗口和一次性用户选择文件已满足需求，拒绝。

**Sources**: [Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox),
[Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox),
[App Sandbox](https://developer.apple.com/documentation/security/app-sandbox),
[Developer ID](https://developer.apple.com/support/developer-id/),
[Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
[Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime)

## Apple Silicon 架构与签名

**Decision**: Release 配置显式限定为 Apple Silicon `arm64`，并验证产物不存在 `x86_64`
slice 或 Universal Binary 兼容性声明。本地开发采用 ad-hoc 或 Apple Development 签名；
发布渠道确定后再使用 Developer ID。每次发布候选都分别执行架构和严格签名验证。

**Rationale**: 产品范围与宪章 2.0.0 已明确排除 Intel Mac。显式固定 `arm64` 可避免构建设置
随 Xcode 默认值变化而意外恢复 `x86_64`；架构与签名完整性仍是不同门禁，必须分别验证。

**Alternatives considered**:

- Universal Binary：扩大构建、签名与硬件验收矩阵，已被产品范围明确排除。
- 单独构建后手工 `lipo` 合并：不符合仅交付 `arm64` 和以 Xcode 为唯一入口的范围。
- 仅 ad-hoc 分发：适合本地开发，不足以替代未来面向用户的 Developer ID 与公证流程。

**Sources**: [Building a universal macOS binary](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary),
[Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)

## 词库布局与查询

**Decision**: 使用构建期生成、版本化、只读的紧凑二进制文件。记录按压缩后的四字母编码、
稳定 rank 和词条 UTF-8 字节排序；一至二位前缀使用小型范围表，范围内再二分查找并只解码
当前页最多九项。运行时以只读映射方式加载，加载前验证 magic、版本、边界和校验值。

**Rationale**: 避免把完整产品词库展开成 Swift 字典和字符串对象，可将主要数据保留在映射
文件中并控制 15 MB 内存预算；稳定排序和有界解码同时支持确定性和 2 ms 查询门禁。

**Alternatives considered**:

- `[String: [String]]` 全量加载：实现简单，但对象和字符串开销难以满足 15 MB。
- SQLite：系统自带但不是纯 Swift 核心，且查询层和缓存更难做严格内存核算。
- 完整引用节点 trie：查询快，但节点与引用开销较高；最多四位编码可用紧凑前缀范围解决。
- 文本词库运行时解析：便于编辑，但启动成本、内存与损坏恢复更难控制。

## 测试与性能测量

**Decision**: 使用 XCTest 覆盖纯核心状态转换、词库格式、损坏输入、适配器契约和性能。
查询性能以预热后的代表性一至四位编码集测量 p99；内存门禁使用 Release 输入法进程在固定
设备/系统/词库/样本上的常驻内存峰值。跨应用加载和候选 UI 采用发布 bundle 实机验收。

**Rationale**: 核心测试无需运行完整输入法，反馈快且可注入所有失败；系统加载、签名、
候选窗口和进程内存只能由真实 bundle 证明。两层测试共同覆盖逻辑与系统边界。

**Alternatives considered**:

- 只做端到端测试：故障注入困难、反馈慢且难定位性能回归。
- 只做单元测试：无法证明系统加载、签名、候选 UI、分发安全或真实进程内存。

**Sources**: [XCTest performance tests](https://developer.apple.com/documentation/xctest/performance-tests),
[XCTClockMetric](https://developer.apple.com/documentation/xctest/xctclockmetric),
[XCTMemoryMetric](https://developer.apple.com/documentation/xctest/xctmemorymetric),
[ContinuousClock](https://developer.apple.com/documentation/swift/continuousclock)

## 支持范围

**Decision**: 产品首个支持基线为 macOS 13.0，仅在 Apple Silicon Mac 上做发布验收；
矩阵必须覆盖 macOS 13 和开发时最新支持的 macOS 版本。Swift 使用版本 5 语言模式，避免
依赖只在更新系统存在的运行时能力。

**Rationale**: macOS 13 提供足够广的 Apple Silicon 系统基线。明确的最低版本、目标架构
和最新支持版本使安装、签名与 InputMethodKit 验收可复现。

**Alternatives considered**:

- Intel Mac 与 Universal Binary：超出宪章 2.0.0 和当前产品范围。
- 仅支持最新 macOS：测试矩阵最小，但会无必要地排除较早的 Apple Silicon 系统。
- 支持 macOS 12 或更早：扩大兼容验证和签名差异，当前暂无用户证据支持该成本。

## 个性化数据与原子迁移

**Decision**: Settings、UserLexicon 和 Learning 分别存放在
`~/Library/Application Support/org.macwubi.inputmethod/` 中的版本化快照；目录权限为
`0700`，数据文件权限为 `0600`。每次更新先在目标卷构建并验证完整替代文件，再用 Foundation 文件替换
保留一个 previous；未知未来版本保持原样并加载该域安全默认。三个域独立提交和恢复。

**Rationale**: Foundation 的 Application Support 目录解析提供稳定的用户级路径；实现必须
创建专用子目录并强制最小 POSIX 权限。文件替换 API 支持避免数据丢失并保留备份。按域原子性与规格的故障隔离一致，也避免伪造跨多个文件的
系统级事务保证。UserDefaults 只适合非敏感小型配置且未加密，不满足词库、学习和回退要求。

**Alternatives considered**:

- UserDefaults 保存全部状态：缺少所需版本快照和回退语义，且不适合用户词条或学习数据。
- 一个产品级复合大文件：可提供跨域单事务，但任一域变化都重写全部数据，扩大损坏面。
- 数据库：引入不必要的查询与迁移层，并增加内存核算复杂度。

**Sources**: [Application Support directory](https://developer.apple.com/documentation/foundation/url/applicationsupportdirectory),
[FileManager directory lookup](https://developer.apple.com/documentation/foundation/filemanager/url%28for%3Ain%3Aappropriatefor%3Acreate%3A%29),
[FileManager replacement](https://developer.apple.com/documentation/foundation/filemanager/replaceitem%28at%3Awithitemat%3Abackupitemname%3Aoptions%3Aresultingitemurl%3A%29),
[UserDefaults](https://developer.apple.com/documentation/foundation/userdefaults)

## 本地导入导出

**Decision**: 只从设置窗口通过系统打开/保存面板执行一次性导入导出；操作后立即释放
文件引用，不保存安全作用域书签。导入先形成完整新快照，
验证成功后才替换 UserLexicon；导出使用版本化产品格式或文档化 UTF-8 文本。

**Rationale**: 标准面板表达明确用户意图。即使非沙箱进程具有更宽文件系统能力，产品也
只访问当次面板返回的 URL；不保留书签、不扫描目录可避免读取不相关内容。

**Alternatives considered**:

- 自动扫描其他输入法目录：超出授权、不可审计且可能涉及私有格式，拒绝。
- 持久化文件书签：无后台同步或自动更新需求，拒绝。
- 网络导入：违反零网络产品边界，拒绝。

**Sources**: [NSOpenPanel](https://developer.apple.com/documentation/appkit/nsopenpanel),
[NSSavePanel](https://developer.apple.com/documentation/appkit/nssavepanel)

## 安全输入与私密模式

**Decision**: 不宣称自动识别密码框。产品只处理当前 InputMethodKit 会话交付的事件，禁止
全局监听或绕过 Secure Event Input；候选学习只能来自本输入法的成功提交，并提供可见、
可快速切换的私密模式及全局学习开关，二者都能确定性禁止写入和学习排序。

**Rationale**: Apple 的公开 InputMethodKit API 没有可靠的每客户端安全输入状态回调。
归档的 Secure Event Input 说明保护启用它的进程按键，但不是输入法客户端分类契约。显式
私密模式是当前可证明、可测试的产品控制，不能用全局状态探测伪装成自动保证。

**Alternatives considered**:

- 用全局安全事件状态判断当前客户端：Apple 未记录这种归因，证据不足。
- 监听系统级按键判断密码框：违反隐私与输入边界，拒绝。
- 移除本地学习：牺牲长期替代能力；以明确开关和私密模式控制更合适。

**Sources**: [InputMethodKit](https://developer.apple.com/documentation/inputmethodkit),
[TN2150: Using Secure Event Input Fairly](https://developer.apple.com/library/archive/technotes/tn2150/_index.html)

## 候选与设置无障碍

**Decision**: 设置窗口使用标准 AppKit 控件。T020 选择自定义非激活 `NSPanel` 候选展示，
以标准可访问 AppKit 元素明确表达候选、序号、选中状态、页码和操作；不采用
`IMKCandidates` 作为发布候选窗。

**Rationale**: 当前 SDK 的 `IMKCandidates` 能配置选择键、三种固定 panel、候选字体、
可见性和位置提示，但公开接口不暴露每个候选的辅助标签、值、选中状态、顺序、动作或焦点
策略；字体设置还明确不影响选择键字体。运行时类只继承 `NSResponder` 的通用辅助方法，
没有公开候选元素映射。无法证明 VoiceOver、Accessibility Inspector、完整字号缩放和焦点
契约时，规格要求选择可验证的自定义实现。

**Alternatives considered**:

- 假定系统候选窗口天然符合规格：缺少文档证据，拒绝。
- 继续使用 `IMKCandidates`：键盘选择和基础定位可用，但关键无障碍语义无法通过公开 API
  保证，拒绝作为发布实现。

**Sources**: [Accessibility for AppKit](https://developer.apple.com/documentation/appkit/accessibility-for-appkit),
[Integrating accessibility](https://developer.apple.com/documentation/accessibility/integrating-accessibility-into-your-app),
[IMKCandidates](https://developer.apple.com/documentation/inputmethodkit/imkcandidates)

## 离线更新边界

**Decision**: 所有发布 target 都不包含网络 client/server entitlement。产品和基础词库更新
只能通过签名应用发布包或用户主动选择的本地导入文件完成，不实现应用内检查或下载。

**Rationale**: 非沙箱进程不能依赖 entitlement 阻止联网，因此零网络承诺必须由禁止网络
框架/符号的静态检查、运行时网络观察和发布审计共同证明。

**Alternatives considered**:

- 只关闭遥测但保留更新网络：扩大攻击和信任面，不符合“完全隐私”的简洁承诺。
- 配套更新守护进程：会绕开输入法 target 的网络边界，拒绝。

**Source**: [Outgoing network entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client)
