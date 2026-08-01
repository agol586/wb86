import Foundation

enum ScriptConversionError: Error, Equatable {
    case invalidHeader
    case unsupportedVersion
    case invalidBounds
    case checksumMismatch
    case invalidUTF8
    case invalidRecord
}

struct ScriptConverter: Sendable {
    private static let headerSize = 40
    private static let recordSize = 16
    private static let maximumRecords = 100_000
    private static let maximumStringBytes = 16 * 1_024 * 1_024

    private let image: Data
    private let recordCount: Int
    private let recordOffset: Int
    private let stringOffset: Int
    private let stringLength: Int
    private let maximumSourceLength: Int

    init(data: Data) throws {
        guard data.count >= Self.headerSize,
              data.prefix(4) == Data("MWSC".utf8) else {
            throw ScriptConversionError.invalidHeader
        }
        guard try data.readUInt16(at: 4) == 1 else {
            throw ScriptConversionError.unsupportedVersion
        }
        let headerSize = Int(try data.readUInt16(at: 6))
        let recordCount = Int(try data.readUInt32(at: 8))
        let recordOffset = Int(try data.readUInt32(at: 12))
        let stringOffset = Int(try data.readUInt32(at: 16))
        let stringLength = Int(try data.readUInt32(at: 20))
        let checksum = try data.readUInt64(at: 24)
        let totalLength = Int(try data.readUInt32(at: 32))
        let declaredMaximum = Int(try data.readUInt32(at: 36))

        let recordsLength = recordCount.multipliedReportingOverflow(by: Self.recordSize)
        guard headerSize == Self.headerSize,
              recordCount <= Self.maximumRecords,
              !recordsLength.overflow,
              recordOffset == headerSize,
              stringOffset == recordOffset + recordsLength.partialValue,
              stringLength <= Self.maximumStringBytes,
              totalLength == stringOffset + stringLength,
              totalLength == data.count,
              declaredMaximum <= 64 else {
            throw ScriptConversionError.invalidBounds
        }
        guard DictionaryChecksum.fnv1a64(data.subdata(in: recordOffset..<totalLength)) == checksum else {
            throw ScriptConversionError.checksumMismatch
        }

        var previousSource: [UInt8]?
        var actualMaximum = 0
        for index in 0..<recordCount {
            let offset = recordOffset + index * Self.recordSize
            let source = try Self.readString(data, recordAt: offset, fieldOffset: 0,
                                             stringsAt: stringOffset, stringsLength: stringLength)
            let target = try Self.readString(data, recordAt: offset, fieldOffset: 8,
                                             stringsAt: stringOffset, stringsLength: stringLength)
            let sourceBytes = Array(source.utf8)
            guard !source.isEmpty, !target.isEmpty, source.count <= 64,
                  previousSource.map({ $0.lexicographicallyPrecedes(sourceBytes) }) ?? true else {
                throw ScriptConversionError.invalidRecord
            }
            previousSource = sourceBytes
            actualMaximum = max(actualMaximum, source.count)
        }
        guard actualMaximum == declaredMaximum else { throw ScriptConversionError.invalidRecord }
        image = data
        self.recordCount = recordCount
        self.recordOffset = recordOffset
        self.stringOffset = stringOffset
        self.stringLength = stringLength
        maximumSourceLength = actualMaximum
    }

    func convert(_ text: String, to script: OutputScript) -> String {
        guard script == .traditional, !text.isEmpty, maximumSourceLength > 0 else { return text }
        var output = ""
        var start = text.startIndex
        while start < text.endIndex {
            let remaining = text.distance(from: start, to: text.endIndex)
            let attemptLength = min(maximumSourceLength, remaining)
            var match: (String.Index, String)?
            if attemptLength > 0 {
                for length in stride(from: attemptLength, through: 1, by: -1) {
                    let end = text.index(start, offsetBy: length)
                    if let replacement = lookup(String(text[start..<end])) {
                        match = (end, replacement)
                        break
                    }
                }
            }
            if let match {
                output.append(match.1)
                start = match.0
            } else {
                let next = text.index(after: start)
                output.append(contentsOf: text[start..<next])
                start = next
            }
        }
        return output
    }

    private func lookup(_ source: String) -> String? {
        let query = Data(source.utf8)
        var lowerBound = 0
        var upperBound = recordCount
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            let offset = recordOffset + middle * Self.recordSize
            guard let candidate = try? Self.readBytes(
                image,
                recordAt: offset,
                fieldOffset: 0,
                stringsAt: stringOffset,
                stringsLength: stringLength
            ) else { return nil }
            if candidate == query {
                guard let target = try? Self.readBytes(
                    image,
                    recordAt: offset,
                    fieldOffset: 8,
                    stringsAt: stringOffset,
                    stringsLength: stringLength
                ) else { return nil }
                return String(data: target, encoding: .utf8)
            }
            if candidate.lexicographicallyPrecedes(query) {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return nil
    }

    func convert(_ candidate: Candidate, to script: OutputScript) throws -> Candidate {
        try Candidate(text: convert(candidate.text, to: script), code: candidate.code,
                      source: candidate.source, baseRank: candidate.baseRank,
                      learnedScore: candidate.learnedScore, ordinal: candidate.ordinal)
    }

    func convert(_ page: CandidatePage, to script: OutputScript) throws -> CandidatePage {
        try CandidatePage(items: page.items.map { try convert($0, to: script) },
                          pageIndex: page.pageIndex, pageSize: page.pageSize,
                          totalCount: page.totalCount)
    }

    private static func readString(_ data: Data, recordAt recordOffset: Int,
                                   fieldOffset: Int, stringsAt stringOffset: Int,
                                   stringsLength: Int) throws -> String {
        let bytes = try readBytes(data, recordAt: recordOffset, fieldOffset: fieldOffset,
                                  stringsAt: stringOffset, stringsLength: stringsLength)
        guard let value = String(data: bytes, encoding: .utf8) else {
            throw ScriptConversionError.invalidUTF8
        }
        return value
    }

    private static func readBytes(_ data: Data, recordAt recordOffset: Int,
                                  fieldOffset: Int, stringsAt stringOffset: Int,
                                  stringsLength: Int) throws -> Data {
        let relativeOffset = Int(try data.readUInt32(at: recordOffset + fieldOffset))
        let length = Int(try data.readUInt32(at: recordOffset + fieldOffset + 4))
        let end = relativeOffset.addingReportingOverflow(length)
        guard !end.overflow, relativeOffset <= stringsLength, end.partialValue <= stringsLength else {
            throw ScriptConversionError.invalidBounds
        }
        return data.subdata(in: (stringOffset + relativeOffset)..<(stringOffset + end.partialValue))
    }
}

private extension Data {
    func readUInt16(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { throw ScriptConversionError.invalidBounds }
        return withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
        }
    }

    func readUInt32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { throw ScriptConversionError.invalidBounds }
        return withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            let low = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
            let high = UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
            return low | high
        }
    }

    func readUInt64(at offset: Int) throws -> UInt64 {
        guard offset >= 0, offset + 8 <= count else { throw ScriptConversionError.invalidBounds }
        return withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var value: UInt64 = 0
            for index in 0..<8 { value |= UInt64(bytes[offset + index]) << UInt64(index * 8) }
            return value
        }
    }
}
