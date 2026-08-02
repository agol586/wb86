import XCTest
@testable import MacWubi

final class CoreModelTests: XCTestCase {
    func testInputCodeNormalizesASCIIAndPacksDeterministically() throws {
        let upper = try XCTUnwrap(InputCode("WbIx"))
        let lower = try XCTUnwrap(InputCode("wbix"))

        XCTAssertEqual(upper.letters, "wbix")
        XCTAssertEqual(upper, lower)
        XCTAssertEqual(upper.packedValue, lower.packedValue)
        XCTAssertEqual(Set([InputCode("a")!.packedValue,
                            InputCode("aa")!.packedValue,
                            InputCode("b")!.packedValue]).count, 3)
    }

    func testInputCodeRejectsInvalidOrPartialValues() {
        for invalid in ["", "abcde", "z", "a1", "é", "中", "a z"] {
            XCTAssertNil(InputCode(invalid), "unexpectedly accepted \(invalid.debugDescription)")
        }
    }

    func testGeneralCompositionSequenceRoutesAndCandidateIdentity() throws {
        XCTAssertNil(CompositionKeySequence(""))
        XCTAssertNil(CompositionKeySequence(String(repeating: "a", count: 33)))
        XCTAssertNil(CompositionKeySequence("ni-hao"))

        let pinyin = try XCTUnwrap(CompositionKeySequence("Shang"))
        XCTAssertEqual(pinyin.letters, "shang")
        XCTAssertNil(pinyin.wubiCode)
        XCTAssertEqual(CompositionRoute.resolve(sequence: pinyin, mixedPinyinEnabled: true),
                       .pinyinOnly)

        let shared = try XCTUnwrap(CompositionKeySequence("wq"))
        XCTAssertEqual(shared.wubiCode, InputCode("wq"))
        XCTAssertEqual(CompositionRoute.resolve(sequence: shared, mixedPinyinEnabled: true),
                       .mixed)
        XCTAssertEqual(CompositionRoute.resolve(sequence: shared, mixedPinyinEnabled: false),
                       .wubiOnly)

        let pinyinKey = try XCTUnwrap(CandidateQueryKey(kind: .pinyin, code: "nihao"))
        let identity = try CandidateIdentity(queryKey: pinyinKey, text: "你好")
        XCTAssertEqual(identity.queryKey.normalizedCode, "nihao")
        let candidate = try Candidate(text: "你好", queryKey: pinyinKey,
                                      source: .localPinyin, baseRank: 0,
                                      learnedScore: 0, ordinal: 1,
                                      wubiHint: InputCode("wqvb"))
        XCTAssertEqual(candidate.source, .localPinyin)
        XCTAssertEqual(candidate.wubiHint, InputCode("wqvb"))
        XCTAssertEqual(CandidateSource.base.rawValue, "baseWubi")
        XCTAssertThrowsError(try CandidateIdentity(queryKey: pinyinKey, text: ""))
    }

    func testInputEventVocabularyIsValueSemantic() {
        XCTAssertEqual(InputEvent.letter("A"), .letter("A"))
        XCTAssertNotEqual(InputEvent.select(1), .select(9))
        XCTAssertEqual(Set([InputEvent.cancel, .backspace, .pageNext]).count, 3)
    }

    func testInputModeDefaultsAndIndependentFields() {
        var mode = InputMode.default
        XCTAssertEqual(mode.language, .chinese)
        XCTAssertEqual(mode.punctuation, .chinese)
        XCTAssertEqual(mode.width, .half)
        XCTAssertEqual(mode.script, .simplified)

        mode.language = .directEnglish
        XCTAssertEqual(mode.language, .directEnglish)
        XCTAssertEqual(mode.punctuation, .chinese)
    }

    func testCandidateValidatesTextRankScoreAndOrdinal() throws {
        let code = try XCTUnwrap(InputCode("wq"))
        XCTAssertThrowsError(try Candidate(text: "", code: code, source: .base,
                                           baseRank: 0, learnedScore: 0, ordinal: 1))
        XCTAssertThrowsError(try Candidate(text: "我", code: code, source: .base,
                                           baseRank: -1, learnedScore: 0, ordinal: 1))
        XCTAssertThrowsError(try Candidate(text: "我", code: code, source: .base,
                                           baseRank: 0, learnedScore: 0, ordinal: 0))

        let candidate = try Candidate(text: "我", code: code, source: .base,
                                      baseRank: 0, learnedScore: 3, ordinal: 1)
        XCTAssertEqual(candidate.text, "我")
    }

    func testCandidatePageEnforcesBoundsAndNavigation() throws {
        let code = try XCTUnwrap(InputCode("wq"))
        let candidates = try (1...6).map {
            try Candidate(text: "候\($0)", code: code, source: .base,
                          baseRank: $0 - 1, learnedScore: 0, ordinal: $0)
        }
        XCTAssertThrowsError(try CandidatePage(items: candidates, pageIndex: 0,
                                               pageSize: 5, totalCount: 6))

        let page = try CandidatePage(items: Array(candidates.prefix(5)), pageIndex: 0,
                                     pageSize: 5, totalCount: 6)
        XCTAssertFalse(page.hasPrevious)
        XCTAssertTrue(page.hasNext)
    }

    func testCompositionStateRejectsMismatchedCodePageAndSelection() throws {
        let code = try XCTUnwrap(InputCode("wq"))
        let otherCode = try XCTUnwrap(InputCode("aa"))
        let candidate = try Candidate(text: "我", code: otherCode, source: .base,
                                      baseRank: 0, learnedScore: 0, ordinal: 1)
        let page = try CandidatePage(items: [candidate], pageIndex: 0,
                                     pageSize: 5, totalCount: 1)

        XCTAssertThrowsError(try CompositionState.composing(
            code: code, candidates: page, pageIndex: 0, selectionIndex: 0
        ))
        XCTAssertEqual(CompositionState.idle.kind, .idle)
    }

    func testDiagnosticsExposeOnlyFixedCategoryCounts() {
        let diagnostics = DiagnosticCounter()
        diagnostics.record(.invalidEvent)
        diagnostics.record(.invalidEvent)
        diagnostics.record(.dictionaryLoadFailure)

        XCTAssertEqual(diagnostics.count(for: .invalidEvent), 2)
        XCTAssertEqual(diagnostics.snapshot()[.dictionaryLoadFailure], 1)
        XCTAssertEqual(Set(diagnostics.snapshot().keys), [.invalidEvent, .dictionaryLoadFailure])
    }
}
