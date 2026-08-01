import AppKit

enum SettingsDestructiveAction: Sendable {
    case clearLearning
    case deleteUserLexicon
    case deleteAllPersonalization
}

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController(
        settings: SettingsCoordinator.shared?.settings ?? .default,
        saveHandler: { try SettingsCoordinator.shared?.save($0) }
    )

    let groupTitles = ["输入", "按键", "候选", "学习", "用户词库", "隐私"]
    private(set) var accessibleControls = [NSControl]()
    private(set) var focusOrderLabels = [String]()
    private(set) var lastValidationAnnouncement: String?
    private(set) var settings: InputSettings
    private let saveHandler: (InputSettings) throws -> Void
    private var controlsByTitle = [String: NSButton]()
    private var pageKeysPopup: NSPopUpButton?
    private var pageSizeStepper: NSStepper?
    private var layoutPopup: NSPopUpButton?
    private var fontScaleSlider: NSSlider?
    private let panelController = ImportExportPanelController()
    private let importReportController = ImportReportViewController()
    private let privacyViewController = PrivacyViewController.makeDefault()

    init(settings: InputSettings,
         saveHandler: @escaping (InputSettings) throws -> Void = { _ in }) {
        self.settings = settings
        self.saveHandler = saveHandler
        super.init(window: nil)
    }

    required init?(coder: NSCoder) { nil }

    static func makeForTesting() -> SettingsWindowController {
        SettingsWindowController(settings: .default)
    }

    override func loadWindow() {
        accessibleControls.removeAll()
        controlsByTitle.removeAll()
        pageKeysPopup = nil
        pageSizeStepper = nil
        layoutPopup = nil
        fontScaleSlider = nil
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 500),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Mac Wubi 设置"
        window.setAccessibilityLabel("Mac Wubi 设置")
        let tabs = NSTabView(frame: NSRect(x: 12, y: 54, width: 656, height: 434))
        tabs.autoresizingMask = [.width, .height]
        for title in groupTitles {
            let tab = NSTabViewItem(identifier: title)
            tab.label = title
            tab.view = groupView(title)
            tabs.addTabViewItem(tab)
        }
        let applyButton = makeButton("应用设置", action: #selector(applyFromControls))
        applyButton.frame = NSRect(x: 560, y: 14, width: 96, height: 30)
        let restoreButton = makeButton("恢复默认…", action: #selector(confirmRestoreDefaults))
        restoreButton.frame = NSRect(x: 448, y: 14, width: 104, height: 30)
        window.contentView?.addSubview(tabs)
        window.contentView?.addSubview(applyButton)
        window.contentView?.addSubview(restoreButton)
        focusOrderLabels = accessibleControls.compactMap { $0.accessibilityLabel() }
        for (current, next) in zip(accessibleControls, accessibleControls.dropFirst()) {
            current.nextKeyView = next
        }
        accessibleControls.last?.nextKeyView = accessibleControls.first
        window.initialFirstResponder = accessibleControls.first
        self.window = window
    }

    func apply(_ value: InputSettings) throws {
        let validated = try value.validated()
        try saveHandler(validated)
        settings = validated
    }

    @discardableResult
    func validateAndApply(_ value: InputSettings) -> Bool {
        do {
            try apply(value)
            lastValidationAnnouncement = nil
            return true
        } catch SettingsValidationError.invalidPageSize {
            announce("设置无效：候选数量必须为 5 至 9。")
        } catch SettingsValidationError.invalidFontScale {
            announce("设置无效：候选字号缩放必须为 0.8 至 2.0。")
        } catch {
            announce("设置无效，请检查冲突按键和输入值。")
        }
        return false
    }

    @discardableResult
    func restoreDefaults(confirmed: Bool) throws -> Bool {
        guard confirmed else { return false }
        try apply(.default)
        return true
    }

    func confirmationMessage(for action: SettingsDestructiveAction) -> String {
        switch action {
        case .clearLearning: return "确认清除学习数据？用户词库不会改变。"
        case .deleteUserLexicon: return "确认删除用户词库？学习数据不会改变。"
        case .deleteAllPersonalization: return "确认删除全部个性化数据？基础词库会保留。"
        }
    }

    func show() {
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func groupView(_ title: String) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 390))
        let labels: [String]
        switch title {
        case "输入": labels = ["四码自动上屏", "默认中文输入", "默认中文标点", "默认半角", "默认简体"]
        case "按键":
            labels = ["启用 Control-Shift-1…4 模式键"]
            let popup = NSPopUpButton(frame: NSRect(x: 24, y: 280, width: 260, height: 30))
            popup.addItems(withTitles: ["翻页键 - 和 =", "翻页键 , 和 .", "翻页键 [ 和 ]"])
            popup.selectItem(at: settings.keyBindings.pageKeys.index)
            register(popup, label: "候选翻页键")
            pageKeysPopup = popup
            view.addSubview(popup)
        case "候选":
            labels = ["候选纵向排列"]
            let stepper = NSStepper()
            stepper.frame = NSRect(x: 24, y: 280, width: 96, height: 30)
            stepper.minValue = 5
            stepper.maxValue = 9
            stepper.integerValue = settings.candidatePageSize
            stepper.increment = 1
            register(stepper, label: "每页候选数量 5 至 9")
            pageSizeStepper = stepper
            view.addSubview(stepper)

            let layout = NSPopUpButton(frame: NSRect(x: 24, y: 232, width: 200, height: 30))
            layout.addItems(withTitles: ["纵向候选", "横向候选"])
            layout.selectItem(at: settings.candidateLayout == .vertical ? 0 : 1)
            register(layout, label: "候选布局")
            layoutPopup = layout
            view.addSubview(layout)

            let slider = NSSlider(value: settings.candidateFontScale, minValue: 0.8,
                                  maxValue: 2, target: nil, action: nil)
            slider.frame = NSRect(x: 24, y: 184, width: 260, height: 30)
            register(slider, label: "候选字号缩放")
            fontScaleSlider = slider
            view.addSubview(slider)

            let preview = NSTextField(labelWithString: "1  示例    2  示例    3  示例")
            preview.frame = NSRect(x: 24, y: 120, width: 430, height: 40)
            preview.setAccessibilityLabel("无正文实时预览")
            view.addSubview(preview)
        case "学习": labels = ["启用本地学习", "私密模式", "清除学习数据…"]
        case "用户词库":
            labels = ["搜索用户词条", "添加词条", "编辑词条", "删除词条…"]
            let importButton = makeButton("导入用户词库…", action: #selector(importLexicon))
            importButton.frame = NSRect(x: 24, y: 138, width: 150, height: 30)
            view.addSubview(importButton)
            let exportButton = makeButton("导出用户词库…", action: #selector(exportLexicon))
            exportButton.frame = NSRect(x: 184, y: 138, width: 150, height: 30)
            view.addSubview(exportButton)
        default:
            privacyViewController.loadView()
            accessibleControls.append(contentsOf: privacyViewController.controls)
            return privacyViewController.view
        }
        for (index, label) in labels.enumerated() {
            let control = makeButton(label, action: nil)
            control.frame = NSRect(x: 24, y: 330 - index * 48, width: 430, height: 30)
            view.addSubview(control)
        }
        return view
    }

    private func register(_ control: NSControl, label: String) {
        control.setAccessibilityLabel(label)
        switch control {
        case let popup as NSPopUpButton:
            control.setAccessibilityValue(popup.titleOfSelectedItem ?? "")
        case let stepper as NSStepper:
            control.setAccessibilityValue(String(stepper.integerValue))
        case let slider as NSSlider:
            control.setAccessibilityValue(slider.doubleValue)
        default:
            break
        }
        accessibleControls.append(control)
    }

    private func makeButton(_ title: String, action: Selector?) -> NSButton {
        let button = action == nil
            ? NSButton(checkboxWithTitle: title, target: nil, action: nil)
            : NSButton(title: title, target: self, action: action)
        button.setAccessibilityLabel(title)
        button.refusesFirstResponder = false
        accessibleControls.append(button)
        controlsByTitle[title] = button
        configureInitialState(button, title: title)
        return button
    }

    @objc private func applyFromControls() {
        var updated = settings
        updated.autoCommitAtFour = isOn("四码自动上屏")
        updated.learningEnabled = isOn("启用本地学习")
        updated.candidatePageSize = Int(pageSizeStepper?.integerValue ?? 5)
        updated.candidateLayout = layoutPopup?.indexOfSelectedItem == 1 ? .horizontal : .vertical
        updated.candidateFontScale = fontScaleSlider?.doubleValue ?? 1
        updated.defaultMode.language = isOn("默认中文输入") ? .chinese : .directEnglish
        updated.defaultMode.punctuation = isOn("默认中文标点") ? .chinese : .english
        updated.defaultMode.width = isOn("默认半角") ? .half : .full
        updated.defaultMode.script = isOn("默认简体") ? .simplified : .traditional
        updated.keyBindings = try! KeyBindingSettings(
            modeSwitch: isOn("启用 Control-Shift-1…4 模式键") ? .controlShiftDigits : .disabled,
            pageKeys: CandidatePageKeySet(index: pageKeysPopup?.indexOfSelectedItem ?? 0)
        )
        _ = validateAndApply(updated)
    }

    private func isOn(_ title: String) -> Bool { controlsByTitle[title]?.state == .on }

    private func configureInitialState(_ button: NSButton, title: String) {
        switch title {
        case "四码自动上屏": button.state = settings.autoCommitAtFour ? .on : .off
        case "默认中文输入": button.state = settings.defaultMode.language == .chinese ? .on : .off
        case "默认中文标点": button.state = settings.defaultMode.punctuation == .chinese ? .on : .off
        case "默认半角": button.state = settings.defaultMode.width == .half ? .on : .off
        case "默认简体": button.state = settings.defaultMode.script == .simplified ? .on : .off
        case "启用 Control-Shift-1…4 模式键":
            button.state = settings.keyBindings.modeSwitch == .disabled ? .off : .on
        case "候选纵向排列": button.state = settings.candidateLayout == .vertical ? .on : .off
        case "启用本地学习": button.state = settings.learningEnabled ? .on : .off
        case "私密模式": button.state = PrivacyModeController.shared.privateMode ? .on : .off
        default: break
        }
        if button.target == nil {
            button.setAccessibilityValue(button.state == .on ? "已启用" : "未启用")
        }
    }

    private func announce(_ message: String) {
        lastValidationAnnouncement = message
        NSAccessibility.post(element: window ?? self,
                             notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    @objc private func confirmRestoreDefaults() {
        let alert = NSAlert()
        alert.messageText = "恢复默认设置？"
        alert.informativeText = "只恢复 Settings；用户词库和学习数据不会删除。"
        alert.addButton(withTitle: "恢复默认")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn { _ = try? restoreDefaults(confirmed: true) }
    }

    @objc private func importLexicon() {
        guard let importer = PersonalizationCoordinator.shared.lexiconImporter else { return }
        _ = try? panelController.performImport { [weak self] data in
            let report = data.starts(with: Data("MWARCH01".utf8))
                ? try importer.importArchive(data) : try importer.importText(data)
            self?.importReportController.present(report)
        }
    }

    @objc private func exportLexicon() {
        guard let exporter = PersonalizationCoordinator.shared.lexiconExporter,
              let data = try? exporter.archiveData(includeLearning: false) else { return }
        _ = try? panelController.performExport(data, using: exporter) {
            _ = try LexiconArchiveCodec.decode($0)
        }
    }
}

private extension CandidatePageKeySet {
    var index: Int {
        switch self { case .minusEquals: return 0; case .commaPeriod: return 1; case .bracketPair: return 2 }
    }

    init(index: Int) {
        switch index { case 1: self = .commaPeriod; case 2: self = .bracketPair; default: self = .minusEquals }
    }
}
