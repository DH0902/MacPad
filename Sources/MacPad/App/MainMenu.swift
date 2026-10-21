import AppKit
import MacPadCore

/// Builds the menu bar. Items with no explicit target go through the responder chain, so document
/// actions are enabled only while an editor window is in front.
@MainActor
enum MainMenu {
    static func build(appDelegate: AppDelegate) -> NSMenu {
        let main = NSMenu()
        let find = FindReplacePanel.shared

        main.addSubmenu("MacPad") { menu in
            menu.add("About MacPad", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
            menu.addItem(.separator())
            menu.add("Hide MacPad", #selector(NSApplication.hide(_:)), key: "h")
            menu.addItem(.separator())
            menu.add("Quit MacPad", #selector(NSApplication.terminate(_:)), key: "q")
        }

        main.addSubmenu("File") { menu in
            menu.add("New", #selector(NSDocumentController.newDocument(_:)), key: "n")
            menu.add("Open…", #selector(NSDocumentController.openDocument(_:)), key: "o")
            menu.addSubmenu("Open Recent") { recent in
                recent.add("Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:)))
            }
            menu.addItem(.separator())
            menu.add("Close", #selector(NSWindow.performClose(_:)), key: "w")
            menu.add("Save", #selector(NSDocument.save(_:)), key: "s")
            menu.add("Save As…", #selector(NSDocument.saveAs(_:)), key: "S")
            menu.add("Revert to Saved", #selector(NSDocument.revertToSaved(_:)))
        }

        main.addSubmenu("Edit") { menu in
            menu.add("Undo", Selector(("undo:")), key: "z")
            menu.add("Redo", Selector(("redo:")), key: "Z")
            menu.addItem(.separator())
            menu.add("Cut", #selector(NSText.cut(_:)), key: "x")
            menu.add("Copy", #selector(NSText.copy(_:)), key: "c")
            menu.add("Paste", #selector(NSText.paste(_:)), key: "v")
            menu.add("Select All", #selector(NSText.selectAll(_:)), key: "a")
            menu.addItem(.separator())
            menu.addSubmenu("Find") { menu in
                menu.add("Find…", #selector(AppDelegate.showFind(_:)), key: "f", target: appDelegate)
                menu.add("Find and Replace…", #selector(AppDelegate.showFindReplace(_:)), key: "f",
                         modifiers: [.command, .option], target: appDelegate)
                menu.add("Find Next", #selector(FindReplacePanel.findNext(_:)), key: "g", target: find)
                menu.add("Find Previous", #selector(FindReplacePanel.findPrevious(_:)), key: "G", target: find)
                menu.add("Use Selection for Find", #selector(FindReplacePanel.useSelectionForFind(_:)), key: "e", target: find)
            }
        }

        main.addSubmenu("Format") { menu in
            menu.add("Pretty Print XML", #selector(TextDocument.prettyPrintXML(_:)), key: "P")
            menu.add("Pretty Print JSON", #selector(TextDocument.prettyPrintJSON(_:)), key: "J")
            menu.add("Toggle Word Wrap", #selector(TextDocument.toggleWordWrap(_:)))
        }

        main.addSubmenu("View") { menu in
            menu.add("Zoom In", #selector(TextDocument.zoomIn(_:)), key: "=")
            menu.add("Zoom Out", #selector(TextDocument.zoomOut(_:)), key: "-")
            menu.add("Actual Size", #selector(TextDocument.resetZoom(_:)), key: "0")
        }

        main.addSubmenu("Language") { menu in
            for language in SyntaxLanguage.allCases {
                menu.add(language.title, #selector(TextDocument.setLanguage(_:))).tag = language.rawValue
                if language == .auto { menu.addItem(.separator()) }
            }
        }

        main.addSubmenu("Tools") { menu in
            menu.add("CSV Lint", #selector(TextDocument.lintCSV(_:)), key: "L")
            menu.addItem(.separator())
            menu.addSubmenu("Compare With") { $0.delegate = appDelegate }  // filled on open
            menu.add("Compare With File…", #selector(TextDocument.compareWithFile(_:)))
            menu.add("Compare With Saved Version", #selector(TextDocument.compareWithSavedVersion(_:)))
        }

        NSApp.windowsMenu = main.addSubmenu("Window") { menu in
            menu.add("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m")
            menu.add("Zoom", #selector(NSWindow.performZoom(_:)))
        }

        NSApp.helpMenu = main.addSubmenu("Help") { menu in
            menu.add("Keyboard Shortcuts", #selector(AppDelegate.showShortcuts(_:)), key: "/", target: appDelegate)
        }

        return main
    }
}

@MainActor
private extension NSMenu {
    @discardableResult
    func add(_ title: String, _ action: Selector, key: String = "",
             modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let item = addItem(withTitle: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }

    @discardableResult
    func addSubmenu(_ title: String, _ build: (NSMenu) -> Void) -> NSMenu {
        let submenu = NSMenu(title: title)
        build(submenu)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
        return submenu
    }
}
