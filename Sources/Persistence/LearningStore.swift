import Foundation

enum LearningStoreError: Error, Equatable {
    case invalidCandidate
    case invalidAmount
    case corruptPayload
}

struct LearningKey: Equatable, Hashable, Sendable {
    let candidateIdentity: CandidateIdentity

    init(queryKey: CandidateQueryKey, candidateText: String) throws {
        candidateIdentity = try CandidateIdentity(queryKey: queryKey, text: candidateText)
    }

    var queryKey: CandidateQueryKey { candidateIdentity.queryKey }
    var candidateText: String { candidateIdentity.text }
}

struct LearningRecord: Equatable, Hashable, Sendable {
    let key: LearningKey
    let score: Int
    let decayEpoch: UInt64

    init(key: LearningKey, score: Int, decayEpoch: UInt64) {
        self.key = key
        self.score = score
        self.decayEpoch = decayEpoch
    }

    init(code: InputCode, candidateText: String, score: Int, decayEpoch: UInt64) throws {
        key = try LearningKey(queryKey: .wubi(code), candidateText: candidateText)
        self.score = score
        self.decayEpoch = decayEpoch
    }

    var queryKey: CandidateQueryKey { key.queryKey }
    var code: InputCode? { queryKey.wubiCode }
    var candidateText: String { key.candidateText }
}

struct LearningSnapshot: Equatable, Sendable {
    let generation: UInt64
    let records: [LearningRecord]
}

final class LearningStore {
    static let schemaVersion: UInt32 = 2
    private let writer: SnapshotWriter
    private let maxRecords: Int
    private let maximumScore: Int
    private let lock = NSRecursiveLock()
    private var storedSnapshot = LearningSnapshot(generation: 0, records: [])
    var snapshot: LearningSnapshot {
        lock.lock(); defer { lock.unlock() }
        return storedSnapshot
    }
    private var storedIsEnabled = true
    var isEnabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return storedIsEnabled }
        set { lock.lock(); defer { lock.unlock() }; storedIsEnabled = newValue }
    }

    init(writer: SnapshotWriter, maxRecords: Int = 50_000,
         maximumScore: Int = 1_000_000) throws {
        precondition(maxRecords > 0 && maxRecords <= 50_000)
        precondition(maximumScore >= 3 && maximumScore <= 1_000_000)
        self.writer = writer
        self.maxRecords = maxRecords
        self.maximumScore = maximumScore
        if let stored = try writer.recover(.learning,
                                           supportedSchemaVersions: [Self.schemaVersion]) {
            storedSnapshot = try Self.decode(stored, maximumScore: maximumScore,
                                       maxRecords: maxRecords)
        }
    }

    func recordSelection(code: InputCode, candidateText: String, amount: Int = 1) throws {
        try recordSelection(key: LearningKey(queryKey: .wubi(code), candidateText: candidateText),
                            amount: amount)
    }

    func recordSelection(key: LearningKey, amount: Int = 1) throws {
        lock.lock(); defer { lock.unlock() }
        guard storedIsEnabled else { return }
        guard amount > 0 else { throw LearningStoreError.invalidAmount }
        try Self.validate(key.candidateText)
        var records = storedSnapshot.records
        if let index = records.firstIndex(where: { $0.key == key }) {
            let existing = records[index]
            records[index] = LearningRecord(key: key,
                                            score: min(maximumScore, existing.score + amount),
                                            decayEpoch: existing.decayEpoch)
        } else {
            records.append(LearningRecord(key: key,
                                          score: min(maximumScore, amount), decayEpoch: 0))
        }
        records = Self.ordered(records)
        if records.count > maxRecords { records = Array(records.prefix(maxRecords)) }
        try publish(records)
    }

    func score(code: InputCode, candidateText: String) -> Int {
        guard let key = try? LearningKey(queryKey: .wubi(code), candidateText: candidateText) else {
            return 0
        }
        return score(key: key)
    }

    func score(key: LearningKey) -> Int {
        lock.lock(); defer { lock.unlock() }
        return storedSnapshot.records.first { $0.key == key }?.score ?? 0
    }

    func isPromoted(code: InputCode, candidateText: String) -> Bool {
        score(code: code, candidateText: candidateText) >= 3
    }

    func decay(to epoch: UInt64) throws {
        lock.lock(); defer { lock.unlock() }
        var changed = false
        let records = storedSnapshot.records.compactMap { record -> LearningRecord? in
            guard epoch > record.decayEpoch else { return record }
            let steps = min(epoch - record.decayEpoch, 63)
            let score = record.score >> Int(steps)
            changed = true
            return score > 0 ? LearningRecord(key: record.key,
                                              score: score, decayEpoch: epoch) : nil
        }
        if changed { try publish(records) }
    }

    func clear() throws {
        lock.lock(); defer { lock.unlock() }
        try publish([])
    }

    func mergeImported(_ proposed: [LearningRecord]) throws {
        lock.lock(); defer { lock.unlock() }
        var records = storedSnapshot.records
        var indices = Dictionary(uniqueKeysWithValues: records.enumerated().map {
            ($0.element.key, $0.offset)
        })
        for item in proposed {
            try Self.validate(item.candidateText)
            guard item.score > 0, item.score <= maximumScore else {
                throw LearningStoreError.invalidAmount
            }
            if let index = indices[item.key] {
                let existing = records[index]
                records[index] = LearningRecord(key: existing.key,
                                                score: max(existing.score, item.score),
                                                decayEpoch: max(existing.decayEpoch, item.decayEpoch))
            } else {
                records.append(item)
                indices[item.key] = records.count - 1
            }
        }
        guard records.count <= maxRecords else { throw LearningStoreError.corruptPayload }
        if !proposed.isEmpty { try publish(records) }
    }

    private func publish(_ records: [LearningRecord]) throws {
        let ordered = Self.ordered(records)
        let generation = storedSnapshot.generation + 1
        let payload = try Self.encode(ordered)
        try writer.commit(try DataSnapshot(domain: .learning,
                                           schemaVersion: Self.schemaVersion,
                                           generation: generation, payload: payload))
        storedSnapshot = LearningSnapshot(generation: generation, records: ordered)
    }

    private static func ordered(_ records: [LearningRecord]) -> [LearningRecord] {
        records.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.queryKey.kind != $1.queryKey.kind {
                return $0.queryKey.kind.rawValue < $1.queryKey.kind.rawValue
            }
            if $0.queryKey.normalizedCode != $1.queryKey.normalizedCode {
                return $0.queryKey.normalizedCode < $1.queryKey.normalizedCode
            }
            return $0.candidateText.utf8.lexicographicallyPrecedes($1.candidateText.utf8)
        }
    }

    private static func validate(_ text: String) throws {
        guard !text.isEmpty, text.count <= UserLexiconEntry.maximumCharacters,
              text.utf8.count <= UserLexiconEntry.maximumUTF8Bytes,
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw LearningStoreError.invalidCandidate
        }
    }

    private struct Payload: Codable {
        let records: [Record]
        struct Record: Codable {
            let kind: CandidateQueryKind
            let normalizedCode: String
            let candidateText: String
            let score: Int
            let decayEpoch: UInt64
        }
    }

    private struct LegacyPayloadV1: Codable {
        let records: [Record]
        struct Record: Codable {
            let code: String
            let candidateText: String
            let score: Int
            let decayEpoch: UInt64
        }
    }

    private static func encode(_ records: [LearningRecord]) throws -> Data {
        try JSONEncoder.sorted.encode(Payload(records: records.map {
            Payload.Record(kind: $0.queryKey.kind,
                           normalizedCode: $0.queryKey.normalizedCode,
                           candidateText: $0.candidateText,
                           score: $0.score, decayEpoch: $0.decayEpoch)
        }))
    }

    private static func decode(_ snapshot: DataSnapshot, maximumScore: Int,
                               maxRecords: Int) throws -> LearningSnapshot {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: snapshot.payload),
              payload.records.count <= maxRecords else { throw LearningStoreError.corruptPayload }
        var unique = Set<LearningKey>()
        let records = try payload.records.map { item -> LearningRecord in
            guard let queryKey = CandidateQueryKey(kind: item.kind,
                                                   code: item.normalizedCode),
                  (1...maximumScore).contains(item.score) else {
                throw LearningStoreError.corruptPayload
            }
            try validate(item.candidateText)
            let key = try LearningKey(queryKey: queryKey, candidateText: item.candidateText)
            guard unique.insert(key).inserted else {
                throw LearningStoreError.corruptPayload
            }
            return LearningRecord(key: key, score: item.score, decayEpoch: item.decayEpoch)
        }
        return LearningSnapshot(generation: snapshot.generation, records: ordered(records))
    }

    static func migrateV1Payload(_ data: Data) throws -> Data {
        guard let legacy = try? JSONDecoder().decode(LegacyPayloadV1.self, from: data),
              legacy.records.count <= 50_000 else {
            throw LearningStoreError.corruptPayload
        }
        var unique = Set<LearningKey>()
        let records = try legacy.records.map { item -> LearningRecord in
            guard let code = InputCode(item.code), (1...1_000_000).contains(item.score) else {
                throw LearningStoreError.corruptPayload
            }
            try validate(item.candidateText)
            let key = try LearningKey(queryKey: .wubi(code), candidateText: item.candidateText)
            guard unique.insert(key).inserted else { throw LearningStoreError.corruptPayload }
            return LearningRecord(key: key, score: item.score, decayEpoch: item.decayEpoch)
        }
        return try encode(ordered(records))
    }
}
