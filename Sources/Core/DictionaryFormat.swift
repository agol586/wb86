import Foundation

enum DictionaryFormatError: Error, Equatable {
    case invalidMagic
    case unsupportedVersion
    case invalidHeader
    case invalidBounds
    case checksumMismatch
    case invalidPrefixRanges
    case invalidRecord
    case invalidOrdering
    case invalidUTF8
}

struct DictionaryHeaderV1: Equatable, Sendable {
    static let byteCount = 64
    static let schemaVersion: UInt16 = 1
    static let checksumByteCount = 8
    static let prefixCount = 650

    let magic: String
    let schemaVersion: UInt16
    let buildIdentifier: UInt64
    let prefixOffset: UInt32
    let prefixCount: UInt32
    let recordOffset: UInt32
    let recordCount: UInt32
    let stringOffset: UInt32
    let stringLength: UInt32
    let checksumOffset: UInt32
    let totalLength: UInt64
}

struct DictionaryPrefixRange: Equatable, Sendable {
    static let byteCount = 8

    let start: UInt32
    let end: UInt32
}

struct DictionaryEntryRecord: Equatable, Sendable {
    static let byteCount = 24

    let code: InputCode
    let rank: UInt32
    let text: String

    init(code: InputCode, rank: UInt32, text: String) throws {
        guard !text.isEmpty else { throw DictionaryFormatError.invalidRecord }
        self.code = code
        self.rank = rank
        self.text = text
    }
}

struct DecodedDictionaryV1: Equatable, Sendable {
    let header: DictionaryHeaderV1
    let prefixRanges: [DictionaryPrefixRange]
    let records: [DictionaryEntryRecord]
}

enum DictionaryChecksum {
    static func fnv1a64(_ data: Data) -> UInt64 {
        data.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { partial, byte in
            (partial ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
    }

    static func fnv1a64(_ data: Data, in range: Range<Int>) -> UInt64 {
        range.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { partial, index in
            (partial ^ UInt64(data[index])) &* 0x0000_0100_0000_01b3
        }
    }
}

enum DictionaryFormatV1 {
    private static let magic = Data("WB86".utf8)

    static func encode(records: [DictionaryEntryRecord], buildIdentifier: UInt64) throws -> Data {
        try validateOrdering(records)

        let prefixOffset = DictionaryHeaderV1.byteCount
        let recordOffset = try checkedAdd(
            prefixOffset,
            try checkedMultiply(DictionaryHeaderV1.prefixCount, DictionaryPrefixRange.byteCount)
        )
        let stringOffset = try checkedAdd(
            recordOffset,
            try checkedMultiply(records.count, DictionaryEntryRecord.byteCount)
        )

        var stringBlob = Data()
        var stringReferences = [(offset: UInt32, length: UInt32)]()
        stringReferences.reserveCapacity(records.count)
        for record in records {
            let bytes = Data(record.text.utf8)
            guard !bytes.isEmpty,
                  let offset = UInt32(exactly: try checkedAdd(stringOffset, stringBlob.count)),
                  let length = UInt32(exactly: bytes.count) else {
                throw DictionaryFormatError.invalidBounds
            }
            stringReferences.append((offset, length))
            stringBlob.append(bytes)
        }

        let checksumOffset = try checkedAdd(stringOffset, stringBlob.count)
        let totalLength = try checkedAdd(checksumOffset, DictionaryHeaderV1.checksumByteCount)
        guard let prefixOffset32 = UInt32(exactly: prefixOffset),
              let recordOffset32 = UInt32(exactly: recordOffset),
              let recordCount32 = UInt32(exactly: records.count),
              let stringOffset32 = UInt32(exactly: stringOffset),
              let stringLength32 = UInt32(exactly: stringBlob.count),
              let checksumOffset32 = UInt32(exactly: checksumOffset) else {
            throw DictionaryFormatError.invalidBounds
        }

        let ranges = makePrefixRanges(records: records)
        var image = Data()
        image.append(magic)
        image.appendLittleEndian(DictionaryHeaderV1.schemaVersion)
        image.appendLittleEndian(UInt16(DictionaryHeaderV1.byteCount))
        image.appendLittleEndian(buildIdentifier)
        image.appendLittleEndian(prefixOffset32)
        image.appendLittleEndian(UInt32(DictionaryHeaderV1.prefixCount))
        image.appendLittleEndian(recordOffset32)
        image.appendLittleEndian(recordCount32)
        image.appendLittleEndian(stringOffset32)
        image.appendLittleEndian(stringLength32)
        image.appendLittleEndian(checksumOffset32)
        image.appendLittleEndian(UInt16(DictionaryHeaderV1.checksumByteCount))
        image.appendLittleEndian(UInt16(0))
        image.appendLittleEndian(UInt64(totalLength))
        image.appendLittleEndian(UInt64(0))
        guard image.count == DictionaryHeaderV1.byteCount else {
            throw DictionaryFormatError.invalidHeader
        }

        for range in ranges {
            image.appendLittleEndian(range.start)
            image.appendLittleEndian(range.end)
        }
        for (index, record) in records.enumerated() {
            image.appendLittleEndian(record.code.packedValue)
            image.append(UInt8(record.code.length))
            image.append(contentsOf: [0, 0, 0])
            image.appendLittleEndian(record.rank)
            image.appendLittleEndian(stringReferences[index].offset)
            image.appendLittleEndian(stringReferences[index].length)
            image.appendLittleEndian(UInt32(0))
        }
        image.append(stringBlob)
        let checksum = DictionaryChecksum.fnv1a64(image.subdata(
            in: DictionaryHeaderV1.byteCount..<checksumOffset
        ))
        image.appendLittleEndian(checksum)
        return image
    }

    static func decode(_ image: Data) throws -> DecodedDictionaryV1 {
        guard image.count >= DictionaryHeaderV1.byteCount + DictionaryHeaderV1.checksumByteCount else {
            throw DictionaryFormatError.invalidBounds
        }
        guard image.prefix(4) == magic else { throw DictionaryFormatError.invalidMagic }
        let version: UInt16 = try image.readLittleEndian(at: 4)
        guard version == DictionaryHeaderV1.schemaVersion else {
            throw DictionaryFormatError.unsupportedVersion
        }
        let headerSize: UInt16 = try image.readLittleEndian(at: 6)
        let buildIdentifier: UInt64 = try image.readLittleEndian(at: 8)
        let prefixOffset: UInt32 = try image.readLittleEndian(at: 16)
        let prefixCount: UInt32 = try image.readLittleEndian(at: 20)
        let recordOffset: UInt32 = try image.readLittleEndian(at: 24)
        let recordCount: UInt32 = try image.readLittleEndian(at: 28)
        let stringOffset: UInt32 = try image.readLittleEndian(at: 32)
        let stringLength: UInt32 = try image.readLittleEndian(at: 36)
        let checksumOffset: UInt32 = try image.readLittleEndian(at: 40)
        let checksumLength: UInt16 = try image.readLittleEndian(at: 44)
        let reserved: UInt16 = try image.readLittleEndian(at: 46)
        let totalLength: UInt64 = try image.readLittleEndian(at: 48)
        let trailingReserved: UInt64 = try image.readLittleEndian(at: 56)

        guard headerSize == DictionaryHeaderV1.byteCount,
              prefixCount == DictionaryHeaderV1.prefixCount,
              checksumLength == DictionaryHeaderV1.checksumByteCount,
              reserved == 0, trailingReserved == 0 else {
            throw DictionaryFormatError.invalidHeader
        }

        let expectedRecordOffset = try checkedAdd(
            Int(prefixOffset),
            try checkedMultiply(Int(prefixCount), DictionaryPrefixRange.byteCount)
        )
        let expectedStringOffset = try checkedAdd(
            Int(recordOffset),
            try checkedMultiply(Int(recordCount), DictionaryEntryRecord.byteCount)
        )
        let expectedChecksumOffset = try checkedAdd(Int(stringOffset), Int(stringLength))
        let expectedTotalLength = try checkedAdd(Int(checksumOffset), Int(checksumLength))
        guard prefixOffset == DictionaryHeaderV1.byteCount,
              Int(recordOffset) == expectedRecordOffset,
              Int(stringOffset) == expectedStringOffset,
              Int(checksumOffset) == expectedChecksumOffset,
              UInt64(expectedTotalLength) == totalLength,
              expectedTotalLength == image.count else {
            throw DictionaryFormatError.invalidBounds
        }

        let storedChecksum: UInt64 = try image.readLittleEndian(at: Int(checksumOffset))
        let actualChecksum = DictionaryChecksum.fnv1a64(image.subdata(
            in: DictionaryHeaderV1.byteCount..<Int(checksumOffset)
        ))
        guard storedChecksum == actualChecksum else { throw DictionaryFormatError.checksumMismatch }

        var ranges = [DictionaryPrefixRange]()
        ranges.reserveCapacity(Int(prefixCount))
        for index in 0..<Int(prefixCount) {
            let offset = Int(prefixOffset) + index * DictionaryPrefixRange.byteCount
            let start: UInt32 = try image.readLittleEndian(at: offset)
            let end: UInt32 = try image.readLittleEndian(at: offset + 4)
            guard start <= end, end <= recordCount else {
                throw DictionaryFormatError.invalidPrefixRanges
            }
            ranges.append(DictionaryPrefixRange(start: start, end: end))
        }

        var records = [DictionaryEntryRecord]()
        records.reserveCapacity(Int(recordCount))
        for index in 0..<Int(recordCount) {
            let offset = Int(recordOffset) + index * DictionaryEntryRecord.byteCount
            let packed: UInt32 = try image.readLittleEndian(at: offset)
            let length = Int(image[offset + 4])
            guard image[offset + 5] == 0, image[offset + 6] == 0, image[offset + 7] == 0,
                  let code = InputCode(packedValue: packed, length: length) else {
                throw DictionaryFormatError.invalidRecord
            }
            let rank: UInt32 = try image.readLittleEndian(at: offset + 8)
            let textOffset: UInt32 = try image.readLittleEndian(at: offset + 12)
            let textLength: UInt32 = try image.readLittleEndian(at: offset + 16)
            let recordReserved: UInt32 = try image.readLittleEndian(at: offset + 20)
            let textEnd = try checkedAdd(Int(textOffset), Int(textLength))
            guard recordReserved == 0, textLength > 0,
                  textOffset >= stringOffset, textEnd <= Int(checksumOffset) else {
                throw DictionaryFormatError.invalidRecord
            }
            let textData = image.subdata(in: Int(textOffset)..<textEnd)
            guard let text = String(data: textData, encoding: .utf8), !text.isEmpty else {
                throw DictionaryFormatError.invalidUTF8
            }
            records.append(try DictionaryEntryRecord(code: code, rank: rank, text: text))
        }
        try validateOrdering(records)
        guard ranges == makePrefixRanges(records: records) else {
            throw DictionaryFormatError.invalidPrefixRanges
        }

        return DecodedDictionaryV1(
            header: DictionaryHeaderV1(
                magic: "WB86",
                schemaVersion: version,
                buildIdentifier: buildIdentifier,
                prefixOffset: prefixOffset,
                prefixCount: prefixCount,
                recordOffset: recordOffset,
                recordCount: recordCount,
                stringOffset: stringOffset,
                stringLength: stringLength,
                checksumOffset: checksumOffset,
                totalLength: totalLength
            ),
            prefixRanges: ranges,
            records: records
        )
    }

    /// Validates a mapped product dictionary without materializing all records. Runtime lookup decodes
    /// only the requested candidates, keeping the complete-record decode available for compiler tests.
    static func validateMappedImage(_ image: Data) throws
        -> (header: DictionaryHeaderV1, prefixRanges: [DictionaryPrefixRange]) {
        guard image.count >= DictionaryHeaderV1.byteCount + DictionaryHeaderV1.checksumByteCount else {
            throw DictionaryFormatError.invalidBounds
        }
        guard image.prefix(4) == magic else { throw DictionaryFormatError.invalidMagic }
        let version: UInt16 = try image.readLittleEndian(at: 4)
        guard version == DictionaryHeaderV1.schemaVersion else {
            throw DictionaryFormatError.unsupportedVersion
        }
        let headerSize: UInt16 = try image.readLittleEndian(at: 6)
        let buildIdentifier: UInt64 = try image.readLittleEndian(at: 8)
        let prefixOffset: UInt32 = try image.readLittleEndian(at: 16)
        let prefixCount: UInt32 = try image.readLittleEndian(at: 20)
        let recordOffset: UInt32 = try image.readLittleEndian(at: 24)
        let recordCount: UInt32 = try image.readLittleEndian(at: 28)
        let stringOffset: UInt32 = try image.readLittleEndian(at: 32)
        let stringLength: UInt32 = try image.readLittleEndian(at: 36)
        let checksumOffset: UInt32 = try image.readLittleEndian(at: 40)
        let checksumLength: UInt16 = try image.readLittleEndian(at: 44)
        let reserved: UInt16 = try image.readLittleEndian(at: 46)
        let totalLength: UInt64 = try image.readLittleEndian(at: 48)
        let trailingReserved: UInt64 = try image.readLittleEndian(at: 56)

        guard headerSize == DictionaryHeaderV1.byteCount,
              prefixCount == DictionaryHeaderV1.prefixCount,
              checksumLength == DictionaryHeaderV1.checksumByteCount,
              reserved == 0, trailingReserved == 0 else {
            throw DictionaryFormatError.invalidHeader
        }
        let expectedRecordOffset = try checkedAdd(
            Int(prefixOffset),
            try checkedMultiply(Int(prefixCount), DictionaryPrefixRange.byteCount)
        )
        let expectedStringOffset = try checkedAdd(
            Int(recordOffset),
            try checkedMultiply(Int(recordCount), DictionaryEntryRecord.byteCount)
        )
        let expectedChecksumOffset = try checkedAdd(Int(stringOffset), Int(stringLength))
        let expectedTotalLength = try checkedAdd(Int(checksumOffset), Int(checksumLength))
        guard prefixOffset == DictionaryHeaderV1.byteCount,
              Int(recordOffset) == expectedRecordOffset,
              Int(stringOffset) == expectedStringOffset,
              Int(checksumOffset) == expectedChecksumOffset,
              UInt64(expectedTotalLength) == totalLength,
              expectedTotalLength == image.count else {
            throw DictionaryFormatError.invalidBounds
        }

        let storedChecksum: UInt64 = try image.readLittleEndian(at: Int(checksumOffset))
        let actualChecksum = DictionaryChecksum.fnv1a64(
            image, in: DictionaryHeaderV1.byteCount..<Int(checksumOffset)
        )
        guard storedChecksum == actualChecksum else { throw DictionaryFormatError.checksumMismatch }

        var ranges = [DictionaryPrefixRange]()
        ranges.reserveCapacity(Int(prefixCount))
        for index in 0..<Int(prefixCount) {
            let offset = Int(prefixOffset) + index * DictionaryPrefixRange.byteCount
            let start: UInt32 = try image.readLittleEndian(at: offset)
            let end: UInt32 = try image.readLittleEndian(at: offset + 4)
            guard start <= end, end <= recordCount else {
                throw DictionaryFormatError.invalidPrefixRanges
            }
            ranges.append(DictionaryPrefixRange(start: start, end: end))
        }

        let header = DictionaryHeaderV1(
            magic: "WB86", schemaVersion: version, buildIdentifier: buildIdentifier,
            prefixOffset: prefixOffset, prefixCount: prefixCount,
            recordOffset: recordOffset, recordCount: recordCount,
            stringOffset: stringOffset, stringLength: stringLength,
            checksumOffset: checksumOffset, totalLength: totalLength
        )
        var observed = Array(
            repeating: DictionaryPrefixRange(start: recordCount, end: recordCount),
            count: DictionaryHeaderV1.prefixCount
        )
        var previous: MappedRecord?
        for index in 0..<Int(recordCount) {
            let record = try decodeMappedRecord(in: image, header: header, index: index)
            if let previous {
                guard mappedRecordPrecedes(previous, record, in: image) else {
                    throw DictionaryFormatError.invalidOrdering
                }
                guard previous.packedCode != record.packedCode
                        || !equalText(previous, record, in: image) else {
                    throw DictionaryFormatError.invalidRecord
                }
            }
            notePrefixRanges(for: record, recordIndex: UInt32(index), in: &observed)
            previous = record
        }
        guard ranges == observed else { throw DictionaryFormatError.invalidPrefixRanges }
        return (header, ranges)
    }

    private struct MappedRecord {
        let packedCode: UInt32
        let codeLength: Int
        let rank: UInt32
        let textRange: Range<Int>
    }

    private static func decodeMappedRecord(in image: Data, header: DictionaryHeaderV1,
                                           index: Int) throws -> MappedRecord {
        let offset = Int(header.recordOffset) + index * DictionaryEntryRecord.byteCount
        let packed: UInt32 = try image.readLittleEndian(at: offset)
        let length = Int(image[offset + 4])
        guard image[offset + 5] == 0, image[offset + 6] == 0, image[offset + 7] == 0,
              let code = InputCode(packedValue: packed, length: length) else {
            throw DictionaryFormatError.invalidRecord
        }
        let rank: UInt32 = try image.readLittleEndian(at: offset + 8)
        let textOffset: UInt32 = try image.readLittleEndian(at: offset + 12)
        let textLength: UInt32 = try image.readLittleEndian(at: offset + 16)
        let recordReserved: UInt32 = try image.readLittleEndian(at: offset + 20)
        let textEnd = try checkedAdd(Int(textOffset), Int(textLength))
        guard recordReserved == 0, textLength > 0,
              textOffset >= header.stringOffset, textEnd <= Int(header.checksumOffset) else {
            throw DictionaryFormatError.invalidRecord
        }
        let textRange = Int(textOffset)..<textEnd
        guard isValidUTF8(image, in: textRange) else { throw DictionaryFormatError.invalidUTF8 }
        return MappedRecord(packedCode: code.packedValue, codeLength: length,
                            rank: rank, textRange: textRange)
    }

    private static func notePrefixRanges(for record: MappedRecord, recordIndex: UInt32,
                                         in ranges: inout [DictionaryPrefixRange]) {
        let first = Int((record.packedCode >> 15) & 0x1f) - 1
        noteRange(first, recordIndex: recordIndex, in: &ranges)
        if record.codeLength >= 2 {
            let second = 25 + first * 25 + Int((record.packedCode >> 10) & 0x1f) - 1
            noteRange(second, recordIndex: recordIndex, in: &ranges)
        }
    }

    private static func noteRange(_ rangeIndex: Int, recordIndex: UInt32,
                                  in ranges: inout [DictionaryPrefixRange]) {
        let current = ranges[rangeIndex]
        ranges[rangeIndex] = DictionaryPrefixRange(
            start: current.start == current.end ? recordIndex : current.start,
            end: recordIndex + 1
        )
    }

    private static func mappedRecordPrecedes(_ lhs: MappedRecord, _ rhs: MappedRecord,
                                             in image: Data) -> Bool {
        if lhs.packedCode != rhs.packedCode { return lhs.packedCode < rhs.packedCode }
        if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
        return lexicographicallyPrecedes(image, lhs.textRange, rhs.textRange)
    }

    private static func equalText(_ lhs: MappedRecord, _ rhs: MappedRecord,
                                  in image: Data) -> Bool {
        guard lhs.textRange.count == rhs.textRange.count else { return false }
        return zip(lhs.textRange, rhs.textRange).allSatisfy { image[$0] == image[$1] }
    }

    private static func lexicographicallyPrecedes(_ data: Data, _ lhs: Range<Int>,
                                                  _ rhs: Range<Int>) -> Bool {
        var left = lhs.lowerBound
        var right = rhs.lowerBound
        while left < lhs.upperBound, right < rhs.upperBound {
            if data[left] != data[right] { return data[left] < data[right] }
            left += 1
            right += 1
        }
        return lhs.count < rhs.count
    }

    private static func isValidUTF8(_ data: Data, in range: Range<Int>) -> Bool {
        var index = range.lowerBound
        while index < range.upperBound {
            let first = data[index]
            if first <= 0x7f { index += 1; continue }

            let length: Int
            let secondRange: ClosedRange<UInt8>
            switch first {
            case 0xc2...0xdf: length = 2; secondRange = 0x80...0xbf
            case 0xe0: length = 3; secondRange = 0xa0...0xbf
            case 0xe1...0xec, 0xee...0xef: length = 3; secondRange = 0x80...0xbf
            case 0xed: length = 3; secondRange = 0x80...0x9f
            case 0xf0: length = 4; secondRange = 0x90...0xbf
            case 0xf1...0xf3: length = 4; secondRange = 0x80...0xbf
            case 0xf4: length = 4; secondRange = 0x80...0x8f
            default: return false
            }
            guard index + length <= range.upperBound,
                  secondRange.contains(data[index + 1]) else { return false }
            if length > 2 {
                for continuation in (index + 2)..<(index + length) {
                    guard (0x80...0xbf).contains(data[continuation]) else { return false }
                }
            }
            index += length
        }
        return true
    }

    static func replaceChecksum(in image: inout Data) {
        guard image.count >= DictionaryHeaderV1.byteCount,
              let checksumOffset: UInt32 = try? image.readLittleEndian(at: 40),
              Int(checksumOffset) + DictionaryHeaderV1.checksumByteCount <= image.count else { return }
        let checksum = DictionaryChecksum.fnv1a64(image.subdata(
            in: DictionaryHeaderV1.byteCount..<Int(checksumOffset)
        ))
        image.replaceSubrange(
            Int(checksumOffset)..<(Int(checksumOffset) + DictionaryHeaderV1.checksumByteCount),
            with: checksum.littleEndianBytes
        )
    }

    private static func validateOrdering(_ records: [DictionaryEntryRecord]) throws {
        for index in records.indices.dropFirst() {
            let previous = records[index - 1]
            let current = records[index]
            if compare(previous, current) != .orderedAscending {
                throw DictionaryFormatError.invalidOrdering
            }
            if previous.code == current.code, previous.text == current.text {
                throw DictionaryFormatError.invalidRecord
            }
        }
    }

    private static func compare(_ lhs: DictionaryEntryRecord,
                                _ rhs: DictionaryEntryRecord) -> ComparisonResult {
        if lhs.code.packedValue != rhs.code.packedValue {
            return lhs.code.packedValue < rhs.code.packedValue ? .orderedAscending : .orderedDescending
        }
        if lhs.rank != rhs.rank {
            return lhs.rank < rhs.rank ? .orderedAscending : .orderedDescending
        }
        if lhs.text == rhs.text { return .orderedSame }
        return lhs.text.utf8.lexicographicallyPrecedes(rhs.text.utf8)
            ? .orderedAscending : .orderedDescending
    }

    private static func makePrefixRanges(records: [DictionaryEntryRecord]) -> [DictionaryPrefixRange] {
        var prefixes = [String]()
        prefixes.reserveCapacity(DictionaryHeaderV1.prefixCount)
        for first in UInt8(ascii: "a")...UInt8(ascii: "y") {
            prefixes.append(String(UnicodeScalar(first)))
        }
        for first in UInt8(ascii: "a")...UInt8(ascii: "y") {
            for second in UInt8(ascii: "a")...UInt8(ascii: "y") {
                prefixes.append(String(decoding: [first, second], as: UTF8.self))
            }
        }
        return prefixes.map { prefix in
            let start = records.firstIndex(where: { $0.code.letters.hasPrefix(prefix) }) ?? records.count
            let end = records[start...].firstIndex(where: { !$0.code.letters.hasPrefix(prefix) }) ?? records.count
            return DictionaryPrefixRange(start: UInt32(start), end: UInt32(end))
        }
    }

    private static func checkedAdd(_ lhs: Int, _ rhs: Int) throws -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else { throw DictionaryFormatError.invalidBounds }
        return result.partialValue
    }

    private static func checkedMultiply(_ lhs: Int, _ rhs: Int) throws -> Int {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        guard !result.overflow else { throw DictionaryFormatError.invalidBounds }
        return result.partialValue
    }
}

private extension FixedWidthInteger {
    var littleEndianBytes: [UInt8] {
        let value = littleEndian
        return withUnsafeBytes(of: value) { Array($0) }
    }
}

extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        append(contentsOf: value.littleEndianBytes)
    }

    func readLittleEndian<T: FixedWidthInteger>(at offset: Int) throws -> T {
        guard offset >= 0, offset + MemoryLayout<T>.size <= count else {
            throw DictionaryFormatError.invalidBounds
        }
        var value: T = 0
        for byteIndex in 0..<MemoryLayout<T>.size {
            value |= T(self[offset + byteIndex]) << T(byteIndex * 8)
        }
        return value
    }
}
