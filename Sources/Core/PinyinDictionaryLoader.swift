import Foundation

enum PinyinDictionaryLoadError: Error, Equatable {
    case invalidDictionary
}

/// A validated, read-only mapped Pinyin image. Construction is internal to the loader so callers
/// cannot observe a partially validated replacement.
final class PinyinDictionaryImage: @unchecked Sendable {
    let header: PinyinDictionaryHeaderV1
    let bucketRanges: [PinyinBucketRange]
    let bytes: Data
    let wb86Image: BaseDictionaryImage

    fileprivate init(bytes: Data, header: PinyinDictionaryHeaderV1,
                     bucketRanges: [PinyinBucketRange], wb86Image: BaseDictionaryImage) {
        self.bytes = bytes
        self.header = header
        self.bucketRanges = bucketRanges
        self.wb86Image = wb86Image
    }
}

enum PinyinDictionaryLoader {
    static func load(from url: URL, wb86Image: BaseDictionaryImage) throws
        -> PinyinDictionaryImage {
        do {
            let bytes = try Data(contentsOf: url, options: [.alwaysMapped, .uncached])
            let validated = try PinyinDictionaryFormatV1.validateMappedImage(
                bytes,
                expectedWB86BuildIdentifier: wb86Image.header.buildIdentifier,
                wb86RecordCount: wb86Image.header.recordCount
            )
            return PinyinDictionaryImage(
                bytes: bytes,
                header: validated.header,
                bucketRanges: validated.bucketRanges,
                wb86Image: wb86Image
            )
        } catch {
            // Deliberately collapse paths, bytes, offsets, and source text into one safe domain error.
            throw PinyinDictionaryLoadError.invalidDictionary
        }
    }

    static func loadIfValid(from url: URL, wb86Image: BaseDictionaryImage)
        -> PinyinDictionaryImage? {
        try? load(from: url, wb86Image: wb86Image)
    }
}
