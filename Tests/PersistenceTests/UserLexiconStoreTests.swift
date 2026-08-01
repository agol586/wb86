import Foundation
import XCTest
@testable import MacWubi

final class UserLexiconStoreTests: XCTestCase {
    func testValidationAndDuplicateMerge() throws {
        let store = try makeStore()
        let code = try XCTUnwrap(InputCode("abcd"))
        let added = try store.upsert(code: code, text: "自定义词", fixedRank: 4, createdBy: .manual)
        let merged = try store.upsert(code: code, text: "自定义词", fixedRank: 1, createdBy: .imported)
        XCTAssertEqual(added, .added)
        XCTAssertEqual(merged, .merged)
        XCTAssertEqual(store.snapshot.entries.count, 1)
        XCTAssertEqual(store.snapshot.entries[0].fixedRank, 1)
        XCTAssertEqual(store.snapshot.entries[0].createdBy, .manual)
        XCTAssertThrowsError(try store.upsert(code: code, text: "bad\ntext",
                                              fixedRank: nil, createdBy: .manual))
    }

    func testSearchEditDeleteAndRestart() throws {
        let root = temporaryDirectory()
        let writer = try SnapshotWriter(rootURL: root)
        let store = try UserLexiconStore(writer: writer)
        let code = try XCTUnwrap(InputCode("abcd"))
        _ = try store.upsert(code: code, text: "项目术语", fixedRank: nil, createdBy: .manual)
        let entry = try XCTUnwrap(store.search("项目").first)
        XCTAssertEqual(store.search("abcd").count, 1)
        try store.edit(id: entry.id, code: code, text: "项目名", fixedRank: 2)

        let restarted = try UserLexiconStore(writer: SnapshotWriter(rootURL: root))
        XCTAssertEqual(restarted.snapshot.entries.map(\.text), ["项目名"])
        XCTAssertTrue(try restarted.delete(id: entry.id))
        XCTAssertTrue(restarted.snapshot.entries.isEmpty)
        XCTAssertFalse(try restarted.delete(id: entry.id))
    }

    func testServiceReturnsCountOnlyMutationResults() throws {
        let store = try makeStore()
        let service = UserLexiconService(store: store)
        let code = try XCTUnwrap(InputCode("abcd"))
        let added = try service.add(code: code, text: "隐私词")
        XCTAssertEqual(added, UserLexiconMutationResult(kind: .added,
                                                        generation: 1, totalCount: 1))
        let id = try XCTUnwrap(service.search("隐私").first?.id)
        let deleted = try service.delete(id: id)
        XCTAssertEqual(deleted.kind, .deleted)
        XCTAssertEqual(deleted.totalCount, 0)
    }

    private func makeStore() throws -> UserLexiconStore {
        try UserLexiconStore(writer: SnapshotWriter(rootURL: temporaryDirectory()))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWubiLexiconTests-\(UUID().uuidString)", isDirectory: true)
    }
}
