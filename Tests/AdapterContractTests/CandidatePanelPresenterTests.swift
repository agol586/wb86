import AppKit
import XCTest
@testable import MacWubi

@MainActor
final class CandidatePanelPresenterTests: XCTestCase {
    func testMouseSelectionUsesNormalCandidateCallbackWithoutTakingKeyFocus() throws {
        var selected = [Int]()
        let presenter = CandidatePanelPresenter { selected.append($0) }
        let code = try XCTUnwrap(InputCode("wq"))
        let page = try CandidatePage(items: [
            Candidate(text: "甲", code: code, source: .base, baseRank: 0,
                      learnedScore: 0, ordinal: 1),
            Candidate(text: "乙", code: code, source: .base, baseRank: 1,
                      learnedScore: 0, ordinal: 2)
        ], pageIndex: 0, pageSize: 5, totalCount: 7)

        presenter.update(with: page)

        XCTAssertEqual(presenter.displayedCandidateTitles, ["1  甲", "2  乙"])
        XCTAssertFalse(presenter.canTakeKeyboardFocus)
        XCTAssertTrue(presenter.performMouseSelection(ordinal: 2))
        XCTAssertEqual(selected, [2])
        XCTAssertFalse(presenter.performMouseSelection(ordinal: 9))
    }

    func testScreenBoundsScalingReducedMotionAndHighContrast() {
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
    }

    func testPresenterAppliesHintFontAndOrientationToNewRows() throws {
        let presenter = CandidatePanelPresenter()
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

        settings.codeHintEnabled = false
        settings.candidateLayout = .vertical
        settings.candidateFontScale = 1
        presenter.apply(settings: settings)
        XCTAssertFalse(presenter.usesHorizontalLayout)
        XCTAssertEqual(presenter.displayedCandidateTitles, ["1  输入法"])
    }
}
