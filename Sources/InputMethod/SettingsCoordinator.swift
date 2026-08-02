import Foundation

@MainActor
protocol SettingsSessionControlling: AnyObject {
    var state: CompositionState { get }
    var activeSnapshot: SettingsSnapshot { get }
    var pendingSnapshot: SettingsSnapshot? { get }
    func stage(settingsSnapshot: SettingsSnapshot)
    func applyPendingSettingsIfIdle()
}

@MainActor
final class SettingsCoordinator {
    static let shared: SettingsCoordinator? = {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first?
            .appendingPathComponent("org.macwubi.inputmethod", isDirectory: true),
              let writer = try? SnapshotWriter(rootURL: root),
              let store = try? SettingsStore(writer: writer) else { return nil }
        return SettingsCoordinator(store: store)
    }()

    private let store: SettingsStore
    private final class WeakSession {
        weak var value: SettingsSessionControlling?
        init(_ value: SettingsSessionControlling) { self.value = value }
    }
    private var sessions: [WeakSession] = []
    private let globalApply: (InputSettings) -> Void

    init(store: SettingsStore, globalApply: @escaping (InputSettings) -> Void = { _ in }) {
        self.store = store
        self.globalApply = globalApply
    }

    var settings: InputSettings { store.settings }

    func register(_ session: SettingsSessionControlling) {
        sessions.removeAll { $0.value == nil || $0.value === session }
        sessions.append(WeakSession(session))
        session.stage(settingsSnapshot: store.snapshot)
    }

    func save(_ settings: InputSettings) throws {
        try store.save(settings)
        sessions.removeAll { $0.value == nil }
        let published = store.snapshot
        sessions.compactMap(\.value).forEach { $0.stage(settingsSnapshot: published) }
        globalApply(published.settings)
    }

    func applyPendingAtIdle() {
        sessions.removeAll { $0.value == nil }
        sessions.compactMap(\.value).forEach { $0.applyPendingSettingsIfIdle() }
    }

    func restoreDefaults() throws { try save(.default) }
}
