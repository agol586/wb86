import XCTest
@testable import MacWubi

final class InputEngineTests: XCTestCase {
    func testModeShortcutsSafelyCancelCompositionWithoutCommittingRawCode() throws {
        let cases: [(InputEvent, (InputMode) -> Bool)] = [
            (.switchLanguage, { $0.language == .directEnglish }),
            (.switchScript, { $0.script == .traditional }),
            (.switchWidth, { $0.width == .full })
        ]

        for (event, modeChanged) in cases {
            let engine = InputEngine(query: query)
            _ = engine.process(.letter("w"))
            let result = engine.process(event)

            XCTAssertEqual(result.state, .idle)
            XCTAssertEqual(result.clientActions.actions, [.clearMarkedText])
            XCTAssertEqual(result.candidateAction, .hide)
            XCTAssertFalse(result.clientActions.actions.contains(.commitText("w")))
            XCTAssertNil(result.learningDelta)
            XCTAssertTrue(result.consumed)
            XCTAssertTrue(modeChanged(engine.mode))
        }
    }

    func testInitialModeIsSeparateFromRuntimePolicyApplication() throws {
        let engine = InputEngine(query: query)
        var first = InputSettings.default
        first.defaultMode = InputMode(language: .directEnglish, punctuation: .english,
                                      width: .full, script: .traditional)
        engine.applyRuntimePolicy(settings: first, generation: 1)
        XCTAssertEqual(engine.mode, .default)

        engine.initializeMode(from: first.defaultMode)
        XCTAssertEqual(engine.mode, first.defaultMode)
        _ = engine.process(.switchLanguage)
        XCTAssertEqual(engine.mode.language, .chinese)

        var changed = first
        changed.defaultMode = InputMode(language: .directEnglish, punctuation: .english,
                                        width: .half, script: .simplified)
        changed.candidatePageSize = 9
        engine.applyRuntimePolicy(settings: changed, generation: 2)
        XCTAssertEqual(engine.mode.language, .chinese)
        XCTAssertEqual(engine.mode.width, .full)
        XCTAssertEqual(engine.rankingPolicy.settingsGeneration, 2)

        engine.initializeMode(from: changed.defaultMode)
        XCTAssertEqual(engine.mode, changed.defaultMode)
    }

    func testOrderedClientActionBatchPreservesOrderAndDropsNoOp() {
        let batch = ClientTextActionBatch([
            .commitText("旧候选"),
            .none,
            .setMarkedText("a")
        ])

        XCTAssertEqual(batch.actions, [.commitText("旧候选"), .setMarkedText("a")])
        XCTAssertEqual(ClientTextActionBatch.none.actions, [])
        XCTAssertEqual(ClientTextActionBatch.single(.clearMarkedText).actions,
                       [.clearMarkedText])
    }

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

    func testEmptyResultNeverCommitsAndBoundaryPagingPassesThrough() throws {
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
        XCTAssertFalse(previous.consumed)
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

    func testFourCodeAutoCommitRequiresExactlyOneCurrentCompleteResult() throws {
        let cases: [(name: String, items: Int, totalCount: Int, expectedCommit: String?)] = [
            ("zero", 0, 0, nil),
            ("unique", 1, 1, "候选1"),
            ("multiple", 2, 2, nil),
            ("stale partial page", 1, 2, nil)
        ]

        for testCase in cases {
            let engine = InputEngine { code, pageIndex in
                let candidates = try (0..<testCase.items).map { offset in
                    let ordinal = offset + 1
                    return try Candidate(text: "候选\(ordinal)", code: code, source: .base,
                                         baseRank: ordinal - 1, learnedScore: 0,
                                         ordinal: ordinal)
                }
                return try CandidatePage(items: candidates, pageIndex: pageIndex,
                                         pageSize: 5, totalCount: testCase.totalCount)
            }
            var settings = InputSettings.default
            settings.autoCommitAtFour = true
            settings.automaticFrequency = true
            engine.apply(settings: settings)

            for letter in ["w", "q", "v"] { _ = engine.process(.letter(letter)) }
            let result = engine.process(.letter("b"))

            if let expectedCommit = testCase.expectedCommit {
                XCTAssertEqual(result.clientAction, .commitText(expectedCommit), testCase.name)
                XCTAssertEqual(result.candidateAction, .hide, testCase.name)
                XCTAssertEqual(result.state, .idle, testCase.name)
                XCTAssertEqual(result.learningDelta?.code, InputCode("wqvb"), testCase.name)
            } else {
                XCTAssertEqual(result.clientAction, .setMarkedText("wqvb"), testCase.name)
                XCTAssertEqual(result.state.composition?.code, InputCode("wqvb"), testCase.name)
                XCTAssertNil(result.learningDelta, testCase.name)
            }
        }
    }

    func testFifthCodeCommitsOldFirstCandidateThenStartsNewCompositionAtomically() throws {
        let engine = InputEngine { code, pageIndex in
            let texts = code.letters == "wqvb" ? ["旧首选", "旧次选"] : ["新候选"]
            let candidates = try texts.enumerated().map { offset, text in
                try Candidate(text: text, code: code, source: .base, baseRank: offset,
                              learnedScore: 0, ordinal: offset + 1)
            }
            return try CandidatePage(items: candidates, pageIndex: pageIndex,
                                     pageSize: 5, totalCount: candidates.count)
        }
        var settings = InputSettings.default
        settings.autoCommitAtFour = false
        settings.autoCommitFirstAtFive = true
        settings.automaticFrequency = true
        engine.apply(settings: settings)

        for letter in ["w", "q", "v", "b"] { _ = engine.process(.letter(letter)) }
        let result = engine.process(.letter("a"))

        XCTAssertEqual(result.clientActions.actions,
                       [.commitText("旧首选"), .setMarkedText("a")])
        XCTAssertEqual(result.state.composition?.code, InputCode("a"))
        XCTAssertEqual(result.candidateAction.page?.items.map(\.text), ["新候选"])
        XCTAssertEqual(result.learningDelta?.candidateText, "旧首选")
        XCTAssertEqual(result.clientActions.actions.filter {
            if case .commitText = $0 { return true }
            return false
        }.count, 1)
    }

    func testFifthCodeWithoutOldCandidateStartsNewCompositionWithoutEmptyCommit() throws {
        let engine = InputEngine { code, pageIndex in
            let candidates: [Candidate]
            if code.letters == "wqvb" {
                candidates = []
            } else {
                candidates = [try Candidate(text: "新候选", code: code, source: .base,
                                            baseRank: 0, learnedScore: 0, ordinal: 1)]
            }
            return try CandidatePage(items: candidates, pageIndex: pageIndex,
                                     pageSize: 5, totalCount: candidates.count)
        }
        var settings = InputSettings.default
        settings.autoCommitAtFour = false
        settings.autoCommitFirstAtFive = true
        engine.apply(settings: settings)

        for letter in ["w", "q", "v", "b"] { _ = engine.process(.letter(letter)) }
        let result = engine.process(.letter("a"))

        XCTAssertEqual(result.clientActions.actions, [.setMarkedText("a")])
        XCTAssertEqual(result.state.composition?.code, InputCode("a"))
        XCTAssertNil(result.learningDelta)
    }

    func testFifthCodeDoesNotCommitAChangedFirstCandidateSnapshot() throws {
        var fourCodeQueries = 0
        let engine = InputEngine { code, pageIndex in
            let text: String
            if code.letters == "wqvb" {
                fourCodeQueries += 1
                text = fourCodeQueries == 1 ? "已显示首选" : "已变化首选"
            } else {
                text = "新候选"
            }
            let candidate = try Candidate(text: text, code: code, source: .base,
                                          baseRank: 0, learnedScore: 0, ordinal: 1)
            return try CandidatePage(items: [candidate], pageIndex: pageIndex,
                                     pageSize: 5, totalCount: 1)
        }
        var settings = InputSettings.default
        settings.autoCommitAtFour = false
        settings.autoCommitFirstAtFive = true
        engine.apply(settings: settings)

        for letter in ["w", "q", "v", "b"] { _ = engine.process(.letter(letter)) }
        let result = engine.process(.letter("a"))

        XCTAssertEqual(result.clientActions.actions, [.setMarkedText("a")])
        XCTAssertFalse(result.clientActions.actions.contains(.commitText("已显示首选")))
        XCTAssertFalse(result.clientActions.actions.contains(.commitText("已变化首选")))
        XCTAssertEqual(result.state.composition?.code, InputCode("a"))
    }

    func testFourAndFiveCodeAutoCommitSwitchesDoNotDuplicateOrLoseNextKey() throws {
        let engine = InputEngine { code, pageIndex in
            let candidate = try Candidate(text: "候选-\(code.letters)", code: code,
                                          source: .base, baseRank: 0,
                                          learnedScore: 0, ordinal: 1)
            return try CandidatePage(items: [candidate], pageIndex: pageIndex,
                                     pageSize: 5, totalCount: 1)
        }
        var settings = InputSettings.default
        settings.autoCommitAtFour = true
        settings.autoCommitFirstAtFive = true
        engine.apply(settings: settings)

        for letter in ["w", "q", "v"] { _ = engine.process(.letter(letter)) }
        let fourth = engine.process(.letter("b"))
        let fifth = engine.process(.letter("a"))

        XCTAssertEqual(fourth.clientActions.actions, [.commitText("候选-wqvb")])
        XCTAssertEqual(fifth.clientActions.actions, [.setMarkedText("a")])
        XCTAssertEqual(fifth.state.composition?.code, InputCode("a"))
        XCTAssertFalse(fifth.clientActions.actions.contains(.commitText("候选-wqvb")))
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
