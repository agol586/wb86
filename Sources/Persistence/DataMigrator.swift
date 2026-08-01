import Foundation

enum MigrationResult: Equatable, Sendable {
    case noData
    case current
    case migrated(from: UInt32, to: UInt32)
    case preservedFuture(version: UInt32)
}

enum DataMigrationError: Error, Equatable {
    case missingCurrentVersion
    case missingSequentialStep(from: UInt32)
}

final class DataMigrator {
    typealias Step = (Data) throws -> Data
    private let writer: SnapshotWriter
    private let currentVersions: [DataDomain: UInt32]
    private let steps: [DataDomain: [UInt32: Step]]

    init(writer: SnapshotWriter,
         currentVersions: [DataDomain: UInt32] = [.settings: 1, .userLexicon: 1, .learning: 1],
         steps: [DataDomain: [UInt32: Step]] = [:]) {
        self.writer = writer
        self.currentVersions = currentVersions
        self.steps = steps
    }

    func migrate(_ domain: DataDomain) throws -> MigrationResult {
        guard let target = currentVersions[domain] else {
            throw DataMigrationError.missingCurrentVersion
        }
        guard var snapshot = try writer.load(domain) else { return .noData }
        if snapshot.schemaVersion > target {
            return .preservedFuture(version: snapshot.schemaVersion)
        }
        if snapshot.schemaVersion == target { return .current }
        let original = snapshot.schemaVersion
        while snapshot.schemaVersion < target {
            guard let step = steps[domain]?[snapshot.schemaVersion] else {
                throw DataMigrationError.missingSequentialStep(from: snapshot.schemaVersion)
            }
            let payload = try step(snapshot.payload)
            snapshot = try DataSnapshot(domain: domain,
                                        schemaVersion: snapshot.schemaVersion + 1,
                                        generation: snapshot.generation + 1,
                                        payload: payload)
            try writer.commit(snapshot)
        }
        return .migrated(from: original, to: target)
    }

    func migrateAll() throws -> [DataDomain: MigrationResult] {
        var results = [DataDomain: MigrationResult]()
        for domain in DataDomain.allCases { results[domain] = try migrate(domain) }
        return results
    }
}
