import Foundation

enum DataDomain: UInt8, CaseIterable, Codable, Sendable {
    case settings = 1
    case userLexicon = 2
    case learning = 3

    var directoryName: String {
        switch self {
        case .settings: return "Settings"
        case .userLexicon: return "UserLexicon"
        case .learning: return "Learning"
        }
    }
}

enum DataSnapshotError: Error, Equatable {
    case invalidSchemaVersion
    case invalidGeneration
    case payloadTooLarge
    case invalidHeader
    case unsupportedEnvelopeVersion
    case invalidDomain
    case invalidLength
    case checksumMismatch
}

struct DataSnapshot: Equatable, Sendable {
    static let maximumPayloadBytes = 16 * 1_024 * 1_024
    private static let headerSize = 32

    let domain: DataDomain
    let schemaVersion: UInt32
    let generation: UInt64
    let payload: Data

    init(domain: DataDomain, schemaVersion: UInt32, generation: UInt64,
         payload: Data) throws {
        guard schemaVersion > 0 else { throw DataSnapshotError.invalidSchemaVersion }
        guard generation > 0 else { throw DataSnapshotError.invalidGeneration }
        guard payload.count <= Self.maximumPayloadBytes else {
            throw DataSnapshotError.payloadTooLarge
        }
        self.domain = domain
        self.schemaVersion = schemaVersion
        self.generation = generation
        self.payload = payload
    }

    func encoded() -> Data {
        var data = Data("MWSN".utf8)
        data.appendLE(UInt16(1))
        data.append(domain.rawValue)
        data.append(0)
        data.appendLE(schemaVersion)
        data.appendLE(generation)
        data.appendLE(UInt32(payload.count))
        data.appendLE(DictionaryChecksum.fnv1a64(payload))
        data.append(payload)
        return data
    }

    static func decode(_ data: Data) throws -> DataSnapshot {
        guard data.count >= headerSize, data.prefix(4) == Data("MWSN".utf8) else {
            throw DataSnapshotError.invalidHeader
        }
        guard try data.integer(UInt16.self, at: 4) == 1 else {
            throw DataSnapshotError.unsupportedEnvelopeVersion
        }
        guard let domain = DataDomain(rawValue: data[6]) else {
            throw DataSnapshotError.invalidDomain
        }
        let schema = try data.integer(UInt32.self, at: 8)
        let generation = try data.integer(UInt64.self, at: 12)
        let payloadLength = Int(try data.integer(UInt32.self, at: 20))
        let checksum = try data.integer(UInt64.self, at: 24)
        guard payloadLength <= maximumPayloadBytes,
              headerSize + payloadLength == data.count else {
            throw DataSnapshotError.invalidLength
        }
        let payload = data.subdata(in: headerSize..<data.count)
        guard DictionaryChecksum.fnv1a64(payload) == checksum else {
            throw DataSnapshotError.checksumMismatch
        }
        return try DataSnapshot(domain: domain, schemaVersion: schema,
                                generation: generation, payload: payload)
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    func integer<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) throws -> T {
        let width = MemoryLayout<T>.size
        guard offset >= 0, offset + width <= count else { throw DataSnapshotError.invalidLength }
        var value: T = 0
        for index in 0..<width {
            value |= T(self[offset + index]) << T(index * 8)
        }
        return value
    }
}
