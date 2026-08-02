import XCTest
@testable import MacWubi

final class CandidateQueryTests: XCTestCase {
    func testRankingPolicyFreezesGenerationPagingAndLearning() throws {
        let code = try XCTUnwrap(InputCode("a"))
        let records = try (0..<7).map {
            try DictionaryEntryRecord(code: code, rank: UInt32($0), text: "词\($0)")
        }
        let learning = LearnedCandidateRanking(code: code, candidateText: "词6", score: 10)
        let frozen = CandidateRankingPolicy(settingsGeneration: 4, pageSize: 5,
                                            automaticFrequency: true)
        let changed = CandidateRankingPolicy(settingsGeneration: 5, pageSize: 9,
                                             automaticFrequency: false)

        let first = try CandidateRanker(policy: frozen).page(
            for: code, records: records, userEntries: [], learningRecords: [learning],
            pageIndex: 0
        )
        let second = try CandidateRanker(policy: frozen).page(
            for: code, records: records, userEntries: [], learningRecords: [learning],
            pageIndex: 1
        )
        XCTAssertEqual(first.pageSize, 5)
        XCTAssertEqual(first.items.first?.text, "词6")
        XCTAssertEqual(second.items.count, 2)

        let changedPage = try CandidateRanker(policy: changed).page(
            for: code, records: records, userEntries: [], learningRecords: [learning],
            pageIndex: 0
        )
        XCTAssertEqual(changedPage.pageSize, 9)
        XCTAssertEqual(changedPage.items.first?.text, "词0")
    }

    func testBaseCandidatesOrderByRankThenUTF8Bytes() throws {
        let code = try XCTUnwrap(InputCode("wqvb"))
        let records = try [
            DictionaryEntryRecord(code: code, rank: 1, text: "您好"),
            DictionaryEntryRecord(code: code, rank: 0, text: "𠛈"),
            DictionaryEntryRecord(code: code, rank: 0, text: "你好")
        ]

        let page = try CandidateRanker(pageSize: 5).page(
            for: code, records: records, pageIndex: 0
        )

        XCTAssertEqual(page.items.map(\.text), ["你好", "𠛈", "您好"])
        XCTAssertEqual(page.items.map(\.ordinal), [1, 2, 3])
    }

    func testPagingSlicesAndRenumbersEachPage() throws {
        let code = try XCTUnwrap(InputCode("a"))
        let records = try (0..<7).map {
            try DictionaryEntryRecord(code: code, rank: UInt32($0), text: "词\($0)")
        }
        let ranker = CandidateRanker(pageSize: 5)

        let first = try ranker.page(for: code, records: records, pageIndex: 0)
        let second = try ranker.page(for: code, records: records, pageIndex: 1)

        XCTAssertEqual(first.items.count, 5)
        XCTAssertTrue(first.hasNext)
        XCTAssertEqual(second.items.map(\.text), ["词5", "词6"])
        XCTAssertEqual(second.items.map(\.ordinal), [1, 2])
        XCTAssertTrue(second.hasPrevious)
        XCTAssertFalse(second.hasNext)
    }

    func testEmptyAndOutOfRangePagesAreSafeAndDeterministic() throws {
        let code = try XCTUnwrap(InputCode("a"))
        let ranker = CandidateRanker(pageSize: 5)

        let empty = try ranker.page(for: code, records: [], pageIndex: 0)
        XCTAssertTrue(empty.items.isEmpty)
        XCTAssertEqual(empty.totalCount, 0)
        XCTAssertThrowsError(try ranker.page(for: code, records: [], pageIndex: 1)) {
            XCTAssertEqual($0 as? CandidateQueryError, .pageOutOfRange)
        }
    }

    func testMismatchedRecordsAreRejectedInsteadOfLeakingCandidates() throws {
        let code = try XCTUnwrap(InputCode("a"))
        let other = try XCTUnwrap(InputCode("b"))
        let records = [try DictionaryEntryRecord(code: other, rank: 0, text: "了")]

        XCTAssertThrowsError(try CandidateRanker(pageSize: 5).page(
            for: code, records: records, pageIndex: 0
        )) {
            XCTAssertEqual($0 as? CandidateQueryError, .mismatchedCode)
        }
    }

    func testUserFixedRankThenLearningThenBaseRankMergeDeterministically() throws {
        let code = try XCTUnwrap(InputCode("a"))
        let base = try [
            DictionaryEntryRecord(code: code, rank: 0, text: "甲"),
            DictionaryEntryRecord(code: code, rank: 1, text: "乙")
        ]
        let user = UserCandidateRanking(code: code, text: "用户词", fixedRank: 0)
        let learning = LearnedCandidateRanking(code: code, candidateText: "乙", score: 3)
        let ranker = CandidateRanker(pageSize: 5)

        let learned = try ranker.page(for: code, records: base, userEntries: [user],
                                      learningRecords: [learning], learningEnabled: true,
                                      pageIndex: 0)
        XCTAssertEqual(learned.items.map(\.text), ["用户词", "乙", "甲"])
        XCTAssertEqual(learned.items.map(\.source), [.user, .base, .base])

        let disabled = try ranker.page(for: code, records: base, userEntries: [user],
                                       learningRecords: [learning], learningEnabled: false,
                                       pageIndex: 0)
        XCTAssertEqual(disabled.items.map(\.text), ["用户词", "甲", "乙"])
    }

    func testLearningRequiresExactTypedQueryKeyAndCannotCrossSourceTier() throws {
        let code = try XCTUnwrap(InputCode("a"))
        let otherCode = try XCTUnwrap(InputCode("b"))
        let records = try [
            DictionaryEntryRecord(code: code, rank: 0, text: "甲"),
            DictionaryEntryRecord(code: code, rank: 1, text: "乙")
        ]
        let learning = [
            LearnedCandidateRanking(queryKey: .wubi(code), candidateText: "乙", score: 5),
            LearnedCandidateRanking(
                queryKey: try XCTUnwrap(CandidateQueryKey(kind: .pinyin, code: "a")),
                candidateText: "甲", score: 99
            ),
            LearnedCandidateRanking(queryKey: .wubi(otherCode),
                                    candidateText: "甲", score: 99)
        ]
        let page = try CandidateRanker(pageSize: 5).page(
            for: code, records: records, userEntries: [], learningRecords: learning,
            learningEnabled: true, pageIndex: 0
        )
        XCTAssertEqual(page.items.map(\.text), ["乙", "甲"])
        XCTAssertEqual(page.items.map(\.learnedScore), [5, 0])

        let wubi = try Candidate(text: "五笔", code: code, source: .base,
                                 baseRank: 1, learnedScore: 0, ordinal: 1)
        let pinyinKey = try XCTUnwrap(CandidateQueryKey(kind: .pinyin, code: "a"))
        let pinyin = try Candidate(text: "拼音", queryKey: pinyinKey,
                                   source: .localPinyin, baseRank: 0,
                                   learnedScore: 100, ordinal: 2)
        XCTAssertEqual(CandidateRanker.rank(candidates: [pinyin, wubi],
                                            learningEnabled: true).map(\.text),
                       ["五笔", "拼音"])
    }
}
