import AppKit
import MacPadCore

/// Floating panel listing CSV Lint results; selecting an issue jumps to it in the document.
@MainActor
final class CSVLintPanel: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = CSVLintPanel()

    private weak var lintedDocument: TextDocument?
    private var issues: [CSVIssue] = []
    private var lintTask: Task<Void, Never>?
    private let delimiterPopup = NSPopUpButton()
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private lazy var tableView = NSTableView.make(columns: [
        .init(id: "type", title: "Type", width: 70, fixedWidth: true),
        .init(id: "line", title: "Line", width: 55, fixedWidth: true),
        .init(id: "col", title: "Col", width: 45, fixedWidth: true),
        .init(id: "message", title: "Message", width: 480),
    ], owner: self)

    private init() {
        super.init(window: NSPanel.utility(title: "CSV Lint", size: NSSize(width: 680, height: 380)))
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func lint(_ document: TextDocument) {
        lintedDocument = document
        if window?.isVisible == false { window?.center() }
        runLint(nil)
        showWindow(nil)
    }

    // MARK: - Linting

    @objc private func runLint(_ sender: Any?) {
        lintTask?.cancel()
        guard let document = lintedDocument, let text = document.textView?.string else {
            show([], summary: "The linted document has been closed.")
            return
        }
        let choice = delimiterPopup.indexOfSelectedItem
        let delimiter = choice > 0 ? CSVDelimiter.allCases[choice - 1] : nil
        summaryLabel.stringValue = "Linting…"
        window?.title = "CSV Lint — \(document.displayName ?? "Untitled")"

        lintTask = Task {
            let result = await inBackground { CSVLinter.lint(text, delimiter: delimiter) }
            guard !Task.isCancelled else { return }
            show(result.issues, summary: Self.summary(of: result))
        }
    }

    private func show(_ issues: [CSVIssue], summary: String) {
        self.issues = issues
        tableView.reloadData()
        summaryLabel.stringValue = summary
    }

    private static func summary(of result: CSVLintResult) -> String {
        let shape = "\(result.delimiter.name)-delimited · \(result.columnCount) columns · \(result.rowCount) data rows — "
        guard !result.issues.isEmpty else { return shape + "✅ No problems found." }
        let plural = { (count: Int, noun: String) in "\(count) \(noun)\(count == 1 ? "" : "s")" }
        var text = shape + "\(plural(result.errorCount, "error")), \(plural(result.warningCount, "warning"))"
        if result.hiddenIssueCount > 0 {
            text += " (showing the first \(CSVLinter.maxIssues); \(result.hiddenIssueCount) more hidden)"
        }
        return text + "."
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { issues.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let cell = tableView.labelCell(for: tableColumn, owner: self) else { return nil }
        let issue = issues[row]
        cell.textColor = .labelColor
        cell.toolTip = nil
        switch tableColumn?.identifier.rawValue {
        case "type":
            cell.stringValue = issue.severity == .error ? "Error" : "Warning"
            cell.textColor = issue.severity == .error ? .systemRed : .systemOrange
        case "line":
            cell.stringValue = String(issue.line)
        case "col":
            cell.stringValue = String(issue.column)
        default:
            cell.stringValue = issue.message
            cell.toolTip = issue.message
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard issues.indices.contains(row), let textView = lintedDocument?.textView else { return }
        let text = textView.string as NSString
        let location = min(issues[row].offset, text.length)
        let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
        textView.setSelectedRange(lineRange)
        textView.scrollRangeToVisible(lineRange)
        textView.showFindIndicator(for: NSRange(location: location, length: min(1, text.length - location)))
    }

    // MARK: - UI

    private func buildUI() {
        delimiterPopup.addItem(withTitle: "Auto-detect")
        delimiterPopup.addItems(withTitles: CSVDelimiter.allCases.map(\.name))
        delimiterPopup.target = self
        delimiterPopup.action = #selector(runLint(_:))
        let controls = NSStackView(views: [
            NSTextField(labelWithString: "Delimiter:"), delimiterPopup,
            NSButton(title: "Lint Again", target: self, action: #selector(runLint(_:))),
        ])
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        let stack = NSStackView.fullWidthColumn([controls, summaryLabel, tableView.inScrollView()],
                                                insets: NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12))
        window?.contentView = .container(pinning: stack)
    }
}
