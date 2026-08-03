import AppKit

@MainActor
final class ImportReportViewController: NSViewController {
    private(set) var report: ImportReport?
    private(set) var summary = ""
    private var reportWindowController: NSWindowController?

    func present(_ report: ImportReport) {
        self.report = report
        summary = "新增 \(report.acceptedCount)，合并 \(report.mergedCount)，跳过 \(report.skippedCount)，失败 \(report.failedCount)"
        let label = NSTextField(labelWithString: summary)
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 100))
        label.frame = NSRect(x: 20, y: 34, width: 380, height: 24)
        view.addSubview(label)
    }

    func show() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 100),
                              styleMask: [.titled, .closable], backing: .buffered,
                              defer: false)
        window.title = "用户词库导入结果"
        window.contentViewController = self
        window.isReleasedWhenClosed = false
        let controller = NSWindowController(window: window)
        reportWindowController = controller
        window.center()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
