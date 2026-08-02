import AppKit
import XCTest
@testable import MacWubi

@MainActor
final class InputModeControllerTests: XCTestCase {
    func testModeItemsContainNoHardCodedOrUnavailableShortcutHints() {
        let menu = InputModeController.shared.menu(mode: .default)
        let modeItems = Array(menu.items.prefix(4))

        XCTAssertEqual(modeItems.map(\.title), [
            "中文输入", "中文标点", "全角字符", "繁体输出"
        ])
        XCTAssertTrue(modeItems.allSatisfy { $0.keyEquivalent.isEmpty })
        XCTAssertTrue(modeItems.allSatisfy {
            !$0.title.contains("⌃⇧") && !$0.title.contains("Control-Shift")
        })
    }

    func testControllerCreatesNoStandaloneStatusItemAndUsesIMKCommandSelectors() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("Sources/InputMethod/InputModeController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertFalse(source.contains("NSStatusBar.system.statusItem"))
        XCTAssertFalse(source.contains("NSStatusItem"))

        let menu = InputModeController.shared.menu(mode: .default)
        XCTAssertEqual(Array(menu.items.prefix(4)).map(\.action),
                       Array(repeating: NSSelectorFromString("selectInputMode:"), count: 4))
        XCTAssertTrue(Array(menu.items.prefix(4)).allSatisfy { $0.target == nil })
        let events: [InputEvent] = Array(menu.items.prefix(4)).compactMap {
            InputModeController.event(forCommandTag: $0.tag)
        }
        XCTAssertEqual(events, [.switchLanguage, .switchPunctuation,
                                .switchWidth, .switchScript])
        XCTAssertEqual(menu.items.last?.title, "设置…")
        XCTAssertEqual(menu.items.last?.action, NSSelectorFromString("showSettings:"))
        XCTAssertNil(menu.items.last?.target)
        XCTAssertTrue(InputController.instancesRespond(to: NSSelectorFromString("selectInputMode:")))
        XCTAssertTrue(InputController.instancesRespond(to: NSSelectorFromString("showSettings:")))
    }
}
