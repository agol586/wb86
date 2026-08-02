import AppKit

final class InputModeController: NSObject {
    static let shared = InputModeController()

    private var handler: ((InputEvent) -> Void)?
    private var currentMode = InputMode.default

    private override init() { super.init() }

    func activate(mode: InputMode, handler: @escaping (InputEvent) -> Void) {
        precondition(Thread.isMainThread)
        self.handler = handler
        update(mode: mode)
    }

    func menu(mode: InputMode, handler: @escaping (InputEvent) -> Void) -> NSMenu {
        activate(mode: mode, handler: handler)
        return makeMenu()
    }

    func update(mode: InputMode) {
        precondition(Thread.isMainThread)
        currentMode = mode
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Mac Wubi 输入模式")
        menu.autoenablesItems = false
        menu.addItem(item(title: "中文输入", event: .switchLanguage,
                          checked: currentMode.language == .chinese))
        menu.addItem(item(title: "中文标点", event: .switchPunctuation,
                          checked: currentMode.punctuation == .chinese))
        menu.addItem(item(title: "全角字符", event: .switchWidth,
                          checked: currentMode.width == .full))
        menu.addItem(item(title: "繁体输出", event: .switchScript,
                          checked: currentMode.script == .traditional))
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(showSettings),
                                  keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        return menu
    }

    private func item(title: String, event: InputEvent, checked: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(selectMode(_:)),
                              keyEquivalent: "")
        item.target = self
        item.representedObject = EventBox(event)
        item.state = checked ? .on : .off
        item.isEnabled = true
        return item
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let event = (sender.representedObject as? EventBox)?.event else { return }
        handler?(event)
    }

    @objc private func showSettings() { SettingsWindowController.shared.show() }

    static func label(for mode: InputMode) -> String {
        let language = mode.language == .chinese ? "中" : "英"
        let punctuation = mode.punctuation == .chinese ? "中标" : "英标"
        let width = mode.width == .half ? "半" : "全"
        let script = mode.script == .simplified ? "简" : "繁"
        return "五·\(language)·\(punctuation)·\(width)·\(script)"
    }

}

private final class EventBox: NSObject {
    let event: InputEvent
    init(_ event: InputEvent) { self.event = event }
}
