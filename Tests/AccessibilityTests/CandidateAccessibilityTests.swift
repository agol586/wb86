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

    func testCodeHintToggleKeepsAccessibleBodyBeforeOptionalHint() throws {
        let queryKey = try XCTUnwrap(CandidateQueryKey(kind: .pinyin, code: "shurufa"))
        let candidate = try Candidate(
            text: "输入法", queryKey: queryKey, source: .localPinyin,
            baseRank: 0, learnedScore: 0, ordinal: 1,
            wubiHint: XCTUnwrap(InputCode("lwy"))
        )
        let page = try CandidatePage(items: [candidate], pageIndex: 0,
                                     pageSize: 5, totalCount: 1)

        let hidden = AccessibilityAdapter.snapshot(page: page, showsCodeHints: false)
        let shown = AccessibilityAdapter.snapshot(page: page, showsCodeHints: true)

        XCTAssertNil(hidden.candidates.first?.wubiHint)
        XCTAssertEqual(hidden.candidates.first?.value, "输入法")
        XCTAssertEqual(shown.candidates.first?.value, "输入法")
        XCTAssertEqual(shown.candidates.first?.wubiHint, "lwy")
        XCTAssertTrue(shown.announcement.contains("候选 1，输入法，五笔编码 lwy"))
        XCTAssertFalse(shown.announcement.contains("候选 1，lwy，输入法"))
    }

    func testRowLayoutDropsHintBeforeTruncatingCandidateBody() throws {
        let candidate = try Candidate(
            text: "这是必须优先保留的候选正文",
            queryKey: XCTUnwrap(CandidateQueryKey(kind: .pinyin, code: "ceshi")),
            source: .localPinyin, baseRank: 0, learnedScore: 0, ordinal: 1,
            wubiHint: XCTUnwrap(InputCode("abcd"))
        )
        let controller = CandidateLayoutController()
        let roomy = controller.rowPresentation(
            for: candidate, showsCodeHint: true, maximumWidth: 520,
            font: .systemFont(ofSize: NSFont.systemFontSize)
        )
        let narrow = controller.rowPresentation(
            for: candidate, showsCodeHint: true, maximumWidth: 80,
            font: .systemFont(ofSize: NSFont.systemFontSize)
        )

        XCTAssertEqual(roomy.visibleHint, "abcd")
        XCTAssertTrue(roomy.title.hasSuffix("abcd"))
        XCTAssertNil(narrow.visibleHint)
        XCTAssertFalse(narrow.title.contains("abcd"))
        XCTAssertTrue(narrow.title.contains(candidate.text))
        XCTAssertEqual(narrow.accessibilityValue, candidate.text)
        XCTAssertEqual(narrow.accessibilityHint, "abcd")
    }

    func testPresenterAppliesHintFontAndOrientationToNewRows() throws {
        let presenter = AccessibleCandidatePresenter()
        var settings = InputSettings.default
        settings.codeHintEnabled = true
        settings.candidateLayout = .horizontal
        settings.candidateFontScale = 1.5
        presenter.apply(settings: settings)
        let candidate = try Candidate(
            text: "输入法",
            queryKey: XCTUnwrap(CandidateQueryKey(kind: .pinyin, code: "shurufa")),
            source: .localPinyin, baseRank: 0, learnedScore: 0, ordinal: 1,
            wubiHint: XCTUnwrap(InputCode("lwy"))
        )
        presenter.update(with: try CandidatePage(items: [candidate], pageIndex: 0,
                                                 pageSize: 5, totalCount: 1))

        XCTAssertTrue(presenter.usesHorizontalLayout)
        XCTAssertEqual(presenter.displayedCandidateTitles, ["1  输入法  lwy"])
        XCTAssertEqual(presenter.displayedCandidateFontSizes,
                       [NSFont.systemFontSize * 1.5])
        XCTAssertEqual(presenter.accessibilitySnapshot?.candidates.first?.value, "输入法")
        XCTAssertEqual(presenter.accessibilitySnapshot?.candidates.first?.wubiHint, "lwy")

        settings.codeHintEnabled = false
        settings.candidateLayout = .vertical
        settings.candidateFontScale = 1
        presenter.apply(settings: settings)
        XCTAssertFalse(presenter.usesHorizontalLayout)
        XCTAssertEqual(presenter.displayedCandidateTitles, ["1  输入法"])
        XCTAssertNil(presenter.accessibilitySnapshot?.candidates.first?.wubiHint)
    }
}
