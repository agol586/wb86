import Foundation

enum PinyinDictionaryQueryError: Error, Equatable {
    case invalidPageSize
    case pageOutOfRange
    case corruptImage
}

struct PinyinLookupCandidate: Equatable, Sendable {
    let text: String
    let weight: UInt64
    let baseRank: Int
    let wubiHint: InputCode?
}

struct PinyinLookupPage: Equatable, Sendable {
    let items: [PinyinLookupCandidate]
    let pageIndex: Int
    let pageSize: Int
    let totalCount: Int

    var hasPrevious: Bool { pageIndex > 0 }
    var hasNext: Bool { (pageIndex + 1) * pageSize < totalCount }
}

/// Bounded lookup over a validated MWPY mapping. Keys are decoded from the nearest 32-key restart,
/// and only the requested candidate page is decoded.
struct PinyinDictionaryIndex: Sendable {
    private let image: PinyinDictionaryImage

    init(image: PinyinDictionaryImage) {
        self.image = image
    }

    func prefixExists(_ sequence: CompositionKeySequence) -> Bool {
        let query = Array(sequence.letters.utf8)
        let range = bucketRange(for: query)
        guard range.start < range.end,
              let index = lowerBound(for: query, in: range),
              index < Int(range.end),
              let key = keyBytes(at: index) else { return false }
        return key.starts(with: query)
    }

    func page(for sequence: CompositionKeySequence, pageIndex: Int,
              pageSize: Int) throws -> PinyinLookupPage {
        guard (5...9).contains(pageSize) else {
            throw PinyinDictionaryQueryError.invalidPageSize
        }
        guard pageIndex >= 0 else { throw PinyinDictionaryQueryError.pageOutOfRange }
        let query = Array(sequence.letters.utf8)
        let range = bucketRange(for: query)
        guard range.start < range.end,
              let index = lowerBound(for: query, in: range),
              index < Int(range.end),
              keyBytes(at: index) == query else {
            guard pageIndex == 0 else { throw PinyinDictionaryQueryError.pageOutOfRange }
            return PinyinLookupPage(items: [], pageIndex: 0,
                                    pageSize: pageSize, totalCount: 0)
        }
        guard let record = keyRecord(at: index), (1...64).contains(Int(record.candidateCount))
        else { throw PinyinDictionaryQueryError.corruptImage }

        let totalCount = Int(record.candidateCount)
        let pageStart = pageIndex.multipliedReportingOverflow(by: pageSize)
        guard !pageStart.overflow, pageStart.partialValue <= totalCount,
              pageIndex == 0 || pageStart.partialValue < totalCount else {
            throw PinyinDictionaryQueryError.pageOutOfRange
        }
        let pageEnd = min(pageStart.partialValue + pageSize, totalCount)
        var items = [PinyinLookupCandidate]()
        items.reserveCapacity(pageEnd - pageStart.partialValue)
        for relativeIndex in pageStart.partialValue..<pageEnd {
            let absoluteIndex = Int(record.candidateStart) + relativeIndex
            guard let candidate = candidate(at: absoluteIndex, baseRank: relativeIndex) else {
                throw PinyinDictionaryQueryError.corruptImage
            }
            items.append(candidate)
        }
        return PinyinLookupPage(items: items, pageIndex: pageIndex,
                                pageSize: pageSize, totalCount: totalCount)
    }

    private func bucketRange(for query: [UInt8]) -> PinyinBucketRange {
        guard let firstByte = query.first else {
            return PinyinBucketRange(start: 0, end: 0)
        }
        let first = Int(firstByte - UInt8(ascii: "a"))
        let bucket: Int
        if query.count == 1 {
            bucket = first
        } else {
            bucket = 26 + first * 26 + Int(query[1] - UInt8(ascii: "a"))
        }
        guard image.bucketRanges.indices.contains(bucket) else {
            return PinyinBucketRange(start: 0, end: 0)
        }
        return image.bucketRanges[bucket]
    }

    private func lowerBound(for query: [UInt8], in range: PinyinBucketRange) -> Int? {
        var lower = Int(range.start)
        var upper = Int(range.end)
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            guard let key = keyBytes(at: middle) else { return nil }
            if key.lexicographicallyPrecedes(query) {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func keyBytes(at index: Int) -> [UInt8]? {
        guard index >= 0, index < Int(image.header.keyCount) else { return nil }
        let interval = Int(image.header.restartInterval)
        let checkpoint = index - index % interval
        var previous = [UInt8]()
        for current in checkpoint...index {
            guard let record = keyRecord(at: current) else { return nil }
            let start = Int(record.suffixOffset)
            let end = start + Int(record.suffixLength)
            guard start >= Int(image.header.keyBlobOffset),
                  end <= Int(image.header.candidateRecordOffset),
                  Int(record.prefixLength) <= previous.count else { return nil }
            previous = Array(previous.prefix(Int(record.prefixLength)))
                + Array(image.bytes[start..<end])
        }
        return previous
    }

    private func keyRecord(at index: Int) -> PinyinKeyRecordV1? {
        guard index >= 0, index < Int(image.header.keyCount) else { return nil }
        let offset = Int(image.header.keyRecordOffset) + index * PinyinKeyRecordV1.byteCount
        guard let suffixOffset: UInt32 = try? image.bytes.readLittleEndian(at: offset + 4),
              let candidateStart: UInt32 = try? image.bytes.readLittleEndian(at: offset + 8),
              let candidateCount: UInt16 = try? image.bytes.readLittleEndian(at: offset + 12)
        else { return nil }
        return PinyinKeyRecordV1(
            prefixLength: image.bytes[offset],
            suffixLength: image.bytes[offset + 1],
            isRestart: image.bytes[offset + 2] == 1,
            suffixOffset: suffixOffset,
            candidateStart: candidateStart,
            candidateCount: candidateCount
        )
    }

    private func candidate(at index: Int, baseRank: Int) -> PinyinLookupCandidate? {
        guard index >= 0, index < Int(image.header.candidateCount) else { return nil }
        let offset = Int(image.header.candidateRecordOffset)
            + index * PinyinCandidateRecordV1.byteCount
        guard let weight: UInt64 = try? image.bytes.readLittleEndian(at: offset),
              let textOffset: UInt32 = try? image.bytes.readLittleEndian(at: offset + 8),
              let textLength: UInt32 = try? image.bytes.readLittleEndian(at: offset + 12),
              let rawWB86Index: UInt32 = try? image.bytes.readLittleEndian(at: offset + 16),
              let hintPacked: UInt32 = try? image.bytes.readLittleEndian(at: offset + 20)
        else { return nil }
        let hintLength = Int(image.bytes[offset + 24])
        let hint = hintLength == 0
            ? nil : InputCode(packedValue: hintPacked, length: hintLength)
        let text: String?
        if rawWB86Index == PinyinCandidateRecordV1.missingWB86Record {
            let end = Int(textOffset) + Int(textLength)
            guard Int(textOffset) >= Int(image.header.textOffset),
                  end <= Int(image.header.checksumOffset) else { return nil }
            text = String(data: image.bytes.subdata(in: Int(textOffset)..<end), encoding: .utf8)
        } else {
            text = wb86Text(at: Int(rawWB86Index))
        }
        guard let text, !text.isEmpty else { return nil }
        return PinyinLookupCandidate(text: text, weight: weight,
                                     baseRank: baseRank, wubiHint: hint)
    }

    private func wb86Text(at index: Int) -> String? {
        let wb86 = image.wb86Image
        guard index >= 0, index < Int(wb86.header.recordCount) else { return nil }
        let offset = Int(wb86.header.recordOffset) + index * DictionaryEntryRecord.byteCount
        guard let textOffset: UInt32 = try? wb86.bytes.readLittleEndian(at: offset + 12),
              let textLength: UInt32 = try? wb86.bytes.readLittleEndian(at: offset + 16) else {
            return nil
        }
        let end = Int(textOffset) + Int(textLength)
        guard Int(textOffset) >= Int(wb86.header.stringOffset),
              end <= Int(wb86.header.checksumOffset) else { return nil }
        return String(data: wb86.bytes.subdata(in: Int(textOffset)..<end), encoding: .utf8)
    }
}
