import Foundation
import XCTest
@testable import MacWubi

@MainActor
final class SettingsIntegrationTests: XCTestCase {
    func testSessionsFreezeActiveSnapshotAndKeepOnlyLatestPendingGeneration() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWubiSessionSnapshots-\(UUID().uuidString)")
        let store = try SettingsStore(writer: SnapshotWriter(rootURL: root))
        let coordinator = SettingsCoordinator(store: store)
        let idle = SettingsIntegrationSession()
        let composing = SettingsIntegrationSession()
        composing.state = try .composing(
            code: XCTUnwrap(InputCode("a")),
            candidates: CandidatePage(items: [], pageIndex: 0, pageSize: 5, totalCount: 0),
            pageIndex: 0,
            selectionIndex: nil
        )
        coordinator.register(idle)
        coordinator.register(composing)

        var first = InputSettings.default
        first.candidatePageSize = 7
        try coordinator.save(first)
        XCTAssertEqual(idle.activeSnapshot.generation, 1)
        XCTAssertNil(idle.pendingSnapshot)
        XCTAssertEqual(composing.activeSnapshot.generation, 0)
        XCTAssertEqual(composing.pendingSnapshot?.generation, 1)

        var latest = first
        latest.candidatePageSize = 9
        try coordinator.save(latest)
        XCTAssertEqual(idle.activeSnapshot, SettingsSnapshot(generation: 2, settings: latest))
        XCTAssertEqual(composing.pendingSnapshot,
                       SettingsSnapshot(generation: 2, settings: latest))

        composing.state = .idle
        coordinator.applyPendingAtIdle()
        XCTAssertEqual(composing.activeSnapshot,
                       SettingsSnapshot(generation: 2, settings: latest))
        XCTAssertNil(composing.pendingSnapshot)

        let newSession = SettingsIntegrationSession()
        coordinator.register(newSession)
        XCTAssertEqual(newSession.activeSnapshot,
                       SettingsSnapshot(generation: 2, settings: latest))
    }

    func testEverySettingPersistsAppliesAndRestoresWithoutPersonalizationLoss() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacWubiSettingsFlow-\(UUID().uuidString)")
        let writer = try SnapshotWriter(rootURL: root)
        let code = try XCTUnwrap(InputCode("wqvb"))
        try UserLexiconStore(writer: writer).upsert(code: code, text: "用户词",
                                                         fixedRank: 1, createdBy: .manual)
        try LearningStore(writer: writer).recordSelection(code: code,
                                                          candidateText: "学习词", amount: 3)
        let userBefore = try Data(contentsOf: writer.currentURL(for: .userLexicon))
        let learningBefore = try Data(contentsOf: writer.currentURL(for: .learning))

        let store = try SettingsStore(writer: writer)
        var globallyApplied = [InputSettings]()
        let coordinator = SettingsCoordinator(store: store) { globallyApplied.append($0) }
        let session = SettingsIntegrationSession()
        coordinator.register(session)
        session.applied.removeAll()

        let changed = try InputSettings(
            candidatePageSize: 9,
            candidateLayout: .horizontal,
            candidateFontScale: 1.6,
            keyBindings: KeyBindingSettings(modeSwitch: .disabled, pageKeys: .bracketPair),
            autoCommitAtFour: true,
            defaultMode: InputMode(language: .directEnglish, punctuation: .english,
                                   width: .full, script: .traditional),
            learningEnabled: false
        )
        try coordinator.save(changed)

        XCTAssertEqual(session.applied, [changed])
        XCTAssertEqual(globallyApplied, [changed])
        XCTAssertEqual(try SettingsStore(writer: SnapshotWriter(rootURL: root)).settings, changed)
        let preview = CandidateAppearanceController().preview(settings: changed)
        XCTAssertEqual(preview.layout, .horizontal)
        XCTAssertEqual(preview.fontScale, 1.6)

        try coordinator.restoreDefaults()
        XCTAssertEqual(try SettingsStore(writer: SnapshotWriter(rootURL: root)).settings, .default)
        XCTAssertEqual(try Data(contentsOf: writer.currentURL(for: .userLexicon)), userBefore)
        XCTAssertEqual(try Data(contentsOf: writer.currentURL(for: .learning)), learningBefore)
    }
}

private final class SettingsIntegrationSession: SettingsSessionControlling {
    var state = CompositionState.idle
    var applied = [InputSettings]()
    var activeSnapshot = SettingsSnapshot(generation: 0, settings: .default)
    var pendingSnapshot: SettingsSnapshot?
    func stage(settingsSnapshot: SettingsSnapshot) {
        if state == .idle {
            activeSnapshot = settingsSnapshot
            applied.append(settingsSnapshot.settings)
        } else if pendingSnapshot == nil
                    || settingsSnapshot.generation >= pendingSnapshot!.generation {
            pendingSnapshot = settingsSnapshot
        }
    }
    func applyPendingSettingsIfIdle() {
        guard state == .idle, let pendingSnapshot else { return }
        self.pendingSnapshot = nil
        activeSnapshot = pendingSnapshot
        applied.append(pendingSnapshot.settings)
    }
}
