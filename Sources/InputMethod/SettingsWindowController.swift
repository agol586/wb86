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

    let groupTitles = ["常用", "按键", "外观", "高级"]
    private(set) var accessibleControls = [NSControl]()
    private(set) var focusOrderLabels = [String]()
    private(set) var lastValidationAnnouncement: String?
    private(set) var lastFocusedControlLabel: String?
    private(set) var settings: InputSettings
    private(set) var draftSettings: InputSettings
    var savedSettings: InputSettings { settings }
    private let saveHandler: (InputSettings) throws -> Void
    private var controlsByTitle = [String: NSButton]()
    private var pageKeysPopup: NSPopUpButton?
    private var pageSizeStepper: NSStepper?
    private var layoutPopup: NSPopUpButton?
    private var fontScaleSlider: NSSlider?
    private var popupsByLabel = [String: NSPopUpButton]()
    private weak var tabView: NSTabView?
    private let panelController = ImportExportPanelController()
    private let importReportController = ImportReportViewController()
    private let privacyViewController = PrivacyViewController.makeDefault()

    init(settings: InputSettings,
         saveHandler: @escaping (InputSettings) throws -> Void = { _ in }) {
        self.settings = settings
        draftSettings = settings
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
        popupsByLabel.removeAll()
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
        tabView = tabs
        tabs.autoresizingMask = [.width, .height]
        for title in groupTitles {
            let tab = NSTabViewItem(identifier: title)
            tab.label = title
            tab.view = groupView(title)
            tabs.addTabViewItem(tab)
        }
        let applyButton = makeButton("保存", action: #selector(applyFromControls))
        applyButton.frame = NSRect(x: 560, y: 14, width: 96, height: 30)
        let cancelButton = makeButton("取消", action: #selector(cancelFromControls))
        cancelButton.frame = NSRect(x: 456, y: 14, width: 96, height: 30)
        let restoreButton = makeButton("恢复默认…", action: #selector(confirmRestoreDefaults))
        restoreButton.frame = NSRect(x: 336, y: 14, width: 112, height: 30)
        window.contentView?.addSubview(tabs)
        window.contentView?.addSubview(applyButton)
        window.contentView?.addSubview(cancelButton)
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
        draftSettings = validated
    }

    @discardableResult
    func validateAndApply(_ value: InputSettings) -> Bool {
        do {
            try apply(value)
            lastFocusedControlLabel = nil
            announce("设置已保存。")
            return true
        } catch SettingsValidationError.invalidPageSize {
            reject("设置无效：候选数量必须为 5 至 9。", focus: "每页候选数量 5 至 9")
        } catch SettingsValidationError.invalidFontScale {
            reject("设置无效：候选字号缩放必须为 0.8 至 2.0。", focus: "候选字号缩放")
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
        lastValidationAnnouncement = nil
        lastFocusedControlLabel = nil
        refreshCommonControls()
    }

    @discardableResult
    func restoreDefaults(confirmed: Bool) throws -> Bool {
        guard confirmed else { return false }
        try apply(.default)
        return true
    }

    func updateDraft(_ update: (inout InputSettings) -> Void) {
        update(&draftSettings)
        refreshCommonControls()
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
        case "常用":
            addCommonControls(to: view)
            return view
        case "按键":
            labels = ["按键设置将在此页显示"]
        case "外观":
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
        case "高级":
            labels = ["私密模式", "清除学习数据…", "搜索用户词条", "添加词条", "编辑词条", "删除词条…"]
            let importButton = makeButton("导入用户词库…", action: #selector(importLexicon))
            importButton.frame = NSRect(x: 24, y: 42, width: 150, height: 30)
            view.addSubview(importButton)
            let exportButton = makeButton("导出用户词库…", action: #selector(exportLexicon))
            exportButton.frame = NSRect(x: 184, y: 42, width: 150, height: 30)
            view.addSubview(exportButton)
        default:
            labels = []
        }
        for (index, label) in labels.enumerated() {
            let control = makeButton(label, action: nil)
            control.frame = NSRect(x: 24, y: 330 - index * 48, width: 430, height: 30)
            view.addSubview(control)
        }
        return view
    }

    private func addCommonControls(to view: NSView) {
        let popupRows: [(String, [String], Int)] = [
            ("初始语言", ["中文", "英文"], draftSettings.defaultMode.language == .chinese ? 0 : 1),
            ("初始简繁体", ["简体", "繁体"], draftSettings.defaultMode.script == .simplified ? 0 : 1),
            ("初始全半角", ["半角", "全角"], draftSettings.defaultMode.width == .half ? 0 : 1),
            ("中文模式标点", ["英文标点", "中文标点"],
             draftSettings.defaultMode.punctuation == .english ? 0 : 1)
        ]
        for (index, row) in popupRows.enumerated() {
            let caption = NSTextField(labelWithString: row.0)
            caption.frame = NSRect(x: 24, y: 340 - index * 44, width: 130, height: 24)
            let popup = NSPopUpButton(frame: NSRect(x: 162, y: 334 - index * 44,
                                                    width: 170, height: 30))
            popup.addItems(withTitles: row.1)
            popup.selectItem(at: row.2)
            register(popup, label: row.0)
            popupsByLabel[row.0] = popup
            view.addSubview(caption)
            view.addSubview(popup)
        }

        let options = [
            "四码唯一时直接上屏", "第五码将首选词上屏", "五笔自动调频",
            "五笔拼音混合输入", "开启编码提示", "分号和单引号候选快捷键"
        ]
        for (index, title) in options.enumerated() {
            let button = makeButton(title, action: nil)
            let column = index / 3
            let row = index % 3
            button.frame = NSRect(x: 24 + column * 300, y: 130 - row * 42,
                                  width: 285, height: 30)
            view.addSubview(button)
        }
    }

    private func register(_ control: NSControl, label: String) {
        control.setAccessibilityLabel(label)
        control.setAccessibilityHelp("配置“\(label)”；更改仅在按下保存后生效。")
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
        button.setAccessibilityHelp("操作“\(title)”；可使用键盘聚焦并执行。")
        button.refusesFirstResponder = false
        accessibleControls.append(button)
        controlsByTitle[title] = button
        configureInitialState(button, title: title)
        return button
    }

    @objc private func applyFromControls() {
        var updated = draftSettings
        updated.autoCommitAtFour = isOn("四码唯一时直接上屏")
        updated.autoCommitFirstAtFive = isOn("第五码将首选词上屏")
        updated.automaticFrequency = isOn("五笔自动调频")
        updated.mixedPinyinEnabled = isOn("五笔拼音混合输入")
        updated.codeHintEnabled = isOn("开启编码提示")
        updated.candidate2And3ShortcutsEnabled = isOn("分号和单引号候选快捷键")
        updated.candidatePageSize = Int(pageSizeStepper?.integerValue ?? 5)
        updated.candidateLayout = layoutPopup?.indexOfSelectedItem == 1 ? .horizontal : .vertical
        updated.candidateFontScale = fontScaleSlider?.doubleValue ?? 1
        updated.defaultMode.language = selectedIndex("初始语言") == 0 ? .chinese : .directEnglish
        updated.defaultMode.script = selectedIndex("初始简繁体") == 0 ? .simplified : .traditional
        updated.defaultMode.width = selectedIndex("初始全半角") == 0 ? .half : .full
        updated.defaultMode.punctuation = selectedIndex("中文模式标点") == 0 ? .english : .chinese
        draftSettings = updated
        _ = validateAndApply(updated)
    }

    @objc private func cancelFromControls() { cancelDraft() }

    private func selectedIndex(_ label: String) -> Int {
        popupsByLabel[label]?.indexOfSelectedItem ?? 0
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
        case "候选纵向排列": button.state = draftSettings.candidateLayout == .vertical ? .on : .off
        case "私密模式": button.state = PrivacyModeController.shared.privateMode ? .on : .off
        default: break
        }
        if button.target == nil {
            button.setAccessibilityValue(button.state == .on ? "已启用" : "未启用")
        }
    }

    private func refreshCommonControls() {
        controlsByTitle.forEach { configureInitialState($0.value, title: $0.key) }
        popupsByLabel["初始语言"]?.selectItem(at: draftSettings.defaultMode.language == .chinese ? 0 : 1)
        popupsByLabel["初始简繁体"]?.selectItem(at: draftSettings.defaultMode.script == .simplified ? 0 : 1)
        popupsByLabel["初始全半角"]?.selectItem(at: draftSettings.defaultMode.width == .half ? 0 : 1)
        popupsByLabel["中文模式标点"]?.selectItem(at: draftSettings.defaultMode.punctuation == .english ? 0 : 1)
    }

    private func announce(_ message: String) {
        lastValidationAnnouncement = message
        NSAccessibility.post(element: window ?? self,
                             notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    private func reject(_ message: String, focus label: String) {
        lastFocusedControlLabel = label
        if label == "每页候选数量 5 至 9" || label == "候选字号缩放" {
            tabView?.selectTabViewItem(withIdentifier: "外观")
        }
        if let control = accessibleControls.first(where: { $0.accessibilityLabel() == label }) {
            window?.makeFirstResponder(control)
        }
        announce(message)
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
