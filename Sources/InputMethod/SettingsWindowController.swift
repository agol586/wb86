import AppKit

enum SettingsDestructiveAction: Sendable {
    case clearLearning
    case deleteUserLexicon
    case deleteAllPersonalization
}

private enum SettingsWindowValidationError: Error {
    case keyBinding(KeyBindingConflict)
}

final class SettingsWindowController: NSWindowController {
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
    private var controlsByTitle = [String: NSButton]()
    private var pageSizeStepper: NSStepper?
    private var layoutPopup: NSPopUpButton?
    private var fontScaleSlider: NSSlider?
    private var popupsByLabel = [String: NSPopUpButton]()
    private var bindingChoicesByLabel = [String: [(title: String, binding: ModeSwitchBinding)]]()
    private var titlesByControl = [ObjectIdentifier: String]()
    private weak var tabView: NSTabView?
    private let panelController = ImportExportPanelController()
    private let importReportController = ImportReportViewController()

    init(settings: InputSettings,
         access: SettingsStoreAccess = .writable,
         privacyController: PrivacyModeController = .shared,
         saveHandler: @escaping (InputSettings) throws -> Void = { _ in },
         layoutAvailability: @escaping KeyBindingValidator.LayoutAvailability = { _ in true }) {
        self.settings = settings
        draftSettings = settings
        self.access = access
        self.privacyController = privacyController
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 500),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Mac Wubi 设置"
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
        var initialResponder: NSView? = registeredControls.first
        if let message = readOnlyMessage {
            let status = NSTextField(wrappingLabelWithString: message)
            status.frame = NSRect(x: 12, y: 4, width: 316, height: 46)
            status.isSelectable = true
            register(status, label: "设置状态")
            window.contentView?.addSubview(status)
            registeredControls.forEach { control in
                let title = title(for: control)
                if title != "取消" && title != "设置状态" { control.isEnabled = false }
            }
            lastValidationMessage = message
            lastFocusedControlTitle = "设置状态"
            initialResponder = status
        }
        focusOrderTitles = registeredControls.compactMap { title(for: $0) }
        for (current, next) in zip(registeredControls, registeredControls.dropFirst()) {
            current.nextKeyView = next
        }
        registeredControls.last?.nextKeyView = registeredControls.first
        window.initialFirstResponder = initialResponder
        self.window = window
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
        lastValidationMessage = nil
        lastFocusedControlTitle = nil
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
        let labels: [String]
        switch title {
        case "常用":
            addCommonControls(to: view)
            return view
        case "按键":
            addKeyControls(to: view)
            return view
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
            view.addSubview(preview)
        case "高级":
            for (index, title) in ["私密模式", "本地学习"].enumerated() {
                let control = makeButton(title, action: nil)
                control.target = self
                control.action = #selector(runtimePolicyChanged(_:))
                control.frame = NSRect(x: 24, y: 330 - index * 48, width: 430, height: 30)
                view.addSubview(control)
            }
            for (index, title) in ["清除学习数据…", "搜索用户词条", "添加词条", "编辑词条", "删除词条…"].enumerated() {
                let control = makeButton(title, action: nil)
                control.frame = NSRect(x: 24, y: 234 - index * 38, width: 430, height: 30)
                view.addSubview(control)
            }
            let importButton = makeButton("导入用户词库…", action: #selector(importLexicon))
            importButton.frame = NSRect(x: 24, y: 42, width: 150, height: 30)
            view.addSubview(importButton)
            let exportButton = makeButton("导出用户词库…", action: #selector(exportLexicon))
            exportButton.frame = NSRect(x: 184, y: 42, width: 150, height: 30)
            view.addSubview(exportButton)
            return view
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
            button.target = self
            button.action = #selector(commonOptionChanged(_:))
            let column = index / 3
            let row = index % 3
            button.frame = NSRect(x: 24 + column * 300, y: 130 - row * 42,
                                  width: 285, height: 30)
            view.addSubview(button)
        }
    }

    private func addKeyControls(to view: NSView) {
        let bindingRows: [(String, ModeSwitchBinding)] = [
            ("中英文切换", draftSettings.keyBindings.languageSwitch),
            ("简繁切换", draftSettings.keyBindings.scriptSwitch),
            ("全半角切换", draftSettings.keyBindings.widthSwitch)
        ]
        for (index, row) in bindingRows.enumerated() {
            let caption = NSTextField(labelWithString: row.0)
            caption.frame = NSRect(x: 24, y: 340 - index * 44, width: 130, height: 24)
            let popup = NSPopUpButton(frame: NSRect(x: 162, y: 334 - index * 44,
                                                    width: 220, height: 30))
            let choices = bindingChoices(for: row.0, current: row.1)
            bindingChoicesByLabel[row.0] = choices
            popup.addItems(withTitles: choices.map(\.title))
            popup.selectItem(at: choices.firstIndex { $0.binding == row.1 } ?? 0)
            register(popup, label: row.0)
            popupsByLabel[row.0] = popup
            view.addSubview(caption)
            view.addSubview(popup)
        }

        let layoutCaption = NSTextField(labelWithString: "键盘布局")
        layoutCaption.frame = NSRect(x: 24, y: 208, width: 130, height: 24)
        let keyboardLayout = NSPopUpButton(frame: NSRect(x: 162, y: 202,
                                                        width: 220, height: 30))
        keyboardLayout.addItems(withTitles: ["美国 ANSI", "跟随系统布局"])
        keyboardLayout.selectItem(at: draftSettings.keyBindings.keyboardLayout == .us ? 0 : 1)
        register(keyboardLayout, label: "键盘布局")
        popupsByLabel["键盘布局"] = keyboardLayout
        view.addSubview(layoutCaption)
        view.addSubview(keyboardLayout)

        let pageOptions = [
            "逗号句号翻页", "减号等号翻页", "中括号翻页",
            "Tab/Shift-Tab 翻页", "上下方向键翻页"
        ]
        for (index, title) in pageOptions.enumerated() {
            let button = makeButton(title, action: nil)
            let column = index / 3
            let row = index % 3
            button.frame = NSRect(x: 24 + column * 300, y: 150 - row * 40,
                                  width: 285, height: 30)
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
        var keyBindings = updated.keyBindings
        keyBindings.languageSwitch = selectedBinding("中英文切换")
        keyBindings.scriptSwitch = selectedBinding("简繁切换")
        keyBindings.widthSwitch = selectedBinding("全半角切换")
        keyBindings.pageKeyGroups = Set(CandidatePageKeyGroup.allCases.filter {
            isOn(pageTitle(for: $0))
        })
        keyBindings.keyboardLayout = selectedIndex("键盘布局") == 0 ? .us : .followSystem
        updated.keyBindings = keyBindings
        draftSettings = updated
        _ = validateAndApply(updated)
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
        default: return
        }
    }

    @objc private func runtimePolicyChanged(_ sender: NSButton) {
        switch sender.title {
        case "私密模式": privacyController.setPrivateMode(sender.state == .on)
        case "本地学习": privacyController.setLearningEnabled(sender.state == .on)
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
        case "候选纵向排列": button.state = draftSettings.candidateLayout == .vertical ? .on : .off
        case "私密模式": button.state = privacyController.privateMode ? .on : .off
        case "本地学习": button.state = privacyController.learningEnabled ? .on : .off
        default: break
        }
    }

    private func refreshCommonControls() {
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
        refreshRuntimePolicyControls()
    }

    private func refreshRuntimePolicyControls() {
        controlsByTitle["私密模式"]?.state = privacyController.privateMode ? .on : .off
        controlsByTitle["本地学习"]?.state = privacyController.learningEnabled ? .on : .off
    }

    private func publishMessage(_ message: String) {
        lastValidationMessage = message
    }

    private func reject(_ message: String, focus label: String) {
        lastFocusedControlTitle = label
        if label == "每页候选数量 5 至 9" || label == "候选字号缩放" {
            tabView?.selectTabViewItem(withIdentifier: "外观")
        } else if ["中英文切换", "简繁切换", "全半角切换", "键盘布局"]
            .contains(label) {
            tabView?.selectTabViewItem(withIdentifier: "按键")
        }
        if let control = registeredControls.first(where: { title(for: $0) == label }) {
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
