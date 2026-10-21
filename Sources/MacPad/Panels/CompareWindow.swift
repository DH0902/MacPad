import AppKit
import MacPadCore

/// Side-by-side diff window, in the style of Notepad++'s Compare plugin. The diff is computed off
/// the main thread; closing the window cancels it.
@MainActor
final class CompareWindow: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    struct Side: Sendable {
        let name: String
        let text: String
    }

    private struct Diff: Sendable {
        let leftLines: [String]
        let rightLines: [String]
        let rows: [LineDiff.Row]
        let hunkStarts: [Int]
    }

    /// Keeps windows alive while open (nothing else owns them).
    private static var openWindows: Set<CompareWindow> = []

    private var diff = Diff(leftLines: [], rightLines: [], rows: [], hunkStarts: [])
    private var inlineChanges: [Int: (left: NSRange, right: NSRange)?] = [:]
    private var diffTask: Task<Void, Never>?
    private let summaryLabel = NSTextField(labelWithString: "Comparing…")
    private let font = EditorPreferences.font(size: 12)
    private lazy var tableView = NSTableView.make(columns: [
        .init(id: "lnL", title: "", width: 48, fixedWidth: true),
        .init(id: "textL", title: "", width: 540),
        .init(id: "lnR", title: "", width: 48, fixedWidth: true),
        .init(id: "textR", title: "", width: 540),
    ], owner: self)

    static func show(left: Side, right: Side) {
        let controller = CompareWindow(left: left, right: right)
        openWindows.insert(controller)
        controller.showWindow(nil)
    }

    private init(left: Side, right: Side) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 750),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Compare — \(left.name) ↔ \(right.name)"
        window.center()
        super.init(window: window)
        window.delegate = self
        buildUI(leftName: left.name, rightName: right.name)

        diffTask = Task {
            let diff = await inBackground {
                let leftLines = LineDiff.lines(of: left.text)
                let rightLines = LineDiff.lines(of: right.text)
                let rows = LineDiff.align(leftLines, rightLines)
                return Diff(leftLines: leftLines, rightLines: rightLines, rows: rows, hunkStarts: LineDiff.hunkStarts(in: rows))
            }
            guard !Task.isCancelled else { return }
            show(diff)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func windowWillClose(_ notification: Notification) {
        diffTask?.cancel()
        Self.openWindows.remove(self)
    }

    private func show(_ diff: Diff) {
        self.diff = diff
        tableView.reloadData()
        let count = { (kind: LineDiff.Kind) in diff.rows.count { $0.kind == kind } }
        let hunks = diff.hunkStarts.count
        summaryLabel.stringValue = hunks == 0
            ? "✅ The files are identical."
            : "\(hunks) difference\(hunks == 1 ? "" : "s") — \(count(.changed)) changed, \(count(.added)) added, \(count(.removed)) removed lines"
        goToNextDifference(nil)
    }

    // MARK: - Navigation

    @objc private func goToNextDifference(_ sender: Any?) {
        let current = tableView.selectedRow
        guard let target = diff.hunkStarts.first(where: { $0 > current }) ?? diff.hunkStarts.first else { return }
        jump(to: target)
    }

    @objc private func goToPreviousDifference(_ sender: Any?) {
        let current = tableView.selectedRow
        guard let target = diff.hunkStarts.last(where: { $0 < current }) ?? diff.hunkStarts.last else { return }
        jump(to: target)
    }

    private func jump(to row: Int) {
        tableView.selectRowIndexes([row], byExtendingSelection: false)
        // Show a few lines of context around the difference.
        tableView.scrollRowToVisible(min(row + 8, diff.rows.count - 1))
        tableView.scrollRowToVisible(max(row - 3, 0))
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { diff.rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier.rawValue else { return nil }
        let isLineNumber = id.hasPrefix("ln")
        guard let cell = tableView.labelCell(for: tableColumn, owner: self, configure: { cell in
            cell.font = self.font
            cell.drawsBackground = true
            if isLineNumber {
                cell.alignment = .right
                cell.textColor = .secondaryLabelColor
            }
        }) else { return nil }

        let diffRow = diff.rows[row]
        let isLeft = id.hasSuffix("L")
        let index = isLeft ? diffRow.left : diffRow.right
        cell.backgroundColor = Self.background(for: diffRow.kind, present: index != nil)
        if isLineNumber {
            cell.stringValue = index.map { String($0 + 1) } ?? ""
        } else {
            cell.attributedStringValue = text(forRow: row, isLeft: isLeft)
        }
        return cell
    }

    private static func background(for kind: LineDiff.Kind, present: Bool) -> NSColor {
        guard present else { return kind == .same ? .clear : NSColor.gray.withAlphaComponent(0.12) }
        switch kind {
        case .same: return .clear
        case .changed: return NSColor.systemYellow.withAlphaComponent(0.18)
        case .added: return NSColor.systemGreen.withAlphaComponent(0.2)
        case .removed: return NSColor.systemRed.withAlphaComponent(0.2)
        }
    }

    /// The line's text; on changed rows the differing middle part is highlighted more strongly.
    private func text(forRow row: Int, isLeft: Bool) -> NSAttributedString {
        let diffRow = diff.rows[row]
        guard let index = isLeft ? diffRow.left : diffRow.right else { return NSAttributedString() }
        let line = isLeft ? diff.leftLines[index] : diff.rightLines[index]
        let result = NSMutableAttributedString(string: line, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        guard diffRow.kind == .changed, let left = diffRow.left, let right = diffRow.right else { return result }

        if inlineChanges[row] == nil {
            inlineChanges[row] = LineDiff.inlineChange(diff.leftLines[left], diff.rightLines[right])
        }
        if let change = inlineChanges[row] ?? nil {
            result.addAttribute(.backgroundColor, value: NSColor.systemOrange.withAlphaComponent(0.45),
                                range: isLeft ? change.left : change.right)
        }
        return result
    }

    // MARK: - UI

    private func buildUI(leftName: String, rightName: String) {
        let previous = Self.navigationButton("▲ Previous", key: .upArrow, tip: "Previous difference (⌥⌘↑)",
                                             target: self, action: #selector(goToPreviousDifference(_:)))
        let next = Self.navigationButton("▼ Next", key: .downArrow, tip: "Next difference (⌥⌘↓)",
                                         target: self, action: #selector(goToNextDifference(_:)))
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let toolbar = NSStackView(views: [summaryLabel, spacer, previous, next])
        toolbar.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

        tableView.tableColumns[1].title = leftName
        tableView.tableColumns[3].title = rightName
        tableView.intercellSpacing = .zero
        tableView.rowHeight = 17
        tableView.gridStyleMask = .solidVerticalGridLineMask
        tableView.allowsColumnReordering = false

        let stack = NSStackView.fullWidthColumn([toolbar, tableView.inScrollView(bordered: false)], spacing: 0)
        window?.contentView = .container(pinning: stack)
    }

    private static func navigationButton(_ title: String, key: NSEvent.SpecialKey, tip: String,
                                         target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.keyEquivalent = String(key.unicodeScalar)
        button.keyEquivalentModifierMask = [.command, .option]
        button.toolTip = tip
        return button
    }
}
