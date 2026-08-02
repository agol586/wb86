import Foundation
import XCTest
@testable import MacWubi

final class PersonalizationIntegrationTests: XCTestCase {
    func testQueryPagingRankingAndLearningUseOneExplicitFrozenPolicy() throws {
        let root = temporaryDirectory()
        let writer = try SnapshotWriter(rootURL: root)
        let users = try UserLexiconStore(writer: writer)
        let learning = try LearningStore(writer: writer)
        let code = try XCTUnwrap(InputCode("a"))
        for index in 0..<7 {
            _ = try users.upsert(code: code, text: "词\(index)", fixedRank: nil,
                                 createdBy: .manual)
        }
        try learning.recordSelection(code: code, candidateText: "词6", amount: 4)
        let coordinator = PersonalizationCoordinator(index: nil, userStore: users,
                                                     learningStore: learning)
        let frozen = CandidateRankingPolicy(settingsGeneration: 8, pageSize: 5,
                                            automaticFrequency: true)

        let first = try coordinator.page(for: code, pageIndex: 0, policy: frozen)
        let second = try coordinator.page(for: code, pageIndex: 1, policy: frozen)
        XCTAssertEqual(first.pageSize, 5)
        XCTAssertEqual(first.items.first?.text, "词6")
        XCTAssertEqual(second.pageSize, 5)

        let generation = learning.snapshot.generation
        coordinator.record(LearningDelta(code: code, candidateText: "词0", amount: 1),
                           policy: CandidateRankingPolicy(settingsGeneration: 9, pageSize: 9,
                                                          automaticFrequency: false))
        XCTAssertEqual(learning.snapshot.generation, generation)
        coordinator.record(LearningDelta(code: code, candidateText: "词0", amount: 1),
                           policy: frozen)
        XCTAssertEqual(learning.snapshot.generation, generation + 1)
    }

    func testRestartConcurrentGenerationAndDomainIsolation() throws {
        let root = temporaryDirectory()
        let writer = try SnapshotWriter(rootURL: root)
        let userStore = try UserLexiconStore(writer: writer)
        let learningStore = try LearningStore(writer: writer)
        let code = try XCTUnwrap(InputCode("a"))
        _ = try userStore.upsert(code: code, text: "用户词", fixedRank: 0, createdBy: .manual)
        try learningStore.recordSelection(code: code, candidateText: "乙", amount: 3)

        let capturedGeneration = userStore.snapshot
        _ = try userStore.upsert(code: code, text: "第二词", fixedRank: nil, createdBy: .manual)
        XCTAssertEqual(capturedGeneration.entries.map(\.text), ["用户词"])
        XCTAssertEqual(userStore.snapshot.entries.count, 2)

        let restartedUsers = try UserLexiconStore(writer: SnapshotWriter(rootURL: root))
        let restartedLearning = try LearningStore(writer: SnapshotWriter(rootURL: root))
        XCTAssertEqual(restartedUsers.snapshot.entries.count, 2)
        XCTAssertEqual(restartedLearning.score(code: code, candidateText: "乙"), 3)

        try Data("corrupt-learning".utf8).write(to: writer.currentURL(for: .learning))
        let isolatedUsers = try UserLexiconStore(writer: SnapshotWriter(rootURL: root))
        XCTAssertEqual(isolatedUsers.snapshot.entries.count, 2)
        XCTAssertNotNil(try SnapshotWriter(rootURL: root).load(.userLexicon))
    }

    func testLearningPromotionClearAndTenThousandPrivateSubmitsProduceNoWrites() throws {
        let root = temporaryDirectory()
        let writer = try SnapshotWriter(rootURL: root)
        let learningStore = try LearningStore(writer: writer)
        let code = try XCTUnwrap(InputCode("a"))
        let baseRecords = try [
            DictionaryEntryRecord(code: code, rank: 0, text: "甲"),
            DictionaryEntryRecord(code: code, rank: 1, text: "乙")
        ]
        let ranker = CandidateRanker(pageSize: 5)
        for _ in 0..<3 { try learningStore.recordSelection(code: code, candidateText: "乙") }
        var page = try ranker.page(for: code, records: baseRecords, userEntries: [],
                                   learningRecords: learningStore.snapshot.records.map {
                                       LearnedCandidateRanking(code: $0.code,
                                                               candidateText: $0.candidateText,
                                                               score: $0.score)
                                   },
                                   learningEnabled: true, pageIndex: 0)
        XCTAssertEqual(page.items.map(\.text), ["乙", "甲"])
        try learningStore.clear()
        page = try ranker.page(for: code, records: baseRecords, userEntries: [],
                               learningRecords: learningStore.snapshot.records.map {
                                   LearnedCandidateRanking(code: $0.code,
                                                           candidateText: $0.candidateText,
                                                           score: $0.score)
                               },
                               learningEnabled: true, pageIndex: 0)
        XCTAssertEqual(page.items.map(\.text), ["甲", "乙"])

        let before = try filesystemFingerprint(root)
        let engine = InputEngine { _, pageIndex in
            try ranker.page(for: code, records: baseRecords, pageIndex: pageIndex)
        }
        engine.privateMode = true
        for _ in 0..<10_000 {
            _ = engine.process(.letter("a"))
            XCTAssertNil(engine.process(.selectFirst).learningDelta)
        }
        XCTAssertEqual(try filesystemFingerprint(root), before)
        XCTAssertEqual(engine.state, .idle)
    }

    private func filesystemFingerprint(_ root: URL) throws -> [String: UInt64] {
        let enumerator = FileManager.default.enumerator(at: root,
                                                       includingPropertiesForKeys: [.fileSizeKey],
                                                       options: [.skipsHiddenFiles])
        var result = [String: UInt64]()
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let data = try Data(contentsOf: url)
            result[url.path.replacingOccurrences(of: root.path, with: "")] =
                DictionaryChecksum.fnv1a64(data)
        }
        return result
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWubiPersonalizationTests-\(UUID().uuidString)", isDirectory: true)
    }
}
