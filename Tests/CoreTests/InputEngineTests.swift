import XCTest
@testable import MacWubi

final class InputEngineTests: XCTestCase {
    func testLanguageSwitchCommitsRawCodeWhileOtherModeShortcutsCancel() throws {
        let cases: [(InputEvent, (InputMode) -> Bool)] = [
            (.switchScript, { $0.script == .traditional }),
            (.switchWidth, { $0.width == .full })
        ]

        let languageEngine = InputEngine(query: query)
        _ = languageEngine.process(.letter("w"))
        _ = languageEngine.process(.letter("q"))
        let languageResult = languageEngine.process(.switchLanguage)

        XCTAssertEqual(languageResult.state, .idle)
        XCTAssertEqual(languageResult.clientActions.actions, [.commitText("wq")])
        XCTAssertEqual(languageResult.candidateAction, .hide)
        XCTAssertNil(languageResult.learningDelta)
        XCTAssertTrue(languageResult.consumed)
        XCTAssertEqual(languageEngine.mode.language, .directEnglish)

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

        let first = engine.process(.letter("w"))
        XCTAssertEqual(first.clientAction, .setMarkedText("w"))
        XCTAssertEqual(first.candidateAction.page?.pageIndex, 0)
        XCTAssertTrue(first.consumed)

        let second = engine.process(.letter("q"))
        XCTAssertEqual(second.state.composition?.code, InputCode("wq"))
        XCTAssertEqual(second.clientAction, .setMarkedText("wq"))
        XCTAssertEqual(second.candidateAction.page?.items.map(\.text), ["候选1", "候选2"])
    }

    func testUppercaseInitialShowsOneDirectInputCandidateAndCommitsOnSpace() {
        let engine = InputEngine(query: query)

        let first = engine.process(.letter("W"))
        XCTAssertTrue(first.consumed)
        XCTAssertEqual(first.clientAction, .setMarkedText("W"))
        XCTAssertEqual(first.candidateAction.page?.items.map(\.text), ["W"])
        XCTAssertEqual(first.state.directInput?.text, "W")
        XCTAssertEqual(engine.mode.language, .chinese)

        XCTAssertEqual(engine.process(.letter("q")).clientAction, .setMarkedText("Wq"))
        XCTAssertEqual(engine.process(.letter("V")).clientAction, .setMarkedText("WqV"))
        let punctuation = engine.process(.text("_"))
        XCTAssertEqual(punctuation.clientAction, .setMarkedText("WqV_"))
        XCTAssertEqual(punctuation.candidateAction.page?.items.map(\.text), ["WqV_"])

        let committed = engine.process(.text(" "))
        XCTAssertEqual(committed.clientAction, .commitText("WqV_"))
        XCTAssertEqual(committed.candidateAction, .hide)
        XCTAssertEqual(committed.state, .idle)
        XCTAssertEqual(engine.mode.language, .chinese)

        let nextChineseInput = engine.process(.letter("w"))
        XCTAssertTrue(nextChineseInput.consumed)
        XCTAssertEqual(nextChineseInput.clientAction, .setMarkedText("w"))
    }

    func testDirectInputSupportsBackspaceCancelReturnAndModeSwitchWithoutLearning() {
        let engine = InputEngine(query: query)
        _ = engine.process(.letter("M"))
        _ = engine.process(.letter("a"))

        let corrected = engine.process(.backspace)
        XCTAssertEqual(corrected.clientAction, .setMarkedText("M"))
        XCTAssertEqual(corrected.candidateAction.page?.items.map(\.text), ["M"])

        let returned = engine.process(.select(1))
        XCTAssertEqual(returned.clientAction, .commitText("M"))
        XCTAssertTrue(returned.consumed)
        XCTAssertNil(returned.learningDelta)
        XCTAssertEqual(returned.state, .idle)

        _ = engine.process(.letter("G"))
        let switched = engine.process(.switchLanguage)
        XCTAssertEqual(switched.clientAction, .commitText("G"))
        XCTAssertEqual(engine.mode.language, .directEnglish)
        XCTAssertNil(switched.learningDelta)

        _ = engine.process(.switchLanguage)
        _ = engine.process(.letter("C"))
        let cancelled = engine.process(.cancel)
        XCTAssertEqual(cancelled.clientAction, .clearMarkedText)
        XCTAssertEqual(cancelled.candidateAction, .hide)
        XCTAssertEqual(cancelled.state, .idle)
    }

    func testUppercaseAfterCompositionContinuesNormalizedWubiCode() throws {
        let engine = InputEngine(query: query)
        _ = engine.process(.letter("w"))

        let result = engine.process(.letter("Q"))

        XCTAssertTrue(result.consumed)
        XCTAssertEqual(result.clientAction, .setMarkedText("wq"))
        XCTAssertEqual(result.state.composition?.code, InputCode("wq"))
        XCTAssertEqual(engine.mode.language, .chinese)
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

    func testViableShangPinyinPrefixDoesNotTriggerFifthCodeTruncation() throws {
        let engine = InputEngine(sequencePolicyQuery: { sequence, pageIndex, policy, _, mixed in
            let pinyinState: PinyinQueryState
            if mixed, "shang".hasPrefix(sequence.letters) {
                pinyinState = sequence.letters == "shang" ? .exactMatch : .viablePrefix
            } else {
                pinyinState = .noMatch
            }
            let items: [Candidate]
            if sequence.letters == "shang" {
                let key = try XCTUnwrap(
                    CandidateQueryKey(kind: .pinyin, code: sequence.letters)
                )
                items = [try Candidate(text: "上", queryKey: key, source: .localPinyin,
                                       baseRank: 0, learnedScore: 0, ordinal: 1)]
            } else if let code = sequence.wubiCode {
                items = [try Candidate(text: "四码首选", code: code, source: .baseWubi,
                                       baseRank: 0, learnedScore: 0, ordinal: 1)]
            } else {
                items = []
            }
            return SequenceQueryResult(
                pinyinState: pinyinState,
                page: try CandidatePage(items: items, pageIndex: pageIndex,
                                        pageSize: policy.pageSize, totalCount: items.count)
            )
        })
        var settings = InputSettings.default
        settings.mixedPinyinEnabled = true
        settings.autoCommitFirstAtFive = true
        settings.autoCommitAtFour = false
        engine.apply(settings: settings)

        for letter in ["s", "h", "a", "n"] { _ = engine.process(.letter(letter)) }
        let fifth = engine.process(.letter("g"))

        XCTAssertEqual(fifth.clientActions.actions, [.setMarkedText("shang")])
        XCTAssertFalse(fifth.clientActions.actions.contains(.commitText("四码首选")))
        XCTAssertEqual(fifth.state.composition?.sequence.letters, "shang")
        XCTAssertEqual(fifth.state.composition?.route, .pinyinOnly)
        XCTAssertEqual(fifth.candidateAction.page?.items.map(\.text), ["上"])
    }

    func testMixedPinyinDisabledKeepsLegacyFifthCodeBehavior() throws {
        var observedMixedFlags = [Bool]()
        let engine = InputEngine(sequencePolicyQuery: { sequence, pageIndex, policy, _, mixed in
            observedMixedFlags.append(mixed)
            let code = try XCTUnwrap(sequence.wubiCode)
            let text = sequence.letters == "wqvb" ? "旧首选" : "新候选"
            let candidate = try Candidate(text: text, code: code, source: .baseWubi,
                                          baseRank: 0, learnedScore: 0, ordinal: 1)
            return SequenceQueryResult(
                pinyinState: .unavailable,
                page: try CandidatePage(items: [candidate], pageIndex: pageIndex,
                                        pageSize: policy.pageSize, totalCount: 1)
            )
        })
        var settings = InputSettings.default
        settings.mixedPinyinEnabled = false
        settings.autoCommitFirstAtFive = true
        settings.autoCommitAtFour = false
        engine.apply(settings: settings)

        for letter in ["w", "q", "v", "b"] { _ = engine.process(.letter(letter)) }
        let fifth = engine.process(.letter("a"))

        XCTAssertEqual(fifth.clientActions.actions,
                       [.commitText("旧首选"), .setMarkedText("a")])
        XCTAssertEqual(fifth.state.composition?.route, .wubiOnly)
        XCTAssertTrue(observedMixedFlags.allSatisfy { !$0 })
    }

    func testPinyinQueryFailureDuringLongSequenceResetsWithoutCommittingRawOrOldText() throws {
        let engine = InputEngine(sequencePolicyQuery: { sequence, pageIndex, policy, _, _ in
            if sequence.length == 5 { throw TestError.failed }
            let code = try XCTUnwrap(sequence.wubiCode)
            let candidate = try Candidate(text: "旧首选", code: code, source: .baseWubi,
                                          baseRank: 0, learnedScore: 0, ordinal: 1)
            return SequenceQueryResult(
                pinyinState: .viablePrefix,
                page: try CandidatePage(items: [candidate], pageIndex: pageIndex,
                                        pageSize: policy.pageSize, totalCount: 1)
            )
        })
        var settings = InputSettings.default
        settings.mixedPinyinEnabled = true
        settings.autoCommitFirstAtFive = true
        settings.autoCommitAtFour = false
        engine.apply(settings: settings)

        for letter in ["s", "h", "a", "n"] { _ = engine.process(.letter(letter)) }
        let result = engine.process(.letter("g"))

        XCTAssertEqual(result.state, .idle)
        XCTAssertEqual(result.clientActions.actions, [.clearMarkedText])
        XCTAssertEqual(result.candidateAction, .hide)
        XCTAssertFalse(result.clientActions.actions.contains(.commitText("旧首选")))
        XCTAssertFalse(result.clientActions.actions.contains(.commitText("shang")))
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
