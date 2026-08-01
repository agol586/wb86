import AppKit
import XCTest
@testable import MacWubi

@MainActor
final class CandidateAccessibilityTests: XCTestCase {
    func testRoleLabelValueSelectedOrderActionAndFocusContract() throws {
        var selected = [Int]()
        let presenter = AccessibleCandidatePresenter { selected.append($0) }
        let code = try XCTUnwrap(InputCode("wq"))
        let page = try CandidatePage(items: [
            Candidate(text: "甲", code: code, source: .base, baseRank: 0, learnedScore: 0, ordinal: 1),
            Candidate(text: "乙", code: code, source: .base, baseRank: 1, learnedScore: 0, ordinal: 2)
        ], pageIndex: 0, pageSize: 5, totalCount: 7)
        presenter.update(with: page)

        let snapshot = try XCTUnwrap(presenter.accessibilitySnapshot)
        XCTAssertEqual(snapshot.containerRole, .group)
        XCTAssertEqual(snapshot.containerLabel, "五笔候选")
        XCTAssertEqual(snapshot.codeValue, "wq")
        XCTAssertEqual(snapshot.candidates.map(\.ordinal), [1, 2])
        XCTAssertEqual(snapshot.candidates.map(\.isSelected), [true, false])
        XCTAssertEqual(snapshot.pageValue, "第 1 页，共 2 页，可向后翻页")
        XCTAssertEqual(snapshot.announcement,
                       "五笔候选窗口。编码 wq。第 1 页，共 2 页，可向后翻页。候选 1，甲，已选中。候选 2，乙。")
        XCTAssertEqual(presenter.accessibilityTopLevelCandidateOrdinals, [1, 2])
        XCTAssertFalse(presenter.canTakeKeyboardFocus)
        XCTAssertTrue(presenter.performAccessibilitySelection(ordinal: 2))
        XCTAssertEqual(selected, [2])
    }


    func testScreenBoundsScalingFullScreenReducedMotionAndHighContrast() {
        let controller = CandidateLayoutController()
        let environment = CandidateLayoutEnvironment(
            visibleFrames: [NSRect(x: 0, y: 0, width: 800, height: 600),
                            NSRect(x: 800, y: 0, width: 640, height: 480)],
            reduceMotion: true, increaseContrast: true, backingScale: 2
        )
        let result = controller.layout(contentSize: NSSize(width: 900, height: 700),
                                       anchorTopLeft: NSPoint(x: 1_400, y: 470),
                                       environment: environment)
        XCTAssertTrue(environment.visibleFrames[1].contains(result.frame))
        XCTAssertFalse(result.animates)
        XCTAssertTrue(result.usesHighContrastBorder)
        XCTAssertEqual(result.backingScale, 2)
    }
}
