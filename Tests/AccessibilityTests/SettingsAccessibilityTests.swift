import AppKit
import XCTest
@testable import MacWubi

@MainActor
final class SettingsAccessibilityTests: XCTestCase {
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

        var invalid = InputSettings.default
        invalid.candidatePageSize = 99
        XCTAssertFalse(controller.validateAndApply(invalid))
        XCTAssertEqual(controller.lastValidationAnnouncement, "设置无效：候选数量必须为 5 至 9。")
        XCTAssertTrue(controller.confirmationMessage(for: .deleteAllPersonalization).contains("基础词库"))
    }
}
