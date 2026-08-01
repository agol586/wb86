import XCTest
@testable import MacWubi

final class InputEngineTests: XCTestCase {
    func testLettersBuildMarkedCodeAndRefreshFromFirstPage() throws {
        let engine = InputEngine(query: query)

        let first = engine.process(.letter("W"))
        XCTAssertEqual(first.clientAction, .setMarkedText("w"))
        XCTAssertEqual(first.candidateAction.page?.pageIndex, 0)
        XCTAssertTrue(first.consumed)

        let second = engine.process(.letter("q"))
        XCTAssertEqual(second.state.composition?.code, InputCode("wq"))
        XCTAssertEqual(second.clientAction, .setMarkedText("wq"))
        XCTAssertEqual(second.candidateAction.page?.items.map(\.text), ["候选1", "候选2"])
    }

    func testSelectionCommitsExactlyOneCandidateAndReturnsIdle() {
        let engine = InputEngine(query: query)
        _ = engine.process(.letter("w"))

        let result = engine.process(.select(2))

        XCTAssertEqual(result.clientAction, .commitText("候选2"))
        XCTAssertEqual(result.candidateAction, .hide)
        XCTAssertEqual(result.state, .idle)
        XCTAssertEqual(result.learningDelta?.candidateText, "候选2")
    }

    func testEmptyResultNeverCommitsAndBoundaryPagingIsConsumed() throws {
        let emptyEngine = InputEngine(query: { code, page in
            try CandidatePage(items: [], pageIndex: page, pageSize: 5, totalCount: 0)
        })
        _ = emptyEngine.process(.letter("a"))
        XCTAssertEqual(emptyEngine.process(.selectFirst).clientAction, .none)
        XCTAssertEqual(emptyEngine.process(.select(1)).clientAction, .none)

        let engine = InputEngine(query: query)
        _ = engine.process(.letter("w"))
        let before = engine.state
        let previous = engine.process(.pagePrevious)
        XCTAssertTrue(previous.consumed)
        XCTAssertEqual(previous.state, before)
        XCTAssertEqual(previous.clientAction, .none)
        XCTAssertEqual(previous.candidateAction, .none)
    }

    func testBackspaceCancelAndPassThroughNeverCommitOriginalCode() {
        let engine = InputEngine(query: query)
        _ = engine.process(.letter("w"))
        _ = engine.process(.letter("q"))
        XCTAssertEqual(engine.process(.backspace).clientAction, .setMarkedText("w"))

        let cancelled = engine.process(.cancel)
        XCTAssertEqual(cancelled.clientAction, .clearMarkedText)
        XCTAssertNil(cancelled.learningDelta)
        XCTAssertEqual(cancelled.state, .idle)

        _ = engine.process(.letter("w"))
        let passed = engine.process(.passThrough)
        XCTAssertFalse(passed.consumed)
        XCTAssertEqual(passed.clientAction, .clearMarkedText)
        XCTAssertEqual(passed.candidateAction, .hide)
        XCTAssertEqual(passed.state, .idle)
    }

    func testIdleEditingEventsPassThroughWithoutSideEffects() {
        for event in [InputEvent.select(1), .selectFirst, .pagePrevious, .pageNext, .backspace, .cancel] {
            let result = InputEngine(query: query).process(event)
            XCTAssertFalse(result.consumed)
            XCTAssertEqual(result.clientAction, .none)
            XCTAssertEqual(result.candidateAction, .none)
            XCTAssertEqual(result.state, .idle)
        }
    }

    func testInvalidLetterAndQueryFailureRecoverAtomically() {
        let invalid = InputEngine(query: query).process(.letter("z"))
        XCTAssertEqual(invalid.state, .idle)
        XCTAssertEqual(invalid.clientAction, .clearMarkedText)
        XCTAssertEqual(invalid.candidateAction, .hide)
        XCTAssertTrue(invalid.consumed)

        let failing = InputEngine(query: { _, _ in throw TestError.failed })
            .process(.letter("a"))
        XCTAssertEqual(failing.state, .idle)
        XCTAssertEqual(failing.clientAction, .clearMarkedText)
        XCTAssertEqual(failing.candidateAction, .hide)
        XCTAssertNil(failing.learningDelta)
    }

    func testDirectEnglishPassesLettersWithoutQuerying() {
        var queried = false
        let engine = InputEngine(mode: InputMode(language: .directEnglish,
                                                  punctuation: .english,
                                                  width: .half,
                                                  script: .simplified)) { _, _ in
            queried = true
            throw TestError.failed
        }

        let result = engine.process(.letter("a"))
        XCTAssertFalse(result.consumed)
        XCTAssertEqual(result.state, .idle)
        XCTAssertFalse(queried)
    }

    func testFourCodeAutoCommitIsAppliedOnlyWhenEnabled() throws {
        let engine = InputEngine(query: query)
        var settings = InputSettings.default
        settings.autoCommitAtFour = true
        engine.apply(settings: settings)

        for letter in ["w", "q", "v"] { _ = engine.process(.letter(letter)) }
        let committed = engine.process(.letter("b"))

        XCTAssertEqual(committed.clientAction, .commitText("候选1"))
        XCTAssertEqual(committed.candidateAction, .hide)
        XCTAssertEqual(committed.state, .idle)
        XCTAssertEqual(committed.learningDelta?.code, InputCode("wqvb"))
    }

    private func query(code: InputCode, pageIndex: Int) throws -> CandidatePage {
        let items = try [1, 2].map {
            try Candidate(text: "候选\($0)", code: code, source: .base,
                          baseRank: $0 - 1, learnedScore: 0, ordinal: $0)
        }
        return try CandidatePage(items: items, pageIndex: pageIndex, pageSize: 5, totalCount: 2)
    }

    private enum TestError: Error { case failed }
}
