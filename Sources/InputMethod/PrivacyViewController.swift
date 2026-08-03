import AppKit
import Foundation

@MainActor
final class PrivacyViewController: NSViewController {
    private let statusProvider: PrivacyStatusProvider?
    private let deletionCoordinator: PrivacyDeletionCoordinator?
    private(set) var controls = [NSControl]()
    private(set) var lastFeedback = ""
    private var feedbackLabel: NSTextField?

    init(statusProvider: PrivacyStatusProvider?, deletionCoordinator: PrivacyDeletionCoordinator?) {
        self.statusProvider = statusProvider
        self.deletionCoordinator = deletionCoordinator
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }

    static func makeDefault() -> PrivacyViewController {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first?
            .appendingPathComponent("org.macwubi.inputmethod", isDirectory: true),
              let writer = try? SnapshotWriter(rootURL: root) else {
            return PrivacyViewController(statusProvider: nil, deletionCoordinator: nil)
        }
        return PrivacyViewController(statusProvider: PrivacyStatusProvider(writer: writer),
                                     deletionCoordinator: PrivacyDeletionCoordinator(writer: writer))
    }

    override func loadView() {
        controls.removeAll()
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 380))
        let promise = NSTextField(labelWithString: "完全本地处理，不建立网络连接")
        promise.frame = NSRect(x: 20, y: 340, width: 500, height: 24)
        root.addSubview(promise)

        for (index, status) in (statusProvider?.status() ?? []).enumerated() {
            let text = "\(status.domain.directoryName)：\(status.purpose)；\(status.logicalLocation)；\(status.byteCount) 字节"
            let label = NSTextField(labelWithString: text)
            label.frame = NSRect(x: 20, y: 290 - index * 70, width: 470, height: 42)
            label.maximumNumberOfLines = 2
            root.addSubview(label)
            let button = NSButton(title: "删除 \(status.domain.directoryName)…",
                                  target: self, action: #selector(deleteDomain(_:)))
            button.tag = Int(status.domain.rawValue)
            button.frame = NSRect(x: 500, y: 294 - index * 70, width: 110, height: 30)
            controls.append(button); root.addSubview(button)
        }
        let privateMode = NSButton(checkboxWithTitle: "私密模式", target: self,
                                   action: #selector(togglePrivateMode(_:)))
        privateMode.state = PrivacyModeController.shared.privateMode ? .on : .off
        privateMode.frame = NSRect(x: 20, y: 55, width: 140, height: 30)
        controls.append(privateMode); root.addSubview(privateMode)
        let deleteAll = NSButton(title: "删除全部个性化…", target: self,
                                 action: #selector(deleteAllData))
        deleteAll.frame = NSRect(x: 440, y: 42, width: 170, height: 30)
        controls.append(deleteAll); root.addSubview(deleteAll)
        let feedback = NSTextField(wrappingLabelWithString: lastFeedback)
        feedback.frame = NSRect(x: 20, y: 8, width: 590, height: 30)
        feedback.identifier = NSUserInterfaceItemIdentifier("隐私操作反馈")
        feedback.isSelectable = true
        feedbackLabel = feedback
        controls.append(feedback); root.addSubview(feedback)
        view = root
    }

    @objc private func togglePrivateMode(_ sender: NSButton) {
        PrivacyModeController.shared.setPrivateMode(sender.state == .on)
        publish(sender.state == .on ? "私密模式已开启。" : "私密模式已关闭。")
    }

    @objc private func deleteDomain(_ sender: NSButton) {
        guard let domain = DataDomain(rawValue: UInt8(sender.tag)) else { return }
        guard deletionCoordinator != nil else {
            publish("本地数据管理当前不可用。", isError: true)
            return
        }
        guard confirm("删除 \(domain.directoryName) 数据？") else {
            publish("已取消删除 \(domain.directoryName) 数据。")
            return
        }
        let report = deletionCoordinator?.delete(domain)
        loadView()
        publish(report?.results[domain] == .failed
                ? "删除失败，\(domain.directoryName) 数据保持不变。"
                : "\(domain.directoryName) 数据已删除。",
                isError: report?.results[domain] == .failed)
    }

    @objc private func deleteAllData() {
        guard deletionCoordinator != nil else {
            publish("本地数据管理当前不可用。", isError: true)
            return
        }
        guard confirm("删除 Settings、UserLexicon 和 Learning？基础词库会保留。") else {
            publish("已取消删除全部个性化数据。")
            return
        }
        let report = deletionCoordinator?.deleteAll()
        loadView()
        publish(report?.allSucceeded == true
                ? "全部个性化数据已删除，基础词库保留。"
                : "部分数据删除失败；未删除的数据保持不变。",
                isError: report?.allSucceeded != true)
    }

    private func confirm(_ message: String) -> Bool {
        let alert = NSAlert(); alert.messageText = message
        alert.addButton(withTitle: "删除"); alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func publish(_ message: String, isError: Bool = false) {
        lastFeedback = message
        feedbackLabel?.stringValue = message
        feedbackLabel?.textColor = isError ? .systemRed : .secondaryLabelColor
    }
}
