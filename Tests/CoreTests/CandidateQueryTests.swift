import Foundation
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

    func testPinyinIndexAnswersOneThroughThirtyTwoBytePrefixesAndExactKeys() throws {
        let index = try pinyinIndex()
        let maximum = String(repeating: "a", count: 32)

        for raw in ["n", "ni", "nih", "niha", "nihao", "nim", "nimen", maximum] {
            XCTAssertTrue(index.prefixExists(try XCTUnwrap(CompositionKeySequence(raw))), raw)
        }
        for raw in ["b", "niz", "zhonga"] {
            XCTAssertFalse(index.prefixExists(try XCTUnwrap(CompositionKeySequence(raw))), raw)
        }
        XCTAssertNil(CompositionKeySequence(maximum + "a"))

        XCTAssertEqual(
            try index.page(for: XCTUnwrap(CompositionKeySequence("nihao")),
                           pageIndex: 0, pageSize: 5).items.map(\.text),
            ["你好"]
        )
        XCTAssertTrue(
            try index.page(for: XCTUnwrap(CompositionKeySequence("nih")),
                           pageIndex: 0, pageSize: 5).items.isEmpty
        )
    }

    func testPinyinExactLookupDecodesRequestedPageAndResolvesWB86References() throws {
        let index = try pinyinIndex()
        let code = try XCTUnwrap(CompositionKeySequence("ni"))

        let first = try index.page(for: code, pageIndex: 0, pageSize: 5)
        let second = try index.page(for: code, pageIndex: 1, pageSize: 5)
        let third = try index.page(for: code, pageIndex: 2, pageSize: 5)

        XCTAssertEqual(first.items.map(\.text), ["工", "词01", "词02", "词03", "词04"])
        XCTAssertEqual(first.items.first?.wubiHint?.letters, "a")
        XCTAssertEqual(first.items.map(\.baseRank), [0, 1, 2, 3, 4])
        XCTAssertEqual(second.items.count, 5)
        XCTAssertEqual(third.items.map(\.text), ["词10", "词11"])
        XCTAssertEqual(first.totalCount, 12)
        XCTAssertTrue(first.hasNext)
        XCTAssertTrue(third.hasPrevious)
        XCTAssertFalse(third.hasNext)
    }

    func testPinyinLookupKeepsTheValidatedSixtyFourCandidateBound() throws {
        let index = try pinyinIndex()
        let code = try XCTUnwrap(CompositionKeySequence("shi"))
        let last = try index.page(for: code, pageIndex: 7, pageSize: 9)

        XCTAssertEqual(last.totalCount, 64)
        XCTAssertEqual(last.items.count, 1)
        XCTAssertEqual(last.items.first?.baseRank, 63)
        XCTAssertFalse(last.hasNext)
        XCTAssertThrowsError(try index.page(for: code, pageIndex: 8, pageSize: 9)) {
            XCTAssertEqual($0 as? PinyinDictionaryQueryError, .pageOutOfRange)
        }
    }

    func testMixedRankingKeepsUserAndBaseWubiAheadAndLearningInsideEachTier() throws {
        let code = try XCTUnwrap(InputCode("a"))
        let sequence = try XCTUnwrap(CompositionKeySequence("a"))
        let pinyinKey = try XCTUnwrap(CandidateQueryKey(kind: .pinyin, code: "a"))
        let base = try [
            DictionaryEntryRecord(code: code, rank: 0, text: "甲"),
            DictionaryEntryRecord(code: code, rank: 1, text: "乙")
        ]
        let user = [UserCandidateRanking(code: code, text: "用户词", fixedRank: 0)]
        let pinyin = [
            PinyinLookupCandidate(text: "拼一", weight: 20, baseRank: 0, wubiHint: nil),
            PinyinLookupCandidate(text: "拼二", weight: 10, baseRank: 1, wubiHint: nil)
        ]
        let learning = [
            LearnedCandidateRanking(queryKey: .wubi(code), candidateText: "乙", score: 5),
            LearnedCandidateRanking(queryKey: pinyinKey, candidateText: "拼二", score: 100),
            LearnedCandidateRanking(
                queryKey: try XCTUnwrap(CandidateQueryKey(kind: .pinyin, code: "b")),
                candidateText: "拼一", score: 1_000
            )
        ]

        let page = try CandidateRanker(pageSize: 9).mixedPage(
            for: sequence,
            wubiRecords: base,
            userEntries: user,
            pinyinCandidates: pinyin,
            learningRecords: learning,
            learningEnabled: true,
            scriptConverter: nil,
            outputScript: .simplified,
            pageIndex: 0
        )

        XCTAssertEqual(page.items.map(\.text), ["用户词", "乙", "甲", "拼二", "拼一"])
        XCTAssertEqual(page.items.map(\.source),
                       [.userWubi, .baseWubi, .baseWubi, .localPinyin, .localPinyin])
        XCTAssertEqual(page.items.map(\.learnedScore), [0, 5, 0, 100, 0])
        XCTAssertEqual(page.items.map(\.queryKey.kind), [.wubi, .wubi, .wubi, .pinyin, .pinyin])
    }

    func testMixedRankingConvertsBeforeStableDedupeAndRetainsFirstIdentity() throws {
        let code = try XCTUnwrap(InputCode("a"))
        let sequence = try XCTUnwrap(CompositionKeySequence("a"))
        let converter = try bundledScriptConverter()
        let page = try CandidateRanker(pageSize: 5).mixedPage(
            for: sequence,
            wubiRecords: [
                try DictionaryEntryRecord(code: code, rank: 0, text: "后台"),
                try DictionaryEntryRecord(code: code, rank: 1, text: "中国")
            ],
            userEntries: [],
            pinyinCandidates: [
                PinyinLookupCandidate(text: "後臺", weight: 100, baseRank: 0, wubiHint: nil),
                PinyinLookupCandidate(text: "输入法", weight: 90, baseRank: 1,
                                      wubiHint: InputCode("lwy"))
            ],
            learningRecords: [],
            learningEnabled: false,
            scriptConverter: converter,
            outputScript: .traditional,
            pageIndex: 0
        )

        XCTAssertEqual(page.items.map(\.text), ["後臺", "中國", "輸入法"])
        XCTAssertEqual(page.totalCount, 3)
        XCTAssertEqual(page.items.first?.source, .baseWubi)
        XCTAssertEqual(page.items.first?.queryKey, .wubi(code))
        XCTAssertEqual(page.items.last?.wubiHint?.letters, "lwy")
    }

    func testMixedRankingCapsEachSourceTierBeforeMerging() throws {
        let sequence = try XCTUnwrap(CompositionKeySequence("shang"))
        let candidates = (0..<70).map {
            PinyinLookupCandidate(text: "词\($0)", weight: UInt64(70 - $0),
                                  baseRank: $0, wubiHint: nil)
        }
        let ranker = CandidateRanker(pageSize: 9)

        let first = try ranker.mixedPage(
            for: sequence,
            wubiRecords: [], userEntries: [], pinyinCandidates: candidates,
            learningRecords: [], learningEnabled: true, scriptConverter: nil,
            outputScript: .simplified, pageIndex: 0
        )
        let last = try ranker.mixedPage(
            for: sequence,
            wubiRecords: [], userEntries: [], pinyinCandidates: candidates,
            learningRecords: [], learningEnabled: true, scriptConverter: nil,
            outputScript: .simplified, pageIndex: 7
        )

        XCTAssertEqual(first.totalCount, CandidateRanker.maximumCandidatesPerTier)
        XCTAssertEqual(last.items.count, 1)
        XCTAssertEqual(last.items.first?.text, "词63")
    }

    private func pinyinIndex() throws -> PinyinDictionaryIndex {
        let wb86Data = try DictionaryFormatV1.encode(records: [
            DictionaryEntryRecord(code: XCTUnwrap(InputCode("a")), rank: 0, text: "工")
        ], buildIdentifier: 91)
        let niCandidates = (0..<12).map { index in
            if index == 0 {
                return PinyinDictionaryCandidate(
                    text: "工", weight: 100, wubiRecordIndex: 0,
                    wubiHint: InputCode("a")
                )
            }
            return PinyinDictionaryCandidate(
                text: String(format: "词%02d", index),
                weight: UInt64(100 - index)
            )
        }
        let sixtyFour = (0..<64).map {
            PinyinDictionaryCandidate(text: "候选\($0)", weight: UInt64(64 - $0))
        }
        let pinyinData = try PinyinDictionaryFormatV1.encode(
            entries: [
                PinyinDictionaryEntry(
                    key: String(repeating: "a", count: 32),
                    candidates: [PinyinDictionaryCandidate(text: "长键", weight: 1)]
                ),
                PinyinDictionaryEntry(key: "ni", candidates: niCandidates),
                PinyinDictionaryEntry(
                    key: "nihao",
                    candidates: [PinyinDictionaryCandidate(text: "你好", weight: 1)]
                ),
                PinyinDictionaryEntry(
                    key: "nimen",
                    candidates: [PinyinDictionaryCandidate(text: "你们", weight: 1)]
                ),
                PinyinDictionaryEntry(key: "shi", candidates: sixtyFour),
                PinyinDictionaryEntry(
                    key: "zhong",
                    candidates: [PinyinDictionaryCandidate(text: "中", weight: 1)]
                )
            ],
            wb86BuildIdentifier: 91,
            sourceIdentifier: 1
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let wb86URL = directory.appendingPathComponent("wb86.bin")
        let pinyinURL = directory.appendingPathComponent("pinyin.bin")
        try wb86Data.write(to: wb86URL)
        try pinyinData.write(to: pinyinURL)
        let wb86 = try DictionaryLoader.load(from: wb86URL)
        return PinyinDictionaryIndex(
            image: try PinyinDictionaryLoader.load(from: pinyinURL, wb86Image: wb86)
        )
    }

    private func bundledScriptConverter() throws -> ScriptConverter {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "script-conversion", withExtension: "bin")
                ?? Bundle(for: Self.self).url(forResource: "script-conversion",
                                              withExtension: "bin")
        )
        return try ScriptConverter(data: Data(contentsOf: url))
    }
}
