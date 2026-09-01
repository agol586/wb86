import AppKit

enum SettingsDestructiveAction: Sendable {
    case clearLearning
    case deleteUserLexicon
    case deleteAllPersonalization
}

private enum SettingsWindowValidationError: Error {
    case keyBinding(KeyBindingConflict)
}

private final class CandidatePreviewView: NSView {
    private let rows = (1...3).map { CandidatePreviewRow(ordinal: $0, text: "示例") }
    private(set) var usesHorizontalLayout = false

    var candidateTitles: [String] { rows.map(\.candidateTitle) }
    var emphasizedOrdinals: [Int] { rows.filter(\.isEmphasized).map(\.ordinal) }
    var candidateFontSizes: [CGFloat] { rows.map(\.candidateFontSize) }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        rows.enumerated().forEach { index, row in
            row.isEmphasized = index == 0
            addSubview(row)
        }
        updateColors()
    }

    required init?(coder: NSCoder) { nil }

    func update(layout: CandidateLayout, pointSize: CGFloat) {
        usesHorizontalLayout = layout == .horizontal
        rows.forEach { $0.candidateFontSize = pointSize }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 8
        if usesHorizontalLayout {
            let spacing: CGFloat = 5
            let availableWidth = bounds.width - inset * 2 - spacing * 2
            let rowWidth = floor(availableWidth / 3)
            let rowHeight: CGFloat = min(42, bounds.height - inset * 2)
            for (index, row) in rows.enumerated() {
                row.frame = NSRect(x: inset + CGFloat(index) * (rowWidth + spacing),
                                   y: (bounds.height - rowHeight) / 2,
                                   width: rowWidth, height: rowHeight)
            }
        } else {
            let spacing: CGFloat = 3
            let rowHeight = floor((bounds.height - inset * 2 - spacing * 2) / 3)
            for (index, row) in rows.enumerated() {
                row.frame = NSRect(x: inset,
                                   y: inset + CGFloat(index) * (rowHeight + spacing),
                                   width: bounds.width - inset * 2, height: rowHeight)
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
        rows.forEach { $0.updateColors() }
    }

    private func updateColors() {
        layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.72).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
    }
}

private final class CandidatePreviewRow: NSView {
    let ordinal: Int
    private let ordinalLabel: NSTextField
    private let candidateLabel: NSTextField
    private let defaultIndicator = NSView()

    var isEmphasized = false {
        didSet {
            defaultIndicator.isHidden = !isEmphasized
            updateColors()
        }
    }
    var candidateTitle: String { "\(ordinal)  \(candidateLabel.stringValue)" }
    var candidateFontSize: CGFloat {
        get { candidateLabel.font?.pointSize ?? 0 }
        set { candidateLabel.font = .systemFont(ofSize: newValue, weight: .regular) }
    }

    init(ordinal: Int, text: String) {
        self.ordinal = ordinal
        ordinalLabel = NSTextField(labelWithString: "\(ordinal)")
        candidateLabel = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        ordinalLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        ordinalLabel.alignment = .center
        candidateLabel.lineBreakMode = .byTruncatingTail
        addSubview(defaultIndicator)
        addSubview(ordinalLabel)
        addSubview(candidateLabel)
        updateColors()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        defaultIndicator.frame = NSRect(x: 1, y: 6, width: 3,
                                        height: max(0, bounds.height - 12))
        ordinalLabel.frame = NSRect(x: 8, y: (bounds.height - 16) / 2,
                                    width: 18, height: 16)
        candidateLabel.frame = NSRect(x: 29, y: (bounds.height - 22) / 2,
                                      width: max(0, bounds.width - 35), height: 22)
    }

    func updateColors() {
        layer?.backgroundColor = isEmphasized
            ? NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
            : NSColor.clear.cgColor
        defaultIndicator.wantsLayer = true
        defaultIndicator.layer?.cornerRadius = 1.5
        defaultIndicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        ordinalLabel.textColor = .secondaryLabelColor
        candidateLabel.textColor = .labelColor
    }
}

final class SettingsWindowController: NSWindowController, NSToolbarDelegate, NSTabViewDelegate {
    private static let toolbarIdentifier = NSToolbar.Identifier("MacWubiSettingsToolbar")
    static let shared = SettingsWindowController(
        settings: SettingsCoordinator.shared?.settings ?? .default,
        access: SettingsCoordinator.shared?.access ?? .writable,
        saveHandler: { try SettingsCoordinator.shared?.save($0) },
        layoutAvailability: { selection in
            selection == .us || KeyboardLayoutTranslator.isCurrentSystemLayoutAvailable
        }
    )

    let groupTitles = ["常用", "按键", "外观", "高级"]
    private(set) var registeredControls = [NSControl]()
    private(set) var focusOrderTitles = [String]()
    private(set) var lastValidationMessage: String?
    private(set) var lastFocusedControlTitle: String?
    private(set) var settings: InputSettings
    private(set) var draftSettings: InputSettings
    var savedSettings: InputSettings { settings }
    let access: SettingsStoreAccess
    var isReadOnly: Bool { access != .writable }
    var readOnlyMessage: String? {
        switch access {
        case .writable:
            return nil
        case let .readOnlyFuture(schemaVersion):
            return "设置由更高版本（版本 \(schemaVersion)）创建。当前版本以安全默认值只读运行，不会覆盖原设置。"
        case .readOnlyRecoveryFailure:
            return "设置迁移或恢复失败。当前版本以安全默认值只读运行，原设置文件保持不变。"
        }
    }
    private let saveHandler: (InputSettings) throws -> Void
    private let keyBindingValidator: KeyBindingValidator
    private let privacyController: PrivacyModeController
    private let personalizationCoordinator: PersonalizationCoordinator
    private var controlsByTitle = [String: NSButton]()
    private var pageSizeStepper: NSStepper?
    private var layoutPopup: NSPopUpButton?
    private var fontScaleSlider: NSSlider?
    private weak var pageSizeValueLabel: NSTextField?
    private weak var fontScaleValueLabel: NSTextField?
    private weak var appearancePreviewView: CandidatePreviewView?
    private var popupsByLabel = [String: NSPopUpButton]()
    private var bindingChoicesByLabel = [String: [(title: String, binding: ModeSwitchBinding)]]()
    private var titlesByControl = [ObjectIdentifier: String]()
    private weak var tabView: NSTabView?
    private weak var feedbackLabel: NSTextField?
    private weak var saveButton: NSButton?
    private weak var cancelButton: NSButton?
    private let panelController = ImportExportPanelController()
    private let importReportController = ImportReportViewController()
    private var privacyWindowController: NSWindowController?
    private lazy var userLexiconWindowController = UserLexiconWindowController(
        serviceProvider: { [weak self] in
            self?.personalizationCoordinator.userLexiconService
        }
    )

    var hasUnsavedChanges: Bool { draftSettings != settings }
    var appearancePreviewCandidateTitles: [String] {
        appearancePreviewView?.candidateTitles ?? []
    }
    var appearancePreviewEmphasizedOrdinals: [Int] {
        appearancePreviewView?.emphasizedOrdinals ?? []
    }
    var appearancePreviewUsesHorizontalLayout: Bool {
        appearancePreviewView?.usesHorizontalLayout ?? false
    }
    var appearancePreviewFontSizes: [CGFloat] {
        appearancePreviewView?.candidateFontSizes ?? []
    }

    init(settings: InputSettings,
         access: SettingsStoreAccess = .writable,
         privacyController: PrivacyModeController = .shared,
         personalizationCoordinator: PersonalizationCoordinator = .shared,
         saveHandler: @escaping (InputSettings) throws -> Void = { _ in },
         layoutAvailability: @escaping KeyBindingValidator.LayoutAvailability = { _ in true }) {
        self.settings = settings
        draftSettings = settings
        self.access = access
        self.privacyController = privacyController
        self.personalizationCoordinator = personalizationCoordinator
        self.saveHandler = saveHandler
        keyBindingValidator = KeyBindingValidator(isLayoutAvailable: layoutAvailability)
        super.init(window: nil)
    }

    required init?(coder: NSCoder) { nil }

    static func makeForTesting() -> SettingsWindowController {
        SettingsWindowController(settings: .default)
    }

    override func loadWindow() {
        registeredControls.removeAll()
        titlesByControl.removeAll()
        controlsByTitle.removeAll()
        popupsByLabel.removeAll()
        bindingChoicesByLabel.removeAll()
        pageSizeStepper = nil
        layoutPopup = nil
        fontScaleSlider = nil
        pageSizeValueLabel = nil
        fontScaleValueLabel = nil
        appearancePreviewView = nil
        feedbackLabel = nil
        saveButton = nil
        cancelButton = nil
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 500),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "常用 — Mac Wubi 设置"
        window.toolbarStyle = .preference
        window.tabbingMode = .disallowed
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false

        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconAndLabel
        toolbar.selectedItemIdentifier = toolbarIdentifier(for: "常用")
        window.toolbar = toolbar

        let tabs = NSTabView(frame: NSRect(x: 12, y: 54, width: 656, height: 434))
        tabView = tabs
        tabs.tabViewType = .noTabsNoBorder
        tabs.delegate = self
        tabs.autoresizingMask = [.width, .height]
        for title in groupTitles {
            let tab = NSTabViewItem(identifier: title)
            tab.label = title
            tab.view = groupView(title)
            tabs.addTabViewItem(tab)
        }
        let applyButton = makeButton("保存", action: #selector(applyFromControls))
        applyButton.frame = NSRect(x: 560, y: 14, width: 96, height: 30)
        applyButton.keyEquivalent = "\r"
        applyButton.bezelStyle = .rounded
        saveButton = applyButton
        let cancelButton = makeButton("取消", action: #selector(cancelFromControls))
        cancelButton.frame = NSRect(x: 456, y: 14, width: 96, height: 30)
        cancelButton.keyEquivalent = "\u{1b}"
        self.cancelButton = cancelButton
        let restoreButton = makeButton("恢复默认…", action: #selector(confirmRestoreDefaults))
        restoreButton.frame = NSRect(x: 336, y: 14, width: 112, height: 30)
        window.contentView?.addSubview(tabs)
        window.contentView?.addSubview(applyButton)
        window.contentView?.addSubview(cancelButton)
        window.contentView?.addSubview(restoreButton)
        window.defaultButtonCell = applyButton.cell as? NSButtonCell
        let feedback = NSTextField(wrappingLabelWithString:
            lastValidationMessage ?? "所有更改均已保存。")
        feedback.frame = NSRect(x: 12, y: 6, width: 312, height: 40)
        feedback.identifier = NSUserInterfaceItemIdentifier("操作反馈")
        feedback.isSelectable = true
        feedbackLabel = feedback
        register(feedback, label: "操作反馈")
        window.contentView?.addSubview(feedback)
        var initialResponder: NSView? = registeredControls.first
        if let message = readOnlyMessage {
            feedback.stringValue = message
            feedback.identifier = NSUserInterfaceItemIdentifier("设置状态")
            titlesByControl[ObjectIdentifier(feedback)] = "设置状态"
            registeredControls.forEach { control in
                let title = title(for: control)
                if title != "取消" && title != "设置状态" { control.isEnabled = false }
            }
            lastValidationMessage = message
            lastFocusedControlTitle = "设置状态"
            initialResponder = feedback
        }
        let focusControls = registeredControls.filter { $0 !== feedback || readOnlyMessage != nil }
        focusOrderTitles = focusControls.compactMap { title(for: $0) }
        for (current, next) in zip(focusControls, focusControls.dropFirst()) {
            current.nextKeyView = next
        }
        focusControls.last?.nextKeyView = focusControls.first
        window.initialFirstResponder = initialResponder
        self.window = window
        refreshDraftState(publishesMessage: false)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        groupTitles.map(toolbarIdentifier(for:))
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let title = groupTitle(for: itemIdentifier) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = title
        item.paletteLabel = title
        item.toolTip = "显示\(title)设置"
        item.image = NSImage(systemSymbolName: toolbarSymbolName(for: title),
                             accessibilityDescription: nil)
        item.target = self
        item.action = #selector(selectSettingsPane(_:))
        return item
    }

    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        guard let title = tabViewItem?.identifier as? String else { return }
        window?.title = "\(title) — Mac Wubi 设置"
        window?.toolbar?.selectedItemIdentifier = toolbarIdentifier(for: title)
    }

    @objc private func selectSettingsPane(_ sender: NSToolbarItem) {
        guard let title = groupTitle(for: sender.itemIdentifier) else { return }
        tabView?.selectTabViewItem(withIdentifier: title)
    }

    private func toolbarIdentifier(for title: String) -> NSToolbarItem.Identifier {
        NSToolbarItem.Identifier(title)
    }

    private func groupTitle(for identifier: NSToolbarItem.Identifier) -> String? {
        groupTitles.first { toolbarIdentifier(for: $0) == identifier }
    }

    private func toolbarSymbolName(for title: String) -> String {
        switch title {
        case "常用": return "slider.horizontal.3"
        case "按键": return "keyboard"
        case "外观": return "textformat.size"
        case "高级": return "lock.shield"
        default: return "gearshape"
        }
    }

    func apply(_ value: InputSettings) throws {
        guard access == .writable else { throw SettingsValidationError.unsupportedSchema }
        let validated = try value.validated()
        if let conflict = keyBindingValidator.validate(validated.keyBindings).conflicts.first {
            throw SettingsWindowValidationError.keyBinding(conflict)
        }
        try saveHandler(validated)
        settings = validated
        draftSettings = validated
    }

    @discardableResult
    func validateAndApply(_ value: InputSettings) -> Bool {
        do {
            try apply(value)
            lastFocusedControlTitle = nil
            publishMessage("设置已保存。")
            refreshDraftState(publishesMessage: false)
            return true
        } catch SettingsValidationError.invalidPageSize {
            reject("设置无效：候选数量必须为 5 至 9。", focus: "每页候选数量 5 至 9")
        } catch SettingsValidationError.invalidFontScale {
            reject("设置无效：候选字号缩放必须为 0.8 至 2.0。", focus: "候选字号缩放")
        } catch SettingsValidationError.unsupportedSchema {
            reject(readOnlyMessage ?? "当前设置为只读，无法保存或恢复默认。", focus: "设置状态")
        } catch let SettingsWindowValidationError.keyBinding(conflict) {
            reject(message(for: conflict), focus: label(for: conflict.field))
        } catch SettingsValidationError.corruptPayload,
                SettingsValidationError.generationExhausted,
                SettingsValidationError.readbackMismatch {
            reject("保存失败，最后有效设置保持不变。", focus: "初始语言")
        } catch {
            reject("保存失败，最后有效设置保持不变。", focus: "初始语言")
        }
        return false
    }

    @discardableResult
    func saveDraft() -> Bool { validateAndApply(draftSettings) }

    func cancelDraft() {
        draftSettings = settings
        lastFocusedControlTitle = nil
        refreshAllControls()
        publishMessage("未保存的修改已取消。")
        refreshDraftState(publishesMessage: false)
    }

    @discardableResult
    func restoreDefaults(confirmed: Bool) throws -> Bool {
        guard confirmed else { return false }
        try apply(.default)
        refreshAllControls()
        publishMessage("已恢复默认设置。")
        refreshDraftState(publishesMessage: false)
        return true
    }

    func updateDraft(_ update: (inout InputSettings) -> Void) {
        update(&draftSettings)
        refreshAllControls()
        refreshDraftState()
    }

    func confirmationMessage(for action: SettingsDestructiveAction) -> String {
        switch action {
        case .clearLearning: return "确认清除学习数据？用户词库不会改变。"
        case .deleteUserLexicon: return "确认删除用户词库？学习数据不会改变。"
        case .deleteAllPersonalization: return "确认删除全部个性化数据？基础词库会保留。"
        }
    }

    func show() {
        // The input method is an LSUIElement agent: it stays out of the Dock but may own
        // this user-requested settings window. Ensure a stale background activation policy
        // inherited by an already-running process cannot leave the window ordered behind apps.
        _ = NSApp.setActivationPolicy(.accessory)
        // NSWindowController(window: nil) may report `isWindowLoaded == true` even
        // though no window exists. Check the actual window so the programmatic UI
        // is always constructed on its first presentation.
        if window == nil { loadWindow() }
        guard let window else { return }
        window.isReleasedWhenClosed = false
        refreshRuntimePolicyControls()
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func groupView(_ title: String) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 390))
        switch title {
        case "常用":
            addCommonControls(to: view)
            return finalizedGroupView(view)
        case "按键":
            addKeyControls(to: view)
            return finalizedGroupView(view)
        case "外观":
            addAppearanceControls(to: view)
            return finalizedGroupView(view)
        case "高级":
            addPageHeader(title: "高级", summary: "管理运行时状态、用户词库与本地数据", to: view)
            addSectionCard(identifier: "运行状态分区",
                           frame: NSRect(x: 24, y: 254, width: 592, height: 68), to: view)
            let runtimeLabel = sectionLabel("运行状态", identifier: "运行状态标题")
            runtimeLabel.frame = NSRect(x: 34, y: 326, width: 160, height: 20)
            view.addSubview(runtimeLabel)
            for (index, title) in ["私密模式", "本地学习"].enumerated() {
                let control = makeButton(title, action: nil)
                control.target = self
                control.action = #selector(runtimePolicyChanged(_:))
                control.frame = NSRect(x: 44 + index * 260, y: 273, width: 230, height: 30)
                view.addSubview(control)
            }
            addSectionCard(identifier: "用户词库分区",
                           frame: NSRect(x: 24, y: 108, width: 592, height: 116), to: view)
            let lexiconLabel = sectionLabel("用户词库", identifier: "用户词库标题")
            lexiconLabel.frame = NSRect(x: 34, y: 228, width: 160, height: 20)
            view.addSubview(lexiconLabel)
            let actionButtons: [(String, Selector, NSRect)] = [
                ("搜索用户词条", #selector(searchUserLexicon),
                 NSRect(x: 44, y: 170, width: 135, height: 30)),
                ("添加词条", #selector(addUserLexiconEntry),
                 NSRect(x: 189, y: 170, width: 105, height: 30)),
                ("编辑词条", #selector(editUserLexiconEntry),
                 NSRect(x: 304, y: 170, width: 105, height: 30)),
                ("删除词条…", #selector(deleteUserLexiconEntry),
                 NSRect(x: 419, y: 170, width: 125, height: 30))
            ]
            for (buttonTitle, action, frame) in actionButtons {
                let control = makeActionButton(buttonTitle, action: action)
                control.frame = frame
                view.addSubview(control)
            }
            let importButton = makeButton("导入用户词库…", action: #selector(importLexicon))
            importButton.frame = NSRect(x: 44, y: 126, width: 150, height: 30)
            view.addSubview(importButton)
            let exportButton = makeButton("导出用户词库…", action: #selector(exportLexicon))
            exportButton.frame = NSRect(x: 204, y: 126, width: 150, height: 30)
            view.addSubview(exportButton)
            addSectionCard(identifier: "本地数据分区",
                           frame: NSRect(x: 24, y: 12, width: 592, height: 66), to: view)
            let dataLabel = sectionLabel("本地数据", identifier: "本地数据标题")
            dataLabel.frame = NSRect(x: 34, y: 82, width: 160, height: 20)
            view.addSubview(dataLabel)
            let clearButton = makeActionButton("清除学习数据…", action: #selector(confirmClearLearning))
            clearButton.frame = NSRect(x: 44, y: 30, width: 170, height: 30)
            view.addSubview(clearButton)
            let privacyButton = makeActionButton("隐私与数据管理…", action: #selector(showPrivacyData))
            privacyButton.frame = NSRect(x: 224, y: 30, width: 190, height: 30)
            view.addSubview(privacyButton)
            return finalizedGroupView(view)
        default:
            return view
        }
    }

    private func finalizedGroupView(_ view: NSView) -> NSView {
        // The hidden-tab NSTabView content area is 434 pt tall. The original pages were
        // 390 pt tall, so AppKit centered them vertically and left a conspicuous blank band
        // below the preference toolbar. Match the container and preserve the original 24 pt
        // page margin by moving the existing layout into the added height.
        let addedHeight: CGFloat = 44
        view.frame.size.height += addedHeight
        for subview in view.subviews {
            subview.frame.origin.y += addedHeight
        }
        return view
    }

    private func addAppearanceControls(to view: NSView) {
        addPageHeader(title: "外观", summary: "调整候选窗口的密度与阅读大小", to: view)

        let settingsCard = appearanceCard(frame: NSRect(x: 24, y: 66, width: 330, height: 230))
        let previewCard = appearanceCard(frame: NSRect(x: 370, y: 66, width: 246, height: 230))
        view.addSubview(settingsCard)
        view.addSubview(previewCard)

        let pageTitle = identifiedLabel("每页候选", identifier: "每页候选标题",
                                        font: .systemFont(ofSize: 13, weight: .medium))
        pageTitle.frame = NSRect(x: 44, y: 248, width: 130, height: 20)
        let pageHelp = identifiedLabel("控制翻页前显示的项目数", identifier: "每页候选说明",
                                       color: .secondaryLabelColor)
        pageHelp.frame = NSRect(x: 44, y: 226, width: 170, height: 18)
        let pageValue = identifiedLabel("", identifier: "每页候选当前值",
                                        font: .monospacedDigitSystemFont(ofSize: 13,
                                                                        weight: .medium))
        pageValue.alignment = .right
        pageValue.frame = NSRect(x: 218, y: 239, width: 62, height: 24)
        pageSizeValueLabel = pageValue
        let stepper = NSStepper(frame: NSRect(x: 294, y: 236, width: 22, height: 28))
        stepper.minValue = 5
        stepper.maxValue = 9
        stepper.integerValue = draftSettings.candidatePageSize
        stepper.increment = 1
        stepper.target = self
        stepper.action = #selector(appearanceControlChanged(_:))
        register(stepper, label: "每页候选数量 5 至 9")
        pageSizeStepper = stepper

        let layoutTitle = identifiedLabel("排列方式", identifier: "排列方式标题",
                                          font: .systemFont(ofSize: 13, weight: .medium))
        layoutTitle.frame = NSRect(x: 44, y: 181, width: 130, height: 20)
        let layoutHelp = identifiedLabel("横向紧凑，纵向便于浏览", identifier: "排列方式说明",
                                         color: .secondaryLabelColor)
        layoutHelp.frame = NSRect(x: 44, y: 159, width: 170, height: 18)
        let layout = NSPopUpButton(frame: NSRect(x: 210, y: 165, width: 106, height: 30))
        layout.addItems(withTitles: ["纵向", "横向"])
        layout.selectItem(at: draftSettings.candidateLayout == .vertical ? 0 : 1)
        layout.target = self
        layout.action = #selector(appearanceControlChanged(_:))
        register(layout, label: "候选布局")
        layoutPopup = layout

        let fontTitle = identifiedLabel("文字大小", identifier: "文字大小标题",
                                        font: .systemFont(ofSize: 13, weight: .medium))
        fontTitle.frame = NSRect(x: 44, y: 114, width: 130, height: 20)
        let fontHelp = identifiedLabel("保持正文清楚，不随比例暴涨", identifier: "文字大小说明",
                                       color: .secondaryLabelColor)
        fontHelp.frame = NSRect(x: 44, y: 92, width: 180, height: 18)
        let fontValue = identifiedLabel("", identifier: "字号当前值",
                                        font: .monospacedDigitSystemFont(ofSize: 12,
                                                                        weight: .medium))
        fontValue.alignment = .right
        fontValue.frame = NSRect(x: 210, y: 112, width: 106, height: 20)
        fontScaleValueLabel = fontValue
        let slider = NSSlider(value: draftSettings.candidateFontScale, minValue: 0.8,
                              maxValue: 2, target: self,
                              action: #selector(appearanceControlChanged(_:)))
        slider.frame = NSRect(x: 210, y: 83, width: 106, height: 24)
        slider.numberOfTickMarks = 5
        slider.allowsTickMarkValuesOnly = false
        register(slider, label: "候选字号缩放")
        fontScaleSlider = slider

        [pageTitle, pageHelp, pageValue, stepper, layoutTitle, layoutHelp, layout,
         fontTitle, fontHelp, fontValue, slider].forEach(view.addSubview)

        let previewTitle = identifiedLabel("候选预览", identifier: "候选预览标题",
                                           font: .systemFont(ofSize: 13, weight: .medium))
        previewTitle.frame = NSRect(x: 390, y: 252, width: 150, height: 20)
        let previewHelp = identifiedLabel("保存前确认实际密度", identifier: "候选预览说明",
                                          color: .secondaryLabelColor)
        previewHelp.frame = NSRect(x: 390, y: 230, width: 180, height: 18)
        let preview = CandidatePreviewView(frame: NSRect(x: 390, y: 91,
                                                         width: 206, height: 124))
        preview.identifier = NSUserInterfaceItemIdentifier("候选预览")
        appearancePreviewView = preview
        view.addSubview(previewTitle)
        view.addSubview(previewHelp)
        view.addSubview(preview)
        refreshAppearanceControls()
    }

    private func identifiedLabel(_ value: String, identifier: String,
                                 font: NSFont = .systemFont(ofSize: 12),
                                 color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.identifier = NSUserInterfaceItemIdentifier(identifier)
        label.font = font
        label.textColor = color
        return label
    }

    private func addPageHeader(title: String, summary: String, to view: NSView) {
        let heading = identifiedLabel(title, identifier: "\(title)页标题",
                                      font: .systemFont(ofSize: 17, weight: .semibold))
        heading.frame = NSRect(x: 24, y: 342, width: 300, height: 24)
        let description = identifiedLabel(summary, identifier: "\(title)页说明",
                                          color: .secondaryLabelColor)
        description.frame = NSRect(x: 24, y: 316, width: 560, height: 20)
        view.addSubview(heading)
        view.addSubview(description)
    }

    private func sectionLabel(_ title: String, identifier: String) -> NSTextField {
        identifiedLabel(title, identifier: identifier,
                        font: .systemFont(ofSize: 12, weight: .semibold),
                        color: .secondaryLabelColor)
    }

    private func addSectionCard(identifier: String, frame: NSRect, to view: NSView) {
        let box = appearanceCard(frame: frame)
        box.identifier = NSUserInterfaceItemIdentifier(identifier)
        view.addSubview(box, positioned: .below, relativeTo: nil)
    }

    private func appearanceCard(frame: NSRect) -> NSBox {
        let box = NSBox(frame: frame)
        box.boxType = .custom
        box.titlePosition = .noTitle
        box.fillColor = .controlBackgroundColor.withAlphaComponent(0.72)
        box.borderColor = .separatorColor.withAlphaComponent(0.55)
        box.borderWidth = 1
        box.cornerRadius = 10
        return box
    }

    private func addCommonControls(to view: NSView) {
        addPageHeader(title: "常用", summary: "设置新输入会话的默认状态与输入效率", to: view)
        addSectionCard(identifier: "新会话默认分区",
                       frame: NSRect(x: 24, y: 164, width: 592, height: 136), to: view)
        let defaultsLabel = sectionLabel("新会话默认", identifier: "新会话默认标题")
        defaultsLabel.frame = NSRect(x: 34, y: 304, width: 160, height: 20)
        view.addSubview(defaultsLabel)
        let popupRows: [(String, [String], Int)] = [
            ("初始语言", ["中文", "英文"], draftSettings.defaultMode.language == .chinese ? 0 : 1),
            ("初始简繁体", ["简体", "繁体"], draftSettings.defaultMode.script == .simplified ? 0 : 1),
            ("初始全半角", ["半角", "全角"], draftSettings.defaultMode.width == .half ? 0 : 1),
            ("中文模式标点", ["英文标点", "中文标点"],
             draftSettings.defaultMode.punctuation == .english ? 0 : 1)
        ]
        for (index, row) in popupRows.enumerated() {
            let column = index / 2
            let itemRow = index % 2
            let baseX: CGFloat = 44 + CGFloat(column) * 288
            let y: CGFloat = 254 - CGFloat(itemRow) * 54
            let caption = NSTextField(labelWithString: row.0)
            caption.frame = NSRect(x: baseX, y: y + 4, width: 104, height: 24)
            let popup = NSPopUpButton(frame: NSRect(x: baseX + 108, y: y,
                                                    width: 126, height: 30))
            popup.addItems(withTitles: row.1)
            popup.selectItem(at: row.2)
            popup.target = self
            popup.action = #selector(persistedControlChanged(_:))
            register(popup, label: row.0)
            popupsByLabel[row.0] = popup
            view.addSubview(caption)
            view.addSubview(popup)
        }

        addSectionCard(identifier: "输入效率分区",
                       frame: NSRect(x: 24, y: 18, width: 592, height: 136), to: view)
        let efficiencyLabel = sectionLabel("输入效率", identifier: "输入效率标题")
        efficiencyLabel.frame = NSRect(x: 34, y: 158, width: 160, height: 20)
        view.addSubview(efficiencyLabel)
        let options = [
            "四码唯一时直接上屏", "第五码将首选词上屏", "五笔自动调频",
            "五笔拼音混合输入", "开启编码提示", "分号和单引号候选快捷键",
            "显示扩展汉字"
        ]
        for (index, title) in options.enumerated() {
            let button = makeButton(title, action: nil)
            button.target = self
            button.action = #selector(commonOptionChanged(_:))
            let column = index / 4
            let row = index % 4
            button.frame = NSRect(x: 44 + column * 288, y: 112 - row * 30,
                                  width: 260, height: 26)
            view.addSubview(button)
        }
    }

    private func addKeyControls(to view: NSView) {
        addPageHeader(title: "按键", summary: "按你的键盘习惯配置切换与候选翻页", to: view)
        addSectionCard(identifier: "模式切换分区",
                       frame: NSRect(x: 24, y: 158, width: 592, height: 142), to: view)
        let bindingsLabel = sectionLabel("模式切换", identifier: "模式切换标题")
        bindingsLabel.frame = NSRect(x: 34, y: 304, width: 160, height: 20)
        view.addSubview(bindingsLabel)
        let bindingRows: [(String, ModeSwitchBinding)] = [
            ("中英文切换", draftSettings.keyBindings.languageSwitch),
            ("简繁切换", draftSettings.keyBindings.scriptSwitch),
            ("全半角切换", draftSettings.keyBindings.widthSwitch)
        ]
        for (index, row) in bindingRows.enumerated() {
            let caption = NSTextField(labelWithString: row.0)
            caption.frame = NSRect(x: 44, y: 255 - index * 40, width: 110, height: 24)
            let popup = NSPopUpButton(frame: NSRect(x: 154, y: 249 - index * 40,
                                                    width: 170, height: 30))
            let choices = bindingChoices(for: row.0, current: row.1)
            bindingChoicesByLabel[row.0] = choices
            popup.addItems(withTitles: choices.map(\.title))
            popup.selectItem(at: choices.firstIndex { $0.binding == row.1 } ?? 0)
            popup.target = self
            popup.action = #selector(persistedControlChanged(_:))
            register(popup, label: row.0)
            popupsByLabel[row.0] = popup
            view.addSubview(caption)
            view.addSubview(popup)
        }

        let layoutCaption = NSTextField(labelWithString: "键盘布局")
        layoutCaption.frame = NSRect(x: 350, y: 255, width: 100, height: 24)
        let keyboardLayout = NSPopUpButton(frame: NSRect(x: 440, y: 249,
                                                        width: 150, height: 30))
        keyboardLayout.addItems(withTitles: ["美国 ANSI", "跟随系统布局"])
        keyboardLayout.selectItem(at: draftSettings.keyBindings.keyboardLayout == .us ? 0 : 1)
        keyboardLayout.target = self
        keyboardLayout.action = #selector(persistedControlChanged(_:))
        register(keyboardLayout, label: "键盘布局")
        popupsByLabel["键盘布局"] = keyboardLayout
        view.addSubview(layoutCaption)
        view.addSubview(keyboardLayout)

        addSectionCard(identifier: "候选翻页分区",
                       frame: NSRect(x: 24, y: 18, width: 592, height: 104), to: view)
        let pagingLabel = sectionLabel("候选翻页", identifier: "候选翻页标题")
        pagingLabel.frame = NSRect(x: 34, y: 126, width: 160, height: 20)
        view.addSubview(pagingLabel)
        let pageOptions = [
            "逗号句号翻页", "减号等号翻页", "中括号翻页",
            "Tab/Shift-Tab 翻页", "上下方向键翻页"
        ]
        for (index, title) in pageOptions.enumerated() {
            let button = makeButton(title, action: nil)
            button.target = self
            button.action = #selector(persistedControlChanged(_:))
            let column = index / 3
            let row = index % 3
            button.frame = NSRect(x: 44 + column * 288, y: 82 - row * 30,
                                  width: 260, height: 26)
            view.addSubview(button)
        }
    }

    private func register(_ control: NSControl, label: String) {
        control.identifier = NSUserInterfaceItemIdentifier(label)
        titlesByControl[ObjectIdentifier(control)] = label
        registeredControls.append(control)
    }

    private func makeButton(_ title: String, action: Selector?) -> NSButton {
        let button = action == nil
            ? NSButton(checkboxWithTitle: title, target: nil, action: nil)
            : NSButton(title: title, target: self, action: action)
        button.identifier = NSUserInterfaceItemIdentifier(title)
        titlesByControl[ObjectIdentifier(button)] = title
        button.refusesFirstResponder = false
        registeredControls.append(button)
        controlsByTitle[title] = button
        configureInitialState(button, title: title)
        return button
    }

    private func makeActionButton(_ title: String, action: Selector) -> NSButton {
        makeButton(title, action: action)
    }

    @objc private func applyFromControls() {
        draftSettings = settingsFromControls()
        _ = validateAndApply(draftSettings)
        refreshDraftState(publishesMessage: false)
    }

    private func settingsFromControls() -> InputSettings {
        var updated = draftSettings
        updated.autoCommitAtFour = isOn("四码唯一时直接上屏")
        updated.autoCommitFirstAtFive = isOn("第五码将首选词上屏")
        updated.automaticFrequency = isOn("五笔自动调频")
        updated.mixedPinyinEnabled = isOn("五笔拼音混合输入")
        updated.codeHintEnabled = isOn("开启编码提示")
        updated.candidate2And3ShortcutsEnabled = isOn("分号和单引号候选快捷键")
        updated.extendedCharacterSetEnabled = isOn("显示扩展汉字")
        updated.candidatePageSize = Int(pageSizeStepper?.integerValue ?? 5)
        updated.candidateLayout = layoutPopup?.indexOfSelectedItem == 1 ? .horizontal : .vertical
        updated.candidateFontScale = fontScaleSlider?.doubleValue ?? 1
        updated.defaultMode.language = selectedIndex("初始语言") == 0 ? .chinese : .directEnglish
        updated.defaultMode.script = selectedIndex("初始简繁体") == 0 ? .simplified : .traditional
        updated.defaultMode.width = selectedIndex("初始全半角") == 0 ? .half : .full
        updated.defaultMode.punctuation = selectedIndex("中文模式标点") == 0 ? .english : .chinese
        var keyBindings = updated.keyBindings
        keyBindings.languageSwitch = selectedBinding("中英文切换")
        keyBindings.scriptSwitch = selectedBinding("简繁切换")
        keyBindings.widthSwitch = selectedBinding("全半角切换")
        keyBindings.pageKeyGroups = Set(CandidatePageKeyGroup.allCases.filter {
            isOn(pageTitle(for: $0))
        })
        keyBindings.keyboardLayout = selectedIndex("键盘布局") == 0 ? .us : .followSystem
        updated.keyBindings = keyBindings
        return updated
    }

    @objc private func persistedControlChanged(_ sender: NSControl) {
        draftSettings = settingsFromControls()
        refreshDraftState()
    }

    @objc private func commonOptionChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        switch sender.title {
        case "四码唯一时直接上屏": draftSettings.autoCommitAtFour = enabled
        case "第五码将首选词上屏": draftSettings.autoCommitFirstAtFive = enabled
        case "五笔自动调频": draftSettings.automaticFrequency = enabled
        case "五笔拼音混合输入": draftSettings.mixedPinyinEnabled = enabled
        case "开启编码提示": draftSettings.codeHintEnabled = enabled
        case "分号和单引号候选快捷键":
            draftSettings.candidate2And3ShortcutsEnabled = enabled
        case "显示扩展汉字": draftSettings.extendedCharacterSetEnabled = enabled
        default: return
        }
        refreshDraftState()
    }

    @objc private func appearanceControlChanged(_ sender: NSControl) {
        if sender === pageSizeStepper {
            draftSettings.candidatePageSize = pageSizeStepper?.integerValue
                ?? draftSettings.candidatePageSize
        } else if sender === layoutPopup {
            draftSettings.candidateLayout = layoutPopup?.indexOfSelectedItem == 1
                ? .horizontal : .vertical
        } else if sender === fontScaleSlider {
            draftSettings.candidateFontScale = fontScaleSlider?.doubleValue
                ?? draftSettings.candidateFontScale
        }
        refreshAppearanceControls()
        refreshDraftState()
    }

    @objc private func runtimePolicyChanged(_ sender: NSButton) {
        switch sender.title {
        case "私密模式":
            privacyController.setPrivateMode(sender.state == .on)
            publishMessage(sender.state == .on ? "私密模式已开启。" : "私密模式已关闭。")
        case "本地学习":
            privacyController.setLearningEnabled(sender.state == .on)
            publishMessage(sender.state == .on ? "本地学习已开启。" : "本地学习已关闭。")
        default: return
        }
        refreshRuntimePolicyControls()
    }

    @objc private func cancelFromControls() { cancelDraft() }

    private func selectedIndex(_ label: String) -> Int {
        popupsByLabel[label]?.indexOfSelectedItem ?? 0
    }

    private func selectedBinding(_ label: String) -> ModeSwitchBinding {
        let choices = bindingChoicesByLabel[label] ?? []
        let index = selectedIndex(label)
        return choices.indices.contains(index) ? choices[index].binding : .disabled
    }

    private func isOn(_ title: String) -> Bool { controlsByTitle[title]?.state == .on }

    private func configureInitialState(_ button: NSButton, title: String) {
        switch title {
        case "四码唯一时直接上屏": button.state = draftSettings.autoCommitAtFour ? .on : .off
        case "第五码将首选词上屏": button.state = draftSettings.autoCommitFirstAtFive ? .on : .off
        case "五笔自动调频": button.state = draftSettings.automaticFrequency ? .on : .off
        case "五笔拼音混合输入": button.state = draftSettings.mixedPinyinEnabled ? .on : .off
        case "开启编码提示": button.state = draftSettings.codeHintEnabled ? .on : .off
        case "分号和单引号候选快捷键":
            button.state = draftSettings.candidate2And3ShortcutsEnabled ? .on : .off
        case "显示扩展汉字":
            button.state = draftSettings.extendedCharacterSetEnabled ? .on : .off
        case "逗号句号翻页":
            button.state = draftSettings.keyBindings.pageKeyGroups.contains(.commaPeriod) ? .on : .off
        case "减号等号翻页":
            button.state = draftSettings.keyBindings.pageKeyGroups.contains(.minusEquals) ? .on : .off
        case "中括号翻页":
            button.state = draftSettings.keyBindings.pageKeyGroups.contains(.bracketPair) ? .on : .off
        case "Tab/Shift-Tab 翻页":
            button.state = draftSettings.keyBindings.pageKeyGroups.contains(.tab) ? .on : .off
        case "上下方向键翻页":
            button.state = draftSettings.keyBindings.pageKeyGroups.contains(.arrows) ? .on : .off
        case "私密模式": button.state = privacyController.privateMode ? .on : .off
        case "本地学习": button.state = privacyController.learningEnabled ? .on : .off
        default: break
        }
    }

    private func refreshAllControls() {
        controlsByTitle.forEach { configureInitialState($0.value, title: $0.key) }
        popupsByLabel["初始语言"]?.selectItem(at: draftSettings.defaultMode.language == .chinese ? 0 : 1)
        popupsByLabel["初始简繁体"]?.selectItem(at: draftSettings.defaultMode.script == .simplified ? 0 : 1)
        popupsByLabel["初始全半角"]?.selectItem(at: draftSettings.defaultMode.width == .half ? 0 : 1)
        popupsByLabel["中文模式标点"]?.selectItem(at: draftSettings.defaultMode.punctuation == .english ? 0 : 1)
        refreshBindingPopup("中英文切换", current: draftSettings.keyBindings.languageSwitch)
        refreshBindingPopup("简繁切换", current: draftSettings.keyBindings.scriptSwitch)
        refreshBindingPopup("全半角切换", current: draftSettings.keyBindings.widthSwitch)
        popupsByLabel["键盘布局"]?.selectItem(
            at: draftSettings.keyBindings.keyboardLayout == .us ? 0 : 1
        )
        pageSizeStepper?.integerValue = draftSettings.candidatePageSize
        layoutPopup?.selectItem(at: draftSettings.candidateLayout == .vertical ? 0 : 1)
        fontScaleSlider?.doubleValue = draftSettings.candidateFontScale
        refreshAppearanceControls()
        refreshRuntimePolicyControls()
    }

    private func refreshAppearanceControls() {
        pageSizeValueLabel?.stringValue = "\(draftSettings.candidatePageSize) 个"
        let pointSize = CandidateTypography.candidatePointSize(
            for: draftSettings.candidateFontScale
        )
        let displayName = CandidateTypography.displayName(for: draftSettings.candidateFontScale)
        fontScaleValueLabel?.stringValue = "\(displayName) · \(Int(pointSize.rounded())) pt"
        appearancePreviewView?.update(layout: draftSettings.candidateLayout,
                                      pointSize: pointSize)
    }

    private func refreshRuntimePolicyControls() {
        controlsByTitle["私密模式"]?.state = privacyController.privateMode ? .on : .off
        controlsByTitle["本地学习"]?.state = privacyController.learningEnabled ? .on : .off
    }

    private func refreshDraftState(publishesMessage: Bool = true) {
        let isDirty = hasUnsavedChanges && !isReadOnly
        saveButton?.isEnabled = isDirty
        cancelButton?.isEnabled = isDirty
        guard publishesMessage, !isReadOnly else { return }
        publishMessage(isDirty ? "有未保存的修改。" : "所有更改均已保存。")
    }

    private func publishMessage(_ message: String) {
        lastValidationMessage = message
        feedbackLabel?.stringValue = message
        feedbackLabel?.textColor = message.contains("失败") || message.contains("无效")
            || message.contains("冲突") || message.contains("不可用")
            ? .systemRed : .secondaryLabelColor
    }

    private func reject(_ message: String, focus label: String) {
        lastFocusedControlTitle = label
        if label == "每页候选数量 5 至 9" || label == "候选字号缩放" {
            tabView?.selectTabViewItem(withIdentifier: "外观")
        } else if ["中英文切换", "简繁切换", "全半角切换", "键盘布局"]
            .contains(label) {
            tabView?.selectTabViewItem(withIdentifier: "按键")
        } else if ["清除学习数据…", "搜索用户词条", "添加词条", "编辑词条",
                   "删除词条…", "导入用户词库…", "导出用户词库…",
                   "隐私与数据管理…"].contains(label) {
            tabView?.selectTabViewItem(withIdentifier: "高级")
        }
        if let control = registeredControls.first(where: { title(for: $0) == label }),
           control.window != nil {
            window?.makeFirstResponder(control)
        }
        publishMessage(message)
    }

    private func title(for control: NSControl) -> String? {
        titlesByControl[ObjectIdentifier(control)] ?? control.identifier?.rawValue
    }

    @objc private func confirmRestoreDefaults() {
        let alert = NSAlert()
        alert.messageText = "恢复默认设置？"
        alert.informativeText = "只恢复 Settings；用户词库和学习数据不会删除。"
        alert.addButton(withTitle: "恢复默认")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else {
            publishMessage("已取消恢复默认设置。")
            return
        }
        do {
            _ = try restoreDefaults(confirmed: true)
        } catch {
            reject("恢复默认设置失败，最后有效设置保持不变。", focus: "初始语言")
        }
    }

    @objc private func confirmClearLearning() {
        let alert = NSAlert()
        alert.messageText = "清除全部学习数据？"
        alert.informativeText = "用户词库和设置不会改变。"
        alert.addButton(withTitle: "清除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else {
            publishMessage("已取消清除学习数据。")
            return
        }
        do {
            let removed = try personalizationCoordinator.clearLearning()
            publishMessage("学习数据已清除（\(removed) 条）。")
        } catch {
            reject("清除学习数据失败，原数据保持不变。", focus: "清除学习数据…")
        }
    }

    @objc private func searchUserLexicon() { showUserLexicon(.search, "已打开用户词库搜索。") }
    @objc private func addUserLexiconEntry() { showUserLexicon(.add, "已打开添加词条。") }
    @objc private func editUserLexiconEntry() { showUserLexicon(.edit, "请选择要编辑的词条。") }
    @objc private func deleteUserLexiconEntry() { showUserLexicon(.delete, "请选择要删除的词条。") }

    private func showUserLexicon(_ mode: UserLexiconWindowMode, _ message: String) {
        guard personalizationCoordinator.userLexiconService != nil else {
            reject("用户词库当前不可用。", focus: "搜索用户词条")
            return
        }
        userLexiconWindowController.show(mode: mode)
        publishMessage(message)
    }

    @objc private func showPrivacyData() {
        let content = PrivacyViewController.makeDefault()
        let privacyWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 380),
                                     styleMask: [.titled, .closable, .resizable],
                                     backing: .buffered, defer: false)
        privacyWindow.title = "隐私与本地数据"
        privacyWindow.contentViewController = content
        privacyWindow.isReleasedWhenClosed = false
        let controller = NSWindowController(window: privacyWindow)
        privacyWindowController = controller
        privacyWindow.center()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        publishMessage("已打开隐私与本地数据管理。")
    }

    @objc private func importLexicon() {
        guard let importer = personalizationCoordinator.lexiconImporter else {
            reject("用户词库导入当前不可用。", focus: "导入用户词库…")
            return
        }
        do {
            let selected = try panelController.performImport { [weak self] data in
                let report = data.starts(with: Data("MWARCH01".utf8))
                    ? try importer.importArchive(data) : try importer.importText(data)
                self?.importReportController.present(report)
                self?.importReportController.show()
                self?.publishMessage("导入完成：新增 \(report.acceptedCount)，合并 \(report.mergedCount)，跳过 \(report.skippedCount)，失败 \(report.failedCount)。")
            }
            if !selected { publishMessage("已取消导入。") }
        } catch {
            reject("导入失败，原用户词库保持不变。", focus: "导入用户词库…")
        }
    }

    @objc private func exportLexicon() {
        guard let exporter = personalizationCoordinator.lexiconExporter else {
            reject("用户词库导出当前不可用。", focus: "导出用户词库…")
            return
        }
        do {
            let data = try exporter.archiveData(includeLearning: false)
            let selected = try panelController.performExport(data, using: exporter) {
                _ = try LexiconArchiveCodec.decode($0)
            }
            publishMessage(selected ? "用户词库已导出。" : "已取消导出。")
        } catch {
            reject("导出失败，目标文件保持原状。", focus: "导出用户词库…")
        }
    }

    private func bindingChoices(for label: String,
                                current: ModeSwitchBinding) -> [(title: String,
                                                                  binding: ModeSwitchBinding)] {
        var choices: [(title: String, binding: ModeSwitchBinding)]
        switch label {
        case "中英文切换":
            choices = [
                ("Shift", .standaloneShift),
                ("Control", .standaloneControl),
                ("Caps Lock", .standaloneCapsLock),
                ("禁用快捷键", .disabled)
            ]
        case "简繁切换":
            choices = [("Control-Shift-F", .controlShiftF), ("禁用快捷键", .disabled)]
        case "全半角切换":
            choices = [("Shift-Space", .shiftSpace), ("禁用快捷键", .disabled)]
        default:
            choices = [("禁用快捷键", .disabled)]
        }
        if !choices.contains(where: { $0.binding == current }) {
            choices.append(("旧版设置（需更新）", current))
        }
        return choices
    }

    private func refreshBindingPopup(_ label: String, current: ModeSwitchBinding) {
        guard let popup = popupsByLabel[label] else { return }
        let choices = bindingChoices(for: label, current: current)
        bindingChoicesByLabel[label] = choices
        popup.removeAllItems()
        popup.addItems(withTitles: choices.map(\.title))
        popup.selectItem(at: choices.firstIndex { $0.binding == current } ?? 0)
    }

    private func pageTitle(for group: CandidatePageKeyGroup) -> String {
        switch group {
        case .commaPeriod: return "逗号句号翻页"
        case .minusEquals: return "减号等号翻页"
        case .bracketPair: return "中括号翻页"
        case .tab: return "Tab/Shift-Tab 翻页"
        case .arrows: return "上下方向键翻页"
        }
    }

    private func label(for field: KeyBindingField) -> String {
        switch field {
        case .languageSwitch: return "中英文切换"
        case .scriptSwitch: return "简繁切换"
        case .widthSwitch: return "全半角切换"
        case .keyboardLayout: return "键盘布局"
        }
    }

    private func message(for conflict: KeyBindingConflict) -> String {
        switch conflict.reason {
        case .empty: return "按键设置无效：快捷键不能为空。"
        case .duplicate: return "按键设置冲突：快捷键重复。"
        case .rangeOverlap: return "按键设置冲突：快捷键范围重叠。"
        case .systemReserved: return "按键设置无效：该组合由系统保留。"
        case .unsupportedLegacy: return "按键设置无效：请替换旧版快捷键。"
        case .layoutUnavailable: return "键盘布局不可用，请选择美国 ANSI 或恢复可用布局。"
        }
    }
}
