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

    func testLearningV1MigrationWrapsWubiKeyAndDoesNotTouchOtherDomains() throws {
        let writer = try SnapshotWriter(rootURL: temporaryRoot())
        let legacyPayload = Data(#"{"records":[{"code":"wqvb","candidateText":"你好","score":3,"decayEpoch":7}]}"#.utf8)
        try writer.commit(try DataSnapshot(domain: .learning, schemaVersion: 1,
                                            generation: 4, payload: legacyPayload))
        let settings = try DataSnapshot(domain: .settings, schemaVersion: 77,
                                        generation: 8, payload: Data("settings-future".utf8))
        let lexicon = try DataSnapshot(domain: .userLexicon, schemaVersion: 1,
                                       generation: 9, payload: Data("lexicon-stable".utf8))
        try writer.commit(settings)
        try writer.commit(lexicon)

        let migrator = DataMigrator(writer: writer, currentVersions: [.learning: 2])
        XCTAssertEqual(try migrator.migrate(.learning), .migrated(from: 1, to: 2))
        XCTAssertEqual(try writer.load(.settings), settings)
        XCTAssertEqual(try writer.load(.userLexicon), lexicon)

        let migrated = try XCTUnwrap(writer.load(.learning))
        XCTAssertEqual(migrated.schemaVersion, 2)
        XCTAssertEqual(migrated.generation, 5)
        let store = try LearningStore(writer: SnapshotWriter(rootURL: writer.rootURL))
        let code = try XCTUnwrap(InputCode("wqvb"))
        let key = try LearningKey(queryKey: .wubi(code), candidateText: "你好")
        XCTAssertEqual(store.score(key: key), 3)
        XCTAssertEqual(store.snapshot.records.first?.decayEpoch, 7)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MacWubiMigration-\(UUID().uuidString)")
    }
    private enum Failure: Error { case interrupted }
}
