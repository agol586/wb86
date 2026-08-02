import Foundation
import XCTest
@testable import MacWubi

final class LexiconExporterTests: XCTestCase {
    func testDeterministicTextAndArchiveRoundTripWithOptionalLearning() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWubiExport-\(UUID().uuidString)")
        let writer = try SnapshotWriter(rootURL: root)
        let users = try UserLexiconStore(writer: writer)
        let learning = try LearningStore(writer: writer)
        let code = try XCTUnwrap(InputCode("wqvb"))
        try users.upsert(code: code, text: "你好", fixedRank: 2, createdBy: .manual)
        try learning.recordSelection(code: code, candidateText: "你好", amount: 3)
        let pinyin = try XCTUnwrap(CandidateQueryKey(kind: .pinyin, code: "nihao"))
        try learning.recordSelection(
            key: LearningKey(queryKey: pinyin, candidateText: "你好"), amount: 5
        )
        let exporter = LexiconExporter(userStore: users, learningStore: learning)

        XCTAssertEqual(try exporter.textData(), try exporter.textData())
        let without = try LexiconArchiveCodec.decode(exporter.archiveData(includeLearning: false))
        XCTAssertNil(without.learning)
        let data = try exporter.archiveData(includeLearning: true)
        XCTAssertEqual(data, try exporter.archiveData(includeLearning: true))
        let archive = try LexiconArchiveCodec.decode(data)
        XCTAssertEqual(archive.userLexicon.count, 1)
        XCTAssertEqual(archive.learning?.count, 2)
        XCTAssertEqual(Set(archive.learning?.compactMap(\.kind) ?? []), [.wubi, .pinyin])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(root.path))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("application"))

        var corrupt = data
        corrupt[corrupt.index(before: corrupt.endIndex)] ^= 0xff
        XCTAssertThrowsError(try LexiconArchiveCodec.decode(corrupt))

        let cleanWriter = try SnapshotWriter(rootURL: root.appendingPathComponent("clean"))
        let cleanStore = try UserLexiconStore(writer: cleanWriter)
        let cleanLearning = try LearningStore(writer: cleanWriter)
        _ = try LexiconImporter(store: cleanStore, learningStore: cleanLearning).importArchive(data)
        XCTAssertEqual(cleanStore.snapshot.entries.map(\.text), ["你好"])
        XCTAssertEqual(cleanLearning.snapshot.records.map(\.score), [5, 3])
        XCTAssertEqual(Set(cleanLearning.snapshot.records.map { $0.queryKey.kind }),
                       [.wubi, .pinyin])
    }
}
