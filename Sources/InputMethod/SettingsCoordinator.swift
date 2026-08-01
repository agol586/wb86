import Foundation

protocol SettingsSessionControlling: AnyObject {
    var state: CompositionState { get }
    func apply(settings: InputSettings)
}

final class SettingsCoordinator {
    static let shared: SettingsCoordinator? = {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first?
            .appendingPathComponent("org.macwubi.inputmethod", isDirectory: true),
              let writer = try? SnapshotWriter(rootURL: root),
              let store = try? SettingsStore(writer: writer) else { return nil }
        return SettingsCoordinator(store: store) {
            PersonalizationCoordinator.shared.apply(settings: $0)
        }
    }()

    private let store: SettingsStore
    private final class WeakSession {
        weak var value: SettingsSessionControlling?
        init(_ value: SettingsSessionControlling) { self.value = value }
    }
    private var sessions: [WeakSession] = []
    private var pending: InputSettings?
    private let globalApply: (InputSettings) -> Void

    init(store: SettingsStore, globalApply: @escaping (InputSettings) -> Void = { _ in }) {
        self.store = store
        self.globalApply = globalApply
    }

    var settings: InputSettings { store.settings }

    func register(_ session: SettingsSessionControlling) {
        sessions.removeAll { $0.value == nil || $0.value === session }
        sessions.append(WeakSession(session))
        if session.state == .idle { session.apply(settings: store.settings) }
    }

    func save(_ settings: InputSettings) throws {
        try store.save(settings)
        sessions.removeAll { $0.value == nil }
        let live = sessions.compactMap(\.value)
        if live.allSatisfy({ $0.state == .idle }) {
            live.forEach { $0.apply(settings: settings) }
            globalApply(settings)
            pending = nil
        } else {
            pending = settings
        }
    }

    func applyPendingAtIdle() {
        sessions.removeAll { $0.value == nil }
        let live = sessions.compactMap(\.value)
        guard let pending, live.allSatisfy({ $0.state == .idle }) else { return }
        live.forEach { $0.apply(settings: pending) }
        globalApply(pending)
        self.pending = nil
    }

    func restoreDefaults() throws { try save(.default) }
}
