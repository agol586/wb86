import Foundation

enum ScriptConversionCompilerError: Error, CustomStringConvertible {
    case usage
    case unreadableInput
    case invalidUTF8
    case invalidRecord(file: String, line: Int)
    case duplicateOption
    case tooLarge
    case outputFailure

    var description: String {
        switch self {
        case .usage:
            return "usage: macwubi-dictionary-compiler script-conversion --characters STCharacters.txt --phrases STPhrases.txt --output script-conversion.bin --manifest script-conversion.manifest.json --license-id ID --source-revision REVISION"
        case .unreadableInput: return "conversion input could not be read"
        case .invalidUTF8: return "conversion input is not valid UTF-8"
        case let .invalidRecord(file, line): return "invalid conversion record in \(file) at line \(line)"
        case .duplicateOption: return "an option was provided more than once"
        case .tooLarge: return "conversion resource exceeds its bounded format"
        case .outputFailure: return "compiled conversion output could not be written"
        }
    }
}

enum ScriptConversionCompilerCommand {
    private struct Options {
        let characters: String
        let phrases: String
        let output: String
        let manifest: String
        let licenseIdentifier: String
        let sourceRevision: String

        init(arguments: [String]) throws {
            guard arguments.count == 12 else { throw ScriptConversionCompilerError.usage }
            var values = [String: String]()
            var index = 0
            while index < arguments.count {
                let key = arguments[index]
                guard ["--characters", "--phrases", "--output", "--manifest",
                       "--license-id", "--source-revision"].contains(key),
                      index + 1 < arguments.count, !arguments[index + 1].isEmpty else {
                    throw ScriptConversionCompilerError.usage
                }
                guard values.updateValue(arguments[index + 1], forKey: key) == nil else {
                    throw ScriptConversionCompilerError.duplicateOption
                }
                index += 2
            }
            guard let characters = values["--characters"],
                  let phrases = values["--phrases"],
                  let output = values["--output"],
                  let manifest = values["--manifest"],
                  let licenseIdentifier = values["--license-id"],
                  let sourceRevision = values["--source-revision"] else {
                throw ScriptConversionCompilerError.usage
            }
            self.characters = characters
            self.phrases = phrases
            self.output = output
            self.manifest = manifest
            self.licenseIdentifier = licenseIdentifier
            self.sourceRevision = sourceRevision
        }
    }

    static func run(arguments: [String]) throws {
        let options = try Options(arguments: arguments)
        var mappings = try parse(path: options.characters)
        for (source, target) in try parse(path: options.phrases) {
            mappings[source] = target
        }
        let ordered = mappings.sorted {
            Array($0.key.utf8).lexicographicallyPrecedes(Array($1.key.utf8))
        }
        let image = try encode(ordered)
        let maxSourceLength = ordered.map { $0.key.count }.max() ?? 0
        var manifest = try JSONSerialization.data(withJSONObject: [
            "format": "MWSC",
            "imageChecksumFNV1a64": hex(DictionaryChecksum.fnv1a64(image)),
            "licenseIdentifier": options.licenseIdentifier,
            "maxSourceLength": maxSourceLength,
            "normalization": [
                "Unicode source and target normalized to NFC",
                "first listed OpenCC target selected deterministically",
                "phrase mappings override character mappings",
                "records sorted by source UTF-8 bytes"
            ],
            "recordCount": ordered.count,
            "schemaVersion": 1,
            "sourceRevision": options.sourceRevision
        ], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        manifest.append(0x0a)
        do {
            try image.write(to: URL(fileURLWithPath: options.output), options: .atomic)
            try manifest.write(to: URL(fileURLWithPath: options.manifest), options: .atomic)
        } catch {
            throw ScriptConversionCompilerError.outputFailure
        }
    }

    private static func parse(path: String) throws -> [String: String] {
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
        } catch {
            throw ScriptConversionCompilerError.unreadableInput
        }
        guard let contents = String(data: data, encoding: .utf8) else {
            throw ScriptConversionCompilerError.invalidUTF8
        }
        var result = [String: String]()
        for (offset, rawLine) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = rawLine.last == "\r" ? rawLine.dropLast() : rawLine[...]
            if line.isEmpty || line.hasPrefix("#") { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 2,
                  let firstTarget = fields[1].split(separator: " ").first else {
                throw ScriptConversionCompilerError.invalidRecord(file: path, line: offset + 1)
            }
            let source = String(fields[0]).precomposedStringWithCanonicalMapping
            let target = String(firstTarget).precomposedStringWithCanonicalMapping
            guard !source.isEmpty, !target.isEmpty,
                  source.count <= 64, target.utf8.count <= 1_024 else {
                throw ScriptConversionCompilerError.invalidRecord(file: path, line: offset + 1)
            }
            result[source] = target
        }
        return result
    }

    private static func encode(_ mappings: [(key: String, value: String)]) throws -> Data {
        guard mappings.count <= 100_000 else { throw ScriptConversionCompilerError.tooLarge }
        let headerSize: UInt32 = 40
        let recordSize: UInt32 = 16
        guard let recordCount = UInt32(exactly: mappings.count) else {
            throw ScriptConversionCompilerError.tooLarge
        }
        let recordsLength = recordCount.multipliedReportingOverflow(by: recordSize)
        guard !recordsLength.overflow else { throw ScriptConversionCompilerError.tooLarge }

        var strings = Data()
        var records = Data()
        for mapping in mappings {
            let source = Data(mapping.key.utf8)
            let target = Data(mapping.value.utf8)
            guard let sourceOffset = UInt32(exactly: strings.count),
                  let sourceLength = UInt32(exactly: source.count) else {
                throw ScriptConversionCompilerError.tooLarge
            }
            strings.append(source)
            guard let targetOffset = UInt32(exactly: strings.count),
                  let targetLength = UInt32(exactly: target.count) else {
                throw ScriptConversionCompilerError.tooLarge
            }
            strings.append(target)
            records.appendLE(sourceOffset)
            records.appendLE(sourceLength)
            records.appendLE(targetOffset)
            records.appendLE(targetLength)
        }
        guard strings.count <= 16 * 1_024 * 1_024,
              let stringsLength = UInt32(exactly: strings.count) else {
            throw ScriptConversionCompilerError.tooLarge
        }
        let stringsOffset = headerSize + recordsLength.partialValue
        let totalLength = stringsOffset.addingReportingOverflow(stringsLength)
        guard !totalLength.overflow else { throw ScriptConversionCompilerError.tooLarge }
        var payload = records
        payload.append(strings)

        var image = Data("MWSC".utf8)
        image.appendLE(UInt16(1))
        image.appendLE(UInt16(headerSize))
        image.appendLE(recordCount)
        image.appendLE(headerSize)
        image.appendLE(stringsOffset)
        image.appendLE(stringsLength)
        image.appendLE(DictionaryChecksum.fnv1a64(payload))
        image.appendLE(totalLength.partialValue)
        image.appendLE(UInt32(mappings.map { $0.key.count }.max() ?? 0))
        image.append(payload)
        return image
    }

    private static func hex(_ value: UInt64) -> String {
        String(format: "%016llx", value)
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
