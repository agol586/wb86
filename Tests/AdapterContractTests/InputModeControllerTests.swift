import AppKit
import XCTest
@testable import MacWubi

@MainActor
final class InputModeControllerTests: XCTestCase {
    func testModeItemsContainNoHardCodedOrUnavailableShortcutHints() {
        let menu = InputModeController.shared.menu(mode: .default) { _ in }
        let modeItems = Array(menu.items.prefix(4))

        XCTAssertEqual(modeItems.map(\.title), [
            "中文输入", "中文标点", "全角字符", "繁体输出"
        ])
        XCTAssertTrue(modeItems.allSatisfy { $0.keyEquivalent.isEmpty })
        XCTAssertTrue(modeItems.allSatisfy {
            !$0.title.contains("⌃⇧") && !$0.title.contains("Control-Shift")
        })
    }
}
