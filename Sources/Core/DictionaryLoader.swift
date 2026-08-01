import Foundation

enum DictionaryLoadError: Error, Equatable {
    case invalidDictionary
}

final class BaseDictionaryImage: @unchecked Sendable {
    let header: DictionaryHeaderV1
    let prefixRanges: [DictionaryPrefixRange]
    let bytes: Data

    fileprivate init(bytes: Data, header: DictionaryHeaderV1,
                     prefixRanges: [DictionaryPrefixRange]) {
        self.bytes = bytes
        self.header = header
        self.prefixRanges = prefixRanges
    }
}

enum DictionaryLoader {
    static func load(from url: URL) throws -> BaseDictionaryImage {
        do {
            let bytes = try Data(contentsOf: url, options: [.alwaysMapped, .uncached])
            let validated = try DictionaryFormatV1.validateMappedImage(bytes)
            return BaseDictionaryImage(
                bytes: bytes,
                header: validated.header,
                prefixRanges: validated.prefixRanges
            )
        } catch {
            throw DictionaryLoadError.invalidDictionary
        }
    }
}
