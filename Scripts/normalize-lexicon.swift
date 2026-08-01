#!/usr/bin/env swift

import Foundation

private enum NormalizationError: Error, CustomStringConvertible {
    case usage
    case unreadableInput
    case invalidUTF8
    case missingDataMarker
    case invalidRecord(Int)

    var description: String {
        switch self {
        case .usage: return "usage: normalize-lexicon.swift INPUT.yaml OUTPUT.tsv"
        case .unreadableInput: return "lexicon source could not be read"
        case .invalidUTF8: return "lexicon source is not valid UTF-8"
        case .missingDataMarker: return "lexicon source has no YAML data marker"
        case let .invalidRecord(line): return "invalid lexicon record at line \(line)"
        }
    }
}

private struct Key: Hashable {
    let code: String
    let text: String
}

private struct SourceRecord {
    let code: String
    let text: String
    let weight: UInt64
}

do {
    guard CommandLine.arguments.count == 3 else { throw NormalizationError.usage }
    let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
    guard let bytes = try? Data(contentsOf: inputURL, options: .mappedIfSafe) else {
        throw NormalizationError.unreadableInput
    }
    guard let source = String(data: bytes, encoding: .utf8) else {
        throw NormalizationError.invalidUTF8
    }

    var sawMarker = false
    var unique = [Key: SourceRecord]()
    for (offset, rawLine) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
        let lineNumber = offset + 1
        let line = rawLine.last == "\r" ? rawLine.dropLast() : rawLine[...]
        if !sawMarker {
            sawMarker = line == "..."
            continue
        }
        if line.isEmpty || line.hasPrefix("#") { continue }
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard fields.count >= 2 else { throw NormalizationError.invalidRecord(lineNumber) }
        let text = String(fields[0]).precomposedStringWithCanonicalMapping
        let code = String(fields[1]).lowercased()
        guard (1...4).contains(code.utf8.count),
              code.utf8.allSatisfy({ (97...121).contains($0) }) else {
            continue
        }
        guard !text.isEmpty,
              text == text.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw NormalizationError.invalidRecord(lineNumber)
        }
        let weight: UInt64
        if fields.count < 3 || fields[2].isEmpty {
            weight = 0
        } else if let parsed = UInt64(fields[2]) {
            weight = parsed
        } else {
            throw NormalizationError.invalidRecord(lineNumber)
        }
        let key = Key(code: code, text: text)
        if let old = unique[key], old.weight >= weight { continue }
        unique[key] = SourceRecord(code: code, text: text, weight: weight)
    }
    guard sawMarker else { throw NormalizationError.missingDataMarker }

    let grouped = Dictionary(grouping: unique.values, by: \.code)
    var normalized = [(code: String, text: String, rank: Int)]()
    normalized.reserveCapacity(unique.count)
    for (code, records) in grouped {
        let ordered = records.sorted { lhs, rhs in
            if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
            return lhs.text.utf8.lexicographicallyPrecedes(rhs.text.utf8)
        }
        normalized.append(contentsOf: ordered.enumerated().map {
            (code: code, text: $0.element.text, rank: $0.offset)
        })
    }
    normalized.sort { lhs, rhs in
        let leftPacked = packedCode(lhs.code)
        let rightPacked = packedCode(rhs.code)
        if leftPacked != rightPacked { return leftPacked < rightPacked }
        if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
        return lhs.text.utf8.lexicographicallyPrecedes(rhs.text.utf8)
    }

    let output = normalized.map { "\($0.code)\t\($0.text)\t\($0.rank)\n" }.joined()
    try Data(output.utf8).write(to: outputURL, options: .atomic)
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(64)
}

private func packedCode(_ code: String) -> UInt32 {
    code.utf8.enumerated().reduce(UInt32(0)) { partial, pair in
        partial | UInt32(pair.element - 96) << UInt32((3 - pair.offset) * 5)
    }
}
