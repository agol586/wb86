import Foundation

struct LexiconTransferLearning: Equatable, Codable, Sendable {
    let kind: CandidateQueryKind?
    let code: String
    let candidateText: String
    let score: Int
    let decayEpoch: UInt64

    init(kind: CandidateQueryKind? = nil, code: String, candidateText: String,
         score: Int, decayEpoch: UInt64) {
        self.kind = kind
        self.code = code
        self.candidateText = candidateText
        self.score = score
        self.decayEpoch = decayEpoch
    }
}

struct MacWubiArchive: Equatable, Sendable {
    let userLexicon: [LexiconTransferEntry]
    let learning: [LexiconTransferLearning]?
}

enum LexiconArchiveCodec {
    private static let magic = Data("MWARCH01".utf8)
    private static let version: UInt32 = 1
    private static let headerSize = 48
    private static let maximumPayloadBytes = 16 * 1_024 * 1_024

    static func encode(_ archive: MacWubiArchive) throws -> Data {
        let users = try JSONEncoder.sorted.encode(archive.userLexicon)
        let learning = try archive.learning.map { try JSONEncoder.sorted.encode($0) } ?? Data()
        guard users.count <= maximumPayloadBytes, learning.count <= maximumPayloadBytes else {
            throw LexiconCodecError.fileTooLarge
        }
        var data = Data()
        data.append(magic)
        data.mwAppendLittleEndian(version)
        data.mwAppendLittleEndian(UInt32(archive.learning == nil ? 0 : 1))
        data.mwAppendLittleEndian(UInt64(users.count))
        data.mwAppendLittleEndian(DictionaryChecksum.fnv1a64(users))
        data.mwAppendLittleEndian(UInt64(learning.count))
        data.mwAppendLittleEndian(DictionaryChecksum.fnv1a64(learning))
        data.append(users)
        data.append(learning)
        return data
    }

    static func decode(_ data: Data) throws -> MacWubiArchive {
        guard data.count >= headerSize, data.prefix(8) == magic else {
            throw LexiconCodecError.invalidArchive
        }
        let version: UInt32 = try data.mwReadLittleEndian(at: 8)
        guard version == self.version else { throw LexiconCodecError.unsupportedVersion }
        let flags: UInt32 = try data.mwReadLittleEndian(at: 12)
        guard flags & ~1 == 0 else { throw LexiconCodecError.invalidArchive }
        let userLength: UInt64 = try data.mwReadLittleEndian(at: 16)
        let userChecksum: UInt64 = try data.mwReadLittleEndian(at: 24)
        let learningLength: UInt64 = try data.mwReadLittleEndian(at: 32)
        let learningChecksum: UInt64 = try data.mwReadLittleEndian(at: 40)
        guard userLength <= maximumPayloadBytes, learningLength <= maximumPayloadBytes,
              userLength <= UInt64(Int.max), learningLength <= UInt64(Int.max),
              headerSize + Int(userLength) + Int(learningLength) == data.count else {
            throw LexiconCodecError.invalidArchive
        }
        let userStart = headerSize
        let userData = data.subdata(in: userStart..<(userStart + Int(userLength)))
        let learnData = data.suffix(Int(learningLength))
        guard DictionaryChecksum.fnv1a64(userData) == userChecksum,
              DictionaryChecksum.fnv1a64(learnData) == learningChecksum else {
            throw LexiconCodecError.checksumMismatch
        }
        guard let users = try? JSONDecoder().decode([LexiconTransferEntry].self, from: userData),
              users.count <= LexiconTextCodec.maximumRecords else {
            throw LexiconCodecError.invalidRecord
        }
        let learning: [LexiconTransferLearning]?
        if flags & 1 == 1 {
            guard let decoded = try? JSONDecoder().decode([LexiconTransferLearning].self,
                                                          from: Data(learnData)),
                  decoded.count <= 50_000,
                  decoded.allSatisfy({
                      CandidateQueryKey(kind: $0.kind ?? .wubi, code: $0.code) != nil
                          && !$0.candidateText.isEmpty
                          && $0.score > 0 && $0.score <= 1_000_000
                  }) else {
                throw LexiconCodecError.invalidRecord
            }
            learning = decoded
        } else {
            guard learningLength == 0 else { throw LexiconCodecError.invalidArchive }
            learning = nil
        }
        return MacWubiArchive(userLexicon: users, learning: learning)
    }
}

private extension Data {
    mutating func mwAppendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    func mwReadLittleEndian<T: FixedWidthInteger>(at offset: Int) throws -> T {
        guard offset >= 0, offset + MemoryLayout<T>.size <= count else {
            throw LexiconCodecError.invalidArchive
        }
        var value: T = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { target in
            copyBytes(to: target, from: offset..<(offset + MemoryLayout<T>.size))
        }
        return T(littleEndian: value)
    }
}
