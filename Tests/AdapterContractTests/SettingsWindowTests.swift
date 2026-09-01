import AppKit
import XCTest
@testable import MacWubi

@MainActor
final class SettingsWindowTests: XCTestCase {
    func testShowLoadsAndOrdersTheSettingsWindow() {
        let controller = SettingsWindowController.makeForTesting()

        controller.show()

        XCTAssertTrue(controller.isWindowLoaded)
        XCTAssertTrue(controller.window?.isVisible == true)
        XCTAssertEqual(controller.window?.title, "常用 — Mac Wubi 设置")
        controller.close()
    }

    func testSettingsWindowUsesNativePreferenceToolbarAndKeyboardActions() throws {
        let controller = SettingsWindowController.makeForTesting()
        controller.loadWindow()
        let window = try XCTUnwrap(controller.window)
        let toolbar = try XCTUnwrap(window.toolbar)

        XCTAssertEqual(window.toolbarStyle, .preference)
        XCTAssertFalse(toolbar.allowsUserCustomization)
        XCTAssertEqual(toolbar.displayMode, .iconAndLabel)
        XCTAssertEqual(toolbar.selectedItemIdentifier?.rawValue, "常用")
        XCTAssertEqual(Set(toolbar.items.map { $0.itemIdentifier.rawValue }),
                       Set(controller.groupTitles))
        XCTAssertEqual(window.title, "常用 — Mac Wubi 设置")
        XCTAssertFalse(window.styleMask.contains(.resizable))

        let buttons = controller.registeredControls.compactMap { $0 as? NSButton }
        XCTAssertEqual(buttons.first { $0.identifier?.rawValue == "保存" }?.keyEquivalent,
                       "\r")
        XCTAssertEqual(buttons.first { $0.identifier?.rawValue == "取消" }?.keyEquivalent,
                       "\u{1b}")
        XCTAssertTrue(window.defaultButtonCell ===
                      buttons.first { $0.identifier?.rawValue == "保存" }?.cell)
    }

    func testEveryPaneHasConsistentHierarchyAndAdvancedSections() throws {
        let controller = SettingsWindowController.makeForTesting()
        controller.loadWindow()
        let content = try XCTUnwrap(controller.window?.contentView)
        let tabView: NSTabView = try XCTUnwrap(firstView(ofType: NSTabView.self, in: content))
        let paneViews = tabView.tabViewItems.compactMap(\.view)
        let identifiers = Set(paneViews.flatMap(allViews(in:))
            .compactMap { $0.identifier?.rawValue })

        for title in controller.groupTitles {
            XCTAssertTrue(identifiers.contains("\(title)页标题"), title)
            XCTAssertTrue(identifiers.contains("\(title)页说明"), title)
        }
        XCTAssertTrue(identifiers.isSuperset(of: [
            "运行状态分区", "用户词库分区", "本地数据分区"
        ]))
    }

    func testEveryPaneStartsWithACompactConsistentTopMargin() throws {
        let controller = SettingsWindowController.makeForTesting()
        controller.loadWindow()
        let content = try XCTUnwrap(controller.window?.contentView)
        let tabView: NSTabView = try XCTUnwrap(firstView(ofType: NSTabView.self, in: content))
        var measuredMargins = [CGFloat]()

        for title in controller.groupTitles {
            tabView.selectTabViewItem(withIdentifier: title)
            content.layoutSubtreeIfNeeded()
            let pane = try XCTUnwrap(tabView.tabViewItems.first {
                ($0.identifier as? String) == title
            }?.view)
            let header = try XCTUnwrap(allViews(in: pane).first {
                $0.identifier?.rawValue == "\(title)页标题"
            })
            let headerFrame = header.convert(header.bounds, to: content)
            let topMargin = content.bounds.maxY - headerFrame.maxY
            measuredMargins.append(topMargin)
            XCTAssertLessThanOrEqual(topMargin, 44, title)
        }

        let firstMargin = try XCTUnwrap(measuredMargins.first)
        XCTAssertTrue(measuredMargins.allSatisfy { abs($0 - firstMargin) < 1 })
    }

    func testAllGroupsAndKeyboardControlsExist() {
        let controller = SettingsWindowController.makeForTesting()
        controller.loadWindow()
        XCTAssertEqual(controller.groupTitles,
                       ["常用", "按键", "外观", "高级"])
        XCTAssertTrue(controller.registeredControls.allSatisfy {
            !($0.identifier?.rawValue ?? "").isEmpty
        })
        XCTAssertTrue(controller.registeredControls.filter {
            $0.identifier?.rawValue != "操作反馈" && $0.isEnabled
        }.allSatisfy(\.acceptsFirstResponder))
        let stepper = controller.registeredControls.compactMap { $0 as? NSStepper }.first
        XCTAssertEqual(stepper?.minValue, 5)
        XCTAssertEqual(stepper?.maxValue, 9)
        let popups = controller.registeredControls.compactMap { $0 as? NSPopUpButton }
        XCTAssertTrue(popups.contains { $0.itemTitles == ["中文", "英文"] })
        XCTAssertTrue(popups.contains { $0.itemTitles == ["简体", "繁体"] })
        XCTAssertTrue(popups.contains { $0.itemTitles == ["半角", "全角"] })
        XCTAssertTrue(popups.contains { $0.itemTitles == ["英文标点", "中文标点"] })
        XCTAssertTrue(popups.contains { $0.itemTitles == ["纵向", "横向"] })
        let slider = controller.registeredControls.compactMap { $0 as? NSSlider }.first
        XCTAssertEqual(slider?.minValue, 0.8)
        XCTAssertEqual(slider?.maxValue, 2)
        XCTAssertFalse(controller.registeredControls.contains {
            $0.identifier?.rawValue == "候选纵向排列"
        })
        let extended = controller.registeredControls.compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == "显示扩展汉字" }
        XCTAssertEqual(extended?.state, .off)
    }

    func testExtendedCharacterSettingUpdatesDraftSavesAndRestarts() throws {
        var persisted = [InputSettings]()
        let controller = SettingsWindowController(settings: .newInstallDefault) {
            persisted.append($0)
        }
        controller.loadWindow()
        let toggle = try XCTUnwrap(controller.registeredControls.compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == "显示扩展汉字" })
        toggle.performClick(nil)
        XCTAssertTrue(controller.draftSettings.extendedCharacterSetEnabled)

        let save = try XCTUnwrap(controller.registeredControls.compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == "保存" })
        save.performClick(nil)
        let saved = try XCTUnwrap(persisted.last)
        XCTAssertTrue(saved.extendedCharacterSetEnabled)

        let restarted = SettingsWindowController(settings: saved)
        restarted.loadWindow()
        let restartedToggle = try XCTUnwrap(
            restarted.registeredControls.compactMap { $0 as? NSButton }
                .first { $0.identifier?.rawValue == "显示扩展汉字" }
        )
        XCTAssertEqual(restartedToggle.state, .on)
    }

    func testAdvancedOperationsAreActionButtonsWithFeedbackSurface() throws {
        let controller = SettingsWindowController.makeForTesting()
        controller.loadWindow()
        let controls = Dictionary(uniqueKeysWithValues: controller.registeredControls.compactMap {
            control -> (String, NSControl)? in
            guard let identifier = control.identifier?.rawValue else { return nil }
            return (identifier, control)
        })
        for title in [
            "清除学习数据…", "搜索用户词条", "添加词条", "编辑词条", "删除词条…",
            "导入用户词库…", "导出用户词库…", "隐私与数据管理…"
        ] {
            let button = try XCTUnwrap(controls[title] as? NSButton)
            XCTAssertTrue(button.isBordered, title)
            XCTAssertNotNil(button.target, title)
            XCTAssertNotNil(button.action, title)
        }
        let feedback = try XCTUnwrap(controls["操作反馈"] as? NSTextField)
        XCTAssertFalse(feedback.isHidden)
    }

    func testUserLexiconManagementWindowExposesSearchMutationsAndFeedback() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWubiLexiconWindow-\(UUID().uuidString)",
                                   isDirectory: true)
        let store = try UserLexiconStore(writer: SnapshotWriter(rootURL: root))
        let service = UserLexiconService(store: store)
        let controller = UserLexiconWindowController { service }
        controller.loadWindow()
        let content = try XCTUnwrap(controller.window?.contentView)
        let controls = allControls(in: content)
        let identifiers = Set(controls.compactMap { $0.identifier?.rawValue })

        XCTAssertTrue(identifiers.isSuperset(of: [
            "词条搜索", "搜索", "编码", "词条", "固定顺序（可选）",
            "添加", "保存编辑", "删除所选…", "词库操作反馈"
        ]))
        for title in ["搜索", "添加", "保存编辑", "删除所选…"] {
            let button = try XCTUnwrap(controls.compactMap { $0 as? NSButton }
                .first { $0.identifier?.rawValue == title })
            XCTAssertTrue(button.isBordered, title)
            XCTAssertNotNil(button.target, title)
            XCTAssertNotNil(button.action, title)
        }
        let feedback = try XCTUnwrap(controls.compactMap { $0 as? NSTextField }
            .first { $0.identifier?.rawValue == "词库操作反馈" })
        XCTAssertTrue(feedback.isSelectable)
    }

    func testPrivacyRuntimeTogglePublishesVisibleFeedback() throws {
        let baseline = PrivacyModeController.shared.privateMode
        defer { PrivacyModeController.shared.setPrivateMode(baseline) }
        let controller = PrivacyViewController(statusProvider: nil, deletionCoordinator: nil)
        controller.loadView()
        let privateMode = try XCTUnwrap(controller.controls.compactMap { $0 as? NSButton }
            .first { $0.title == "私密模式" })
        let feedback = try XCTUnwrap(controller.controls.compactMap { $0 as? NSTextField }
            .first { $0.identifier?.rawValue == "隐私操作反馈" })

        privateMode.state = baseline ? .off : .on
        privateMode.performClick(nil)

        XCTAssertFalse(controller.lastFeedback.isEmpty)
        XCTAssertEqual(feedback.stringValue, controller.lastFeedback)
    }

    func testCancelAndRestoreRefreshEveryPersistedControl() throws {
        var baseline = InputSettings.default
        baseline.candidatePageSize = 7
        baseline.candidateLayout = .horizontal
        baseline.candidateFontScale = 1.6
        baseline.defaultMode.language = .directEnglish
        let controller = SettingsWindowController(settings: baseline)
        controller.loadWindow()
        let controls = Dictionary(uniqueKeysWithValues: controller.registeredControls.compactMap {
            control -> (String, NSControl)? in
            guard let identifier = control.identifier?.rawValue else { return nil }
            return (identifier, control)
        })
        let stepper = try XCTUnwrap(controls["每页候选数量 5 至 9"] as? NSStepper)
        let layout = try XCTUnwrap(controls["候选布局"] as? NSPopUpButton)
        let slider = try XCTUnwrap(controls["候选字号缩放"] as? NSSlider)
        let language = try XCTUnwrap(controls["初始语言"] as? NSPopUpButton)

        stepper.integerValue = 9
        layout.selectItem(at: 0)
        slider.doubleValue = 0.8
        language.selectItem(at: 0)
        controller.cancelDraft()
        XCTAssertEqual(stepper.integerValue, 7)
        XCTAssertEqual(layout.indexOfSelectedItem, 1)
        XCTAssertEqual(slider.doubleValue, 1.6, accuracy: 0.001)
        XCTAssertEqual(language.indexOfSelectedItem, 1)
        XCTAssertEqual((controls["操作反馈"] as? NSTextField)?.stringValue,
                       "未保存的修改已取消。")

        XCTAssertTrue(try controller.restoreDefaults(confirmed: true))
        XCTAssertEqual(stepper.integerValue, InputSettings.default.candidatePageSize)
        XCTAssertEqual(layout.indexOfSelectedItem, 0)
        XCTAssertEqual(slider.doubleValue, InputSettings.default.candidateFontScale,
                       accuracy: 0.001)
        XCTAssertEqual(language.indexOfSelectedItem, 0)
        XCTAssertEqual((controls["操作反馈"] as? NSTextField)?.stringValue,
                       "已恢复默认设置。")
    }

    func testAppearancePageHasLabeledValuesAndDraftPreview() throws {
        let controller = SettingsWindowController.makeForTesting()
        controller.loadWindow()
        let content = try XCTUnwrap(controller.window?.contentView)
        let tabView: NSTabView = try XCTUnwrap(firstView(ofType: NSTabView.self, in: content))
        tabView.selectTabViewItem(withIdentifier: "外观")
        let controls = Dictionary(uniqueKeysWithValues: allControls(in: content).compactMap {
            control -> (String, NSControl)? in
            guard let identifier = control.identifier?.rawValue else { return nil }
            return (identifier, control)
        })

        XCTAssertEqual((controls["外观页说明"] as? NSTextField)?.stringValue,
                       "调整候选窗口的密度与阅读大小")
        XCTAssertEqual((controls["每页候选标题"] as? NSTextField)?.stringValue, "每页候选")
        XCTAssertEqual((controls["排列方式标题"] as? NSTextField)?.stringValue, "排列方式")
        XCTAssertEqual((controls["文字大小标题"] as? NSTextField)?.stringValue, "文字大小")
        XCTAssertEqual((controls["每页候选当前值"] as? NSTextField)?.stringValue, "5 个")
        XCTAssertEqual((controls["字号当前值"] as? NSTextField)?.stringValue, "标准 · 14 pt")
        XCTAssertEqual(controller.appearancePreviewCandidateTitles,
                       ["1  示例", "2  示例", "3  示例"])
        XCTAssertEqual(controller.appearancePreviewEmphasizedOrdinals, [1])
        XCTAssertFalse(controller.appearancePreviewUsesHorizontalLayout)

        controller.updateDraft { draft in
            draft.candidatePageSize = 8
            draft.candidateLayout = .horizontal
            draft.candidateFontScale = 2
        }

        XCTAssertEqual((controls["每页候选当前值"] as? NSTextField)?.stringValue, "8 个")
        XCTAssertEqual((controls["字号当前值"] as? NSTextField)?.stringValue, "特大 · 17 pt")
        XCTAssertTrue(controller.appearancePreviewUsesHorizontalLayout)
        XCTAssertEqual(controller.appearancePreviewFontSizes, [17, 17, 17])
    }

    func testDraftStateMakesSaveAndCancelAvailabilityExplicit() throws {
        let controller = SettingsWindowController.makeForTesting()
        controller.loadWindow()
        let controls = Dictionary(uniqueKeysWithValues: controller.registeredControls.compactMap {
            control -> (String, NSControl)? in
            guard let identifier = control.identifier?.rawValue else { return nil }
            return (identifier, control)
        })
        let save = try XCTUnwrap(controls["保存"] as? NSButton)
        let cancel = try XCTUnwrap(controls["取消"] as? NSButton)
        let feedback = try XCTUnwrap(controls["操作反馈"] as? NSTextField)

        XCTAssertFalse(controller.hasUnsavedChanges)
        XCTAssertFalse(save.isEnabled)
        XCTAssertFalse(cancel.isEnabled)
        XCTAssertEqual(feedback.stringValue, "所有更改均已保存。")

        let extended = try XCTUnwrap(controls["显示扩展汉字"] as? NSButton)
        extended.performClick(nil)

        XCTAssertTrue(controller.hasUnsavedChanges)
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(cancel.isEnabled)
        XCTAssertEqual(feedback.stringValue, "有未保存的修改。")

        cancel.performClick(nil)
        XCTAssertFalse(controller.hasUnsavedChanges)
        XCTAssertFalse(save.isEnabled)
        XCTAssertFalse(cancel.isEnabled)
        XCTAssertEqual(feedback.stringValue, "未保存的修改已取消。")
    }

    func testEveryPersistedControlPublishesDraftChangesImmediately() throws {
        let controller = SettingsWindowController.makeForTesting()
        controller.loadWindow()
        let persistedControlTitles = [
            "初始语言", "初始简繁体", "初始全半角", "中文模式标点",
            "中英文切换", "简繁切换", "全半角切换", "键盘布局",
            "逗号句号翻页", "减号等号翻页", "中括号翻页",
            "Tab/Shift-Tab 翻页", "上下方向键翻页"
        ]

        for title in persistedControlTitles {
            let control = try XCTUnwrap(controller.registeredControls.first {
                $0.identifier?.rawValue == title
            }, title)
            XCTAssertNotNil(control.target, title)
            XCTAssertNotNil(control.action, title)
        }
    }

    func testAdvancedPageControlsPrivacyAndLearningImmediatelyAndReopensCurrentState() throws {
        var published = [(privateMode: Bool, learningEnabled: Bool)]()
        let privacy = PrivacyModeController {
            published.append((privateMode: $0, learningEnabled: $1))
        }
        privacy.setPrivateMode(true)
        privacy.setLearningEnabled(false)
        let controller = SettingsWindowController(settings: .default,
                                                  privacyController: privacy)
        controller.loadWindow()

        let privateMode = try XCTUnwrap(controller.registeredControls
            .compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == "私密模式" })
        let localLearning = try XCTUnwrap(controller.registeredControls
            .compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == "本地学习" })
        XCTAssertEqual(privateMode.state, .on)
        XCTAssertEqual(localLearning.state, .off)
        let draftBefore = controller.draftSettings

        privateMode.performClick(nil)
        localLearning.performClick(nil)

        XCTAssertFalse(privacy.privateMode)
        XCTAssertTrue(privacy.learningEnabled)
        XCTAssertEqual(controller.draftSettings, draftBefore)
        controller.cancelDraft()
        XCTAssertEqual(privateMode.state, .off)
        XCTAssertEqual(localLearning.state, .on)

        let reopened = SettingsWindowController(settings: .default,
                                                privacyController: privacy)
        reopened.loadWindow()
        let reopenedStates = Dictionary(uniqueKeysWithValues: reopened.registeredControls
            .compactMap { control -> (String, NSControl.StateValue)? in
                guard let button = control as? NSButton,
                      ["私密模式", "本地学习"].contains(button.identifier?.rawValue ?? "")
                else { return nil }
                return (button.identifier!.rawValue, button.state)
            })
        XCTAssertEqual(reopenedStates["私密模式"], .off)
        XCTAssertEqual(reopenedStates["本地学习"], .on)
        XCTAssertEqual(published.last?.privateMode, false)
        XCTAssertEqual(published.last?.learningEnabled, true)
    }

    func testCommonPageUsesNewInstallDefaultsAndSeparatesSavedFromDraft() {
        let controller = SettingsWindowController.makeForTesting()
        controller.loadWindow()
        XCTAssertEqual(controller.savedSettings, .newInstallDefault)
        XCTAssertEqual(controller.draftSettings, .newInstallDefault)

        let labels = Set(controller.registeredControls.compactMap { $0.identifier?.rawValue })
        XCTAssertTrue(labels.isSuperset(of: [
            "初始语言", "初始简繁体", "初始全半角", "中文模式标点",
            "四码唯一时直接上屏", "第五码将首选词上屏", "五笔自动调频",
            "五笔拼音混合输入", "开启编码提示", "分号和单引号候选快捷键"
        ]))

        controller.updateDraft { draft in
            draft.autoCommitAtFour = false
            draft.autoCommitFirstAtFive = true
            draft.automaticFrequency = true
        }
        XCTAssertTrue(controller.savedSettings.autoCommitAtFour)
        XCTAssertFalse(controller.draftSettings.autoCommitAtFour)
        XCTAssertTrue(controller.draftSettings.autoCommitFirstAtFive)
        XCTAssertTrue(controller.draftSettings.automaticFrequency)
    }

    func testAutoCommitAndFrequencyCheckboxesBindSaveAndRestartIndependently() throws {
        var persisted = [InputSettings]()
        let controller = SettingsWindowController(settings: .newInstallDefault) {
            persisted.append($0)
        }
        controller.loadWindow()

        let fourCode = try XCTUnwrap(controller.registeredControls.compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == "四码唯一时直接上屏" })
        let fiveCode = try XCTUnwrap(controller.registeredControls.compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == "第五码将首选词上屏" })
        let frequency = try XCTUnwrap(controller.registeredControls.compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == "五笔自动调频" })

        fourCode.performClick(nil)
        XCTAssertFalse(controller.draftSettings.autoCommitAtFour)
        XCTAssertFalse(controller.draftSettings.autoCommitFirstAtFive)
        XCTAssertFalse(controller.draftSettings.automaticFrequency)

        fiveCode.performClick(nil)
        XCTAssertFalse(controller.draftSettings.autoCommitAtFour)
        XCTAssertTrue(controller.draftSettings.autoCommitFirstAtFive)
        XCTAssertFalse(controller.draftSettings.automaticFrequency)

        frequency.performClick(nil)
        XCTAssertFalse(controller.draftSettings.autoCommitAtFour)
        XCTAssertTrue(controller.draftSettings.autoCommitFirstAtFive)
        XCTAssertTrue(controller.draftSettings.automaticFrequency)

        let save = try XCTUnwrap(controller.registeredControls.compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == "保存" })
        save.performClick(nil)
        let saved = try XCTUnwrap(persisted.last)
        XCTAssertFalse(saved.autoCommitAtFour)
        XCTAssertTrue(saved.autoCommitFirstAtFive)
        XCTAssertTrue(saved.automaticFrequency)
        XCTAssertEqual(saved.mixedPinyinEnabled, InputSettings.newInstallDefault.mixedPinyinEnabled)

        let restarted = SettingsWindowController(settings: saved)
        restarted.loadWindow()
        let restartedButtons = Dictionary(uniqueKeysWithValues: restarted.registeredControls
            .compactMap { control -> (String, NSButton)? in
                guard let button = control as? NSButton,
                      let identifier = button.identifier?.rawValue else { return nil }
                return (identifier, button)
            })
        XCTAssertEqual(restartedButtons["四码唯一时直接上屏"]?.state, .off)
        XCTAssertEqual(restartedButtons["第五码将首选词上屏"]?.state, .on)
        XCTAssertEqual(restartedButtons["五笔自动调频"]?.state, .on)
    }

    func testKeyPageShowsThreeBindingsFivePageGroupsAndKeyboardLayout() {
        let controller = SettingsWindowController.makeForTesting()
        controller.loadWindow()
        let labels = Set(controller.registeredControls.compactMap { $0.identifier?.rawValue })
        XCTAssertTrue(labels.isSuperset(of: [
            "中英文切换", "简繁切换", "全半角切换", "键盘布局",
            "逗号句号翻页", "减号等号翻页", "中括号翻页",
            "Tab/Shift-Tab 翻页", "上下方向键翻页"
        ]))

        let popups = controller.registeredControls.compactMap { $0 as? NSPopUpButton }
        XCTAssertTrue(popups.contains { $0.identifier?.rawValue == "中英文切换"
            && $0.titleOfSelectedItem == "Shift"
            && $0.itemTitles == ["Shift", "Control", "Caps Lock", "禁用快捷键"] })
        XCTAssertTrue(popups.contains { $0.identifier?.rawValue == "简繁切换"
            && $0.titleOfSelectedItem == "Control-Shift-F"
            && $0.itemTitles == ["Control-Shift-F", "禁用快捷键"] })
        XCTAssertTrue(popups.contains { $0.identifier?.rawValue == "全半角切换"
            && $0.titleOfSelectedItem == "禁用快捷键"
            && $0.itemTitles == ["Shift-Space", "禁用快捷键"] })
        XCTAssertTrue(popups.contains { $0.identifier?.rawValue == "键盘布局"
            && $0.itemTitles == ["美国 ANSI", "跟随系统布局"] })

        let pageButtons = controller.registeredControls.compactMap { $0 as? NSButton }
            .filter { ($0.identifier?.rawValue ?? "").hasSuffix("翻页") }
        XCTAssertEqual(pageButtons.count, 5)
        XCTAssertEqual(pageButtons.filter { $0.state == .on }.count, 4)
        XCTAssertEqual(pageButtons.first { $0.identifier?.rawValue == "上下方向键翻页" }?.state,
                       .off)
    }

    func testLanguageModifierChoicesSaveAndReopenWithExactSelection() throws {
        let choices: [(String, ModeSwitchBinding)] = [
            ("Shift", .standaloneShift),
            ("Control", .standaloneControl),
            ("Caps Lock", .standaloneCapsLock),
            ("禁用快捷键", .disabled)
        ]

        for (index, choice) in choices.enumerated() {
            var persisted = [InputSettings]()
            let controller = SettingsWindowController(settings: .default) {
                persisted.append($0)
            }
            controller.loadWindow()
            let popup = try XCTUnwrap(controller.registeredControls
                .compactMap { $0 as? NSPopUpButton }
                .first { $0.identifier?.rawValue == "中英文切换" })
            XCTAssertEqual(popup.itemTitles, choices.map(\.0))
            popup.selectItem(at: index)
            _ = popup.sendAction(popup.action, to: popup.target)
            let save = try XCTUnwrap(controller.registeredControls
                .compactMap { $0 as? NSButton }
                .first { $0.identifier?.rawValue == "保存" })

            save.performClick(nil)

            let saved = persisted.last ?? controller.savedSettings
            XCTAssertEqual(saved.keyBindings.languageSwitch, choice.1)
            let restarted = SettingsWindowController(settings: saved)
            restarted.loadWindow()
            let restartedPopup = try XCTUnwrap(restarted.registeredControls
                .compactMap { $0 as? NSPopUpButton }
                .first { $0.identifier?.rawValue == "中英文切换" })
            XCTAssertEqual(restartedPopup.titleOfSelectedItem, choice.0)
        }
    }

    func testKeyBindingConflictAndUnavailableLayoutFocusExactControl() {
        let conflict = SettingsWindowController.makeForTesting()
        conflict.loadWindow()
        conflict.updateDraft { draft in
            draft.keyBindings.scriptSwitch = .standaloneShift
        }
        XCTAssertFalse(conflict.saveDraft())
        XCTAssertEqual(conflict.lastFocusedControlTitle, "简繁切换")
        XCTAssertTrue(conflict.lastValidationMessage?.contains("重复") == true)

        let unavailable = SettingsWindowController(
            settings: .default,
            layoutAvailability: { $0 == .us }
        )
        unavailable.loadWindow()
        unavailable.updateDraft { draft in
            draft.keyBindings.keyboardLayout = .followSystem
        }
        XCTAssertFalse(unavailable.saveDraft())
        XCTAssertEqual(unavailable.lastFocusedControlTitle, "键盘布局")
        XCTAssertTrue(unavailable.lastValidationMessage?.contains("不可用") == true)
    }

    func testFieldErrorAndSaveFailureKeepLastValidBaseline() {
        let baseline = InputSettings.default
        let controller = SettingsWindowController(settings: baseline) { _ in
            throw SettingsWindowTestError.writeFailed
        }
        controller.loadWindow()

        controller.updateDraft { $0.candidatePageSize = 99 }
        XCTAssertFalse(controller.saveDraft())
        XCTAssertEqual(controller.lastFocusedControlTitle, "每页候选数量 5 至 9")
        XCTAssertTrue(controller.lastValidationMessage?.contains("5 至 9") == true)
        XCTAssertEqual(controller.savedSettings, baseline)

        controller.updateDraft { draft in
            draft.candidatePageSize = 7
            draft.autoCommitAtFour.toggle()
        }
        XCTAssertFalse(controller.saveDraft())
        XCTAssertEqual(controller.lastFocusedControlTitle, "初始语言")
        XCTAssertTrue(controller.lastValidationMessage?.contains("最后有效设置") == true)
        XCTAssertEqual(controller.savedSettings, baseline)
        controller.cancelDraft()
        XCTAssertEqual(controller.draftSettings, baseline)
    }

    func testFutureSchemaShowsReadOnlyStatusAndFocusesVisibleFeedback() throws {
        let controller = SettingsWindowController(
            settings: .default,
            access: .readOnlyFuture(schemaVersion: 99)
        )
        controller.loadWindow()

        XCTAssertTrue(controller.isReadOnly)
        XCTAssertTrue(controller.readOnlyMessage?.contains("版本 99") == true)
        XCTAssertEqual(controller.lastFocusedControlTitle, "设置状态")
        let status = try XCTUnwrap(controller.registeredControls.first {
            $0.identifier?.rawValue == "设置状态"
        })
        XCTAssertEqual((status as? NSTextField)?.stringValue, controller.readOnlyMessage)
        XCTAssertTrue(controller.registeredControls.filter {
            $0.identifier?.rawValue != "设置状态" && $0.identifier?.rawValue != "取消"
        }.allSatisfy { !$0.isEnabled })

        var changed = InputSettings.default
        changed.candidatePageSize = 9
        XCTAssertFalse(controller.validateAndApply(changed))
        XCTAssertEqual(controller.lastFocusedControlTitle, "设置状态")
        XCTAssertTrue(controller.lastValidationMessage?.contains("只读") == true)
        XCTAssertThrowsError(try controller.restoreDefaults(confirmed: true)) { error in
            XCTAssertEqual(error as? SettingsValidationError, .unsupportedSchema)
        }
        XCTAssertEqual(controller.savedSettings, .default)
    }

    func testAppearancePreviewContainsNoCandidateOrInputText() {
        let preview = CandidateAppearanceController().preview(settings: .default)
        XCTAssertEqual(preview.items, ["1  示例", "2  示例", "3  示例"])
        XCTAssertFalse(preview.items.joined().contains("候选词"))
    }

    func testApplyAndRestoreRequireExplicitActions() throws {
        var saved = [InputSettings]()
        let controller = SettingsWindowController(settings: .default) { saved.append($0) }
        var changed = InputSettings.default
        changed.candidatePageSize = 9
        try controller.apply(changed)
        XCTAssertEqual(saved.last?.candidatePageSize, 9)
        XCTAssertFalse(try controller.restoreDefaults(confirmed: false))
        XCTAssertTrue(try controller.restoreDefaults(confirmed: true))
        XCTAssertEqual(saved.last, .default)
    }

    func testDestructiveConfirmationNamesAffectedDomain() {
        let controller = SettingsWindowController.makeForTesting()
        XCTAssertTrue(controller.confirmationMessage(for: .clearLearning).contains("学习"))
        XCTAssertTrue(controller.confirmationMessage(for: .deleteUserLexicon).contains("用户词库"))
        XCTAssertTrue(controller.confirmationMessage(for: .deleteAllPersonalization).contains("全部个性化"))
    }

    private func allControls(in view: NSView) -> [NSControl] {
        view.subviews.flatMap { subview in
            ((subview as? NSControl).map { [$0] } ?? []) + allControls(in: subview)
        }
    }

    private func allViews(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(allViews(in:))
    }

    private func firstView<T: NSView>(ofType type: T.Type, in view: NSView) -> T? {
        if let matchingView = view as? T { return matchingView }
        for subview in view.subviews {
            if let matchingView = firstView(ofType: type, in: subview) {
                return matchingView
            }
        }
        return nil
    }
}

private enum SettingsWindowTestError: Error { case writeFailed }
