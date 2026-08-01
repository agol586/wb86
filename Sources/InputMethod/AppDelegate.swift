import AppKit
import InputMethodKit

@main
enum MacWubiApplication {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var inputMethodServer: IMKServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let connectionName = Bundle.main.object(
            forInfoDictionaryKey: "InputMethodConnectionName"
        ) as? String,
        !connectionName.isEmpty,
        let bundleIdentifier = Bundle.main.bundleIdentifier else {
            NSApplication.shared.terminate(nil)
            return
        }
        inputMethodServer = IMKServer(
            name: connectionName,
            bundleIdentifier: bundleIdentifier
        )
    }
}
