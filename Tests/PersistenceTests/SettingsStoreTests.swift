import Foundation
import XCTest
@testable import MacWubi

final class SettingsStoreTests: XCTestCase {
    func testV2SnapshotPublishesOnlyAfterAtomicValidatedReadback() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWubiSettingsSnapshot-\(UUID().uuidString)")
        let writer = try SnapshotWriter(rootURL: root)
        let store = try SettingsStore(writer: writer)
        XCTAssertEqual(store.snapshot, SettingsSnapshot(generation: 0, settings: .default))

        var first = InputSettings.default
        first.candidatePageSize = 7
        try store.save(first)
        XCTAssertEqual(store.snapshot, SettingsSnapshot(generation: 1, settings: first))
        XCTAssertEqual(try SettingsStore(writer: SnapshotWriter(rootURL: root)).snapshot,
                       store.snapshot)

        var second = first
        second.candidatePageSize = 9
        try store.save(second)
        let published = store.snapshot
        XCTAssertEqual(published.generation, 2)

        writer.failureInjector = { stage in
            if stage == .afterTemporaryValidation { throw TestError.interrupted }
        }
        var rejected = second
        rejected.candidatePageSize = 6
        XCTAssertThrowsError(try store.save(rejected))
        XCTAssertEqual(store.snapshot, published)
        XCTAssertEqual(try writer.load(.settings)?.generation, published.generation)

        var invalid = second
        invalid.candidatePageSize = 32
        XCTAssertThrowsError(try store.save(invalid))
        XCTAssertEqual(store.snapshot, published)
    }

    func testDefaultsValidationAndKeyConflicts() throws {
        let fresh = InputSettings.newInstallDefault
        XCTAssertEqual(fresh.candidatePageSize, 5)
        XCTAssertEqual(fresh.defaultMode, InputMode(language: .chinese, punctuation: .english,
                                                    width: .half, script: .simplified))
        XCTAssertTrue(fresh.autoCommitAtFour)
        XCTAssertFalse(fresh.autoCommitFirstAtFive)
        XCTAssertFalse(fresh.automaticFrequency)
        XCTAssertTrue(fresh.mixedPinyinEnabled)
        XCTAssertTrue(fresh.codeHintEnabled)
        XCTAssertFalse(fresh.candidate2And3ShortcutsEnabled)
        XCTAssertEqual(InputSettings.default, fresh)

        let compatible = InputSettings.migrationCompatibilityDefault
        XCTAssertEqual(compatible.defaultMode, .default)
        XCTAssertFalse(compatible.autoCommitAtFour)
        XCTAssertFalse(compatible.autoCommitFirstAtFive)
        XCTAssertTrue(compatible.automaticFrequency)
        XCTAssertFalse(compatible.mixedPinyinEnabled)
        XCTAssertFalse(compatible.codeHintEnabled)
        XCTAssertFalse(compatible.candidate2And3ShortcutsEnabled)

        XCTAssertThrowsError(try InputSettings(candidatePageSize: 4))
        XCTAssertThrowsError(try InputSettings(candidateFontScale: 3))
        XCTAssertThrowsError(try KeyBindingSettings(modeSwitch: .custom("control-space"),
                                                    pageKeys: .minusEquals))
    }

    func testPersistenceAndRestoreDoNotTouchOtherDomains() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWubiSettingsTests-\(UUID().uuidString)")
        let writer = try SnapshotWriter(rootURL: root)
        try writer.commit(try DataSnapshot(domain: .userLexicon, schemaVersion: 1,
                                           generation: 1, payload: Data("user".utf8)))
        try writer.commit(try DataSnapshot(domain: .learning, schemaVersion: 1,
                                           generation: 1, payload: Data("learning".utf8)))
        let userBefore = try Data(contentsOf: writer.currentURL(for: .userLexicon))
        let learningBefore = try Data(contentsOf: writer.currentURL(for: .learning))
        let store = try SettingsStore(writer: writer)
        var changed = InputSettings.default
        changed.candidatePageSize = 9
        try store.save(changed)
        XCTAssertEqual(try SettingsStore(writer: SnapshotWriter(rootURL: root)).settings,
                       changed)
        try store.restoreDefaults()
        XCTAssertEqual(store.settings, .default)
        XCTAssertEqual(try Data(contentsOf: writer.currentURL(for: .userLexicon)), userBefore)
        XCTAssertEqual(try Data(contentsOf: writer.currentURL(for: .learning)), learningBefore)
    }

    func testCoordinatorDefersApplicationUntilEverySessionIsIdle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWubiSettingsApply-\(UUID().uuidString)")
        let coordinator = SettingsCoordinator(
            store: try SettingsStore(writer: SnapshotWriter(rootURL: root))
        )
        let session = SettingsSessionSpy()
        coordinator.register(session)
        session.applied.removeAll()
        session.currentState = try .composing(
            code: XCTUnwrap(InputCode("a")),
            candidates: CandidatePage(items: [], pageIndex: 0, pageSize: 5, totalCount: 0),
            pageIndex: 0, selectionIndex: nil
        )
        var changed = InputSettings.default
        changed.candidatePageSize = 7
        try coordinator.save(changed)
        XCTAssertTrue(session.applied.isEmpty)
        session.currentState = .idle
        coordinator.applyPendingAtIdle()
        XCTAssertEqual(session.applied, [changed])
    }
}

private enum TestError: Error { case interrupted }

private final class SettingsSessionSpy: SettingsSessionControlling {
    var currentState = CompositionState.idle
    var state: CompositionState { currentState }
    var applied = [InputSettings]()
    func apply(settings: InputSettings) { applied.append(settings) }
}
