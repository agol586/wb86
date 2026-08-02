import AppKit
import XCTest
@testable import MacWubi

@MainActor
final class SettingsWindowTests: XCTestCase {
    func testAllGroupsAndKeyboardAccessibleControlsExist() {
        let controller = SettingsWindowController.makeForTesting()
        controller.loadWindow()
        XCTAssertEqual(controller.groupTitles,
                       ["常用", "按键", "外观", "高级"])
        XCTAssertTrue(controller.accessibleControls.allSatisfy {
            !($0.accessibilityLabel() ?? "").isEmpty
        })
        XCTAssertTrue(controller.accessibleControls.allSatisfy(\.acceptsFirstResponder))
        let stepper = controller.accessibleControls.compactMap { $0 as? NSStepper }.first
        XCTAssertEqual(stepper?.minValue, 5)
        XCTAssertEqual(stepper?.maxValue, 9)
        let popups = controller.accessibleControls.compactMap { $0 as? NSPopUpButton }
        XCTAssertTrue(popups.contains { $0.itemTitles == ["中文", "英文"] })
        XCTAssertTrue(popups.contains { $0.itemTitles == ["简体", "繁体"] })
        XCTAssertTrue(popups.contains { $0.itemTitles == ["半角", "全角"] })
        XCTAssertTrue(popups.contains { $0.itemTitles == ["英文标点", "中文标点"] })
        XCTAssertTrue(popups.contains { $0.itemTitles == ["纵向候选", "横向候选"] })
        let slider = controller.accessibleControls.compactMap { $0 as? NSSlider }.first
        XCTAssertEqual(slider?.minValue, 0.8)
        XCTAssertEqual(slider?.maxValue, 2)
    }

    func testCommonPageUsesNewInstallDefaultsAndSeparatesSavedFromDraft() {
        let controller = SettingsWindowController.makeForTesting()
        controller.loadWindow()
        XCTAssertEqual(controller.savedSettings, .newInstallDefault)
        XCTAssertEqual(controller.draftSettings, .newInstallDefault)

        let labels = Set(controller.accessibleControls.compactMap { $0.accessibilityLabel() })
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

    func testKeyPageShowsThreeBindingsFivePageGroupsAndKeyboardLayout() {
        let controller = SettingsWindowController.makeForTesting()
        controller.loadWindow()
        let labels = Set(controller.accessibleControls.compactMap { $0.accessibilityLabel() })
        XCTAssertTrue(labels.isSuperset(of: [
            "中英文切换", "简繁切换", "全半角切换", "键盘布局",
            "逗号句号翻页", "减号等号翻页", "中括号翻页",
            "Tab/Shift-Tab 翻页", "上下方向键翻页"
        ]))

        let popups = controller.accessibleControls.compactMap { $0 as? NSPopUpButton }
        XCTAssertTrue(popups.contains { $0.accessibilityLabel() == "中英文切换"
            && $0.titleOfSelectedItem == "Shift" })
        XCTAssertTrue(popups.contains { $0.accessibilityLabel() == "简繁切换"
            && $0.titleOfSelectedItem == "Control-Shift-F" })
        XCTAssertTrue(popups.contains { $0.accessibilityLabel() == "全半角切换"
            && $0.titleOfSelectedItem == "禁用" })
        XCTAssertTrue(popups.contains { $0.accessibilityLabel() == "键盘布局"
            && $0.itemTitles == ["美国 ANSI", "跟随系统布局"] })

        let pageButtons = controller.accessibleControls.compactMap { $0 as? NSButton }
            .filter { ($0.accessibilityLabel() ?? "").hasSuffix("翻页") }
        XCTAssertEqual(pageButtons.count, 5)
        XCTAssertEqual(pageButtons.filter { $0.state == .on }.count, 4)
        XCTAssertEqual(pageButtons.first { $0.accessibilityLabel() == "上下方向键翻页" }?.state,
                       .off)
    }

    func testKeyBindingConflictAndUnavailableLayoutFocusExactControl() {
        let conflict = SettingsWindowController.makeForTesting()
        conflict.loadWindow()
        conflict.updateDraft { draft in
            draft.keyBindings.scriptSwitch = .standaloneShift
        }
        XCTAssertFalse(conflict.saveDraft())
        XCTAssertEqual(conflict.lastFocusedControlLabel, "简繁切换")
        XCTAssertTrue(conflict.lastValidationAnnouncement?.contains("重复") == true)

        let unavailable = SettingsWindowController(
            settings: .default,
            layoutAvailability: { $0 == .us }
        )
        unavailable.loadWindow()
        unavailable.updateDraft { draft in
            draft.keyBindings.keyboardLayout = .followSystem
        }
        XCTAssertFalse(unavailable.saveDraft())
        XCTAssertEqual(unavailable.lastFocusedControlLabel, "键盘布局")
        XCTAssertTrue(unavailable.lastValidationAnnouncement?.contains("不可用") == true)
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
