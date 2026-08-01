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

**Decision**: 输入法作为 `LSBackgroundOnly` 应用 bundle。`Info.plist` 至少声明唯一的
`InputMethodConnectionName`、`InputMethodServerControllerClass`、图标和中文字符集信息；
入口持有 `IMKServer` 并运行应用事件循环。开发安装目标为用户级 `~/Library/Input Methods/`。

**Rationale**: `IMKServer` 的 bundle 初始化器会读取这些键，加载控制器类并按连接名注册
客户端通信。用户级安装缩小产品权限与影响面，不需要系统级复制权限。Apple 对第三方
输入法安装路径的专门说明已归档，因此它只作为路径基线，当前系统行为必须实机验证。

**Alternatives considered**:

- 系统级 `/Library/Input Methods/`：适合多用户部署，但需要管理员权限，不作为默认路径。
- 额外设置应用：当前没有必须独立配置的功能，增加 target 和签名面没有用户价值。

**Sources**: [IMKServer bundle initializer and Info.plist keys](https://developer.apple.com/documentation/inputmethodkit/imkserver/init%28name%3Abundleidentifier%3A%29),
[QA1810: third-party input method management](https://developer.apple.com/library/archive/qa/qa1810/_index.html),
[inputMethodsDirectory](https://developer.apple.com/documentation/foundation/filemanager/searchpathdirectory/inputmethodsdirectory)

## 沙盒与权限策略

**Decision**: 输入法 target 启用 `com.apple.security.app-sandbox`，不申请网络、Apple
Events 或硬件权限；仅为用户显式导入导出申请 User Selected Files Read/Write。基础词库
从 bundle 读取，个性化数据写入容器 Application Support。将沙盒下的 `IMKServer` 注册与
跨应用输入作为首个系统集成阻断测试；通过前不把沙盒兼容性或分发资格标记为已证明。

**Rationale**: App Sandbox 按 target 启用，并通过 entitlement 仅恢复必需能力。本设计的
固定 bundle 资源不要求额外文件权限。Apple 文档说明 `IMKServer` 使用命名连接，但没有
发布 InputMethodKit 专用沙盒 entitlement、例外或端到端兼容性声明，因此文档证据不足以
证明沙盒化系统输入法可运行；实机纵切是继续实现的硬门禁。

**Alternatives considered**:

- 禁用沙盒：直接违反宪章，拒绝。
- 预先添加临时例外或非沙盒 XPC：没有已证实需求，会扩大权限和复杂性，拒绝。
- App Group 或固定外部词库目录：单一进程设置窗口和一次性用户选择文件已满足需求，拒绝。

**Sources**: [Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox),
[Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox),
[Enabling App Sandbox](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html)

## Universal Binary 与签名

**Decision**: Release 配置使用 Xcode Standard Architectures，显式验证产物同时包含
`arm64` 和 `x86_64`。本地开发采用 ad-hoc 或 Apple Development 签名；发布渠道确定后再
使用 Developer ID。每次发布候选都执行严格签名验证并分别检查两种架构的签名信息。

**Rationale**: Apple 说明 Xcode 的标准 macOS 架构会为 Release 构建生成 Universal Binary，
并且每个架构 slice 独立签名。架构存在性与签名完整性是不同门禁，必须分别验证。

**Alternatives considered**:

- 单独构建后手工 `lipo` 合并：适用于自定义构建系统，但本项目以 Xcode 为唯一入口。
- 仅 ad-hoc 分发：适合本地开发，不足以替代未来面向用户的 Developer ID 与公证流程。

**Sources**: [Building a universal macOS binary](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary),
[Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/),
[TN3126: signatures in universal binaries](https://developer.apple.com/documentation/technotes/tn3126-inside-code-signing-hashes)

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
- 只做单元测试：无法证明系统加载、签名、候选 UI、沙盒或真实进程内存。

**Sources**: [XCTest performance tests](https://developer.apple.com/documentation/xctest/performance-tests),
[XCTClockMetric](https://developer.apple.com/documentation/xctest/xctclockmetric),
[XCTMemoryMetric](https://developer.apple.com/documentation/xctest/xctmemorymetric),
[ContinuousClock](https://developer.apple.com/documentation/swift/continuousclock)

## 支持范围

**Decision**: 产品首个支持基线为 macOS 13.0，并在一台 Apple Silicon Mac 与一台
Intel Mac 上做发布验收；还需覆盖开发时最新支持的 macOS 版本。Swift 使用版本 5 语言
模式，避免依赖只在更新系统存在的运行时能力。

**Rationale**: macOS 13 提供足够广的现代系统基线，并保留可实际获得的 Intel 测试范围。
明确的最低版本使安装、沙盒和 InputMethodKit 验收可复现。

**Alternatives considered**:

- 仅支持最新 macOS：测试矩阵最小，但无必要地排除仍可原生运行的 Intel 设备。
- 支持 macOS 12 或更早：扩大兼容验证和签名差异，当前暂无用户证据支持该成本。

## 个性化数据与原子迁移

**Decision**: Settings、UserLexicon 和 Learning 分别存放在沙盒容器 Application Support
中的版本化快照。每次更新先在目标卷构建并验证完整替代文件，再用 Foundation 文件替换
保留一个 previous；未知未来版本保持原样并加载该域安全默认。三个域独立提交和恢复。

**Rationale**: Foundation 的标准目录解析会把沙盒应用定位到自己的容器；文件替换 API
支持避免数据丢失并保留备份。按域原子性与规格的故障隔离一致，也避免伪造跨多个文件的
系统级事务保证。UserDefaults 只适合非敏感小型配置且未加密，不满足词库、学习和回退要求。

**Alternatives considered**:

- UserDefaults 保存全部状态：缺少所需版本快照和回退语义，且不适合用户词条或学习数据。
- 一个产品级复合大文件：可提供跨域单事务，但任一域变化都重写全部数据，扩大损坏面。
- 数据库：引入不必要的查询与迁移层，并增加内存核算复杂度。

**Sources**: [App Sandbox container](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox),
[Application Support directory](https://developer.apple.com/documentation/foundation/url/applicationsupportdirectory),
[FileManager directory lookup](https://developer.apple.com/documentation/foundation/filemanager/url%28for%3Ain%3Aappropriatefor%3Acreate%3A%29),
[FileManager replacement](https://developer.apple.com/documentation/foundation/filemanager/replaceitem%28at%3Awithitemat%3Abackupitemname%3Aoptions%3Aresultingitemurl%3A%29),
[UserDefaults](https://developer.apple.com/documentation/foundation/userdefaults)

## 本地导入导出

**Decision**: 只从设置窗口通过系统打开/保存面板执行一次性导入导出，启用 User Selected
Files Read/Write；操作后立即释放授权，不保存安全作用域书签。导入先形成完整新快照，
验证成功后才替换 UserLexicon；导出使用版本化产品格式或文档化 UTF-8 文本。

**Rationale**: App Sandbox 会为用户在标准面板中选择的 URL 扩展权限。产品不需要重启后
继续访问外部文件，因此不保留书签，既满足迁移也最小化长期外部文件权限。

**Alternatives considered**:

- 自动扫描其他输入法目录：超出授权、不可审计且可能涉及私有格式，拒绝。
- 持久化文件书签：无后台同步或自动更新需求，拒绝。
- 网络导入：违反零网络产品边界，拒绝。

**Sources**: [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox),
[Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)

## 安全输入与私密模式

**Decision**: 不宣称自动识别密码框。产品只处理当前 InputMethodKit 会话交付的事件，禁止
全局监听或绕过 Secure Event Input；候选学习只能来自本输入法的成功提交，并提供可见、
可快速切换的私密模式及全局学习开关，二者都能确定性禁止写入和学习排序。

**Rationale**: Apple 的公开 InputMethodKit API 没有可靠的每客户端安全输入状态回调。
归档的 Secure Event Input 说明保护启用它的进程按键，但不是输入法客户端分类契约。显式
私密模式是当前可证明、可测试的产品控制，不能用全局状态探测伪装成自动保证。

**Alternatives considered**:

- 用全局安全事件状态判断当前客户端：Apple 未记录这种归因，证据不足。
- 监听系统级按键判断密码框：违反隐私与沙盒原则，拒绝。
- 移除本地学习：牺牲长期替代能力；以明确开关和私密模式控制更合适。

**Sources**: [InputMethodKit](https://developer.apple.com/documentation/inputmethodkit),
[TN2150: Using Secure Event Input Fairly](https://developer.apple.com/library/archive/technotes/tn2150/_index.html)

## 候选与设置无障碍

**Decision**: 设置窗口使用标准 AppKit 控件。候选展示先验证 `IMKCandidates` 的键盘、
VoiceOver 和 Accessibility Inspector 行为；若不能满足规格，则通过候选展示抽象切换到自定义
可访问视图，为候选、序号、选中状态、页码和操作提供明确语义。

**Rationale**: Apple 记录了标准 AppKit 控件的内建无障碍能力及自定义视图应实现的辅助
协议，但没有承诺 `IMKCandidates` 的 VoiceOver 行为。实机门禁必须先于候选 UI 定型。

**Alternatives considered**:

- 假定系统候选窗口天然符合规格：缺少文档证据，拒绝。
- 一开始自绘全部候选 UI：增加窗口定位、焦点和无障碍风险，先验证系统能力更简单。

**Sources**: [Accessibility for AppKit](https://developer.apple.com/documentation/appkit/accessibility-for-appkit),
[Integrating accessibility](https://developer.apple.com/documentation/accessibility/integrating-accessibility-into-your-app),
[IMKCandidates](https://developer.apple.com/documentation/inputmethodkit/imkcandidates)

## 离线更新边界

**Decision**: 所有发布 target 都不包含网络 client/server entitlement。产品和基础词库更新
只能通过签名应用发布包或用户主动选择的本地导入文件完成，不实现应用内检查或下载。

**Rationale**: 缺少网络 entitlement 使沙盒进程不能建立受限网络连接，直接支持可审计的
零网络承诺；最终仍需检查签名 entitlements 并做运行时网络观察。

**Alternatives considered**:

- 只关闭遥测但保留更新网络：扩大攻击和信任面，不符合“完全隐私”的简洁承诺。
- 配套更新守护进程：会绕开输入法 target 的网络边界，拒绝。

**Source**: [Outgoing network entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client)
