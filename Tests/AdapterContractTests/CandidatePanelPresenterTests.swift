import AppKit
import XCTest
@testable import MacWubi

@MainActor
final class CandidatePanelPresenterTests: XCTestCase {
    func testWubiAssociationHintShowsOnlyTheUntypedSuffix() throws {
        let candidate = try Candidate(
            text: "机会", queryKey: .wubi(XCTUnwrap(InputCode("sm"))),
            source: .baseWubi, baseRank: 0, learnedScore: 0, ordinal: 1,
            wubiHint: XCTUnwrap(InputCode("smwf"))
        )
        let row = CandidateLayoutController().rowPresentation(
            for: candidate, showsCodeHint: true, maximumWidth: 300,
            font: .systemFont(ofSize: NSFont.systemFontSize)
        )

        XCTAssertEqual(row.visibleHint, "wf")
        XCTAssertEqual(row.title, "1  机会  wf")
    }

    func testTypographyKeepsEveryScaleInADailyReadingRange() {
        XCTAssertEqual(CandidateTypography.candidatePointSize(for: 0.8), 13,
                       accuracy: 0.01)
        XCTAssertEqual(CandidateTypography.candidatePointSize(for: 1), 14,
                       accuracy: 0.01)
        XCTAssertEqual(CandidateTypography.candidatePointSize(for: 2), 17,
                       accuracy: 0.01)
        XCTAssertLessThanOrEqual(CandidateTypography.candidatePointSize(for: 2), 18)
    }

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
        XCTAssertEqual(presenter.emphasizedCandidateOrdinals, [1])
        XCTAssertTrue(presenter.candidateRowsHavePointerFeedback)
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

    func testReducedTransparencyAndHighContrastUseASolidCandidateSurface() {
        var preferences = CandidateVisualPreferences(
            reduceMotion: false,
            increaseContrast: false,
            reduceTransparency: true
        )
        let presenter = CandidatePanelPresenter(
            visualPreferencesProvider: { preferences }
        )

        presenter.refreshVisualPreferences()

        XCTAssertTrue(presenter.usesSolidVisualBackground)
        XCTAssertFalse(presenter.usesTranslucentPopoverMaterial)
        XCTAssertEqual(presenter.visualBorderWidth, 1)

        preferences = CandidateVisualPreferences(
            reduceMotion: false,
            increaseContrast: true,
            reduceTransparency: false
        )
        presenter.refreshVisualPreferences()

        XCTAssertTrue(presenter.usesSolidVisualBackground)
        XCTAssertFalse(presenter.usesTranslucentPopoverMaterial)
        XCTAssertEqual(presenter.visualBorderWidth, 2)
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
                       [CandidateTypography.candidatePointSize(for: 1.5)])
        XCTAssertGreaterThanOrEqual(presenter.visualCornerRadius, 8)
        XCTAssertEqual(presenter.visualBorderWidth, 1)
        XCTAssertTrue(presenter.showsPageIndicator)
        XCTAssertEqual(presenter.emphasizedCandidateOrdinals, [1])
        XCTAssertTrue(presenter.usesCandidateTextHierarchy)

        settings.codeHintEnabled = false
        settings.candidateLayout = .vertical
        settings.candidateFontScale = 1
        presenter.apply(settings: settings)
        XCTAssertFalse(presenter.usesHorizontalLayout)
        XCTAssertEqual(presenter.displayedCandidateTitles, ["1  输入法"])
    }

    func testVerticalCandidatesUseFullRowsAndSeparatedPaginationFooter() throws {
        let presenter = CandidatePanelPresenter()
        var settings = InputSettings.default
        settings.candidateLayout = .vertical
        presenter.apply(settings: settings)
        let code = try XCTUnwrap(InputCode("wq"))
        presenter.update(with: try CandidatePage(items: [
            Candidate(text: "甲", code: code, source: .base, baseRank: 0,
                      learnedScore: 0, ordinal: 1),
            Candidate(text: "乙", code: code, source: .base, baseRank: 1,
                      learnedScore: 0, ordinal: 2)
        ], pageIndex: 0, pageSize: 5, totalCount: 7))

        XCTAssertTrue(presenter.candidateRowsFillAvailableWidth)
        XCTAssertEqual(presenter.defaultCandidateIndicatorOrdinals, [1],
                       "The default choice needs a non-color shape cue")
        XCTAssertEqual(presenter.displayedPageIndicator, "第 1 / 2 页")
        XCTAssertEqual(presenter.pageIndicatorAlignment, .right)
        XCTAssertTrue(presenter.usesSeparatedPageFooter)
        XCTAssertFalse(presenter.canTakeKeyboardFocus)
    }

    func testHorizontalCandidatesUseClearerInterCandidateSpacingWithoutEmptyFooter() throws {
        let presenter = CandidatePanelPresenter()
        var settings = InputSettings.default
        settings.candidateLayout = .horizontal
        presenter.apply(settings: settings)
        let code = try XCTUnwrap(InputCode("wq"))
        presenter.update(with: try CandidatePage(items: [
            Candidate(text: "甲", code: code, source: .base, baseRank: 0,
                      learnedScore: 0, ordinal: 1),
            Candidate(text: "乙", code: code, source: .base, baseRank: 1,
                      learnedScore: 0, ordinal: 2)
        ], pageIndex: 0, pageSize: 5, totalCount: 2))

        XCTAssertTrue(presenter.usesHorizontalLayout)
        XCTAssertGreaterThan(presenter.candidateSpacing, 4)
        XCTAssertFalse(presenter.candidateRowsFillAvailableWidth)
        XCTAssertEqual(presenter.displayedPageIndicator, "1/1")
        XCTAssertFalse(presenter.usesSeparatedPageFooter)
    }

    func testHorizontalPageIndicatorStaysOnFirstRowWithoutResizingForPagination() throws {
        let presenter = CandidatePanelPresenter()
        var settings = InputSettings.default
        let code = try XCTUnwrap(InputCode("wq"))
        let items = try [
            Candidate(text: "甲", code: code, source: .base, baseRank: 0,
                      learnedScore: 0, ordinal: 1),
            Candidate(text: "乙", code: code, source: .base, baseRank: 1,
                      learnedScore: 0, ordinal: 2)
        ]
        for scale in [0.8, 1.0, 2.0] {
            settings.candidateFontScale = scale
            settings.candidateLayout = .horizontal
            presenter.apply(settings: settings)
            presenter.update(with: try CandidatePage(items: items, pageIndex: 0,
                                                     pageSize: 5, totalCount: 2))
            let singlePageSize = presenter.displayedPanelSize
            for (index, count, label) in [(0, 50, "1/10"), (9, 50, "10/10"), (0, 2, "1/1")] {
                presenter.update(with: try CandidatePage(items: items, pageIndex: index,
                                                         pageSize: 5, totalCount: count))
                XCTAssertEqual(presenter.displayedPageIndicator, label)
                XCTAssertEqual(presenter.displayedPanelSize.width, singlePageSize.width, accuracy: 0.5)
                XCTAssertEqual(presenter.displayedPanelSize.height, singlePageSize.height, accuracy: 0.5)
                XCTAssertEqual(presenter.pageIndicatorFrame.midY, presenter.candidateContentFrame.midY,
                               accuracy: 0.5)
                XCTAssertGreaterThan(presenter.pageIndicatorFrame.minX, presenter.candidateContentFrame.maxX)
                XCTAssertFalse(presenter.usesSeparatedPageFooter)
            }
            settings.candidateLayout = .vertical
            presenter.apply(settings: settings)
            XCTAssertNil(presenter.displayedPageIndicator)
            presenter.update(with: try CandidatePage(items: items, pageIndex: 0,
                                                     pageSize: 5, totalCount: 50))
            XCTAssertEqual(presenter.displayedPageIndicator, "第 1 / 10 页")
            XCTAssertTrue(presenter.usesSeparatedPageFooter)
        }
    }

}
