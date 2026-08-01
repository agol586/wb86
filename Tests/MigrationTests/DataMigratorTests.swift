import Foundation
import XCTest
@testable import MacWubi

final class DataMigratorTests: XCTestCase {
    func testSequentialMigrationAndIdempotencyForEveryDomain() throws {
        for domain in DataDomain.allCases {
            let writer = try SnapshotWriter(rootURL: temporaryRoot())
            try writer.commit(try DataSnapshot(domain: domain, schemaVersion: 1,
                                                generation: 1, payload: Data("v1".utf8)))
            let migrator = DataMigrator(writer: writer, currentVersions: [domain: 3], steps: [
                domain: [1: { $0 + Data("-v2".utf8) }, 2: { $0 + Data("-v3".utf8) }]
            ])
            XCTAssertEqual(try migrator.migrate(domain), .migrated(from: 1, to: 3))
            XCTAssertEqual(try writer.load(domain)?.schemaVersion, 3)
            XCTAssertEqual(try writer.load(domain)?.generation, 3)
            XCTAssertEqual(try migrator.migrate(domain), .current)
            XCTAssertEqual(try writer.load(domain)?.generation, 3)
        }
    }

    func testFutureSchemaIsPreservedWithoutDowngrade() throws {
        let writer = try SnapshotWriter(rootURL: temporaryRoot())
        let future = try DataSnapshot(domain: .settings, schemaVersion: 99,
                                      generation: 7, payload: Data("future".utf8))
        try writer.commit(future)
        let migrator = DataMigrator(writer: writer, currentVersions: [.settings: 1])
        XCTAssertEqual(try migrator.migrate(.settings), .preservedFuture(version: 99))
        XCTAssertEqual(try writer.load(.settings), future)
    }

    func testInterruptionRollsBackAndDoesNotAdvanceVisibleSchema() throws {
        let writer = try SnapshotWriter(rootURL: temporaryRoot())
        try writer.commit(try DataSnapshot(domain: .learning, schemaVersion: 1,
                                            generation: 1, payload: Data("stable".utf8)))
        writer.failureInjector = { stage in
            if stage == .afterPreviousReplacement { throw Failure.interrupted }
        }
        let migrator = DataMigrator(writer: writer, currentVersions: [.learning: 2],
                                    steps: [.learning: [1: { $0 + Data("new".utf8) }]])
        XCTAssertThrowsError(try migrator.migrate(.learning))
        XCTAssertEqual(try writer.load(.learning)?.schemaVersion, 1)
        XCTAssertEqual(try writer.load(.learning)?.payload, Data("stable".utf8))
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MacWubiMigration-\(UUID().uuidString)")
    }
    private enum Failure: Error { case interrupted }
}
