import Foundation
import Darwin

private enum CompilerError: Error, CustomStringConvertible {
    case usage
    case unreadableInput
    case invalidUTF8
    case invalidRecord(line: Int)
    case duplicateOption
    case outputFailure

    var description: String {
        switch self {
        case .usage:
            return "usage: macwubi-dictionary-compiler --input SOURCE.tsv --output wb86.bin --manifest wb86.manifest.json --license-id ID --source-revision REVISION [--upstream-sha256 SHA256]"
        case .unreadableInput: return "input could not be read"
        case .invalidUTF8: return "input is not valid UTF-8"
        case let .invalidRecord(line): return "invalid lexicon record at line \(line)"
        case .duplicateOption: return "an option was provided more than once"
        case .outputFailure: return "compiled output could not be written"
        }
    }
}

private struct Options {
    let input: String
    let output: String
    let manifest: String
    let licenseIdentifier: String
    let sourceRevision: String
    let upstreamSHA256: String?

    init(arguments: [String]) throws {
        guard arguments.count == 10 || arguments.count == 12 else { throw CompilerError.usage }
        var values = [String: String]()
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard ["--input", "--output", "--manifest", "--license-id", "--source-revision",
                   "--upstream-sha256"].contains(key),
                  index + 1 < arguments.count,
                  !arguments[index + 1].isEmpty else {
                throw CompilerError.usage
            }
            guard values.updateValue(arguments[index + 1], forKey: key) == nil else {
                throw CompilerError.duplicateOption
            }
            index += 2
        }
        guard let input = values["--input"],
              let output = values["--output"],
              let manifest = values["--manifest"],
              let licenseIdentifier = values["--license-id"],
              let sourceRevision = values["--source-revision"] else {
            throw CompilerError.usage
        }
        self.input = input
        self.output = output
        self.manifest = manifest
        self.licenseIdentifier = licenseIdentifier
        self.sourceRevision = sourceRevision
        upstreamSHA256 = values["--upstream-sha256"]
    }
}

private enum DictionaryCompilerCommand {
    static func run() {
        do {
            let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
            let sourceData: Data
            do {
                sourceData = try Data(contentsOf: URL(fileURLWithPath: options.input), options: .mappedIfSafe)
            } catch {
                throw CompilerError.unreadableInput
            }
            guard let source = String(data: sourceData, encoding: .utf8) else {
                throw CompilerError.invalidUTF8
            }
            let records = try parse(source)
            let canonicalSource = records.map {
                "\($0.code.letters)\t\($0.text)\t\($0.rank)\n"
            }.joined()
            let sourceChecksum = DictionaryChecksum.fnv1a64(Data(canonicalSource.utf8))
            let image = try DictionaryFormatV1.encode(
                records: records,
                buildIdentifier: sourceChecksum
            )
            var manifestObject: [String: Any] = [
                "buildIdentifier": hex(sourceChecksum),
                "format": "WB86",
                "imageChecksumFNV1a64": hex(DictionaryChecksum.fnv1a64(image)),
                "licenseIdentifier": options.licenseIdentifier,
                "normalization": [
                    "ASCII codes normalized to lowercase",
                    "Unicode text normalized to NFC",
                    "duplicate code-text pairs retain the lowest rank",
                    "records sorted by packed code, rank, then UTF-8 bytes"
                ],
                "recordCount": records.count,
                "schemaVersion": 1,
                "sourceChecksumFNV1a64": hex(sourceChecksum),
                "sourceRevision": options.sourceRevision
            ]
            if let upstreamSHA256 = options.upstreamSHA256 {
                manifestObject["upstreamSourceSHA256"] = upstreamSHA256
            }
            var manifest = try JSONSerialization.data(
                withJSONObject: manifestObject,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            manifest.append(0x0a)
            do {
                try image.write(to: URL(fileURLWithPath: options.output), options: .atomic)
                try manifest.write(to: URL(fileURLWithPath: options.manifest), options: .atomic)
            } catch {
                throw CompilerError.outputFailure
            }
        } catch {
            let message = (error as? CompilerError)?.description ?? "dictionary compilation failed"
            FileHandle.standardError.write(Data((message + "\n").utf8))
            Darwin.exit(64)
        }
    }

    private static func parse(_ source: String) throws -> [DictionaryEntryRecord] {
        var unique = [RecordKey: DictionaryEntryRecord]()
        for (offset, rawLine) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.last == "\r" ? rawLine.dropLast() : rawLine[...]
            if line.isEmpty || line.hasPrefix("#") { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 2 || fields.count == 3,
                  let code = InputCode(String(fields[0])) else {
                throw CompilerError.invalidRecord(line: lineNumber)
            }
            let rawText = String(fields[1])
            let text = rawText.precomposedStringWithCanonicalMapping
            guard !text.isEmpty,
                  text == text.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw CompilerError.invalidRecord(line: lineNumber)
            }
            let rank: UInt32
            if fields.count == 3 {
                guard let parsed = UInt32(fields[2]) else {
                    throw CompilerError.invalidRecord(line: lineNumber)
                }
                rank = parsed
            } else {
                rank = 0
            }
            let record = try DictionaryEntryRecord(code: code, rank: rank, text: text)
            let key = RecordKey(code: code, text: text)
            if let previous = unique[key], previous.rank <= rank { continue }
            unique[key] = record
        }
        return unique.values.sorted(by: recordPrecedes)
    }

    private static func recordPrecedes(_ lhs: DictionaryEntryRecord,
                                       _ rhs: DictionaryEntryRecord) -> Bool {
        if lhs.code != rhs.code { return lhs.code < rhs.code }
        if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
        return Array(lhs.text.utf8).lexicographicallyPrecedes(Array(rhs.text.utf8))
    }

    private static func hex(_ value: UInt64) -> String {
        String(format: "%016llx", value)
    }
}

private struct RecordKey: Hashable {
    let code: InputCode
    let text: String
}

let compilerArguments = Array(CommandLine.arguments.dropFirst())
if compilerArguments.first == "script-conversion" {
    do {
        try ScriptConversionCompilerCommand.run(arguments: Array(compilerArguments.dropFirst()))
    } catch {
        let message = (error as? ScriptConversionCompilerError)?.description
            ?? "script conversion compilation failed"
        FileHandle.standardError.write(Data((message + "\n").utf8))
        Darwin.exit(64)
    }
} else {
    DictionaryCompilerCommand.run()
}
