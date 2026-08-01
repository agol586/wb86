import Foundation

struct DictionaryIndex: Sendable {
    private let image: BaseDictionaryImage

    init(image: BaseDictionaryImage) {
        self.image = image
    }

    func lookup(_ code: InputCode) -> [DictionaryEntryRecord] {
        let range = prefixRange(for: code)
        guard range.start < range.end else { return [] }

        var lower = Int(range.start)
        var upper = Int(range.end)
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            guard let packed = packedCode(at: middle) else { return [] }
            if packed < code.packedValue {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        var matches = [DictionaryEntryRecord]()
        var index = lower
        while index < Int(range.end), packedCode(at: index) == code.packedValue {
            guard let record = record(at: index), record.code == code else { return [] }
            matches.append(record)
            index += 1
        }
        return matches
    }

    func records(matchingPrefix prefix: InputCode) -> [DictionaryEntryRecord] {
        let range = prefixRange(for: prefix)
        guard range.start < range.end else { return [] }
        var records = [DictionaryEntryRecord]()
        records.reserveCapacity(Int(range.end - range.start))
        for index in Int(range.start)..<Int(range.end) {
            guard let record = record(at: index) else { return [] }
            if record.code.letters.hasPrefix(prefix.letters) {
                records.append(record)
            }
        }
        return records
    }

    private func prefixRange(for code: InputCode) -> DictionaryPrefixRange {
        let values = code.letters.utf8.map { Int($0 - 96) }
        let index: Int
        if values.count == 1 {
            index = values[0] - 1
        } else {
            index = 25 + (values[0] - 1) * 25 + values[1] - 1
        }
        guard image.prefixRanges.indices.contains(index) else {
            return DictionaryPrefixRange(start: 0, end: 0)
        }
        return image.prefixRanges[index]
    }

    private func packedCode(at index: Int) -> UInt32? {
        guard index >= 0, index < Int(image.header.recordCount) else { return nil }
        let offset = Int(image.header.recordOffset) + index * DictionaryEntryRecord.byteCount
        return try? image.bytes.readLittleEndian(at: offset)
    }

    private func record(at index: Int) -> DictionaryEntryRecord? {
        guard index >= 0, index < Int(image.header.recordCount) else { return nil }
        let offset = Int(image.header.recordOffset) + index * DictionaryEntryRecord.byteCount
        guard let packed: UInt32 = try? image.bytes.readLittleEndian(at: offset),
              let rank: UInt32 = try? image.bytes.readLittleEndian(at: offset + 8),
              let textOffset: UInt32 = try? image.bytes.readLittleEndian(at: offset + 12),
              let textLength: UInt32 = try? image.bytes.readLittleEndian(at: offset + 16),
              let code = InputCode(packedValue: packed, length: Int(image.bytes[offset + 4])) else {
            return nil
        }
        let end = Int(textOffset) + Int(textLength)
        guard Int(textOffset) >= Int(image.header.stringOffset),
              end <= Int(image.header.checksumOffset),
              let text = String(data: image.bytes.subdata(in: Int(textOffset)..<end), encoding: .utf8),
              let record = try? DictionaryEntryRecord(code: code, rank: rank, text: text) else {
            return nil
        }
        return record
    }
}
