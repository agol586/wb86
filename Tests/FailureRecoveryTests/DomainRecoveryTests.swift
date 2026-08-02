import Foundation
import XCTest
@testable import MacWubi

final class DomainRecoveryTests: XCTestCase {
    func testCorruptMutableDomainRecoversPreviousWithoutChangingOtherDomains() throws {
        for damaged in DataDomain.allCases {
            let writer = try SnapshotWriter(rootURL: temporaryRoot())
            for domain in DataDomain.allCases {
                try writer.commit(try snapshot(domain, generation: 1, text: "old-\(domain.rawValue)"))
                try writer.commit(try snapshot(domain, generation: 2, text: "new-\(domain.rawValue)"))
            }
            let unaffected = try Dictionary(uniqueKeysWithValues: DataDomain.allCases
                .filter { $0 != damaged }
                .map { ($0, try Data(contentsOf: writer.currentURL(for: $0))) })
            try Data("corrupt".utf8).write(to: writer.currentURL(for: damaged))
            var resets = 0
            let coordinator = DomainRecoveryCoordinator(writer: writer) { resets += 1 }

            XCTAssertEqual(try coordinator.recover(damaged, supportedSchemas: [1]),
                           .recoveredPrevious(generation: 1))
            XCTAssertEqual(resets, 1)
            XCTAssertEqual(try writer.load(damaged)?.generation, 1)
            for (domain, bytes) in unaffected {
                XCTAssertEqual(try Data(contentsOf: writer.currentURL(for: domain)), bytes)
            }
        }
    }

    func testNoValidSnapshotUsesSafeDefaultAndFutureVersionIsPreserved() throws {
        let writer = try SnapshotWriter(rootURL: temporaryRoot())
        try writer.commit(try snapshot(.settings, generation: 1, text: "only"))
        try Data("bad".utf8).write(to: writer.currentURL(for: .settings))
        var resets = 0
        let coordinator = DomainRecoveryCoordinator(writer: writer) { resets += 1 }
        XCTAssertEqual(try coordinator.recover(.settings, supportedSchemas: [1]), .safeDefault)
        XCTAssertEqual(resets, 1)

        let future = try DataSnapshot(domain: .learning, schemaVersion: 99,
                                      generation: 7, payload: Data("future".utf8))
        try writer.commit(future)
        XCTAssertEqual(try coordinator.recover(.learning, supportedSchemas: [1]),
                       .preservedFuture(version: 99))
        XCTAssertEqual(try writer.load(.learning), future)
    }

    func testCorruptBaseFallsBackAndNextValidInputRecovers() throws {
        var resets = 0
        let coordinator = DomainRecoveryCoordinator(
            writer: try SnapshotWriter(rootURL: temporaryRoot())) { resets += 1 }
        XCTAssertEqual(coordinator.validateBase(Data("bad".utf8)) { _ in false }, .safeDefault)
        XCTAssertEqual(resets, 1)

        var shouldFail = true
        let engine = InputEngine { code, page in
            if shouldFail { throw RecoveryFailure.expected }
            return try CandidatePage(items: [Candidate(text: "恢复", code: code, source: .base,
                                                       baseRank: 0, learnedScore: 0, ordinal: 1)],
                                     pageIndex: page, pageSize: 5, totalCount: 1)
        }
        XCTAssertEqual(engine.process(.letter("a")).state, .idle)
        shouldFail = false
        XCTAssertEqual(engine.process(.letter("a")).state.kind, .composing)
    }

    func testSettingsStartupRecoversValidPreviousAndBothCorruptUseSafeDefault() throws {
        let recoverableRoot = temporaryRoot()
        let recoverableWriter = try SnapshotWriter(rootURL: recoverableRoot)
        var previousSettings = InputSettings.default
        previousSettings.candidatePageSize = 7
        let previous = try settingsSnapshot(previousSettings, generation: 1)
        try recoverableWriter.commit(previous)
        var currentSettings = previousSettings
        currentSettings.candidatePageSize = 9
        try recoverableWriter.commit(try settingsSnapshot(currentSettings, generation: 2))
        try Data("corrupt current".utf8)
            .write(to: recoverableWriter.currentURL(for: .settings))

        let recovered = try SettingsStore(writer: SnapshotWriter(rootURL: recoverableRoot))
        XCTAssertEqual(recovered.snapshot,
                       SettingsSnapshot(generation: 1, settings: previousSettings))
        XCTAssertEqual(try SnapshotWriter(rootURL: recoverableRoot).load(.settings), previous)

        let isolatedRoot = temporaryRoot()
        let isolatedWriter = try SnapshotWriter(rootURL: isolatedRoot)
        try isolatedWriter.commit(try settingsSnapshot(.default, generation: 1))
        try isolatedWriter.commit(try settingsSnapshot(currentSettings, generation: 2))
        try isolatedWriter.commit(try snapshot(.userLexicon, generation: 3, text: "user"))
        let userBefore = try Data(contentsOf: isolatedWriter.currentURL(for: .userLexicon))
        try Data("bad current".utf8).write(to: isolatedWriter.currentURL(for: .settings))
        try Data("bad previous".utf8).write(to: isolatedWriter.previousURL(for: .settings))

        let safe = try SettingsStore(writer: SnapshotWriter(rootURL: isolatedRoot))
        XCTAssertEqual(safe.snapshot, SettingsSnapshot(generation: 0, settings: .default))
        XCTAssertEqual(safe.access, .readOnlyRecoveryFailure)
        XCTAssertThrowsError(try safe.restoreDefaults())
        XCTAssertEqual(try Data(contentsOf: isolatedWriter.currentURL(for: .userLexicon)),
                       userBefore)
    }

    private func snapshot(_ domain: DataDomain, generation: UInt64, text: String) throws -> DataSnapshot {
        try DataSnapshot(domain: domain, schemaVersion: 1, generation: generation,
                         payload: Data(text.utf8))
    }
    private func settingsSnapshot(_ settings: InputSettings,
                                  generation: UInt64) throws -> DataSnapshot {
        try DataSnapshot(domain: .settings, schemaVersion: InputSettings.schemaVersion,
                         generation: generation, payload: JSONEncoder.sorted.encode(settings))
    }
    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MacWubiRecovery-\(UUID().uuidString)")
    }
    private enum RecoveryFailure: Error { case expected }
}
