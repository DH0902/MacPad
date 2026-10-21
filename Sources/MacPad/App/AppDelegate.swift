import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build(appDelegate: self)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    @objc func showFind(_ sender: Any?) {
        FindReplacePanel.shared.show(focusReplace: false)
    }

    @objc func showFindReplace(_ sender: Any?) {
        FindReplacePanel.shared.show(focusReplace: true)
    }

    @objc func showShortcuts(_ sender: Any?) {
        ShortcutsPanel.shared.show()
    }

    /// Fills Tools ▸ Compare With with the other open documents.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let current = NSDocumentController.shared.currentDocument
        let others = NSDocumentController.shared.documents.filter { $0 !== current }
        for document in others {
            let item = menu.addItem(withTitle: document.displayName, action: #selector(TextDocument.compareWithDocument(_:)),
                                    keyEquivalent: "")
            item.representedObject = document
        }
        if others.isEmpty {
            menu.addItem(withTitle: "No Other Open Documents", action: nil, keyEquivalent: "").isEnabled = false
        }
    }
}
