import Foundation
import XCTest
@testable import MacWubi

final class LexiconImporterTests: XCTestCase {
    func testTextParsingBoundsDuplicatesAndInvalidRecords() throws {
        let text = """
        # mac-wubi-user-lexicon v1
        WQVB\t你好\t2
        wqvb\t你好\t1
        abcd\t有效
        zzzz\t非法编码
        abcd\t含\t制表符\t3

        """
        let result = try LexiconTextCodec.decode(Data(text.utf8))
        XCTAssertEqual(result.entries.map(\.code.letters), ["abcd", "wqvb"])
        XCTAssertEqual(result.entries.last?.fixedRank, 1)
        XCTAssertEqual(result.mergedCount, 1)
        XCTAssertEqual(result.failedCount, 2)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertThrowsError(try LexiconTextCodec.decode(Data(repeating: 0xff, count: 4)))
        XCTAssertThrowsError(try LexiconTextCodec.decode(Data("# mac-wubi-user-lexicon v2\na\t词\n".utf8)))
        XCTAssertThrowsError(try LexiconTextCodec.decode(Data(repeating: 0x61,
                                                               count: LexiconTextCodec.maximumFileBytes + 1)))
        var archive = try LexiconArchiveCodec.encode(MacWubiArchive(userLexicon: [], learning: nil))
        archive[8] = 2
        XCTAssertThrowsError(try LexiconArchiveCodec.decode(archive))
    }

    func testImportMergesAtomicallyWithExistingSnapshot() throws {
        let root = temporaryRoot()
        let writer = try SnapshotWriter(rootURL: root)
        let store = try UserLexiconStore(writer: writer)
        try store.upsert(code: try XCTUnwrap(InputCode("wqvb")), text: "你好",
                         fixedRank: 5, createdBy: .manual)
        let importer = LexiconImporter(store: store)
        let report = try importer.importText(Data("""
        # mac-wubi-user-lexicon v1
        wqvb\t你好\t1
        abcd\t新增\t3
        """.utf8))
        XCTAssertEqual(report.acceptedCount, 1)
        XCTAssertEqual(report.mergedCount, 1)
        XCTAssertEqual(store.snapshot.entries.count, 2)
        XCTAssertEqual(store.snapshot.entries.first { $0.text == "你好" }?.fixedRank, 1)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MacWubiImport-\(UUID().uuidString)")
    }
}
