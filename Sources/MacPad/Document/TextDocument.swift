import AppKit
import MacPadCore

/// One open text file: owns its editor window, reads and writes the file, and keeps the original
/// encoding so saving never alters bytes the user didn't edit.
@objc(TextDocument)
final class TextDocument: NSDocument, NSWindowDelegate {
    /// Text read from disk before the window (and its text view) exists.
    private var loadedText = ""
    private var fileFormat = TextFileFormat.utf8
    private(set) weak var textView: NSTextView?
    private(set) var highlighter: SyntaxHighlighter?
    var fontSize = EditorPreferences.fontSize

    /// The current text, whether or not the window has been created yet.
    var text: String { textView?.string ?? loadedText }

    // Classic Save / Save As behaviour (like Notepad++), not macOS auto-save + Duplicate.
    override class var autosavesInPlace: Bool { false }

    // Re-pick the syntax colouring when Save As changes the extension.
    override var fileURL: URL? {
        didSet {
            let ext = fileURL?.pathExtension
            MainActor.assumeIsolated { highlighter?.fileExtension = ext }
        }
    }

    // MARK: - Window

    override func makeWindowControllers() {
        let (scrollView, textView) = EditorPreferences.makeEditor(fontSize: fontSize)
        let highlighter = SyntaxHighlighter(textView: textView, fontSize: fontSize)
        textView.string = loadedText
        highlighter.fileExtension = fileURL?.pathExtension
        self.textView = textView
        self.highlighter = highlighter

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.contentView = scrollView
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("MacPadDocumentWindow")
        addWindowController(NSWindowController(window: window))
        window.makeFirstResponder(textView)
    }

    // Route text-view undo through the document so the "edited" state tracks changes.
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { undoManager }

    // MARK: - Reading / writing

    override func read(from url: URL, ofType typeName: String) throws {
        let (text, format) = try TextFileCodec.read(contentsOf: url)
        // NSDocument reads on the main thread (canConcurrentlyReadDocuments is false).
        MainActor.assumeIsolated {
            loadedText = text
            fileFormat = format
            if let textView {  // Revert to Saved
                textView.string = text
                highlighter?.refresh()
            }
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        MainActor.assumeIsolated {
            let (data, format) = TextFileCodec.encode(text, as: fileFormat)
            fileFormat = format
            return data
        }
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        savePanel.allowsOtherFileTypes = true
        savePanel.isExtensionHidden = false
        return true
    }

    // MARK: - Menu validation

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let hasEditor = textView != nil
        switch menuItem.action {
        case #selector(zoomIn(_:)):
            return hasEditor && fontSize < EditorPreferences.fontSizeRange.upperBound
        case #selector(zoomOut(_:)):
            return hasEditor && fontSize > EditorPreferences.fontSizeRange.lowerBound
        case #selector(resetZoom(_:)):
            return hasEditor && fontSize != EditorPreferences.defaultFontSize
        case #selector(setLanguage(_:)):
            guard let highlighter else { return false }
            menuItem.state = highlighter.language.rawValue == menuItem.tag ? .on : .off
            if menuItem.tag == SyntaxLanguage.auto.rawValue {
                menuItem.title = "\(SyntaxLanguage.auto.title) (\(highlighter.effectiveLanguage.title))"
            }
            return true
        case #selector(toggleWordWrap(_:)):
            menuItem.state = (textView?.textContainer?.widthTracksTextView ?? true) ? .on : .off
            return hasEditor
        case #selector(compareWithSavedVersion(_:)):
            return hasEditor && fileURL != nil
        case #selector(prettyPrintXML(_:)), #selector(prettyPrintJSON(_:)), #selector(lintCSV(_:)),
             #selector(compareWithFile(_:)), #selector(compareWithDocument(_:)):
            return hasEditor
        default:
            return super.validateMenuItem(menuItem)
        }
    }
}
