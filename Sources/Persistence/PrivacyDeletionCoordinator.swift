import Foundation

enum PrivacyDeletionState: Equatable, Sendable { case deleted, alreadyEmpty, failed }

struct PrivacyDeletionReport: Equatable, Sendable {
    let results: [DataDomain: PrivacyDeletionState]
    var allSucceeded: Bool { results.values.allSatisfy { $0 != .failed } }
}

final class PrivacyDeletionCoordinator {
    private let writer: SnapshotWriter
    private let deleteDirectory: (URL) throws -> Void
    private let resetSessions: () -> Void

    init(writer: SnapshotWriter,
         deleteDirectory: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
         resetSessions: @escaping () -> Void = {}) {
        self.writer = writer; self.deleteDirectory = deleteDirectory; self.resetSessions = resetSessions
    }

    func delete(_ domain: DataDomain) -> PrivacyDeletionReport {
        let directory = writer.directory(for: domain)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return PrivacyDeletionReport(results: [domain: .alreadyEmpty])
        }
        do {
            try deleteDirectory(directory)
            resetSessions()
            return PrivacyDeletionReport(results: [domain: .deleted])
        } catch {
            return PrivacyDeletionReport(results: [domain: .failed])
        }
    }

    func deleteAll() -> PrivacyDeletionReport {
        var results = [DataDomain: PrivacyDeletionState]()
        for domain in DataDomain.allCases { results[domain] = delete(domain).results[domain] }
        return PrivacyDeletionReport(results: results)
    }
}
