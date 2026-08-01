import Foundation
import XCTest
@testable import MacWubi

final class PrivacyDataTests: XCTestCase {
    func testInventoryContainsOnlyThreeDomainsPurposeLogicalLocationAndByteCounts() throws {
        let writer = try SnapshotWriter(rootURL: temporaryRoot())
        for domain in DataDomain.allCases {
            try writer.commit(try DataSnapshot(domain: domain, schemaVersion: 1,
                                                generation: 1, payload: Data([domain.rawValue])))
        }
        let status = PrivacyStatusProvider(writer: writer).status()
        XCTAssertEqual(status.map(\.domain), DataDomain.allCases)
        XCTAssertTrue(status.allSatisfy { $0.byteCount > 0 && $0.schemaVersion == 1 })
        XCTAssertTrue(status.allSatisfy { $0.logicalLocation.hasSuffix("/current") })
        XCTAssertFalse(String(describing: status).contains(writer.rootURL.path))
    }

    func testDomainDeleteDeleteAllAndTruthfulPartialFailurePreserveBaseInput() throws {
        let writer = try populatedWriter()
        var resets = 0
        let deletion = PrivacyDeletionCoordinator(writer: writer, resetSessions: { resets += 1 })
        let one = deletion.delete(.learning)
        XCTAssertEqual(one.results[.learning], .deleted)
        XCTAssertNil(try writer.load(.learning))
        XCTAssertNotNil(try writer.load(.settings))
        XCTAssertNotNil(try writer.load(.userLexicon))

        let partial = PrivacyDeletionCoordinator(writer: writer, deleteDirectory: { url in
            if url.lastPathComponent == "UserLexicon" { throw DeleteFailure.expected }
            try FileManager.default.removeItem(at: url)
        }).deleteAll()
        XCTAssertEqual(partial.results[.settings], .deleted)
        XCTAssertEqual(partial.results[.userLexicon], .failed)
        XCTAssertEqual(partial.results[.learning], .alreadyEmpty)
        XCTAssertFalse(partial.allSucceeded)
        XCTAssertGreaterThanOrEqual(resets, 1)

        let code = try XCTUnwrap(InputCode("a"))
        let engine = InputEngine { _, page in
            try CandidatePage(items: [Candidate(text: "基础", code: code, source: .base,
                                                baseRank: 0, learnedScore: 0, ordinal: 1)],
                              pageIndex: page, pageSize: 5, totalCount: 1)
        }
        XCTAssertEqual(engine.process(.letter("a")).state.kind, .composing)
    }

    private func populatedWriter() throws -> SnapshotWriter {
        let writer = try SnapshotWriter(rootURL: temporaryRoot())
        for domain in DataDomain.allCases {
            try writer.commit(try DataSnapshot(domain: domain, schemaVersion: 1,
                                                generation: 1, payload: Data("data".utf8)))
        }
        return writer
    }
    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MacWubiPrivacy-\(UUID().uuidString)")
    }
    private enum DeleteFailure: Error { case expected }
}
