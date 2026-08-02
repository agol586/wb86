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

    func testMappedLoaderRetainsValidatedReadOnlyImageOnlyAfterCompleteValidation() throws {
        let wb86 = try mappedWB86Image(buildIdentifier: 31)
        let pinyin = try mappedFixtureImage(wb86BuildIdentifier: 31)
        try withTemporaryImage(pinyin) { url in
            let loaded = try PinyinDictionaryLoader.load(from: url, wb86Image: wb86)

            XCTAssertEqual(loaded.header.keyCount, 3)
            XCTAssertEqual(loaded.header.candidateCount, 4)
            XCTAssertEqual(loaded.bucketRanges.count, 702)
            XCTAssertEqual(loaded.bytes, pinyin)
            XCTAssertTrue(loaded.wb86Image === wb86)
        }
    }

    func testCheckedInPinyinImagePassesCompleteMappedValidationAgainstBundledWB86() throws {
        let resources = Bundle.main
        let wb86URL = try XCTUnwrap(resources.url(forResource: "wb86", withExtension: "bin"))
        let pinyinURL = try XCTUnwrap(
            resources.url(forResource: "pinyin-simp", withExtension: "bin")
        )
        let wb86 = try DictionaryLoader.load(from: wb86URL)

        let pinyin = try PinyinDictionaryLoader.load(from: pinyinURL, wb86Image: wb86)

        XCTAssertEqual(pinyin.header.keyCount, 38_999)
        XCTAssertEqual(pinyin.header.candidateCount, 60_742)
        XCTAssertEqual(pinyin.header.wb86BuildIdentifier, wb86.header.buildIdentifier)
    }

    func testMappedLoaderAtomicallyDisablesTruncatedAndStructurallyCorruptImages() throws {
        let wb86 = try mappedWB86Image(buildIdentifier: 31)
        let complete = try mappedFixtureImage(wb86BuildIdentifier: 31)
        let header = try PinyinDictionaryFormatV1.decode(
            complete, expectedWB86BuildIdentifier: 31
        ).header
        var corruptions = [
            Data(complete.prefix(20)),
            Data(complete.dropLast()),
            Data(complete.prefix(Int(header.candidateRecordOffset) + 3))
        ]

        var outOfOrder = complete
        outOfOrder[Int(header.keyBlobOffset)] = UInt8(ascii: "z")
        PinyinDictionaryFormatV1.replaceChecksum(in: &outOfOrder)
        corruptions.append(outOfOrder)

        for image in corruptions {
            try withTemporaryImage(image) { url in
                XCTAssertThrowsError(
                    try PinyinDictionaryLoader.load(from: url, wb86Image: wb86)
                ) {
                    XCTAssertEqual($0 as? PinyinDictionaryLoadError, .invalidDictionary)
                }
                XCTAssertNil(PinyinDictionaryLoader.loadIfValid(from: url, wb86Image: wb86))
            }
        }
    }

    func testMappedLoaderRejectsBadUTF8AndOutOfRangeWB86Reference() throws {
        let wb86 = try mappedWB86Image(buildIdentifier: 31)
        var invalidUTF8 = try mappedFixtureImage(wb86BuildIdentifier: 31)
        let decoded = try PinyinDictionaryFormatV1.decode(
            invalidUTF8, expectedWB86BuildIdentifier: 31
        )
        invalidUTF8[Int(decoded.header.textOffset)] = 0xff
        PinyinDictionaryFormatV1.replaceChecksum(in: &invalidUTF8)

        var badReference = try mappedFixtureImage(wb86BuildIdentifier: 31)
        let referencedCandidateOffset = Int(decoded.header.candidateRecordOffset)
            + 2 * PinyinCandidateRecordV1.byteCount
        badReference.replaceLittleEndian(UInt32(1), at: referencedCandidateOffset + 16)
        PinyinDictionaryFormatV1.replaceChecksum(in: &badReference)

        for image in [invalidUTF8, badReference] {
            try withTemporaryImage(image) { url in
                XCTAssertThrowsError(
                    try PinyinDictionaryLoader.load(from: url, wb86Image: wb86)
                ) {
                    XCTAssertEqual($0 as? PinyinDictionaryLoadError, .invalidDictionary)
                }
            }
        }
    }

    func testMappedLoaderRejectsWrongWB86BuildIdentifierWithoutReplacingCurrentImage() throws {
        let wb86 = try mappedWB86Image(buildIdentifier: 31)
        let valid = try mappedFixtureImage(wb86BuildIdentifier: 31)
        let wrong = try mappedFixtureImage(wb86BuildIdentifier: 32)
        var current: PinyinDictionaryImage?

        try withTemporaryImage(valid) { url in
            current = try PinyinDictionaryLoader.load(from: url, wb86Image: wb86)
        }
        try withTemporaryImage(wrong) { url in
            let replacement = PinyinDictionaryLoader.loadIfValid(from: url, wb86Image: wb86)
            XCTAssertNil(replacement)
        }

        XCTAssertEqual(current?.header.wb86BuildIdentifier, 31)
        XCTAssertEqual(current?.header.keyCount, 3)
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

    private func mappedFixtureImage(wb86BuildIdentifier: UInt64) throws -> Data {
        try PinyinDictionaryFormatV1.encode(
            entries: [
                PinyinDictionaryEntry(key: "ni", candidates: [
                    PinyinDictionaryCandidate(text: "你", weight: 20),
                    PinyinDictionaryCandidate(text: "呢", weight: 10)
                ]),
                PinyinDictionaryEntry(key: "nihao", candidates: [
                    PinyinDictionaryCandidate(text: "工", weight: 30,
                                              wubiRecordIndex: 0,
                                              wubiHint: XCTUnwrap(InputCode("a")))
                ]),
                PinyinDictionaryEntry(key: "zhong", candidates: [
                    PinyinDictionaryCandidate(text: "中", weight: 15)
                ])
            ],
            wb86BuildIdentifier: wb86BuildIdentifier,
            sourceIdentifier: 7
        )
    }

    private func mappedWB86Image(buildIdentifier: UInt64) throws -> BaseDictionaryImage {
        let image = try DictionaryFormatV1.encode(records: [
            DictionaryEntryRecord(code: XCTUnwrap(InputCode("a")), rank: 0, text: "工")
        ], buildIdentifier: buildIdentifier)
        var result: BaseDictionaryImage?
        try withTemporaryImage(image) { url in
            result = try DictionaryLoader.load(from: url)
        }
        return try XCTUnwrap(result)
    }

    private func withTemporaryImage<T>(_ image: Data, body: (URL) throws -> T) throws -> T {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try image.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try body(url)
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
