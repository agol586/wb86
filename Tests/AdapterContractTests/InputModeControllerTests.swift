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

    func testControllerCreatesNoStandaloneStatusItemAndMenuActionsStillWork() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("Sources/InputMethod/InputModeController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertFalse(source.contains("NSStatusBar.system.statusItem"))
        XCTAssertFalse(source.contains("NSStatusItem"))

        var selected = [InputEvent]()
        let menu = InputModeController.shared.menu(mode: .default) { selected.append($0) }
        menu.performActionForItem(at: 0)
        menu.performActionForItem(at: 1)

        XCTAssertEqual(selected, [.switchLanguage, .switchPunctuation])
        XCTAssertEqual(menu.items.last?.title, "设置…")
    }
}
