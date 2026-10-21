import AppKit

/// Runs CPU-heavy work off the main actor. It is a structured call, so cancelling the calling task
/// is visible to `work` through `Task.isCancelled`.
@concurrent
func inBackground<T: Sendable>(_ work: @Sendable () throws -> T) async rethrows -> T {
    try work()
}

extension NSPanel {
    /// A floating utility panel that hides while the app is in the background.
    static func utility(title: String, size: NSSize, resizable: Bool = true) -> NSPanel {
        var style: NSWindow.StyleMask = [.titled, .closable, .utilityWindow]
        if resizable { style.insert(.resizable) }
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: style,
                            backing: .buffered, defer: true)
        panel.title = title
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        return panel
    }
}

extension NSView {
    /// A plain container view with `content` pinned to its edges.
    static func container(pinning content: NSView, insets: NSEdgeInsets = NSEdgeInsets()) -> NSView {
        let container = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: insets.top),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -insets.bottom),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -insets.right),
        ])
        return container
    }
}

extension NSStackView {
    /// A vertical stack whose arranged views all span its full width (minus the edge insets).
    static func fullWidthColumn(_ views: [NSView], spacing: CGFloat = 10, insets: NSEdgeInsets = NSEdgeInsets()) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.edgeInsets = insets
        for view in views {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -(insets.left + insets.right)).isActive = true
        }
        return stack
    }
}

extension NSTableView {
    struct Column {
        let id: String
        let title: String
        let width: CGFloat
        var fixedWidth = false
    }

    /// A plain view-based table. Fixed-width columns keep their size; the others share extra space.
    static func make(columns: [Column], owner: NSTableViewDataSource & NSTableViewDelegate) -> NSTableView {
        let table = NSTableView()
        for spec in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(spec.id))
            column.title = spec.title
            column.width = spec.width
            column.resizingMask = spec.fixedWidth ? [] : .autoresizingMask
            table.addTableColumn(column)
        }
        table.style = .plain
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = owner
        table.delegate = owner
        return table
    }

    func inScrollView(bordered: Bool = true) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.documentView = self
        scrollView.hasVerticalScroller = true
        scrollView.borderType = bordered ? .bezelBorder : .noBorder
        return scrollView
    }

    /// Dequeues the label cell for `column`, creating (and configuring once) a new one if needed.
    func labelCell(for column: NSTableColumn?, owner: Any?, configure: (NSTextField) -> Void = { _ in }) -> NSTextField? {
        guard let id = column?.identifier else { return nil }
        if let cell = makeView(withIdentifier: id, owner: owner) as? NSTextField { return cell }
        let cell = NSTextField(labelWithString: "")
        cell.identifier = id
        cell.lineBreakMode = .byTruncatingTail
        configure(cell)
        return cell
    }
}

extension NSTextView {
    var fullRange: NSRange { NSRange(location: 0, length: (string as NSString).length) }

    /// Replaces ascending, non-overlapping `ranges` as one undoable edit, notifying observers
    /// (syntax colouring, the document's edited state) exactly as typing would.
    @discardableResult
    func replaceUndoably(_ ranges: [NSRange], with strings: [String]) -> Bool {
        guard let storage = textStorage,
              shouldChangeText(inRanges: ranges.map { NSValue(range: $0) }, replacementStrings: strings) else { return false }
        storage.beginEditing()
        for (range, string) in zip(ranges, strings).reversed() {
            storage.replaceCharacters(in: range, with: string)
        }
        storage.endEditing()
        didChangeText()
        return true
    }

    func selectAndReveal(_ range: NSRange) {
        setSelectedRange(range)
        scrollRangeToVisible(range)
        showFindIndicator(for: range)
    }
}

extension NSAlert {
    static func show(_ title: String, detail: String, in window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}
