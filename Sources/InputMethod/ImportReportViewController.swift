import AppKit

@MainActor
final class ImportReportViewController: NSViewController {
    private(set) var report: ImportReport?
    private(set) var summary = ""

    func present(_ report: ImportReport) {
        self.report = report
        summary = "新增 \(report.acceptedCount)，合并 \(report.mergedCount)，跳过 \(report.skippedCount)，失败 \(report.failedCount)"
        let label = NSTextField(labelWithString: summary)
        label.setAccessibilityLabel("导入结果统计")
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 100))
        label.frame = NSRect(x: 20, y: 34, width: 380, height: 24)
        view.addSubview(label)
    }
}
