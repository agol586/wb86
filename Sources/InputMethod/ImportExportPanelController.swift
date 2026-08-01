import AppKit
import Foundation

@MainActor
protocol FilePanelPresenting {
    func chooseImportURL() -> URL?
    func chooseExportURL() -> URL?
}

protocol ScopedResourceAccessing {
    func start(_ url: URL) -> Bool
    func stop(_ url: URL)
}

struct SystemScopedResourceAccess: ScopedResourceAccessing {
    func start(_ url: URL) -> Bool { url.startAccessingSecurityScopedResource() }
    func stop(_ url: URL) { url.stopAccessingSecurityScopedResource() }
}

@MainActor
struct SystemFilePanels: FilePanelPresenting {
    func chooseImportURL() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseExportURL() -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MacWubi-Lexicon.macwubi"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

@MainActor
final class ImportExportPanelController {
    private let panels: FilePanelPresenting
    private let scopedAccess: ScopedResourceAccessing

    init(panels: FilePanelPresenting? = nil,
         scopedAccess: ScopedResourceAccessing = SystemScopedResourceAccess()) {
        self.panels = panels ?? SystemFilePanels()
        self.scopedAccess = scopedAccess
    }

    @discardableResult
    func performImport(_ consume: (Data) throws -> Void) throws -> Bool {
        guard let url = panels.chooseImportURL() else { return false }
        let scoped = scopedAccess.start(url)
        defer { if scoped { scopedAccess.stop(url) } }
        try consume(Data(contentsOf: url, options: .mappedIfSafe))
        return true
    }

    @discardableResult
    func performExport(_ data: Data, using exporter: LexiconExporter,
                       validate: (Data) throws -> Void) throws -> Bool {
        guard let url = panels.chooseExportURL() else { return false }
        let scoped = scopedAccess.start(url)
        defer { if scoped { scopedAccess.stop(url) } }
        try exporter.write(data, to: url, validate: validate)
        return true
    }
}
