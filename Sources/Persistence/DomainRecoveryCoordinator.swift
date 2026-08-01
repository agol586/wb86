import Foundation

enum DomainRecoveryResult: Equatable, Sendable {
    case current(generation: UInt64)
    case recoveredPrevious(generation: UInt64)
    case safeDefault
    case preservedFuture(version: UInt32)
}

final class DomainRecoveryCoordinator {
    private let writer: SnapshotWriter
    private let resetSessions: () -> Void
    private let fileManager: FileManager

    init(writer: SnapshotWriter, fileManager: FileManager = .default,
         resetSessions: @escaping () -> Void = {}) {
        self.writer = writer
        self.fileManager = fileManager
        self.resetSessions = resetSessions
    }

    func recover(_ domain: DataDomain, supportedSchemas: Set<UInt32>,
                 validatePayload: (Data) -> Bool = { _ in true }) throws -> DomainRecoveryResult {
        let currentURL = writer.currentURL(for: domain)
        var didReset = false
        if fileManager.fileExists(atPath: currentURL.path) {
            do {
                let current = try DataSnapshot.decode(Data(contentsOf: currentURL, options: .mappedIfSafe))
                guard current.domain == domain else { throw SnapshotWriterError.domainMismatch }
                if !supportedSchemas.contains(current.schemaVersion) {
                    return .preservedFuture(version: current.schemaVersion)
                }
                if validatePayload(current.payload) { return .current(generation: current.generation) }
            } catch {
                // Quarantine below; diagnostics intentionally contain no bytes or path.
            }
            try quarantine(currentURL, in: writer.directory(for: domain), name: "quarantine-current")
            resetSessions()
            didReset = true
        }

        if let previous = try? writer.loadPrevious(domain),
           supportedSchemas.contains(previous.schemaVersion), validatePayload(previous.payload) {
            let destination = writer.currentURL(for: domain)
            try? fileManager.removeItem(at: destination)
            try fileManager.copyItem(at: writer.previousURL(for: domain), to: destination)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            return .recoveredPrevious(generation: previous.generation)
        }
        if !didReset { resetSessions() }
        return .safeDefault
    }

    func validateBase(_ data: Data, validator: (Data) -> Bool) -> DomainRecoveryResult {
        guard validator(data) else {
            resetSessions()
            return .safeDefault
        }
        return .current(generation: 1)
    }

    private func quarantine(_ source: URL, in directory: URL, name: String) throws {
        let destination = directory.appendingPathComponent(name)
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: source, to: destination)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}
