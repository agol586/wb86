import AppKit

protocol PrivacySessionControlling: AnyObject {
    var privateMode: Bool { get set }
    var learningEnabled: Bool { get set }
}

final class PrivacyModeController: NSObject {
    static let shared = PrivacyModeController()

    private final class WeakSession {
        weak var value: PrivacySessionControlling?
        init(_ value: PrivacySessionControlling) { self.value = value }
    }

    private var sessions = [WeakSession]()
    private(set) var privateMode = false
    private(set) var learningEnabled = true
    private let statusItem: NSStatusItem
    private let policyHandler: (Bool, Bool) -> Void

    init(policyHandler: @escaping (Bool, Bool) -> Void = {
        PersonalizationCoordinator.shared.setPolicy(privateMode: $0, learningEnabled: $1)
    }) {
        self.policyHandler = policyHandler
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        updateIndicator()
        statusItem.menu = makeMenu()
    }

    var indicatorLabel: String { privateMode ? "五笔·私密" : "五笔·本地学习" }
    var commandMenu: NSMenu { makeMenu() }

    func register(_ session: PrivacySessionControlling) {
        sessions.removeAll { $0.value == nil || $0.value === session }
        sessions.append(WeakSession(session))
        session.privateMode = privateMode
        session.learningEnabled = learningEnabled
    }

    func setPrivateMode(_ enabled: Bool) {
        privateMode = enabled
        applyToSessions()
        updateIndicator()
        policyHandler(privateMode, learningEnabled)
    }

    func setLearningEnabled(_ enabled: Bool) {
        learningEnabled = enabled
        applyToSessions()
        updateIndicator()
        policyHandler(privateMode, learningEnabled)
    }

    private func applyToSessions() {
        sessions.removeAll { $0.value == nil }
        for session in sessions.compactMap(\.value) {
            session.privateMode = privateMode
            session.learningEnabled = learningEnabled
        }
    }

    private func updateIndicator() {
        statusItem.button?.title = privateMode ? "五·私" : "五·学"
        statusItem.button?.toolTip = indicatorLabel
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Mac Wubi 隐私")
        let privateItem = NSMenuItem(title: "私密模式", action: #selector(togglePrivateMode),
                                     keyEquivalent: "")
        privateItem.target = self
        privateItem.state = privateMode ? .on : .off
        menu.addItem(privateItem)
        let learningItem = NSMenuItem(title: "本地学习", action: #selector(toggleLearning),
                                      keyEquivalent: "")
        learningItem.target = self
        learningItem.state = learningEnabled ? .on : .off
        menu.addItem(learningItem)
        return menu
    }

    @objc private func togglePrivateMode() { setPrivateMode(!privateMode) }
    @objc private func toggleLearning() { setLearningEnabled(!learningEnabled) }
}
