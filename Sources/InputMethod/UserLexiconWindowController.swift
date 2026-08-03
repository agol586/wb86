import AppKit

enum UserLexiconWindowMode {
    case search
    case add
    case edit
    case delete
}

@MainActor
final class UserLexiconWindowController: NSWindowController, NSTableViewDataSource,
    NSTableViewDelegate {
    private let serviceProvider: () -> UserLexiconService?
    private var entries = [UserLexiconEntry]()
    private let searchField = NSSearchField()
    private let codeField = NSTextField()
    private let textField = NSTextField()
    private let rankField = NSTextField()
    private let tableView = NSTableView()
    private let feedbackLabel = NSTextField(wrappingLabelWithString: "")
    private(set) var lastFeedback = ""

    init(serviceProvider: @escaping () -> UserLexiconService?) {
        self.serviceProvider = serviceProvider
        super.init(window: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "用户词库管理"
        window.isReleasedWhenClosed = false
        guard let content = window.contentView else { self.window = window; return }

        searchField.frame = NSRect(x: 20, y: 430, width: 500, height: 28)
        searchField.placeholderString = "搜索编码或词条"
        searchField.target = self
        searchField.action = #selector(searchEntries)
        searchField.identifier = NSUserInterfaceItemIdentifier("词条搜索")
        content.addSubview(searchField)
        let searchButton = actionButton("搜索", #selector(searchEntries))
        searchButton.frame = NSRect(x: 530, y: 428, width: 120, height: 30)
        content.addSubview(searchButton)

        let scroll = NSScrollView(frame: NSRect(x: 20, y: 160, width: 630, height: 255))
        scroll.hasVerticalScroller = true
        tableView.headerView = NSTableHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.delegate = self
        tableView.dataSource = self
        for (identifier, title, width) in [
            ("code", "编码", 110.0), ("text", "词条", 390.0), ("rank", "固定顺序", 100.0)
        ] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            tableView.addTableColumn(column)
        }
        scroll.documentView = tableView
        content.addSubview(scroll)

        addLabeledField("编码", field: codeField, x: 20, width: 120, to: content)
        addLabeledField("词条", field: textField, x: 155, width: 300, to: content)
        addLabeledField("固定顺序（可选）", field: rankField, x: 470, width: 180, to: content)

        let addButton = actionButton("添加", #selector(addEntry))
        addButton.frame = NSRect(x: 20, y: 52, width: 100, height: 30)
        let editButton = actionButton("保存编辑", #selector(editEntry))
        editButton.frame = NSRect(x: 130, y: 52, width: 110, height: 30)
        let deleteButton = actionButton("删除所选…", #selector(deleteEntry))
        deleteButton.frame = NSRect(x: 250, y: 52, width: 120, height: 30)
        content.addSubview(addButton)
        content.addSubview(editButton)
        content.addSubview(deleteButton)

        feedbackLabel.frame = NSRect(x: 20, y: 12, width: 630, height: 34)
        feedbackLabel.identifier = NSUserInterfaceItemIdentifier("词库操作反馈")
        feedbackLabel.isSelectable = true
        content.addSubview(feedbackLabel)
        self.window = window
        reloadEntries()
    }

    func show(mode: UserLexiconWindowMode) {
        if window == nil { loadWindow() }
        guard let window else { return }
        reloadEntries()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        switch mode {
        case .search:
            window.makeFirstResponder(searchField)
        case .add:
            clearEditor()
            publish("请输入编码和词条，然后点击“添加”。")
            window.makeFirstResponder(codeField)
        case .edit:
            publish("请选择词条，修改后点击“保存编辑”。")
            window.makeFirstResponder(tableView)
        case .delete:
            publish("请选择词条，然后点击“删除所选…”。")
            window.makeFirstResponder(tableView)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
        -> NSView? {
        guard entries.indices.contains(row), let identifier = tableColumn?.identifier.rawValue else {
            return nil
        }
        let entry = entries[row]
        let value: String
        switch identifier {
        case "code": value = entry.code.letters
        case "text": value = entry.text
        case "rank": value = entry.fixedRank.map(String.init) ?? ""
        default: value = ""
        }
        let field = NSTextField(labelWithString: value)
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard entries.indices.contains(tableView.selectedRow) else { return }
        let entry = entries[tableView.selectedRow]
        codeField.stringValue = entry.code.letters
        textField.stringValue = entry.text
        rankField.stringValue = entry.fixedRank.map(String.init) ?? ""
    }

    @objc private func searchEntries() {
        guard let service = serviceProvider() else {
            publish("用户词库当前不可用。", isError: true)
            return
        }
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        entries = query.isEmpty ? service.snapshot.entries : service.search(query)
        tableView.reloadData()
        publish("找到 \(entries.count) 条用户词条。")
    }

    @objc private func addEntry() {
        guard let service = serviceProvider() else {
            publish("用户词库当前不可用。", isError: true)
            return
        }
        do {
            let values = try editorValues()
            let result = try service.add(code: values.code, text: values.text,
                                         fixedRank: values.rank)
            reloadEntries(selectingID: UserLexiconEntryID.lookup(in: service.snapshot,
                                                                  code: values.code,
                                                                  text: values.text))
            publish(result.kind == .added ? "词条已添加。" : "词条已合并。")
        } catch {
            publish(editorErrorMessage(error), isError: true)
        }
    }

    @objc private func editEntry() {
        guard let service = serviceProvider(), entries.indices.contains(tableView.selectedRow) else {
            publish("请先选择要编辑的词条。", isError: true)
            return
        }
        let selected = entries[tableView.selectedRow]
        do {
            let values = try editorValues()
            _ = try service.edit(id: selected.id, code: values.code, text: values.text,
                                 fixedRank: values.rank)
            reloadEntries(selectingID: selected.id)
            publish("词条已保存。")
        } catch {
            publish(editorErrorMessage(error), isError: true)
        }
    }

    @objc private func deleteEntry() {
        guard let service = serviceProvider(), entries.indices.contains(tableView.selectedRow) else {
            publish("请先选择要删除的词条。", isError: true)
            return
        }
        let selected = entries[tableView.selectedRow]
        let alert = NSAlert()
        alert.messageText = "删除所选用户词条？"
        alert.informativeText = "此操作只删除所选词条，不影响基础词库和学习数据。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else {
            publish("已取消删除。")
            return
        }
        do {
            let result = try service.delete(id: selected.id)
            reloadEntries()
            publish(result.kind == .deleted ? "词条已删除。" : "词条已不存在。")
        } catch {
            publish("删除失败，用户词库保持不变。", isError: true)
        }
    }

    private func reloadEntries(selectingID: String? = nil) {
        entries = serviceProvider()?.snapshot.entries ?? []
        tableView.reloadData()
        if let selectingID, let index = entries.firstIndex(where: { $0.id == selectingID }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
    }

    private func editorValues() throws -> (code: InputCode, text: String, rank: Int?) {
        guard let code = InputCode(codeField.stringValue) else {
            throw UserLexiconEditorError.invalidCode
        }
        let rankText = rankField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let rank: Int?
        if rankText.isEmpty {
            rank = nil
        } else if let parsed = Int(rankText) {
            rank = parsed
        } else {
            throw UserLexiconEditorError.invalidRank
        }
        return (code, textField.stringValue, rank)
    }

    private func editorErrorMessage(_ error: Error) -> String {
        switch error {
        case UserLexiconEditorError.invalidCode:
            return "编码无效：请输入 1 至 4 位 a–y 五笔编码。"
        case UserLexiconEditorError.invalidRank, UserLexiconError.invalidFixedRank:
            return "固定顺序无效：请输入 0 至 9999，或留空。"
        case UserLexiconError.invalidText:
            return "词条无效：不能为空、包含控制字符或超过长度限制。"
        case UserLexiconError.entryNotFound:
            return "词条已不存在，请刷新后重试。"
        default:
            return "操作失败，用户词库保持不变。"
        }
    }

    private func publish(_ message: String, isError: Bool = false) {
        lastFeedback = message
        feedbackLabel.stringValue = message
        feedbackLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    private func clearEditor() {
        codeField.stringValue = ""
        textField.stringValue = ""
        rankField.stringValue = ""
    }

    private func addLabeledField(_ title: String, field: NSTextField, x: CGFloat,
                                 width: CGFloat, to view: NSView) {
        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: x, y: 128, width: width, height: 20)
        field.frame = NSRect(x: x, y: 92, width: width, height: 28)
        field.identifier = NSUserInterfaceItemIdentifier(title)
        view.addSubview(label)
        view.addSubview(field)
    }

    private func actionButton(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.identifier = NSUserInterfaceItemIdentifier(title)
        return button
    }
}

private enum UserLexiconEditorError: Error {
    case invalidCode
    case invalidRank
}

private enum UserLexiconEntryID {
    static func lookup(in snapshot: UserLexiconSnapshot, code: InputCode, text: String) -> String? {
        snapshot.entries.first { $0.code == code && $0.text == text }?.id
    }
}
