import Foundation
#if canImport(MacWubi)
@testable import MacWubi
#endif

enum PinyinDictionaryCompilerError: Error, Equatable, CustomStringConvertible {
    case usage
    case unreadableInput
    case invalidUTF8
    case missingDataMarker
    case invalidRecord(line: Int)
    case invalidMetadata
    case invalidWB86
    case invalidSimplification
    case outputFailure

    var description: String {
        switch self {
        case .usage:
            return "usage: macwubi-dictionary-compiler pinyin --input pinyin_simp.dict.yaml --wubi-image wb86.bin --script-conversion script-conversion.bin --output pinyin-simp.bin --manifest pinyin-simp.manifest.json --license-id Apache-2.0 --source-revision REVISION --upstream-sha256 SHA256"
        case .unreadableInput: return "pinyin compiler input could not be read"
        case .invalidUTF8: return "pinyin compiler input is not valid UTF-8"
        case .missingDataMarker: return "pinyin dictionary data marker is missing"
        case let .invalidRecord(line): return "invalid pinyin record at line \(line)"
        case .invalidMetadata: return "pinyin compiler metadata is invalid"
        case .invalidWB86: return "WB86 image is invalid"
        case .invalidSimplification: return "script conversion image is invalid"
        case .outputFailure: return "compiled pinyin output could not be written"
        }
    }
}

struct PinyinTextSimplifier: Sendable {
    private let reverseMappings: [String: String]
    private let maximumTargetLength: Int

    init(data: Data) throws {
        _ = try ScriptConverter(data: data)
        let recordCount = Int(try Self.readUInt32(data, at: 8))
        let recordOffset = Int(try Self.readUInt32(data, at: 12))
        let stringOffset = Int(try Self.readUInt32(data, at: 16))
        let stringLength = Int(try Self.readUInt32(data, at: 20))
        var reverse = [String: String]()
        var maximum = 0
        for index in 0..<recordCount {
            let offset = recordOffset + index * 16
            let source = try Self.readString(data, recordAt: offset,
                                             stringsAt: stringOffset,
                                             stringsLength: stringLength)
            let target = try Self.readString(data, recordAt: offset + 8,
                                             stringsAt: stringOffset,
                                             stringsLength: stringLength)
            if let existing = reverse[target],
               !source.utf8.lexicographicallyPrecedes(existing.utf8) {
                continue
            }
            reverse[target] = source
            maximum = max(maximum, target.count)
        }
        reverseMappings = reverse
        maximumTargetLength = maximum
    }

    func simplify(_ text: String) -> String {
        guard !text.isEmpty, maximumTargetLength > 0 else { return text }
        var output = ""
        var start = text.startIndex
        while start < text.endIndex {
            let remaining = text.distance(from: start, to: text.endIndex)
            var match: (end: String.Index, replacement: String)?
            for length in stride(from: min(maximumTargetLength, remaining), through: 1, by: -1) {
                let end = text.index(start, offsetBy: length)
                if let replacement = reverseMappings[String(text[start..<end])] {
                    match = (end, replacement)
                    break
                }
            }
            if let match {
                output.append(match.replacement)
                start = match.end
            } else {
                let next = text.index(after: start)
                output.append(contentsOf: text[start..<next])
                start = next
            }
        }
        return output.precomposedStringWithCanonicalMapping
    }

    private static func readString(_ data: Data, recordAt offset: Int,
                                   stringsAt stringOffset: Int,
                                   stringsLength: Int) throws -> String {
        let relativeOffset = Int(try readUInt32(data, at: offset))
        let length = Int(try readUInt32(data, at: offset + 4))
        let end = relativeOffset.addingReportingOverflow(length)
        guard !end.overflow, relativeOffset <= stringsLength,
              end.partialValue <= stringsLength else {
            throw PinyinDictionaryCompilerError.invalidSimplification
        }
        let lowerBound = stringOffset + relativeOffset
        let upperBound = stringOffset + end.partialValue
        let bytes = data.subdata(in: lowerBound..<upperBound)
        guard let value = String(data: bytes, encoding: .utf8) else {
            throw PinyinDictionaryCompilerError.invalidSimplification
        }
        return value
    }

    private static func readUInt32(_ data: Data, at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else {
            throw PinyinDictionaryCompilerError.invalidSimplification
        }
        var value: UInt32 = 0
        for index in 0..<4 { value |= UInt32(data[offset + index]) << UInt32(index * 8) }
        return value
    }
}

struct PinyinDictionaryCompilation: Equatable, Sendable {
    let entries: [PinyinDictionaryEntry]
    let image: Data
    let manifest: Data
}

enum PinyinDictionaryCompiler {
    private struct UniqueKey: Hashable {
        let key: String
        let text: String
    }

    private struct NormalizedRecord {
        let key: String
        let text: String
        let weight: UInt64
    }

    private struct WubiChoice {
        let index: UInt32
        let record: DictionaryEntryRecord
    }

    static func compile(source: String, wb86Image: Data, sourceRevision: String,
                        upstreamSHA256: String, licenseIdentifier: String,
                        simplifier: PinyinTextSimplifier? = nil)
        throws -> PinyinDictionaryCompilation {
        guard !sourceRevision.isEmpty, !licenseIdentifier.isEmpty,
              upstreamSHA256.utf8.count == 64,
              upstreamSHA256.utf8.allSatisfy({ (0x30...0x39).contains($0)
                  || (0x61...0x66).contains($0) }) else {
            throw PinyinDictionaryCompilerError.invalidMetadata
        }
        let wb86: DecodedDictionaryV1
        do {
            wb86 = try DictionaryFormatV1.decode(wb86Image)
        } catch {
            throw PinyinDictionaryCompilerError.invalidWB86
        }
        let normalized = try parse(source, simplifier: simplifier)
        let reverseWubi = makeReverseWubiIndex(wb86.records)
        let entries = makeEntries(normalized, reverseWubi: reverseWubi)
        let sourceIdentifier = DictionaryChecksum.fnv1a64(Data(source.utf8))
        let image = try PinyinDictionaryFormatV1.encode(
            entries: entries,
            wb86BuildIdentifier: wb86.header.buildIdentifier,
            sourceIdentifier: sourceIdentifier
        )
        let reusedCount = entries.reduce(0) { partial, entry in
            partial + entry.candidates.filter { $0.wubiRecordIndex != nil }.count
        }
        var normalization = [
            "Unicode text normalized to NFC",
            "ASCII Pinyin lowercased and syllable spaces removed",
            "duplicate key-text pairs retain greatest weight",
            "keys sorted by ASCII bytes; candidates by weight descending then UTF-8 bytes",
            "each key retains at most 64 candidates",
            "WB86 hints prefer full four-code, then longer code, lower rank, packed code"
        ]
        if simplifier != nil {
            normalization.insert(
                "traditional variants normalized to product simplified text before dedupe",
                at: 1
            )
        }
        var manifest = try JSONSerialization.data(withJSONObject: [
            "candidateCount": entries.reduce(0) { $0 + $1.candidates.count },
            "format": "MWPY",
            "imageChecksumFNV1a64": hex(DictionaryChecksum.fnv1a64(image)),
            "keyCount": entries.count,
            "licenseIdentifier": licenseIdentifier,
            "maximumCandidatesPerKey": 64,
            "normalization": normalization,
            "restartInterval": Int(PinyinDictionaryHeaderV1.restartInterval),
            "reusedWB86TextCount": reusedCount,
            "schemaVersion": Int(PinyinDictionaryHeaderV1.schemaVersion),
            "sourceChecksumFNV1a64": hex(sourceIdentifier),
            "sourceRevision": sourceRevision,
            "upstreamSourceSHA256": upstreamSHA256,
            "wb86BuildIdentifier": hex(wb86.header.buildIdentifier)
        ], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        manifest.append(0x0a)
        return PinyinDictionaryCompilation(entries: entries, image: image, manifest: manifest)
    }

    private static func parse(_ source: String, simplifier: PinyinTextSimplifier?) throws
        -> [NormalizedRecord] {
        var inData = false
        var sawMarker = false
        var unique = [UniqueKey: NormalizedRecord]()
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.last == "\r" ? rawLine.dropLast() : rawLine[...]
            if !inData {
                if line == "..." {
                    inData = true
                    sawMarker = true
                }
                continue
            }
            if line.isEmpty || line.hasPrefix("#") { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3 else {
                throw PinyinDictionaryCompilerError.invalidRecord(line: lineNumber)
            }
            let rawText = String(fields[0])
            let nfcText = rawText.precomposedStringWithCanonicalMapping
            let text = simplifier?.simplify(nfcText) ?? nfcText
            guard !text.isEmpty,
                  rawText == rawText.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.unicodeScalars.contains(where: {
                      CharacterSet.controlCharacters.contains($0)
                  }) else {
                throw PinyinDictionaryCompilerError.invalidRecord(line: lineNumber)
            }
            let rawCode = String(fields[1])
            guard !rawCode.isEmpty,
                  rawCode.utf8.allSatisfy({ byte in
                      byte == 0x20 || (0x41...0x5a).contains(byte)
                          || (0x61...0x7a).contains(byte)
                  }),
                  let weight = UInt64(fields[2]) else {
                throw PinyinDictionaryCompilerError.invalidRecord(line: lineNumber)
            }
            let key = rawCode.lowercased().replacingOccurrences(of: " ", with: "")
            guard (1...32).contains(key.utf8.count),
                  key.utf8.allSatisfy({ (0x61...0x7a).contains($0) }) else {
                throw PinyinDictionaryCompilerError.invalidRecord(line: lineNumber)
            }
            let record = NormalizedRecord(key: key, text: text, weight: weight)
            let uniqueKey = UniqueKey(key: key, text: text)
            if let current = unique[uniqueKey], current.weight >= weight { continue }
            unique[uniqueKey] = record
        }
        guard sawMarker else { throw PinyinDictionaryCompilerError.missingDataMarker }
        guard !unique.isEmpty else { throw PinyinDictionaryCompilerError.invalidRecord(line: 0) }
        return unique.values.sorted(by: normalizedPrecedes)
    }

    private static func makeEntries(_ records: [NormalizedRecord],
                                    reverseWubi: [String: WubiChoice])
        -> [PinyinDictionaryEntry] {
        var entries = [PinyinDictionaryEntry]()
        var index = 0
        while index < records.count {
            let key = records[index].key
            var end = index + 1
            while end < records.count, records[end].key == key { end += 1 }
            let candidates = records[index..<end].prefix(64).map { record in
                let wubi = reverseWubi[record.text]
                return PinyinDictionaryCandidate(
                    text: record.text,
                    weight: record.weight,
                    wubiRecordIndex: wubi?.index,
                    wubiHint: wubi?.record.code
                )
            }
            entries.append(PinyinDictionaryEntry(key: key, candidates: candidates))
            index = end
        }
        return entries
    }

    private static func makeReverseWubiIndex(_ records: [DictionaryEntryRecord])
        -> [String: WubiChoice] {
        var choices = [String: WubiChoice]()
        for (offset, record) in records.enumerated() {
            guard let index = UInt32(exactly: offset) else { continue }
            let proposed = WubiChoice(index: index, record: record)
            if let existing = choices[record.text], !wubiChoicePrecedes(proposed, existing) {
                continue
            }
            choices[record.text] = proposed
        }
        return choices
    }

    private static func normalizedPrecedes(_ lhs: NormalizedRecord,
                                           _ rhs: NormalizedRecord) -> Bool {
        if lhs.key != rhs.key {
            return lhs.key.utf8.lexicographicallyPrecedes(rhs.key.utf8)
        }
        if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
        return lhs.text.utf8.lexicographicallyPrecedes(rhs.text.utf8)
    }

    private static func wubiChoicePrecedes(_ lhs: WubiChoice, _ rhs: WubiChoice) -> Bool {
        let lhsFull = lhs.record.code.length == 4
        let rhsFull = rhs.record.code.length == 4
        if lhsFull != rhsFull { return lhsFull }
        if lhs.record.code.length != rhs.record.code.length {
            return lhs.record.code.length > rhs.record.code.length
        }
        if lhs.record.rank != rhs.record.rank { return lhs.record.rank < rhs.record.rank }
        return lhs.record.code.packedValue < rhs.record.code.packedValue
    }

    private static func hex(_ value: UInt64) -> String {
        String(format: "%016llx", value)
    }
}

enum PinyinDictionaryCompilerCommand {
    private struct Options {
        let input: String
        let wubiImage: String
        let scriptConversion: String
        let output: String
        let manifest: String
        let licenseIdentifier: String
        let sourceRevision: String
        let upstreamSHA256: String

        init(arguments: [String]) throws {
            guard arguments.count == 16 else { throw PinyinDictionaryCompilerError.usage }
            var values = [String: String]()
            var index = 0
            let accepted = ["--input", "--wubi-image", "--script-conversion",
                            "--output", "--manifest",
                            "--license-id", "--source-revision", "--upstream-sha256"]
            while index < arguments.count {
                let key = arguments[index]
                guard accepted.contains(key), index + 1 < arguments.count,
                      !arguments[index + 1].isEmpty,
                      values.updateValue(arguments[index + 1], forKey: key) == nil else {
                    throw PinyinDictionaryCompilerError.usage
                }
                index += 2
            }
            guard let input = values["--input"],
                  let wubiImage = values["--wubi-image"],
                  let scriptConversion = values["--script-conversion"],
                  let output = values["--output"],
                  let manifest = values["--manifest"],
                  let licenseIdentifier = values["--license-id"],
                  let sourceRevision = values["--source-revision"],
                  let upstreamSHA256 = values["--upstream-sha256"] else {
                throw PinyinDictionaryCompilerError.usage
            }
            self.input = input
            self.wubiImage = wubiImage
            self.scriptConversion = scriptConversion
            self.output = output
            self.manifest = manifest
            self.licenseIdentifier = licenseIdentifier
            self.sourceRevision = sourceRevision
            self.upstreamSHA256 = upstreamSHA256
        }
    }

    static func run(arguments: [String]) throws {
        let options = try Options(arguments: arguments)
        let sourceData: Data
        let wb86Image: Data
        let scriptConversion: Data
        do {
            sourceData = try Data(contentsOf: URL(fileURLWithPath: options.input),
                                  options: .mappedIfSafe)
            wb86Image = try Data(contentsOf: URL(fileURLWithPath: options.wubiImage),
                                 options: .mappedIfSafe)
            scriptConversion = try Data(
                contentsOf: URL(fileURLWithPath: options.scriptConversion),
                options: .mappedIfSafe
            )
        } catch {
            throw PinyinDictionaryCompilerError.unreadableInput
        }
        guard let source = String(data: sourceData, encoding: .utf8) else {
            throw PinyinDictionaryCompilerError.invalidUTF8
        }
        let simplifier: PinyinTextSimplifier
        do {
            simplifier = try PinyinTextSimplifier(data: scriptConversion)
        } catch {
            throw PinyinDictionaryCompilerError.invalidSimplification
        }
        let compilation = try PinyinDictionaryCompiler.compile(
            source: source,
            wb86Image: wb86Image,
            sourceRevision: options.sourceRevision,
            upstreamSHA256: options.upstreamSHA256,
            licenseIdentifier: options.licenseIdentifier,
            simplifier: simplifier
        )
        do {
            try compilation.image.write(to: URL(fileURLWithPath: options.output), options: .atomic)
            try compilation.manifest.write(to: URL(fileURLWithPath: options.manifest), options: .atomic)
        } catch {
            throw PinyinDictionaryCompilerError.outputFailure
        }
    }
}
