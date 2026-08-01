import Foundation

enum UserLexiconEntryOrigin: String, Codable, Sendable {
    case manual
    case imported
}

enum UserLexiconError: Error, Equatable {
    case invalidText
    case invalidFixedRank
    case entryNotFound
    case corruptPayload
    case unsupportedSchema
}

struct UserLexiconEntry: Equatable, Hashable, Sendable {
    static let maximumCharacters = 128
    static let maximumUTF8Bytes = 1_024

    let id: String
    let code: InputCode
    let text: String
    let fixedRank: Int?
    let createdBy: UserLexiconEntryOrigin

    init(id: String? = nil, code: InputCode, text: String, fixedRank: Int?,
         createdBy: UserLexiconEntryOrigin) throws {
        let normalized = text.precomposedStringWithCanonicalMapping
        guard !normalized.isEmpty, normalized.count <= Self.maximumCharacters,
              normalized.utf8.count <= Self.maximumUTF8Bytes,
              normalized == normalized.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw UserLexiconError.invalidText
        }
        if let fixedRank, !(0...9_999).contains(fixedRank) {
            throw UserLexiconError.invalidFixedRank
        }
        self.id = id ?? Self.stableID(code: code, text: normalized)
        self.code = code
        self.text = normalized
        self.fixedRank = fixedRank
        self.createdBy = createdBy
    }

    private static func stableID(code: InputCode, text: String) -> String {
        let checksum = DictionaryChecksum.fnv1a64(Data((code.letters + "\0" + text).utf8))
        return String(format: "%016llx", checksum)
    }
}

struct UserLexiconSnapshot: Equatable, Sendable {
    let generation: UInt64
    let entries: [UserLexiconEntry]
}

enum UserLexiconUpsertResult: Equatable, Sendable {
    case added
    case merged
}

final class UserLexiconStore {
    private static let schemaVersion: UInt32 = 1
    private let writer: SnapshotWriter
    private let lock = NSRecursiveLock()
    private var storedSnapshot = UserLexiconSnapshot(generation: 0, entries: [])
    var snapshot: UserLexiconSnapshot {
        lock.lock(); defer { lock.unlock() }
        return storedSnapshot
    }

    init(writer: SnapshotWriter) throws {
        self.writer = writer
        if let stored = try writer.recover(.userLexicon,
                                           supportedSchemaVersions: [Self.schemaVersion]) {
            storedSnapshot = try Self.decode(stored)
        }
    }

    @discardableResult
    func upsert(code: InputCode, text: String, fixedRank: Int?,
                createdBy: UserLexiconEntryOrigin) throws -> UserLexiconUpsertResult {
        lock.lock(); defer { lock.unlock() }
        let proposed = try UserLexiconEntry(code: code, text: text, fixedRank: fixedRank,
                                            createdBy: createdBy)
        var entries = storedSnapshot.entries
        if let index = entries.firstIndex(where: { $0.code == proposed.code && $0.text == proposed.text }) {
            let existing = entries[index]
            let mergedRank: Int?
            switch (existing.fixedRank, proposed.fixedRank) {
            case let (.some(lhs), .some(rhs)): mergedRank = min(lhs, rhs)
            case let (.some(value), .none), let (.none, .some(value)): mergedRank = value
            case (.none, .none): mergedRank = nil
            }
            let origin: UserLexiconEntryOrigin = existing.createdBy == .manual || proposed.createdBy == .manual
                ? .manual : .imported
            entries[index] = try UserLexiconEntry(id: existing.id, code: code, text: proposed.text,
                                                  fixedRank: mergedRank, createdBy: origin)
            try publish(entries)
            return .merged
        }
        entries.append(proposed)
        try publish(entries)
        return .added
    }

    func edit(id: String, code: InputCode, text: String, fixedRank: Int?) throws {
        lock.lock(); defer { lock.unlock() }
        guard let index = storedSnapshot.entries.firstIndex(where: { $0.id == id }) else {
            throw UserLexiconError.entryNotFound
        }
        var entries = storedSnapshot.entries
        let existing = entries[index]
        let edited = try UserLexiconEntry(id: id, code: code, text: text,
                                          fixedRank: fixedRank, createdBy: existing.createdBy)
        if let duplicate = entries.firstIndex(where: {
            $0.id != id && $0.code == edited.code && $0.text == edited.text
        }) {
            entries.remove(at: duplicate)
        }
        guard let refreshedIndex = entries.firstIndex(where: { $0.id == id }) else {
            throw UserLexiconError.entryNotFound
        }
        entries[refreshedIndex] = edited
        try publish(entries)
    }

    @discardableResult
    func delete(id: String) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        var entries = storedSnapshot.entries
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        entries.remove(at: index)
        try publish(entries)
        return true
    }

    func search(_ query: String, limit: Int = 100) -> [UserLexiconEntry] {
        lock.lock(); defer { lock.unlock() }
        guard !query.isEmpty, limit > 0 else { return [] }
        return storedSnapshot.entries.lazy.filter {
            $0.code.letters.localizedCaseInsensitiveContains(query)
                || $0.text.localizedCaseInsensitiveContains(query)
        }.prefix(min(limit, 100)).map { $0 }
    }

    func mergeImported(_ proposed: [UserLexiconEntry]) throws -> (added: Int, merged: Int) {
        lock.lock(); defer { lock.unlock() }
        var entries = storedSnapshot.entries
        var indices = Dictionary(uniqueKeysWithValues: entries.enumerated().map {
            ($0.element.code.letters + "\0" + $0.element.text, $0.offset)
        })
        var added = 0
        var merged = 0
        for item in proposed {
            let key = item.code.letters + "\0" + item.text
            if let index = indices[key] {
                let existing = entries[index]
                let rank: Int?
                switch (existing.fixedRank, item.fixedRank) {
                case let (.some(lhs), .some(rhs)): rank = min(lhs, rhs)
                case let (.some(value), .none), let (.none, .some(value)): rank = value
                case (.none, .none): rank = nil
                }
                entries[index] = try UserLexiconEntry(
                    id: existing.id, code: existing.code, text: existing.text,
                    fixedRank: rank,
                    createdBy: existing.createdBy == .manual ? .manual : item.createdBy
                )
                merged += 1
            } else {
                entries.append(item)
                indices[key] = entries.count - 1
                added += 1
            }
        }
        if added > 0 || merged > 0 { try publish(entries) }
        return (added, merged)
    }

    private func publish(_ entries: [UserLexiconEntry]) throws {
        let ordered = Self.order(entries)
        let generation = storedSnapshot.generation + 1
        let payload = try Self.encode(generation: generation, entries: ordered)
        let envelope = try DataSnapshot(domain: .userLexicon, schemaVersion: Self.schemaVersion,
                                        generation: generation, payload: payload)
        try writer.commit(envelope) { (try? Self.decodePayload($0)) != nil }
        storedSnapshot = UserLexiconSnapshot(generation: generation, entries: ordered)
    }

    private static func order(_ entries: [UserLexiconEntry]) -> [UserLexiconEntry] {
        entries.sorted {
            if $0.code != $1.code { return $0.code < $1.code }
            if $0.fixedRank != $1.fixedRank { return ($0.fixedRank ?? Int.max) < ($1.fixedRank ?? Int.max) }
            return $0.text.utf8.lexicographicallyPrecedes($1.text.utf8)
        }
    }

    private struct Payload: Codable {
        let entries: [Entry]
        struct Entry: Codable {
            let id: String
            let code: String
            let text: String
            let fixedRank: Int?
            let createdBy: UserLexiconEntryOrigin
        }
    }

    private static func encode(generation: UInt64, entries: [UserLexiconEntry]) throws -> Data {
        let payload = Payload(entries: entries.map {
            Payload.Entry(id: $0.id, code: $0.code.letters, text: $0.text,
                          fixedRank: $0.fixedRank, createdBy: $0.createdBy)
        })
        return try JSONEncoder.sorted.encode(payload)
    }

    private static func decode(_ snapshot: DataSnapshot) throws -> UserLexiconSnapshot {
        guard snapshot.schemaVersion == schemaVersion else { throw UserLexiconError.unsupportedSchema }
        return UserLexiconSnapshot(generation: snapshot.generation,
                                   entries: try decodePayload(snapshot.payload))
    }

    private static func decodePayload(_ data: Data) throws -> [UserLexiconEntry] {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw UserLexiconError.corruptPayload
        }
        var unique = Set<String>()
        var entries = [UserLexiconEntry]()
        for item in payload.entries {
            guard let code = InputCode(item.code) else { throw UserLexiconError.corruptPayload }
            let entry = try UserLexiconEntry(id: item.id, code: code, text: item.text,
                                             fixedRank: item.fixedRank, createdBy: item.createdBy)
            guard unique.insert(code.letters + "\0" + entry.text).inserted else {
                throw UserLexiconError.corruptPayload
            }
            entries.append(entry)
        }
        return order(entries)
    }
}

extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
