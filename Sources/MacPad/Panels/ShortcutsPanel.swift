import AppKit

/// Searchable list of every keyboard shortcut, read live from the main menu so it never goes stale.
@MainActor
final class ShortcutsPanel: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    static let shared = ShortcutsPanel()

    private struct Shortcut {
        let keys: String
        let command: String
        let location: String
    }

    /// Shortcuts of buttons inside other windows rather than in the menu bar.
    private static let windowShortcuts = [
        Shortcut(keys: "↩", command: "Find Next", location: "Find & Replace window"),
        Shortcut(keys: "⌥⌘↑", command: "Previous Difference", location: "Compare window"),
        Shortcut(keys: "⌥⌘↓", command: "Next Difference", location: "Compare window"),
    ]

    private static let specialKeyNames: [String: String] = [
        "\r": "↩", "\t": "⇥", " ": "Space", "\u{1b}": "⎋", "\u{8}": "⌫", "\u{7f}": "⌫",
        String(NSEvent.SpecialKey.upArrow.unicodeScalar): "↑",
        String(NSEvent.SpecialKey.downArrow.unicodeScalar): "↓",
        String(NSEvent.SpecialKey.leftArrow.unicodeScalar): "←",
        String(NSEvent.SpecialKey.rightArrow.unicodeScalar): "→",
    ]

    private var all: [Shortcut] = []
    private var shown: [Shortcut] = []
    private let searchField = NSSearchField()
    private lazy var tableView = NSTableView.make(columns: [
        .init(id: "keys", title: "Shortcut", width: 90, fixedWidth: true),
        .init(id: "command", title: "Command", width: 220),
        .init(id: "location", title: "Menu", width: 200),
    ], owner: self)

    private init() {
        super.init(window: NSPanel.utility(title: "Keyboard Shortcuts", size: NSSize(width: 560, height: 520)))
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        all = (NSApp.mainMenu.map { Self.collect(from: $0, path: []) } ?? []) + Self.windowShortcuts
        searchField.stringValue = ""
        applyFilter()
        if window?.isVisible == false { window?.center() }
        showWindow(nil)
        window?.makeFirstResponder(searchField)
    }

    // MARK: - Collecting

    private static func collect(from menu: NSMenu, path: [String]) -> [Shortcut] {
        menu.items.flatMap { item -> [Shortcut] in
            if let submenu = item.submenu { return collect(from: submenu, path: path + [item.title]) }
            guard !item.keyEquivalent.isEmpty else { return [] }
            return [Shortcut(keys: describe(item), command: item.title, location: path.joined(separator: " ▸ "))]
        }
    }

    /// Formats a menu item's shortcut the way macOS menus show it, e.g. ⇧⌘S.
    private static func describe(_ item: NSMenuItem) -> String {
        var modifiers = item.keyEquivalentModifierMask
        let key = item.keyEquivalent
        // An uppercase key equivalent implies Shift.
        if key.count == 1, key.lowercased() != key { modifiers.insert(.shift) }

        let symbols: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + (specialKeyNames[key] ?? key.uppercased())
    }

    // MARK: - Filtering

    func controlTextDidChange(_ notification: Notification) {
        applyFilter()
    }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        shown = query.isEmpty ? all : all.filter {
            [$0.command, $0.location, $0.keys].contains { $0.localizedCaseInsensitiveContains(query) }
        }
        tableView.reloadData()
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = tableColumn?.identifier.rawValue
        guard let cell = tableView.labelCell(for: tableColumn, owner: self, configure: { cell in
            if id == "keys" { cell.font = .monospacedSystemFont(ofSize: 13, weight: .medium) }
            if id == "location" { cell.textColor = .secondaryLabelColor }
        }) else { return nil }
        let shortcut = shown[row]
        cell.stringValue = switch id {
        case "keys": shortcut.keys
        case "command": shortcut.command
        default: shortcut.location
        }
        return cell
    }

    // MARK: - UI

    private func buildUI() {
        searchField.placeholderString = "Search commands or keys"
        searchField.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let stack = NSStackView.fullWidthColumn([searchField, tableView.inScrollView()],
                                                insets: NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12))
        window?.contentView = .container(pinning: stack)
    }
}
