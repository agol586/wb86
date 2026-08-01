import Foundation

enum SnapshotCommitStage: Equatable, Sendable {
    case afterTemporaryValidation
    case afterPreviousReplacement
}

enum SnapshotWriterError: Error, Equatable {
    case generationNotMonotonic
    case domainMismatch
    case unsupportedSchema
    case validationFailed
}

final class SnapshotWriter {
    typealias FailureInjector = (SnapshotCommitStage) throws -> Void

    let rootURL: URL
    var failureInjector: FailureInjector?
    private let fileManager: FileManager
    private let lock = NSLock()

    init(rootURL: URL, fileManager: FileManager = .default) throws {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
        try fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: self.rootURL.path)
    }

    func directory(for domain: DataDomain) -> URL {
        rootURL.appendingPathComponent(domain.directoryName, isDirectory: true)
    }

    func currentURL(for domain: DataDomain) -> URL {
        directory(for: domain).appendingPathComponent("current")
    }

    func previousURL(for domain: DataDomain) -> URL {
        directory(for: domain).appendingPathComponent("previous")
    }

    func temporaryURL(for domain: DataDomain) -> URL {
        directory(for: domain).appendingPathComponent("staging")
    }

    func commit(_ snapshot: DataSnapshot,
                validatePayload: (Data) -> Bool = { _ in true }) throws {
        lock.lock()
        defer { lock.unlock() }
        try ensureDomainDirectory(snapshot.domain)
        if let current = try? loadUnlocked(currentURL(for: snapshot.domain)),
           snapshot.generation <= current.generation {
            throw SnapshotWriterError.generationNotMonotonic
        }
        let temporary = temporaryURL(for: snapshot.domain)
        try? fileManager.removeItem(at: temporary)
        try snapshot.encoded().write(to: temporary, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        let staged = try loadUnlocked(temporary)
        guard staged == snapshot, validatePayload(staged.payload) else {
            try? fileManager.removeItem(at: temporary)
            throw SnapshotWriterError.validationFailed
        }
        try failureInjector?(.afterTemporaryValidation)

        let current = currentURL(for: snapshot.domain)
        let previous = previousURL(for: snapshot.domain)
        var movedCurrent = false
        do {
            if fileManager.fileExists(atPath: current.path) {
                try? fileManager.removeItem(at: previous)
                try fileManager.moveItem(at: current, to: previous)
                movedCurrent = true
                try failureInjector?(.afterPreviousReplacement)
            }
            try fileManager.moveItem(at: temporary, to: current)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: current.path)
            guard try loadUnlocked(current) == snapshot else {
                throw SnapshotWriterError.validationFailed
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            if movedCurrent, !fileManager.fileExists(atPath: current.path),
               fileManager.fileExists(atPath: previous.path) {
                try? fileManager.copyItem(at: previous, to: current)
                try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: current.path)
            }
            throw error
        }
    }

    func load(_ domain: DataDomain) throws -> DataSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        let url = currentURL(for: domain)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let snapshot = try loadUnlocked(url)
        guard snapshot.domain == domain else { throw SnapshotWriterError.domainMismatch }
        return snapshot
    }

    func loadPrevious(_ domain: DataDomain) throws -> DataSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        let url = previousURL(for: domain)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let snapshot = try loadUnlocked(url)
        guard snapshot.domain == domain else { throw SnapshotWriterError.domainMismatch }
        return snapshot
    }

    func recover(_ domain: DataDomain,
                 supportedSchemaVersions: Set<UInt32>) throws -> DataSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        try ensureDomainDirectory(domain)
        try? fileManager.removeItem(at: temporaryURL(for: domain))
        if let current = validSnapshot(at: currentURL(for: domain), domain: domain,
                                       schemas: supportedSchemaVersions) {
            return current
        }
        guard let previous = validSnapshot(at: previousURL(for: domain), domain: domain,
                                           schemas: supportedSchemaVersions) else {
            return nil
        }
        let currentURL = currentURL(for: domain)
        try? fileManager.removeItem(at: currentURL)
        try fileManager.copyItem(at: previousURL(for: domain), to: currentURL)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: currentURL.path)
        return previous
    }

    private func ensureDomainDirectory(_ domain: DataDomain) throws {
        let directory = directory(for: domain)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func loadUnlocked(_ url: URL) throws -> DataSnapshot {
        try DataSnapshot.decode(Data(contentsOf: url, options: .mappedIfSafe))
    }

    private func validSnapshot(at url: URL, domain: DataDomain,
                               schemas: Set<UInt32>) -> DataSnapshot? {
        guard let snapshot = try? loadUnlocked(url), snapshot.domain == domain,
              schemas.contains(snapshot.schemaVersion) else { return nil }
        return snapshot
    }
}
