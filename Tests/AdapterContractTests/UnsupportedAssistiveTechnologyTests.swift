import Foundation
import XCTest

final class UnsupportedAssistiveTechnologyTests: XCTestCase {
    func testProductSourceContainsNoSpecializedScreenReaderImplementation() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sourceRoot = repositoryRoot.appendingPathComponent("Sources/InputMethod", isDirectory: true)
        let sourceFiles = try FileManager.default.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
        let forbiddenFileNames = ["AccessibilityAdapter.swift", "AccessibleCandidatePresenter.swift"]
        let forbiddenSourceTokens = [
            "NSAccessibility", "setAccessibility", "accessibilityPerformPress",
            "accessibilityChildren", "setAccessibilityFocused",
            "setAccessibilityApplicationFocusedUIElement"
        ]

        XCTAssertTrue(Set(sourceFiles.map(\.lastPathComponent))
            .isDisjoint(with: forbiddenFileNames))
        for file in sourceFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            for token in forbiddenSourceTokens {
                XCTAssertFalse(source.contains(token), "\(file.lastPathComponent) contains \(token)")
            }
        }
    }
}
