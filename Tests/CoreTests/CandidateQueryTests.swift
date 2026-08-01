import XCTest
@testable import MacWubi

final class CandidateQueryTests: XCTestCase {
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
}
