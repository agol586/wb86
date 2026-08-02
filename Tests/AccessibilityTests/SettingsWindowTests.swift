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
