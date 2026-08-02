import Foundation
import XCTest
@testable import MacWubi

final class PinyinDictionaryFormatTests: XCTestCase {
    func testMWPYHeaderRoundTripAndWB86BuildIdentifier() throws {
        let image = try fixtureImage()
        let decoded = try PinyinDictionaryFormatV1.decode(
            image, expectedWB86BuildIdentifier: 0x1122_3344_5566_7788
        )

        XCTAssertEqual(decoded.header.magic, "MWPY")
        XCTAssertEqual(decoded.header.schemaVersion, 1)
        XCTAssertEqual(decoded.header.wb86BuildIdentifier, 0x1122_3344_5566_7788)
        XCTAssertEqual(decoded.header.restartInterval, 32)
        XCTAssertEqual(decoded.header.bucketCount, 702)
        XCTAssertEqual(decoded.entries.map(\.key), ["ni", "nihao", "zhong"])
        XCTAssertEqual(decoded.entries[0].candidates.compactMap(\.text), ["你", "呢"])
        XCTAssertEqual(decoded.entries[1].candidates.first?.wubiRecordIndex, 42)
        XCTAssertEqual(decoded.entries[1].candidates.first?.wubiHint?.letters, "wqvb")
    }

    func testOffsetAndCountOverflowAreRejectedBeforeSlicing() throws {
        var offsetOverflow = try fixtureImage()
        offsetOverflow.replaceLittleEndian(UInt32.max, at: 24)
        XCTAssertThrowsError(try PinyinDictionaryFormatV1.decode(
            offsetOverflow, expectedWB86BuildIdentifier: 0x1122_3344_5566_7788
        )) {
            XCTAssertEqual($0 as? PinyinDictionaryFormatError, .invalidBounds)
        }

        var countOverflow = try fixtureImage()
        countOverflow.replaceLittleEndian(UInt32.max, at: 28)
        XCTAssertThrowsError(try PinyinDictionaryFormatV1.decode(
            countOverflow, expectedWB86BuildIdentifier: 0x1122_3344_5566_7788
        )) {
            XCTAssertEqual($0 as? PinyinDictionaryFormatError, .invalidBounds)
        }
    }

    func testChecksumCoversAllSectionsAfterHeader() throws {
        var image = try fixtureImage()
        image[PinyinDictionaryHeaderV1.byteCount] ^= 0xff

        XCTAssertThrowsError(try PinyinDictionaryFormatV1.decode(
            image, expectedWB86BuildIdentifier: 0x1122_3344_5566_7788
        )) {
            XCTAssertEqual($0 as? PinyinDictionaryFormatError, .checksumMismatch)
        }
    }

    func testRestartAndFrontCodeRulesAreStrictlyValidated() throws {
        let decoded = try PinyinDictionaryFormatV1.decode(
            fixtureImage(), expectedWB86BuildIdentifier: 0x1122_3344_5566_7788
        )

        var missingRestart = try fixtureImage()
        missingRestart[Int(decoded.header.keyRecordOffset) + 2] = 0
        PinyinDictionaryFormatV1.replaceChecksum(in: &missingRestart)
        XCTAssertThrowsError(try PinyinDictionaryFormatV1.decode(
            missingRestart, expectedWB86BuildIdentifier: 0x1122_3344_5566_7788
        )) {
            XCTAssertEqual($0 as? PinyinDictionaryFormatError, .invalidFrontCoding)
        }

        var invalidPrefix = try fixtureImage()
        invalidPrefix[Int(decoded.header.keyRecordOffset) + PinyinKeyRecordV1.byteCount] = 32
        PinyinDictionaryFormatV1.replaceChecksum(in: &invalidPrefix)
        XCTAssertThrowsError(try PinyinDictionaryFormatV1.decode(
            invalidPrefix, expectedWB86BuildIdentifier: 0x1122_3344_5566_7788
        )) {
            XCTAssertEqual($0 as? PinyinDictionaryFormatError, .invalidFrontCoding)
        }
    }

    func testThirtySecondKeyBoundaryRequiresANewFullRestart() throws {
        let keys = (["a"] + (UInt8(ascii: "a")...UInt8(ascii: "z")).map {
            "a" + String(UnicodeScalar($0))
        } + ["b", "ba", "bb", "bc", "bd", "be"])
        XCTAssertEqual(keys.count, 33)
        var image = try PinyinDictionaryFormatV1.encode(
            entries: keys.map {
                PinyinDictionaryEntry(key: $0, candidates: [
                    PinyinDictionaryCandidate(text: "词", weight: 1)
                ])
            },
            wb86BuildIdentifier: 7,
            sourceIdentifier: 8
        )
        let decoded = try PinyinDictionaryFormatV1.decode(
            image, expectedWB86BuildIdentifier: 7
        )
        let checkpoint = Int(decoded.header.keyRecordOffset) + 32 * PinyinKeyRecordV1.byteCount
        image[checkpoint + 2] = 0
        PinyinDictionaryFormatV1.replaceChecksum(in: &image)

        XCTAssertThrowsError(try PinyinDictionaryFormatV1.decode(
            image, expectedWB86BuildIdentifier: 7
        )) {
            XCTAssertEqual($0 as? PinyinDictionaryFormatError, .invalidFrontCoding)
        }
    }

    func testMismatchedWB86BuildIdentifierDisablesTheEnvelope() throws {
        XCTAssertThrowsError(try PinyinDictionaryFormatV1.decode(
            fixtureImage(), expectedWB86BuildIdentifier: 9
        )) {
            XCTAssertEqual($0 as? PinyinDictionaryFormatError, .wb86BuildMismatch)
        }
    }

    private func fixtureImage() throws -> Data {
        try PinyinDictionaryFormatV1.encode(
            entries: [
                PinyinDictionaryEntry(key: "ni", candidates: [
                    PinyinDictionaryCandidate(text: "你", weight: 20),
                    PinyinDictionaryCandidate(text: "呢", weight: 10)
                ]),
                PinyinDictionaryEntry(key: "nihao", candidates: [
                    PinyinDictionaryCandidate(text: "你好", weight: 30,
                                              wubiRecordIndex: 42,
                                              wubiHint: XCTUnwrap(InputCode("wqvb")))
                ]),
                PinyinDictionaryEntry(key: "zhong", candidates: [
                    PinyinDictionaryCandidate(text: "中", weight: 15)
                ])
            ],
            wb86BuildIdentifier: 0x1122_3344_5566_7788,
            sourceIdentifier: 7
        )
    }
}

private extension Data {
    mutating func replaceLittleEndian<T: FixedWidthInteger>(_ value: T, at offset: Int) {
        var encoded = value.littleEndian
        Swift.withUnsafeBytes(of: &encoded) {
            replaceSubrange(offset..<(offset + $0.count), with: $0)
        }
    }
}
