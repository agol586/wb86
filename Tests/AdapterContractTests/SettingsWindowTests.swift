import AppKit
import XCTest
@testable import MacWubi

@MainActor
final class SettingsWindowTests: XCTestCase {
    func testAllGroupsAndKeyboardControlsExist() {
        let controller = SettingsWindowController.makeForTesting()
        controller.loadWindow()
        XCTAssertEqual(controller.groupTitles,
                       ["常用", "按键", "外观", "高级"])
        XCTAssertTrue(controller.registeredControls.allSatisfy {
            !($0.identifier?.rawValue ?? "").isEmpty
        })
        XCTAssertTrue(controller.registeredControls.allSatisfy(\.acceptsFirstResponder))
        let stepper = controller.registeredControls.compactMap { $0 as? NSStepper }.first
        XCTAssertEqual(stepper?.minValue, 5)
        XCTAssertEqual(stepper?.maxValue, 9)
        let popups = controller.registeredControls.compactMap { $0 as? NSPopUpButton }
        XCTAssertTrue(popups.contains { $0.itemTitles == ["中文", "英文"] })
        XCTAssertTrue(popups.contains { $0.itemTitles == ["简体", "繁体"] })
        XCTAssertTrue(popups.contains { $0.itemTitles == ["半角", "全角"] })
        XCTAssertTrue(popups.contains { $0.itemTitles == ["英文标点", "中文标点"] })
        XCTAssertTrue(popups.contains { $0.itemTitles == ["纵向候选", "横向候选"] })
        let slider = controller.registeredControls.compactMap { $0 as? NSSlider }.first
        XCTAssertEqual(slider?.minValue, 0.8)
        XCTAssertEqual(slider?.maxValue, 2)
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
            let save = try XCTUnwrap(controller.registeredControls
                .compactMap { $0 as? NSButton }
                .first { $0.identifier?.rawValue == "保存" })

            save.performClick(nil)

            let saved = try XCTUnwrap(persisted.last)
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
}

private enum SettingsWindowTestError: Error { case writeFailed }
