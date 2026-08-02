import Foundation

enum SnapshotCommitStage: Equatable, CaseIterable, Sendable {
    case beforeTemporaryWrite
    case afterTemporaryWrite
    case afterTemporaryValidation
    case afterPreviousReplacement
    case afterCurrentReplacement
}

enum SnapshotWriterError: Error, Equatable {
    case generationNotMonotonic
    case domainMismatch
    case unsupportedSchema
    case validationFailed
}

enum SnapshotSchemaPreflight: Equatable, Sendable {
    case absent
    case supported(version: UInt32)
    case unsupported(version: UInt32)
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
        let current = currentURL(for: snapshot.domain)
        let previous = previousURL(for: snapshot.domain)
        var movedCurrent = false
        var installedCurrent = false
        do {
            try failureInjector?(.beforeTemporaryWrite)
            try? fileManager.removeItem(at: temporary)
            try snapshot.encoded().write(to: temporary, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600],
                                          ofItemAtPath: temporary.path)
            try failureInjector?(.afterTemporaryWrite)
            let staged = try loadUnlocked(temporary)
            guard staged == snapshot, validatePayload(staged.payload) else {
                throw SnapshotWriterError.validationFailed
            }
            try failureInjector?(.afterTemporaryValidation)

            if fileManager.fileExists(atPath: current.path) {
                try? fileManager.removeItem(at: previous)
                try fileManager.moveItem(at: current, to: previous)
                movedCurrent = true
                try failureInjector?(.afterPreviousReplacement)
            }
            try fileManager.moveItem(at: temporary, to: current)
            installedCurrent = true
            try failureInjector?(.afterCurrentReplacement)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: current.path)
            guard try loadUnlocked(current) == snapshot else {
                throw SnapshotWriterError.validationFailed
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            if movedCurrent, fileManager.fileExists(atPath: previous.path) {
                if installedCurrent || fileManager.fileExists(atPath: current.path) {
                    try? fileManager.removeItem(at: current)
                }
                try? fileManager.copyItem(at: previous, to: current)
                try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: current.path)
            } else if installedCurrent {
                try? fileManager.removeItem(at: current)
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

    /// Inspects only the current envelope and never recovers, replaces, or removes a file.
    /// Callers use this before corruption recovery so a future schema cannot be mistaken for
    /// an invalid current snapshot and overwritten by an older supported previous snapshot.
    func preflightCurrentSchema(
        _ domain: DataDomain,
        supportedSchemaVersions: Set<UInt32>
    ) throws -> SnapshotSchemaPreflight {
        lock.lock()
        defer { lock.unlock() }
        let url = currentURL(for: domain)
        guard fileManager.fileExists(atPath: url.path) else { return .absent }
        let snapshot = try loadUnlocked(url)
        guard snapshot.domain == domain else { throw SnapshotWriterError.domainMismatch }
        if supportedSchemaVersions.contains(snapshot.schemaVersion) {
            return .supported(version: snapshot.schemaVersion)
        }
        return .unsupported(version: snapshot.schemaVersion)
    }

    func recover(_ domain: DataDomain,
                 supportedSchemaVersions: Set<UInt32>,
                 validatePayload: (Data) -> Bool = { _ in true }) throws -> DataSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        try ensureDomainDirectory(domain)
        try? fileManager.removeItem(at: temporaryURL(for: domain))
        if let current = validSnapshot(at: currentURL(for: domain), domain: domain,
                                       schemas: supportedSchemaVersions,
                                       validatePayload: validatePayload) {
            return current
        }
        guard let previous = validSnapshot(at: previousURL(for: domain), domain: domain,
                                           schemas: supportedSchemaVersions,
                                           validatePayload: validatePayload) else {
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
                               schemas: Set<UInt32>,
                               validatePayload: (Data) -> Bool) -> DataSnapshot? {
        guard let snapshot = try? loadUnlocked(url), snapshot.domain == domain,
              schemas.contains(snapshot.schemaVersion),
              validatePayload(snapshot.payload) else { return nil }
        return snapshot
    }
}
