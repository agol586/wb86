import Foundation

struct CompositionKeySequence: Equatable, Hashable, Sendable {
    static let maximumLength = 32
    let letters: String

    init?(_ raw: String) {
        let bytes = Array(raw.utf8)
        guard !bytes.isEmpty, bytes.count <= Self.maximumLength else { return nil }
        var normalized = [UInt8]()
        normalized.reserveCapacity(bytes.count)
        for byte in bytes {
            switch byte {
            case 65...90: normalized.append(byte + 32)
            case 97...122: normalized.append(byte)
            default: return nil
            }
        }
        letters = String(decoding: normalized, as: UTF8.self)
    }

    var length: Int { letters.utf8.count }
    var wubiCode: InputCode? { length <= 4 ? InputCode(letters) : nil }
}

enum CompositionRoute: String, Codable, Sendable {
    case invalid
    case wubiOnly
    case pinyinOnly
    case mixed
    case directInput

    static func resolve(sequence: CompositionKeySequence,
                        mixedPinyinEnabled: Bool) -> CompositionRoute {
        let isWubi = sequence.wubiCode != nil
        guard mixedPinyinEnabled else { return isWubi ? .wubiOnly : .invalid }
        return isWubi ? .mixed : .pinyinOnly
    }
}

enum CandidateQueryKind: String, Codable, Sendable {
    case wubi
    case pinyin
    case directInput
}

struct CandidateQueryKey: Equatable, Hashable, Codable, Sendable {
    let kind: CandidateQueryKind
    let normalizedCode: String

    init?(kind: CandidateQueryKind, code: String) {
        if kind == .directInput {
            guard !code.isEmpty, code.utf8.count <= 1_024,
                  !code.unicodeScalars.contains(where: {
                      CharacterSet.controlCharacters.contains($0)
                  }) else { return nil }
            self.kind = kind
            normalizedCode = code
            return
        }
        guard let sequence = CompositionKeySequence(code) else { return nil }
        if kind == .wubi, sequence.wubiCode == nil { return nil }
        self.kind = kind
        normalizedCode = sequence.letters
    }

    static func wubi(_ code: InputCode) -> CandidateQueryKey {
        CandidateQueryKey(kind: .wubi, code: code.letters)!
    }

    var wubiCode: InputCode? { kind == .wubi ? InputCode(normalizedCode) : nil }
}

enum CandidateIdentityError: Error, Equatable { case emptyText }

struct CandidateIdentity: Equatable, Hashable, Sendable {
    let queryKey: CandidateQueryKey
    let text: String

    init(queryKey: CandidateQueryKey, text: String) throws {
        guard !text.isEmpty else { throw CandidateIdentityError.emptyText }
        self.queryKey = queryKey
        self.text = text
    }
}
