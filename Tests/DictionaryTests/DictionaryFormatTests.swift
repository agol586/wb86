import Foundation
import XCTest
@testable import MacWubi

final class DictionaryFormatTests: XCTestCase {
    func testFNV1a64KnownVector() {
        XCTAssertEqual(DictionaryChecksum.fnv1a64(Data("hello".utf8)), 0xa430_d846_80aa_bd0b)
    }

    func testV1RoundTripPreservesStableOrderingAndUTF8() throws {
        let records = try [
            DictionaryEntryRecord(code: XCTUnwrap(InputCode("a")), rank: 0, text: "工"),
            DictionaryEntryRecord(code: XCTUnwrap(InputCode("aa")), rank: 0, text: "式"),
            DictionaryEntryRecord(code: XCTUnwrap(InputCode("ab")), rank: 2, text: "节")
        ]

        let image = try DictionaryFormatV1.encode(records: records, buildIdentifier: 7)
        let decoded = try DictionaryFormatV1.decode(image)

        XCTAssertEqual(decoded.header.magic, "WB86")
        XCTAssertEqual(decoded.header.schemaVersion, 1)
        XCTAssertEqual(decoded.header.buildIdentifier, 7)
        XCTAssertEqual(decoded.records, records)
        XCTAssertEqual(decoded.prefixRanges.count, 650)
    }

    func testCorruptionFailsChecksumValidation() throws {
        var image = try fixtureImage()
        image[DictionaryHeaderV1.byteCount] ^= 0xff
        XCTAssertThrowsError(try DictionaryFormatV1.decode(image)) {
            XCTAssertEqual($0 as? DictionaryFormatError, .checksumMismatch)
        }
    }

    func testTruncatedAndOutOfBoundsImagesAreRejected() throws {
        let image = try fixtureImage()
        XCTAssertThrowsError(try DictionaryFormatV1.decode(Data(image.prefix(20)))) {
            XCTAssertEqual($0 as? DictionaryFormatError, .invalidBounds)
        }
    }

    func testEncoderRejectsUnstableRecordOrdering() throws {
        let records = try [
            DictionaryEntryRecord(code: XCTUnwrap(InputCode("b")), rank: 0, text: "了"),
            DictionaryEntryRecord(code: XCTUnwrap(InputCode("a")), rank: 0, text: "工")
        ]
        XCTAssertThrowsError(try DictionaryFormatV1.encode(records: records, buildIdentifier: 1)) {
            XCTAssertEqual($0 as? DictionaryFormatError, .invalidOrdering)
        }
    }

    func testInvalidUTF8IsRejectedAfterChecksumValidation() throws {
        var image = try fixtureImage()
        let decoded = try DictionaryFormatV1.decode(image)
        image[Int(decoded.header.stringOffset)] = 0xff
        DictionaryFormatV1.replaceChecksum(in: &image)

        XCTAssertThrowsError(try DictionaryFormatV1.decode(image)) {
            XCTAssertEqual($0 as? DictionaryFormatError, .invalidUTF8)
        }
        XCTAssertThrowsError(try DictionaryFormatV1.validateMappedImage(image)) {
            XCTAssertEqual($0 as? DictionaryFormatError, .invalidUTF8)
        }
    }

    func testMappedLoaderCollapsesEveryValidationFailure() throws {
        var image = try fixtureImage()
        image[DictionaryHeaderV1.byteCount] ^= 0xff
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try image.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try DictionaryLoader.load(from: url)) {
            XCTAssertEqual($0 as? DictionaryLoadError, .invalidDictionary)
        }
    }

    func testMappedValidationMatchesCompleteDecodeWithoutRetainingRecords() throws {
        let image = try fixtureImage()
        let complete = try DictionaryFormatV1.decode(image)
        let mapped = try DictionaryFormatV1.validateMappedImage(image)

        XCTAssertEqual(mapped.header, complete.header)
        XCTAssertEqual(mapped.prefixRanges, complete.prefixRanges)
    }

    func testIndexUsesPrefixRangeAndReturnsExactCodeInRankOrder() throws {
        let records = try [
            DictionaryEntryRecord(code: XCTUnwrap(InputCode("a")), rank: 0, text: "工"),
            DictionaryEntryRecord(code: XCTUnwrap(InputCode("aa")), rank: 0, text: "式"),
            DictionaryEntryRecord(code: XCTUnwrap(InputCode("ab")), rank: 0, text: "节"),
            DictionaryEntryRecord(code: XCTUnwrap(InputCode("wqvb")), rank: 0, text: "你好"),
            DictionaryEntryRecord(code: XCTUnwrap(InputCode("wqvb")), rank: 1, text: "您好")
        ]
        let image = try DictionaryFormatV1.encode(records: records, buildIdentifier: 3)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try image.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let index = DictionaryIndex(image: try DictionaryLoader.load(from: url))
        XCTAssertEqual(index.lookup(try XCTUnwrap(InputCode("wqvb"))).map(\.text), ["你好", "您好"])
        XCTAssertEqual(index.records(matchingPrefix: try XCTUnwrap(InputCode("wq"))).map(\.text),
                       ["你好", "您好"])
        XCTAssertTrue(index.lookup(try XCTUnwrap(InputCode("y"))).isEmpty)
    }

    private func fixtureImage() throws -> Data {
        try DictionaryFormatV1.encode(records: [
            DictionaryEntryRecord(code: XCTUnwrap(InputCode("a")), rank: 0, text: "工")
        ], buildIdentifier: 1)
    }
}
