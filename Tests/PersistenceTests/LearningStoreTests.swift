import Foundation
import XCTest
@testable import MacWubi

final class LearningStoreTests: XCTestCase {
    func testThreeSelectionsPromoteAndScoresAreCapped() throws {
        let store = try makeStore(maxRecords: 10, maximumScore: 5)
        let code = try XCTUnwrap(InputCode("abcd"))
        for _ in 0..<9 { try store.recordSelection(code: code, candidateText: "乙") }
        XCTAssertEqual(store.score(code: code, candidateText: "乙"), 5)
        XCTAssertTrue(store.isPromoted(code: code, candidateText: "乙"))
    }

    func testDecayPruningAndStableOrder() throws {
        let store = try makeStore(maxRecords: 2, maximumScore: 100)
        let code = try XCTUnwrap(InputCode("a"))
        try store.recordSelection(code: code, candidateText: "乙", amount: 4)
        try store.recordSelection(code: code, candidateText: "甲", amount: 4)
        try store.recordSelection(code: code, candidateText: "丙", amount: 1)
        XCTAssertEqual(store.snapshot.records.map(\.candidateText), ["乙", "甲"])
        try store.decay(to: 1)
        XCTAssertEqual(store.score(code: code, candidateText: "乙"), 2)
    }

    func testDisableAndClearDoNotWriteLearning() throws {
        let store = try makeStore(maxRecords: 10, maximumScore: 100)
        let code = try XCTUnwrap(InputCode("a"))
        store.isEnabled = false
        try store.recordSelection(code: code, candidateText: "甲")
        XCTAssertEqual(store.snapshot.generation, 0)
        XCTAssertTrue(store.snapshot.records.isEmpty)
        store.isEnabled = true
        try store.recordSelection(code: code, candidateText: "甲")
        try store.clear()
        XCTAssertTrue(store.snapshot.records.isEmpty)
        XCTAssertGreaterThan(store.snapshot.generation, 1)
    }

    func testTypedWubiAndPinyinLearningKeysRemainIndependentAcrossRestart() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWubiTypedLearning-\(UUID().uuidString)",
                                   isDirectory: true)
        let writer = try SnapshotWriter(rootURL: root)
        let store = try LearningStore(writer: writer, maxRecords: 10, maximumScore: 100)
        let wubiCode = try XCTUnwrap(InputCode("wqvb"))
        let pinyinQuery = try XCTUnwrap(CandidateQueryKey(kind: .pinyin, code: "nihao"))
        let wubiKey = try LearningKey(queryKey: .wubi(wubiCode), candidateText: "你好")
        let pinyinKey = try LearningKey(queryKey: pinyinQuery, candidateText: "你好")

        try store.recordSelection(key: wubiKey, amount: 2)
        try store.recordSelection(key: pinyinKey, amount: 5)

        XCTAssertEqual(store.score(key: wubiKey), 2)
        XCTAssertEqual(store.score(key: pinyinKey), 5)
        XCTAssertEqual(Set(store.snapshot.records.map(\.key)), [wubiKey, pinyinKey])

        let restarted = try LearningStore(writer: SnapshotWriter(rootURL: root),
                                          maxRecords: 10, maximumScore: 100)
        XCTAssertEqual(restarted.score(key: wubiKey), 2)
        XCTAssertEqual(restarted.score(key: pinyinKey), 5)
        XCTAssertEqual(try writer.load(.learning)?.schemaVersion,
                       LearningStore.schemaVersion)
    }

    func testDirectInputCandidateCannotEnterLearningPersistence() throws {
        let store = try makeStore(maxRecords: 10, maximumScore: 100)
        let query = try XCTUnwrap(CandidateQueryKey(kind: .directInput, code: "MacWubi"))
        let key = try LearningKey(queryKey: query, candidateText: "MacWubi")

        XCTAssertThrowsError(try store.recordSelection(key: key))
        XCTAssertTrue(store.snapshot.records.isEmpty)
        XCTAssertEqual(store.snapshot.generation, 0)
    }

    private func makeStore(maxRecords: Int, maximumScore: Int) throws -> LearningStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWubiLearningTests-\(UUID().uuidString)", isDirectory: true)
        return try LearningStore(writer: SnapshotWriter(rootURL: root),
                                 maxRecords: maxRecords, maximumScore: maximumScore)
    }
}
