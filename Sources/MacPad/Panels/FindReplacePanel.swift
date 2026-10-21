import AppKit
import MacPadCore

/// Notepad++-style Find & Replace panel with plain-text or regular-expression search.
/// One shared panel acts on whichever document window is frontmost.
@MainActor
final class FindReplacePanel: NSWindowController {
    static let shared = FindReplacePanel()

    private let findField = NSTextField()
    private let replaceField = NSTextField()
    private let regexBox = NSButton(checkboxWithTitle: "Regular expression", target: nil, action: nil)
    private let dotAllBox = NSButton(checkboxWithTitle: ". matches newline", target: nil, action: nil)
    private let caseBox = NSButton(checkboxWithTitle: "Match case", target: nil, action: nil)
    private let wrapBox = NSButton(checkboxWithTitle: "Wrap around", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    private init() {
        super.init(window: NSPanel.utility(title: "Find & Replace", size: NSSize(width: 560, height: 200), resizable: false))
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(focusReplace: Bool) {
        // Pre-fill with the current single-line selection, like Notepad++.
        if let textView = targetTextView {
            let selected = (textView.string as NSString).substring(with: textView.selectedRange())
            if !selected.isEmpty, !selected.contains(where: \.isNewline), selected.count < 200 {
                findField.stringValue = selected
            }
        }
        if window?.isVisible == false { window?.center() }
        showWindow(nil)
        window?.makeFirstResponder(focusReplace && !findField.stringValue.isEmpty ? replaceField : findField)
        setStatus("")
    }

    // MARK: - Menu actions

    @objc func findNext(_ sender: Any?) {
        // ⌘G with nothing to search for opens the panel instead.
        guard !findField.stringValue.isEmpty else { return show(focusReplace: false) }
        perform { textView, search in try self.selectNextMatch(of: search, in: textView) }
    }

    @objc func findPrevious(_ sender: Any?) {
        guard !findField.stringValue.isEmpty else { return show(focusReplace: false) }
        perform { textView, search in
            guard let match = try search.previousMatch(in: textView.string, before: textView.selectedRange(),
                                                       wrap: self.wrapBox.state == .on) else { return self.reportNoMatch() }
            textView.selectAndReveal(match.range)
            self.setStatus(match.wrapped ? "Wrapped to the bottom." : "")
        }
    }

    /// ⌘E: put the current selection in the Find field without opening the panel.
    @objc func useSelectionForFind(_ sender: Any?) {
        guard let textView = targetTextView else { return }
        findField.stringValue = (textView.string as NSString).substring(with: textView.selectedRange())
    }

    // MARK: - Button actions

    @objc private func count(_ sender: Any?) {
        perform { textView, search in
            let count = try search.count(in: textView.string)
            self.setStatus(count == 1 ? "1 match." : "\(count) matches.")
        }
    }

    @objc private func replace(_ sender: Any?) {
        perform { textView, search in
            // Replace only if the selection is itself a match; then move on to the next one.
            let selection = textView.selectedRange()
            if let replacement = try search.replacement(forExactMatch: selection, in: textView.string),
               textView.replaceUndoably([selection], with: [replacement]) {
                textView.setSelectedRange(NSRange(location: selection.location + (replacement as NSString).length, length: 0))
            }
            try self.selectNextMatch(of: search, in: textView)
        }
    }

    @objc private func replaceAll(_ sender: Any?) {
        perform { textView, search in
            let replacements = try search.replacements(in: textView.string)
            guard !replacements.isEmpty else { return self.reportNoMatch() }
            textView.replaceUndoably(replacements.map(\.range), with: replacements.map(\.replacement))
            self.setStatus(replacements.count == 1 ? "Replaced 1 occurrence." : "Replaced \(replacements.count) occurrences.")
        }
    }

    @objc private func regexToggled(_ sender: Any?) {
        dotAllBox.isEnabled = regexBox.state == .on
    }

    // MARK: - Searching

    private var targetTextView: NSTextView? {
        (NSDocumentController.shared.currentDocument as? TextDocument)?.textView
    }

    /// Builds the query from the panel and runs `body`, reporting any failure (bad pattern, timeout).
    private func perform(_ body: (NSTextView, TextSearch) throws -> Void) {
        guard let textView = targetTextView else { return setStatus("No document is open.", isError: true) }
        do {
            let options = TextSearch.Options(isRegex: regexBox.state == .on, matchCase: caseBox.state == .on,
                                             dotMatchesNewline: dotAllBox.state == .on)
            let search = try TextSearch(query: findField.stringValue, replacement: replaceField.stringValue, options: options)
            try body(textView, search)
        } catch {
            setStatus(error.localizedDescription, isError: true)
            NSSound.beep()
        }
    }

    private func selectNextMatch(of search: TextSearch, in textView: NSTextView) throws {
        guard let match = try search.nextMatch(in: textView.string, after: textView.selectedRange(),
                                               wrap: wrapBox.state == .on) else { return reportNoMatch() }
        textView.selectAndReveal(match.range)
        setStatus(match.wrapped ? "Wrapped to the top." : "")
    }

    private func reportNoMatch() {
        setStatus("No match found.", isError: true)
        NSSound.beep()
    }

    private func setStatus(_ text: String, isError: Bool = false) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    // MARK: - UI

    private func buildUI() {
        findField.placeholderString = "Text or pattern to find"
        replaceField.placeholderString = "Replacement (regex: $1, $2… for groups; \\n, \\t)"
        wrapBox.state = .on
        dotAllBox.isEnabled = false
        regexBox.target = self
        regexBox.action = #selector(regexToggled(_:))
        statusLabel.lineBreakMode = .byTruncatingTail

        let findNextButton = NSButton(title: "Find Next", target: self, action: #selector(findNext(_:)))
        findNextButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [
            NSButton(title: "Find Previous", target: self, action: #selector(findPrevious(_:))),
            findNextButton,
            NSButton(title: "Count", target: self, action: #selector(count(_:))),
            NSButton(title: "Replace", target: self, action: #selector(replace(_:))),
            NSButton(title: "Replace All", target: self, action: #selector(replaceAll(_:))),
        ])
        buttons.spacing = 6
        let options = NSStackView(views: [regexBox, dotAllBox, caseBox, wrapBox])
        options.spacing = 12

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Find:"), findField],
            [NSTextField(labelWithString: "Replace:"), replaceField],
            [NSGridCell.emptyContentView, options],
            [NSGridCell.emptyContentView, buttons],
            [NSGridCell.emptyContentView, statusLabel],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        findField.widthAnchor.constraint(greaterThanOrEqualToConstant: 440).isActive = true
        window?.contentView = .container(pinning: grid, insets: NSEdgeInsets(top: 16, left: 16, bottom: 14, right: 16))
    }
}
