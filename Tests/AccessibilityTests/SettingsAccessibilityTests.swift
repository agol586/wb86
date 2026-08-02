import AppKit
import XCTest
@testable import MacWubi

@MainActor
final class SettingsAccessibilityTests: XCTestCase {
    func testSaveCancelFeedbackAndFailureKeepDraftAndFocus() throws {
        var writes = [InputSettings]()
        let controller = SettingsWindowController(settings: .default) { writes.append($0) }
        controller.loadWindow()
        controller.updateDraft { $0.candidatePageSize = 9 }
        controller.cancelDraft()
        XCTAssertTrue(writes.isEmpty)
        XCTAssertEqual(controller.draftSettings, controller.savedSettings)

        controller.updateDraft { $0.candidatePageSize = 9 }
        XCTAssertTrue(controller.saveDraft())
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(controller.savedSettings.candidatePageSize, 9)
        XCTAssertEqual(controller.lastValidationAnnouncement, "设置已保存。")

        let failing = SettingsWindowController(settings: .default) { _ in
            throw SaveError.failed
        }
        failing.loadWindow()
        failing.updateDraft { $0.candidatePageSize = 8 }
        XCTAssertFalse(failing.saveDraft())
        XCTAssertEqual(failing.savedSettings, .default)
        XCTAssertEqual(failing.draftSettings.candidatePageSize, 8)
        XCTAssertEqual(failing.lastValidationAnnouncement, "保存失败，最后有效设置保持不变。")
        XCTAssertEqual(failing.lastFocusedControlLabel, "初始语言")
    }

    func testKeyboardTraversalValuesFocusOrderAndValidationAnnouncement() {
        let controller = SettingsWindowController.makeForTesting()
        controller.loadWindow()
        XCTAssertFalse(controller.focusOrderLabels.isEmpty)
        XCTAssertEqual(controller.focusOrderLabels, controller.accessibleControls.compactMap {
            $0.accessibilityLabel()
        })
        XCTAssertTrue(controller.accessibleControls.allSatisfy(\.acceptsFirstResponder))
        XCTAssertTrue(controller.accessibleControls.allSatisfy {
            $0.accessibilityValue() != nil || $0 is NSButton
        })
        XCTAssertTrue(controller.accessibleControls.allSatisfy {
            !($0.accessibilityHelp() ?? "").isEmpty
        })

        var invalid = InputSettings.default
        invalid.candidatePageSize = 99
        XCTAssertFalse(controller.validateAndApply(invalid))
        XCTAssertEqual(controller.lastValidationAnnouncement, "设置无效：候选数量必须为 5 至 9。")
        XCTAssertEqual(controller.lastFocusedControlLabel, "每页候选数量 5 至 9")
        XCTAssertTrue(controller.confirmationMessage(for: .deleteAllPersonalization).contains("基础词库"))
    }
}

private enum SaveError: Error { case failed }
