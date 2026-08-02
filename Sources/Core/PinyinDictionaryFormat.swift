import Foundation

enum PinyinDictionaryFormatError: Error, Equatable {
    case invalidMagic
    case unsupportedVersion
    case invalidHeader
    case invalidBounds
    case checksumMismatch
    case invalidBucketRanges
    case invalidFrontCoding
    case invalidKey
    case invalidCandidate
    case invalidOrdering
    case invalidUTF8
    case wb86BuildMismatch
}

struct PinyinDictionaryHeaderV1: Equatable, Sendable {
    static let byteCount = 96
    static let schemaVersion: UInt16 = 1
    static let checksumByteCount: UInt16 = 8
    static let restartInterval: UInt16 = 32
    static let bucketCount = 26 + 26 * 26

    let magic: String
    let schemaVersion: UInt16
    let wb86BuildIdentifier: UInt64
    let bucketOffset: UInt32
    let bucketCount: UInt32
    let keyRecordOffset: UInt32
    let keyCount: UInt32
    let keyBlobOffset: UInt32
    let keyBlobLength: UInt32
    let candidateRecordOffset: UInt32
    let candidateCount: UInt32
    let textOffset: UInt32
    let textLength: UInt32
    let checksumOffset: UInt32
    let restartInterval: UInt16
    let totalLength: UInt64
    let sourceIdentifier: UInt64
}

struct PinyinBucketRange: Equatable, Sendable {
    static let byteCount = 8

    let start: UInt32
    let end: UInt32
}

struct PinyinKeyRecordV1: Equatable, Sendable {
    static let byteCount = 16

    let prefixLength: UInt8
    let suffixLength: UInt8
    let isRestart: Bool
    let suffixOffset: UInt32
    let candidateStart: UInt32
    let candidateCount: UInt16
}

struct PinyinCandidateRecordV1: Equatable, Sendable {
    static let byteCount = 32
    static let missingWB86Record = UInt32.max

    let weight: UInt64
    let textOffset: UInt32
    let textLength: UInt32
    let wubiRecordIndex: UInt32?
    let wubiHint: InputCode?
}

struct PinyinDictionaryCandidate: Equatable, Sendable {
    /// Nil means the candidate text is resolved from `wubiRecordIndex` in the matching WB86 image.
    let text: String?
    let weight: UInt64
    let wubiRecordIndex: UInt32?
    let wubiHint: InputCode?

    init(text: String, weight: UInt64, wubiRecordIndex: UInt32? = nil,
         wubiHint: InputCode? = nil) {
        self.text = text
        self.weight = weight
        self.wubiRecordIndex = wubiRecordIndex
        self.wubiHint = wubiHint
    }

    private init(text: String?, weight: UInt64, wubiRecordIndex: UInt32?,
                 wubiHint: InputCode?) {
        self.text = text
        self.weight = weight
        self.wubiRecordIndex = wubiRecordIndex
        self.wubiHint = wubiHint
    }

    fileprivate static func decoded(text: String?, weight: UInt64,
                                    wubiRecordIndex: UInt32?, wubiHint: InputCode?)
        -> PinyinDictionaryCandidate {
        PinyinDictionaryCandidate(text: text, weight: weight,
                                  wubiRecordIndex: wubiRecordIndex, wubiHint: wubiHint)
    }
}

struct PinyinDictionaryEntry: Equatable, Sendable {
    let key: String
    let candidates: [PinyinDictionaryCandidate]
}

struct DecodedPinyinDictionaryV1: Equatable, Sendable {
    let header: PinyinDictionaryHeaderV1
    let bucketRanges: [PinyinBucketRange]
    let entries: [PinyinDictionaryEntry]
}

enum PinyinDictionaryFormatV1 {
    private static let magic = Data("MWPY".utf8)
    private static let restartFlag: UInt8 = 1
    private static let wb86TextFlag: UInt8 = 1
    static let maximumFileByteCount = 16 * 1_024 * 1_024

    static func encode(entries: [PinyinDictionaryEntry], wb86BuildIdentifier: UInt64,
                       sourceIdentifier: UInt64) throws -> Data {
        try validateEntries(entries)

        var keyBlob = Data()
        var keyRecords = [PinyinKeyRecordV1]()
        var flattenedCandidates = [PinyinDictionaryCandidate]()
        keyRecords.reserveCapacity(entries.count)

        var previousKey = [UInt8]()
        for (index, entry) in entries.enumerated() {
            let key = Array(entry.key.utf8)
            let isRestart = index % Int(PinyinDictionaryHeaderV1.restartInterval) == 0
            let prefixLength = isRestart ? 0 : commonPrefixLength(previousKey, key)
            let suffix = key.dropFirst(prefixLength)
            guard !suffix.isEmpty,
                  let prefix8 = UInt8(exactly: prefixLength),
                  let suffix8 = UInt8(exactly: suffix.count),
                  let candidateStart = UInt32(exactly: flattenedCandidates.count),
                  let candidateCount = UInt16(exactly: entry.candidates.count) else {
                throw PinyinDictionaryFormatError.invalidBounds
            }
            keyRecords.append(PinyinKeyRecordV1(
                prefixLength: prefix8,
                suffixLength: suffix8,
                isRestart: isRestart,
                suffixOffset: 0,
                candidateStart: candidateStart,
                candidateCount: candidateCount
            ))
            keyBlob.append(contentsOf: suffix)
            flattenedCandidates.append(contentsOf: entry.candidates)
            previousKey = key
        }

        let bucketOffset = PinyinDictionaryHeaderV1.byteCount
        let keyRecordOffset = try checkedAdd(
            bucketOffset,
            try checkedMultiply(PinyinDictionaryHeaderV1.bucketCount,
                                PinyinBucketRange.byteCount)
        )
        let keyBlobOffset = try checkedAdd(
            keyRecordOffset,
            try checkedMultiply(keyRecords.count, PinyinKeyRecordV1.byteCount)
        )
        let candidateRecordOffset = try checkedAdd(keyBlobOffset, keyBlob.count)
        let textOffset = try checkedAdd(
            candidateRecordOffset,
            try checkedMultiply(flattenedCandidates.count, PinyinCandidateRecordV1.byteCount)
        )

        var textBlob = Data()
        var candidateRecords = [PinyinCandidateRecordV1]()
        candidateRecords.reserveCapacity(flattenedCandidates.count)
        for candidate in flattenedCandidates {
            let usesWB86Text = candidate.wubiRecordIndex != nil
            let embeddedText: Data
            if usesWB86Text {
                embeddedText = Data()
            } else if let text = candidate.text {
                embeddedText = Data(text.utf8)
            } else {
                throw PinyinDictionaryFormatError.invalidCandidate
            }
            guard let absoluteTextOffset = UInt32(exactly: try checkedAdd(textOffset,
                                                                          textBlob.count)),
                  let textLength = UInt32(exactly: embeddedText.count) else {
                throw PinyinDictionaryFormatError.invalidBounds
            }
            candidateRecords.append(PinyinCandidateRecordV1(
                weight: candidate.weight,
                textOffset: usesWB86Text ? 0 : absoluteTextOffset,
                textLength: usesWB86Text ? 0 : textLength,
                wubiRecordIndex: candidate.wubiRecordIndex,
                wubiHint: candidate.wubiHint
            ))
            textBlob.append(embeddedText)
        }

        let checksumOffset = try checkedAdd(textOffset, textBlob.count)
        let totalLength = try checkedAdd(checksumOffset,
                                         Int(PinyinDictionaryHeaderV1.checksumByteCount))
        guard let bucketOffset32 = UInt32(exactly: bucketOffset),
              let keyRecordOffset32 = UInt32(exactly: keyRecordOffset),
              let keyCount32 = UInt32(exactly: keyRecords.count),
              let keyBlobOffset32 = UInt32(exactly: keyBlobOffset),
              let keyBlobLength32 = UInt32(exactly: keyBlob.count),
              let candidateRecordOffset32 = UInt32(exactly: candidateRecordOffset),
              let candidateCount32 = UInt32(exactly: candidateRecords.count),
              let textOffset32 = UInt32(exactly: textOffset),
              let textLength32 = UInt32(exactly: textBlob.count),
              let checksumOffset32 = UInt32(exactly: checksumOffset) else {
            throw PinyinDictionaryFormatError.invalidBounds
        }

        let bucketRanges = makeBucketRanges(keys: entries.map(\.key))
        var image = Data()
        image.append(magic)
        image.appendLittleEndian(PinyinDictionaryHeaderV1.schemaVersion)
        image.appendLittleEndian(UInt16(PinyinDictionaryHeaderV1.byteCount))
        image.appendLittleEndian(wb86BuildIdentifier)
        image.appendLittleEndian(bucketOffset32)
        image.appendLittleEndian(UInt32(PinyinDictionaryHeaderV1.bucketCount))
        image.appendLittleEndian(keyRecordOffset32)
        image.appendLittleEndian(keyCount32)
        image.appendLittleEndian(keyBlobOffset32)
        image.appendLittleEndian(keyBlobLength32)
        image.appendLittleEndian(candidateRecordOffset32)
        image.appendLittleEndian(candidateCount32)
        image.appendLittleEndian(textOffset32)
        image.appendLittleEndian(textLength32)
        image.appendLittleEndian(checksumOffset32)
        image.appendLittleEndian(PinyinDictionaryHeaderV1.checksumByteCount)
        image.appendLittleEndian(PinyinDictionaryHeaderV1.restartInterval)
        image.appendLittleEndian(UInt64(totalLength))
        image.appendLittleEndian(sourceIdentifier)
        image.appendLittleEndian(UInt64(0))
        image.appendLittleEndian(UInt64(0))
        guard image.count == PinyinDictionaryHeaderV1.byteCount else {
            throw PinyinDictionaryFormatError.invalidHeader
        }

        for range in bucketRanges {
            image.appendLittleEndian(range.start)
            image.appendLittleEndian(range.end)
        }
        var suffixCursor = keyBlobOffset
        for record in keyRecords {
            image.append(record.prefixLength)
            image.append(record.suffixLength)
            image.append(record.isRestart ? restartFlag : 0)
            image.append(0)
            image.appendLittleEndian(UInt32(suffixCursor))
            image.appendLittleEndian(record.candidateStart)
            image.appendLittleEndian(record.candidateCount)
            image.appendLittleEndian(UInt16(0))
            suffixCursor += Int(record.suffixLength)
        }
        image.append(keyBlob)
        for record in candidateRecords {
            image.appendLittleEndian(record.weight)
            image.appendLittleEndian(record.textOffset)
            image.appendLittleEndian(record.textLength)
            image.appendLittleEndian(record.wubiRecordIndex
                                     ?? PinyinCandidateRecordV1.missingWB86Record)
            image.appendLittleEndian(record.wubiHint?.packedValue ?? 0)
            image.append(UInt8(record.wubiHint?.length ?? 0))
            image.append(record.wubiRecordIndex == nil ? 0 : wb86TextFlag)
            image.appendLittleEndian(UInt16(0))
            image.appendLittleEndian(UInt32(0))
        }
        image.append(textBlob)
        let checksum = DictionaryChecksum.fnv1a64(
            image, in: PinyinDictionaryHeaderV1.byteCount..<checksumOffset
        )
        image.appendLittleEndian(checksum)
        guard image.count == totalLength else {
            throw PinyinDictionaryFormatError.invalidBounds
        }
        return image
    }

    static func decode(_ image: Data, expectedWB86BuildIdentifier: UInt64) throws
        -> DecodedPinyinDictionaryV1 {
        let header = try decodeHeader(image)
        guard header.wb86BuildIdentifier == expectedWB86BuildIdentifier else {
            throw PinyinDictionaryFormatError.wb86BuildMismatch
        }
        try validateChecksum(image, header: header)

        var bucketRanges = [PinyinBucketRange]()
        bucketRanges.reserveCapacity(Int(header.bucketCount))
        for index in 0..<Int(header.bucketCount) {
            let offset = Int(header.bucketOffset) + index * PinyinBucketRange.byteCount
            let start: UInt32 = try read(image, at: offset)
            let end: UInt32 = try read(image, at: offset + 4)
            guard start <= end, end <= header.keyCount else {
                throw PinyinDictionaryFormatError.invalidBucketRanges
            }
            bucketRanges.append(PinyinBucketRange(start: start, end: end))
        }

        let decodedKeys = try decodeKeys(image, header: header)
        let candidateGroups = try decodeCandidates(image, header: header,
                                                   keyRecords: decodedKeys.records)
        let entries = zip(decodedKeys.keys, candidateGroups).map {
            PinyinDictionaryEntry(key: $0.0, candidates: $0.1)
        }
        guard bucketRanges == makeBucketRanges(keys: decodedKeys.keys) else {
            throw PinyinDictionaryFormatError.invalidBucketRanges
        }
        return DecodedPinyinDictionaryV1(header: header, bucketRanges: bucketRanges,
                                         entries: entries)
    }

    /// Validates a mapped runtime image without materializing its complete key or candidate tables.
    /// The returned metadata is small and immutable; query code keeps using the mapped bytes.
    static func validateMappedImage(_ image: Data, expectedWB86BuildIdentifier: UInt64,
                                    wb86RecordCount: UInt32) throws
        -> (header: PinyinDictionaryHeaderV1, bucketRanges: [PinyinBucketRange]) {
        guard image.count <= maximumFileByteCount else {
            throw PinyinDictionaryFormatError.invalidBounds
        }
        let header = try decodeHeader(image)
        guard header.wb86BuildIdentifier == expectedWB86BuildIdentifier else {
            throw PinyinDictionaryFormatError.wb86BuildMismatch
        }
        try validateChecksum(image, header: header)

        var ranges = [PinyinBucketRange]()
        ranges.reserveCapacity(Int(header.bucketCount))
        for index in 0..<Int(header.bucketCount) {
            let offset = Int(header.bucketOffset) + index * PinyinBucketRange.byteCount
            let start: UInt32 = try read(image, at: offset)
            let end: UInt32 = try read(image, at: offset + 4)
            guard start <= end, end <= header.keyCount else {
                throw PinyinDictionaryFormatError.invalidBucketRanges
            }
            ranges.append(PinyinBucketRange(start: start, end: end))
        }

        let sentinel = header.keyCount
        var observed = Array(
            repeating: PinyinBucketRange(start: sentinel, end: sentinel),
            count: PinyinDictionaryHeaderV1.bucketCount
        )
        var previous = [UInt8]()
        var suffixCursor = Int(header.keyBlobOffset)
        var candidateCursor: UInt32 = 0
        for index in 0..<Int(header.keyCount) {
            let offset = Int(header.keyRecordOffset) + index * PinyinKeyRecordV1.byteCount
            let prefixLength = Int(image[offset])
            let suffixLength = Int(image[offset + 1])
            let flags = image[offset + 2]
            let reserved = image[offset + 3]
            let suffixOffset: UInt32 = try read(image, at: offset + 4)
            let candidateStart: UInt32 = try read(image, at: offset + 8)
            let candidateCount: UInt16 = try read(image, at: offset + 12)
            let trailingReserved: UInt16 = try read(image, at: offset + 14)
            let isRestart = index % Int(header.restartInterval) == 0
            guard reserved == 0, trailingReserved == 0,
                  flags == (isRestart ? restartFlag : 0), suffixLength > 0,
                  suffixOffset == suffixCursor, candidateStart == candidateCursor,
                  (1...64).contains(Int(candidateCount)),
                  UInt64(candidateStart) + UInt64(candidateCount)
                    <= UInt64(header.candidateCount) else {
                throw PinyinDictionaryFormatError.invalidFrontCoding
            }
            guard isRestart ? prefixLength == 0 : prefixLength <= previous.count else {
                throw PinyinDictionaryFormatError.invalidFrontCoding
            }
            let suffixEnd = try checkedAdd(suffixCursor, suffixLength)
            guard suffixEnd <= Int(header.candidateRecordOffset) else {
                throw PinyinDictionaryFormatError.invalidBounds
            }
            let key = Array(previous.prefix(prefixLength))
                + Array(image[suffixCursor..<suffixEnd])
            guard isValidKeyBytes(key) else { throw PinyinDictionaryFormatError.invalidKey }
            if !previous.isEmpty, !previous.lexicographicallyPrecedes(key) {
                throw PinyinDictionaryFormatError.invalidOrdering
            }
            let first = Int(key[0] - UInt8(ascii: "a"))
            noteBucket(first, index: UInt32(index), ranges: &observed)
            if key.count > 1 {
                let second = Int(key[1] - UInt8(ascii: "a"))
                noteBucket(26 + first * 26 + second,
                           index: UInt32(index), ranges: &observed)
            }
            previous = key
            suffixCursor = suffixEnd
            candidateCursor += UInt32(candidateCount)
        }
        guard suffixCursor == Int(header.candidateRecordOffset),
              candidateCursor == header.candidateCount else {
            throw PinyinDictionaryFormatError.invalidBounds
        }
        guard ranges == observed else {
            throw PinyinDictionaryFormatError.invalidBucketRanges
        }

        try validateMappedCandidates(image, header: header,
                                     wb86RecordCount: wb86RecordCount)
        return (header, ranges)
    }

    static func replaceChecksum(in image: inout Data) {
        guard image.count >= PinyinDictionaryHeaderV1.byteCount,
              let checksumOffset: UInt32 = try? read(image, at: 56),
              Int(checksumOffset) + Int(PinyinDictionaryHeaderV1.checksumByteCount) <= image.count
        else { return }
        let checksum = DictionaryChecksum.fnv1a64(
            image, in: PinyinDictionaryHeaderV1.byteCount..<Int(checksumOffset)
        )
        image.replaceSubrange(
            Int(checksumOffset)..<(Int(checksumOffset)
                + Int(PinyinDictionaryHeaderV1.checksumByteCount)),
            with: littleEndianBytes(checksum)
        )
    }

    private static func decodeHeader(_ image: Data) throws -> PinyinDictionaryHeaderV1 {
        guard image.count <= maximumFileByteCount,
              image.count >= PinyinDictionaryHeaderV1.byteCount
                + Int(PinyinDictionaryHeaderV1.checksumByteCount) else {
            throw PinyinDictionaryFormatError.invalidBounds
        }
        guard image.prefix(4) == magic else { throw PinyinDictionaryFormatError.invalidMagic }
        let version: UInt16 = try read(image, at: 4)
        guard version == PinyinDictionaryHeaderV1.schemaVersion else {
            throw PinyinDictionaryFormatError.unsupportedVersion
        }
        let headerSize: UInt16 = try read(image, at: 6)
        let wb86BuildIdentifier: UInt64 = try read(image, at: 8)
        let bucketOffset: UInt32 = try read(image, at: 16)
        let bucketCount: UInt32 = try read(image, at: 20)
        let keyRecordOffset: UInt32 = try read(image, at: 24)
        let keyCount: UInt32 = try read(image, at: 28)
        let keyBlobOffset: UInt32 = try read(image, at: 32)
        let keyBlobLength: UInt32 = try read(image, at: 36)
        let candidateRecordOffset: UInt32 = try read(image, at: 40)
        let candidateCount: UInt32 = try read(image, at: 44)
        let textOffset: UInt32 = try read(image, at: 48)
        let textLength: UInt32 = try read(image, at: 52)
        let checksumOffset: UInt32 = try read(image, at: 56)
        let checksumLength: UInt16 = try read(image, at: 60)
        let restartInterval: UInt16 = try read(image, at: 62)
        let totalLength: UInt64 = try read(image, at: 64)
        let sourceIdentifier: UInt64 = try read(image, at: 72)
        let reserved1: UInt64 = try read(image, at: 80)
        let reserved2: UInt64 = try read(image, at: 88)

        guard headerSize == PinyinDictionaryHeaderV1.byteCount,
              bucketCount == PinyinDictionaryHeaderV1.bucketCount,
              checksumLength == PinyinDictionaryHeaderV1.checksumByteCount,
              restartInterval == PinyinDictionaryHeaderV1.restartInterval,
              keyCount > 0, candidateCount > 0,
              reserved1 == 0, reserved2 == 0 else {
            throw PinyinDictionaryFormatError.invalidHeader
        }

        let expectedKeyRecordOffset = try checkedAdd(
            Int(bucketOffset),
            try checkedMultiply(Int(bucketCount), PinyinBucketRange.byteCount)
        )
        let expectedKeyBlobOffset = try checkedAdd(
            Int(keyRecordOffset),
            try checkedMultiply(Int(keyCount), PinyinKeyRecordV1.byteCount)
        )
        let expectedCandidateRecordOffset = try checkedAdd(Int(keyBlobOffset),
                                                           Int(keyBlobLength))
        let expectedTextOffset = try checkedAdd(
            Int(candidateRecordOffset),
            try checkedMultiply(Int(candidateCount), PinyinCandidateRecordV1.byteCount)
        )
        let expectedChecksumOffset = try checkedAdd(Int(textOffset), Int(textLength))
        let expectedTotalLength = try checkedAdd(Int(checksumOffset), Int(checksumLength))
        guard bucketOffset == PinyinDictionaryHeaderV1.byteCount,
              Int(keyRecordOffset) == expectedKeyRecordOffset,
              Int(keyBlobOffset) == expectedKeyBlobOffset,
              Int(candidateRecordOffset) == expectedCandidateRecordOffset,
              Int(textOffset) == expectedTextOffset,
              Int(checksumOffset) == expectedChecksumOffset,
              UInt64(expectedTotalLength) == totalLength,
              expectedTotalLength == image.count else {
            throw PinyinDictionaryFormatError.invalidBounds
        }

        return PinyinDictionaryHeaderV1(
            magic: "MWPY", schemaVersion: version,
            wb86BuildIdentifier: wb86BuildIdentifier,
            bucketOffset: bucketOffset, bucketCount: bucketCount,
            keyRecordOffset: keyRecordOffset, keyCount: keyCount,
            keyBlobOffset: keyBlobOffset, keyBlobLength: keyBlobLength,
            candidateRecordOffset: candidateRecordOffset, candidateCount: candidateCount,
            textOffset: textOffset, textLength: textLength,
            checksumOffset: checksumOffset, restartInterval: restartInterval,
            totalLength: totalLength, sourceIdentifier: sourceIdentifier
        )
    }

    private static func validateChecksum(_ image: Data,
                                         header: PinyinDictionaryHeaderV1) throws {
        let stored: UInt64 = try read(image, at: Int(header.checksumOffset))
        let actual = DictionaryChecksum.fnv1a64(
            image, in: PinyinDictionaryHeaderV1.byteCount..<Int(header.checksumOffset)
        )
        guard stored == actual else { throw PinyinDictionaryFormatError.checksumMismatch }
    }

    private static func decodeKeys(_ image: Data, header: PinyinDictionaryHeaderV1) throws
        -> (keys: [String], records: [PinyinKeyRecordV1]) {
        var keys = [String]()
        var records = [PinyinKeyRecordV1]()
        keys.reserveCapacity(Int(header.keyCount))
        records.reserveCapacity(Int(header.keyCount))
        var previous = [UInt8]()
        var suffixCursor = Int(header.keyBlobOffset)
        var candidateCursor: UInt32 = 0

        for index in 0..<Int(header.keyCount) {
            let offset = Int(header.keyRecordOffset) + index * PinyinKeyRecordV1.byteCount
            let prefixLength = image[offset]
            let suffixLength = image[offset + 1]
            let flags = image[offset + 2]
            let reserved = image[offset + 3]
            let suffixOffset: UInt32 = try read(image, at: offset + 4)
            let candidateStart: UInt32 = try read(image, at: offset + 8)
            let candidateCount: UInt16 = try read(image, at: offset + 12)
            let trailingReserved: UInt16 = try read(image, at: offset + 14)
            let isRestart = index % Int(header.restartInterval) == 0
            guard reserved == 0, trailingReserved == 0,
                  flags == (isRestart ? restartFlag : 0),
                  suffixLength > 0,
                  suffixOffset == suffixCursor,
                  candidateStart == candidateCursor,
                  (1...64).contains(Int(candidateCount)),
                  UInt64(candidateStart) + UInt64(candidateCount) <= UInt64(header.candidateCount)
            else { throw PinyinDictionaryFormatError.invalidFrontCoding }
            if isRestart {
                guard prefixLength == 0 else {
                    throw PinyinDictionaryFormatError.invalidFrontCoding
                }
            } else {
                guard Int(prefixLength) <= previous.count else {
                    throw PinyinDictionaryFormatError.invalidFrontCoding
                }
            }
            let suffixEnd = try checkedAdd(suffixCursor, Int(suffixLength))
            guard suffixEnd <= Int(header.candidateRecordOffset) else {
                throw PinyinDictionaryFormatError.invalidBounds
            }
            let keyBytes = Array(previous.prefix(Int(prefixLength)))
                + Array(image[suffixCursor..<suffixEnd])
            guard isValidKeyBytes(keyBytes) else { throw PinyinDictionaryFormatError.invalidKey }
            if !previous.isEmpty, !previous.lexicographicallyPrecedes(keyBytes) {
                throw PinyinDictionaryFormatError.invalidOrdering
            }
            let key = String(decoding: keyBytes, as: UTF8.self)
            keys.append(key)
            records.append(PinyinKeyRecordV1(
                prefixLength: prefixLength, suffixLength: suffixLength,
                isRestart: isRestart, suffixOffset: suffixOffset,
                candidateStart: candidateStart, candidateCount: candidateCount
            ))
            previous = keyBytes
            suffixCursor = suffixEnd
            candidateCursor += UInt32(candidateCount)
        }
        guard suffixCursor == Int(header.candidateRecordOffset),
              candidateCursor == header.candidateCount else {
            throw PinyinDictionaryFormatError.invalidBounds
        }
        return (keys, records)
    }

    private static func decodeCandidates(_ image: Data, header: PinyinDictionaryHeaderV1,
                                         keyRecords: [PinyinKeyRecordV1]) throws
        -> [[PinyinDictionaryCandidate]] {
        var decoded = [PinyinDictionaryCandidate]()
        decoded.reserveCapacity(Int(header.candidateCount))
        var textCursor = Int(header.textOffset)

        for index in 0..<Int(header.candidateCount) {
            let offset = Int(header.candidateRecordOffset)
                + index * PinyinCandidateRecordV1.byteCount
            let weight: UInt64 = try read(image, at: offset)
            let textOffset: UInt32 = try read(image, at: offset + 8)
            let textLength: UInt32 = try read(image, at: offset + 12)
            let rawWB86Index: UInt32 = try read(image, at: offset + 16)
            let hintPacked: UInt32 = try read(image, at: offset + 20)
            let hintLength = Int(image[offset + 24])
            let flags = image[offset + 25]
            let reserved: UInt16 = try read(image, at: offset + 26)
            let trailingReserved: UInt32 = try read(image, at: offset + 28)
            guard reserved == 0, trailingReserved == 0,
                  flags == 0 || flags == wb86TextFlag else {
                throw PinyinDictionaryFormatError.invalidCandidate
            }
            let usesWB86Text = flags == wb86TextFlag
            let wubiRecordIndex: UInt32?
            let text: String?
            if usesWB86Text {
                guard textOffset == 0, textLength == 0,
                      rawWB86Index != PinyinCandidateRecordV1.missingWB86Record else {
                    throw PinyinDictionaryFormatError.invalidCandidate
                }
                wubiRecordIndex = rawWB86Index
                text = nil
            } else {
                guard rawWB86Index == PinyinCandidateRecordV1.missingWB86Record,
                      textLength > 0, textOffset == textCursor else {
                    throw PinyinDictionaryFormatError.invalidCandidate
                }
                let textEnd = try checkedAdd(textCursor, Int(textLength))
                guard textEnd <= Int(header.checksumOffset) else {
                    throw PinyinDictionaryFormatError.invalidBounds
                }
                let bytes = image.subdata(in: textCursor..<textEnd)
                guard let decodedText = String(data: bytes, encoding: .utf8),
                      !decodedText.isEmpty,
                      decodedText == decodedText.precomposedStringWithCanonicalMapping else {
                    throw PinyinDictionaryFormatError.invalidUTF8
                }
                wubiRecordIndex = nil
                text = decodedText
                textCursor = textEnd
            }
            let hint: InputCode?
            if hintLength == 0 {
                guard hintPacked == 0 else {
                    throw PinyinDictionaryFormatError.invalidCandidate
                }
                hint = nil
            } else {
                guard let decodedHint = InputCode(packedValue: hintPacked, length: hintLength) else {
                    throw PinyinDictionaryFormatError.invalidCandidate
                }
                hint = decodedHint
            }
            decoded.append(.decoded(text: text, weight: weight,
                                    wubiRecordIndex: wubiRecordIndex, wubiHint: hint))
        }
        guard textCursor == Int(header.checksumOffset) else {
            throw PinyinDictionaryFormatError.invalidBounds
        }

        return keyRecords.map { record in
            let start = Int(record.candidateStart)
            return Array(decoded[start..<(start + Int(record.candidateCount))])
        }
    }

    private static func validateMappedCandidates(_ image: Data,
                                                 header: PinyinDictionaryHeaderV1,
                                                 wb86RecordCount: UInt32) throws {
        var textCursor = Int(header.textOffset)
        var candidateCursor: UInt32 = 0
        for keyIndex in 0..<Int(header.keyCount) {
            let keyOffset = Int(header.keyRecordOffset)
                + keyIndex * PinyinKeyRecordV1.byteCount
            let candidateStart: UInt32 = try read(image, at: keyOffset + 8)
            let candidateCount: UInt16 = try read(image, at: keyOffset + 12)
            guard candidateStart == candidateCursor else {
                throw PinyinDictionaryFormatError.invalidCandidate
            }
            var previousWeight: UInt64?
            for index in Int(candidateStart)..<Int(candidateStart) + Int(candidateCount) {
                let offset = Int(header.candidateRecordOffset)
                    + index * PinyinCandidateRecordV1.byteCount
                let weight: UInt64 = try read(image, at: offset)
                let textOffset: UInt32 = try read(image, at: offset + 8)
                let textLength: UInt32 = try read(image, at: offset + 12)
                let rawWB86Index: UInt32 = try read(image, at: offset + 16)
                let hintPacked: UInt32 = try read(image, at: offset + 20)
                let hintLength = Int(image[offset + 24])
                let flags = image[offset + 25]
                let reserved: UInt16 = try read(image, at: offset + 26)
                let trailingReserved: UInt32 = try read(image, at: offset + 28)
                guard reserved == 0, trailingReserved == 0,
                      flags == 0 || flags == wb86TextFlag else {
                    throw PinyinDictionaryFormatError.invalidCandidate
                }
                if let previousWeight, weight > previousWeight {
                    throw PinyinDictionaryFormatError.invalidOrdering
                }
                previousWeight = weight

                if flags == wb86TextFlag {
                    guard textOffset == 0, textLength == 0,
                          rawWB86Index != PinyinCandidateRecordV1.missingWB86Record,
                          rawWB86Index < wb86RecordCount else {
                        throw PinyinDictionaryFormatError.invalidCandidate
                    }
                } else {
                    guard rawWB86Index == PinyinCandidateRecordV1.missingWB86Record,
                          textLength > 0, textOffset == textCursor else {
                        throw PinyinDictionaryFormatError.invalidCandidate
                    }
                    let textEnd = try checkedAdd(textCursor, Int(textLength))
                    guard textEnd <= Int(header.checksumOffset) else {
                        throw PinyinDictionaryFormatError.invalidBounds
                    }
                    let bytes = image.subdata(in: textCursor..<textEnd)
                    guard let text = String(data: bytes, encoding: .utf8), !text.isEmpty,
                          text == text.precomposedStringWithCanonicalMapping,
                          !text.unicodeScalars.contains(where: {
                              CharacterSet.controlCharacters.contains($0)
                          }) else {
                        throw PinyinDictionaryFormatError.invalidUTF8
                    }
                    textCursor = textEnd
                }

                if hintLength == 0 {
                    guard hintPacked == 0 else {
                        throw PinyinDictionaryFormatError.invalidCandidate
                    }
                } else if InputCode(packedValue: hintPacked, length: hintLength) == nil {
                    throw PinyinDictionaryFormatError.invalidCandidate
                }
            }
            candidateCursor += UInt32(candidateCount)
        }
        guard candidateCursor == header.candidateCount,
              textCursor == Int(header.checksumOffset) else {
            throw PinyinDictionaryFormatError.invalidBounds
        }
    }

    private static func validateEntries(_ entries: [PinyinDictionaryEntry]) throws {
        guard !entries.isEmpty else { throw PinyinDictionaryFormatError.invalidKey }
        var previous: [UInt8]?
        for entry in entries {
            let key = Array(entry.key.utf8)
            guard isValidKeyBytes(key) else { throw PinyinDictionaryFormatError.invalidKey }
            if let previous, !previous.lexicographicallyPrecedes(key) {
                throw PinyinDictionaryFormatError.invalidOrdering
            }
            guard (1...64).contains(entry.candidates.count) else {
                throw PinyinDictionaryFormatError.invalidCandidate
            }
            for candidate in entry.candidates {
                guard let text = candidate.text, !text.isEmpty,
                      text == text.precomposedStringWithCanonicalMapping,
                      !text.unicodeScalars.contains(where: {
                          CharacterSet.controlCharacters.contains($0)
                      }) else {
                    throw PinyinDictionaryFormatError.invalidCandidate
                }
                if candidate.wubiRecordIndex == nil,
                   Data(text.utf8).isEmpty {
                    throw PinyinDictionaryFormatError.invalidCandidate
                }
            }
            previous = key
        }
    }

    private static func makeBucketRanges(keys: [String]) -> [PinyinBucketRange] {
        let sentinel = UInt32(keys.count)
        var ranges = Array(repeating: PinyinBucketRange(start: sentinel, end: sentinel),
                           count: PinyinDictionaryHeaderV1.bucketCount)
        for (index, key) in keys.enumerated() {
            let bytes = Array(key.utf8)
            noteBucket(Int(bytes[0] - UInt8(ascii: "a")), index: UInt32(index), ranges: &ranges)
            if bytes.count >= 2 {
                let first = Int(bytes[0] - UInt8(ascii: "a"))
                let second = Int(bytes[1] - UInt8(ascii: "a"))
                noteBucket(26 + first * 26 + second, index: UInt32(index), ranges: &ranges)
            }
        }
        return ranges
    }

    private static func noteBucket(_ bucket: Int, index: UInt32,
                                   ranges: inout [PinyinBucketRange]) {
        let existing = ranges[bucket]
        ranges[bucket] = PinyinBucketRange(
            start: existing.start == existing.end ? index : existing.start,
            end: index + 1
        )
    }

    private static func commonPrefixLength(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        var count = 0
        while count < lhs.count, count < rhs.count, lhs[count] == rhs[count] {
            count += 1
        }
        return count
    }

    private static func isValidKeyBytes(_ key: [UInt8]) -> Bool {
        (1...32).contains(key.count) && key.allSatisfy { (0x61...0x7a).contains($0) }
    }

    private static func checkedAdd(_ lhs: Int, _ rhs: Int) throws -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else { throw PinyinDictionaryFormatError.invalidBounds }
        return result.partialValue
    }

    private static func checkedMultiply(_ lhs: Int, _ rhs: Int) throws -> Int {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        guard !result.overflow else { throw PinyinDictionaryFormatError.invalidBounds }
        return result.partialValue
    }

    private static func read<T: FixedWidthInteger>(_ data: Data, at offset: Int) throws -> T {
        guard offset >= 0, offset <= data.count - MemoryLayout<T>.size else {
            throw PinyinDictionaryFormatError.invalidBounds
        }
        var value: T = 0
        for index in 0..<MemoryLayout<T>.size {
            value |= T(data[offset + index]) << T(index * 8)
        }
        return value
    }

    private static func littleEndianBytes<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        var encoded = value.littleEndian
        return Swift.withUnsafeBytes(of: &encoded) { Array($0) }
    }
}
