import Foundation
import XCTest
@testable import MacWubi

final class SnapshotWriterTests: XCTestCase {
    func testEnvelopeKnownVectorAndCorruptionRejection() throws {
        let snapshot = try DataSnapshot(domain: .settings, schemaVersion: 1,
                                        generation: 7, payload: Data("abc".utf8))
        let encoded = snapshot.encoded()
        XCTAssertEqual(String(data: encoded.prefix(4), encoding: .ascii), "MWSN")
        XCTAssertEqual(try DataSnapshot.decode(encoded), snapshot)
        var corrupt = encoded
        corrupt[corrupt.index(before: corrupt.endIndex)] ^= 0xff
        XCTAssertThrowsError(try DataSnapshot.decode(corrupt))
    }

    func testReplacementRetainsExactlyOneValidatedPrevious() throws {
        let writer = try SnapshotWriter(rootURL: temporaryDirectory())
        try writer.commit(try snapshot(.userLexicon, generation: 1, text: "one"))
        try writer.commit(try snapshot(.userLexicon, generation: 2, text: "two"))
        try writer.commit(try snapshot(.userLexicon, generation: 3, text: "three"))

        XCTAssertEqual(try writer.load(.userLexicon)?.generation, 3)
        XCTAssertEqual(try writer.loadPrevious(.userLexicon)?.generation, 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(
            at: writer.directory(for: .userLexicon), includingPropertiesForKeys: nil
        ).map(\.lastPathComponent).sorted(), ["current", "previous"])
    }

    func testInterruptedCommitDoesNotPublishGeneration() throws {
        let writer = try SnapshotWriter(rootURL: temporaryDirectory())
        try writer.commit(try snapshot(.learning, generation: 1, text: "stable"))
        writer.failureInjector = { stage in
            if stage == .afterTemporaryValidation { throw TestError.interrupted }
        }
        XCTAssertThrowsError(try writer.commit(try snapshot(.learning, generation: 2, text: "new")))
        XCTAssertEqual(try writer.load(.learning)?.generation, 1)
    }

    func testEveryCommitInterruptionBoundaryRestoresLastCompleteSnapshotOnRestart() throws {
        for stage in SnapshotCommitStage.allCases {
            let root = temporaryDirectory()
            let writer = try SnapshotWriter(rootURL: root)
            let stable = try snapshot(.settings, generation: 1, text: "stable")
            try writer.commit(stable)
            writer.failureInjector = { current in
                if current == stage { throw TestError.interrupted }
            }

            XCTAssertThrowsError(try writer.commit(
                try snapshot(.settings, generation: 2, text: "replacement")
            ), "stage \(stage)")

            let restarted = try SnapshotWriter(rootURL: root)
            XCTAssertEqual(try restarted.recover(.settings,
                                                 supportedSchemaVersions: [1]), stable,
                           "stage \(stage)")
            XCTAssertEqual(try restarted.load(.settings), stable, "stage \(stage)")
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: restarted.temporaryURL(for: .settings).path
            ))
        }
    }

    func testStartupRecoversPreviousPerDomainAndRemovesInvalidTemporary() throws {
        let writer = try SnapshotWriter(rootURL: temporaryDirectory())
        try writer.commit(try snapshot(.settings, generation: 1, text: "old"))
        try writer.commit(try snapshot(.settings, generation: 2, text: "new"))
        try Data("corrupt".utf8).write(to: writer.currentURL(for: .settings))
        try Data("partial".utf8).write(to: writer.temporaryURL(for: .settings))

        let recovered = try writer.recover(.settings, supportedSchemaVersions: [1])
        XCTAssertEqual(recovered?.generation, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: writer.temporaryURL(for: .settings).path))
        XCTAssertNil(try writer.load(.learning))
    }

    func testPermissionsArePrivate() throws {
        let root = temporaryDirectory()
        let writer = try SnapshotWriter(rootURL: root)
        try writer.commit(try snapshot(.settings, generation: 1, text: "private"))
        XCTAssertEqual(permissions(root), 0o700)
        XCTAssertEqual(permissions(writer.currentURL(for: .settings)), 0o600)
    }

    private func snapshot(_ domain: DataDomain, generation: UInt64, text: String) throws -> DataSnapshot {
        try DataSnapshot(domain: domain, schemaVersion: 1, generation: generation,
                         payload: Data(text.utf8))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWubiSnapshotTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func permissions(_ url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    private enum TestError: Error { case interrupted }
}
