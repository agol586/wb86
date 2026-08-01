import AppKit
import XCTest
@testable import MacWubi

@MainActor
final class SettingsWindowTests: XCTestCase {
    func testAllGroupsAndKeyboardAccessibleControlsExist() {
        let controller = SettingsWindowController.makeForTesting()
        controller.loadWindow()
        XCTAssertEqual(controller.groupTitles,
                       ["输入", "按键", "候选", "学习", "用户词库", "隐私"])
        XCTAssertTrue(controller.accessibleControls.allSatisfy {
            !($0.accessibilityLabel() ?? "").isEmpty
        })
        XCTAssertTrue(controller.accessibleControls.allSatisfy(\.acceptsFirstResponder))
        let stepper = controller.accessibleControls.compactMap { $0 as? NSStepper }.first
        XCTAssertEqual(stepper?.minValue, 5)
        XCTAssertEqual(stepper?.maxValue, 9)
        let popups = controller.accessibleControls.compactMap { $0 as? NSPopUpButton }
        XCTAssertTrue(popups.contains { $0.itemTitles == ["翻页键 - 和 =", "翻页键 , 和 .", "翻页键 [ 和 ]"] })
        XCTAssertTrue(popups.contains { $0.itemTitles == ["纵向候选", "横向候选"] })
        let slider = controller.accessibleControls.compactMap { $0 as? NSSlider }.first
        XCTAssertEqual(slider?.minValue, 0.8)
        XCTAssertEqual(slider?.maxValue, 2)
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
