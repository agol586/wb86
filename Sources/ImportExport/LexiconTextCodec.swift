import Foundation

struct LexiconTransferEntry: Equatable, Codable, Sendable {
    let code: InputCode
    let text: String
    let fixedRank: Int?

    private enum CodingKeys: String, CodingKey { case code, text, fixedRank }
    init(code: InputCode, text: String, fixedRank: Int?) {
        self.code = code; self.text = text; self.fixedRank = fixedRank
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let code = InputCode(try c.decode(String.self, forKey: .code)) else {
            throw LexiconCodecError.invalidRecord
        }
        let entry = try UserLexiconEntry(code: code, text: c.decode(String.self, forKey: .text),
                                         fixedRank: c.decodeIfPresent(Int.self, forKey: .fixedRank),
                                         createdBy: .imported)
        self.init(code: entry.code, text: entry.text, fixedRank: entry.fixedRank)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(code.letters, forKey: .code)
        try c.encode(text, forKey: .text)
        try c.encodeIfPresent(fixedRank, forKey: .fixedRank)
    }
}

enum LexiconCodecError: Error, Equatable {
    case invalidUTF8
    case unsupportedVersion
    case fileTooLarge
    case lineTooLarge
    case tooManyRecords
    case invalidArchive
    case checksumMismatch
    case invalidRecord
}

struct LexiconTextDecodeResult: Equatable, Sendable {
    let entries: [LexiconTransferEntry]
    let mergedCount: Int
    let skippedCount: Int
    let failedCount: Int
}

enum LexiconTextCodec {
    static let maximumFileBytes = 16 * 1_024 * 1_024
    static let maximumLineBytes = 2_048
    static let maximumRecords = 100_000
    static let header = "# mac-wubi-user-lexicon v1"

    static func decode(_ data: Data) throws -> LexiconTextDecodeResult {
        guard data.count <= maximumFileBytes else { throw LexiconCodecError.fileTooLarge }
        let rawLines = data.split(separator: 0x0a, omittingEmptySubsequences: false)
        var lines = [String]()
        lines.reserveCapacity(rawLines.count)
        for raw in rawLines {
            guard raw.count <= maximumLineBytes else { throw LexiconCodecError.lineTooLarge }
            var bytes = raw
            if bytes.last == 0x0d { bytes = bytes.dropLast() }
            guard let line = String(data: Data(bytes), encoding: .utf8) else {
                throw LexiconCodecError.invalidUTF8
            }
            lines.append(line)
        }
        guard lines.first == header else { throw LexiconCodecError.unsupportedVersion }
        var byKey = [String: LexiconTransferEntry]()
        var merged = 0, skipped = 0, failed = 0, acceptedRecords = 0
        for line in lines.dropFirst() {
            if line.isEmpty { skipped += 1; continue }
            if line.hasPrefix("#") { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard (2...3).contains(fields.count), let code = InputCode(String(fields[0]).lowercased()) else {
                failed += 1; continue
            }
            let rank: Int?
            if fields.count == 3, !fields[2].isEmpty {
                guard let parsed = Int(fields[2]), (0...9_999).contains(parsed) else {
                    failed += 1; continue
                }
                rank = parsed
            } else { rank = nil }
            guard let entry = try? UserLexiconEntry(code: code, text: String(fields[1]),
                                                    fixedRank: rank, createdBy: .imported) else {
                failed += 1; continue
            }
            acceptedRecords += 1
            guard acceptedRecords <= maximumRecords else { throw LexiconCodecError.tooManyRecords }
            let key = code.letters + "\0" + entry.text
            if let prior = byKey[key] {
                let best: Int?
                switch (prior.fixedRank, entry.fixedRank) {
                case let (.some(a), .some(b)): best = min(a, b)
                case let (.some(v), .none), let (.none, .some(v)): best = v
                case (.none, .none): best = nil
                }
                byKey[key] = LexiconTransferEntry(code: code, text: entry.text, fixedRank: best)
                merged += 1
            } else {
                byKey[key] = LexiconTransferEntry(code: code, text: entry.text,
                                                  fixedRank: entry.fixedRank)
            }
        }
        let entries = byKey.values.sorted(by: ordered)
        return LexiconTextDecodeResult(entries: entries, mergedCount: merged,
                                       skippedCount: skipped, failedCount: failed)
    }

    static func encode(_ entries: [LexiconTransferEntry]) throws -> Data {
        let lines = try entries.sorted(by: ordered).map { entry -> String in
            _ = try UserLexiconEntry(code: entry.code, text: entry.text,
                                     fixedRank: entry.fixedRank, createdBy: .imported)
            var fields = [entry.code.letters, entry.text]
            if let rank = entry.fixedRank { fields.append(String(rank)) }
            return fields.joined(separator: "\t")
        }
        return Data(([header] + lines).joined(separator: "\n").appending("\n").utf8)
    }

    private static func ordered(_ lhs: LexiconTransferEntry, _ rhs: LexiconTransferEntry) -> Bool {
        if lhs.code != rhs.code { return lhs.code < rhs.code }
        if lhs.fixedRank != rhs.fixedRank { return (lhs.fixedRank ?? Int.max) < (rhs.fixedRank ?? Int.max) }
        return lhs.text.utf8.lexicographicallyPrecedes(rhs.text.utf8)
    }
}
