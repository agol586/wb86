protocol PrivacySessionControlling: AnyObject {
    var privateMode: Bool { get set }
    var learningEnabled: Bool { get set }
}

final class PrivacyModeController {
    static let shared = PrivacyModeController()

    private final class WeakSession {
        weak var value: PrivacySessionControlling?
        init(_ value: PrivacySessionControlling) { self.value = value }
    }

    private var sessions = [WeakSession]()
    private(set) var privateMode = false
    private(set) var learningEnabled = true
    private let policyHandler: (Bool, Bool) -> Void

    init(policyHandler: @escaping (Bool, Bool) -> Void = {
        PersonalizationCoordinator.shared.setPolicy(privateMode: $0, learningEnabled: $1)
    }) {
        self.policyHandler = policyHandler
    }

    func register(_ session: PrivacySessionControlling) {
        sessions.removeAll { $0.value == nil || $0.value === session }
        sessions.append(WeakSession(session))
        session.privateMode = privateMode
        session.learningEnabled = learningEnabled
    }

    func setPrivateMode(_ enabled: Bool) {
        privateMode = enabled
        applyToSessions()
        policyHandler(privateMode, learningEnabled)
    }

    func setLearningEnabled(_ enabled: Bool) {
        learningEnabled = enabled
        applyToSessions()
        policyHandler(privateMode, learningEnabled)
    }

    private func applyToSessions() {
        sessions.removeAll { $0.value == nil }
        for session in sessions.compactMap(\.value) {
            session.privateMode = privateMode
            session.learningEnabled = learningEnabled
        }
    }

}
