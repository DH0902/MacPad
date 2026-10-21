import AppKit
import MacPadCore

/// Colours and font styles per token: Notepad++-like in light mode, VS Code-like in dark mode.
@MainActor
private enum SyntaxTheme {
    enum FontStyle { case regular, bold, italic }

    struct Style {
        let color: NSColor
        var font: FontStyle?  // nil leaves the font as set by an enclosing token (e.g. the tag)
    }

    static let styles: [SyntaxTokenKind: Style] = [
        .tag: Style(color: color(0x0000FF, 0x569CD6), font: .bold),
        .attributeName: Style(color: color(0xFF0000, 0x9CDCFE), font: .regular),
        .attributeValue: Style(color: color(0x8000FF, 0xCE9178), font: .bold),
        .entity: Style(color: color(0xB8860B, 0xD7BA7D)),
        .declaration: Style(color: color(0x808080, 0x9E9E9E), font: .italic),
        .cdata: Style(color: color(0xFF8000, 0xD7BA7D), font: .regular),
        .comment: Style(color: color(0x008000, 0x6A9955), font: .italic),
        .number: Style(color: color(0xFF8000, 0xB5CEA8)),
        .literal: Style(color: color(0x0000FF, 0x569CD6), font: .bold),
        .string: Style(color: color(0x808080, 0xCE9178), font: .regular),
        .key: Style(color: color(0x000080, 0x9CDCFE), font: .bold),
    ]

    /// A colour with separate light- and dark-mode values, given as 0xRRGGBB.
    private static func color(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
}

/// Keeps a text view's syntax colouring up to date. Tokenizing runs off the main thread after typing
/// pauses; any newer edit cancels a pass in flight, so stale results are never applied.
/// Colours are layout-manager temporary attributes and bold/italic are font attributes; neither
/// touches the saved text, the undo stack or the document's edited state.
@MainActor
final class SyntaxHighlighter: NSObject {
    private static let typingPause: Duration = .milliseconds(150)

    private weak var textView: NSTextView?
    private let layoutManager: NSLayoutManager?
    private var pendingPass: Task<Void, Never>?
    private var regularFont: NSFont
    private var boldFont: NSFont

    var language: SyntaxLanguage = .auto { didSet { refresh() } }
    var fileExtension: String? { didSet { refresh() } }
    var fontSize: CGFloat {
        didSet {
            regularFont = EditorPreferences.font(size: fontSize)
            boldFont = EditorPreferences.font(size: fontSize, bold: true)
            refresh()
        }
    }

    init(textView: NSTextView, fontSize: CGFloat) {
        self.textView = textView
        self.fontSize = fontSize
        regularFont = EditorPreferences.font(size: fontSize)
        boldFont = EditorPreferences.font(size: fontSize, bold: true)
        // Accessing the layout manager opts the view into TextKit 1, which supports temporary
        // attributes; non-contiguous layout then only lays out what is visible.
        layoutManager = textView.layoutManager
        layoutManager?.allowsNonContiguousLayout = true
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(textDidChange(_:)),
                                               name: NSText.didChangeNotification, object: textView)
    }

    /// The language in use: the chosen one, or for Auto a guess from the extension, then the content.
    var effectiveLanguage: SyntaxLanguage {
        language == .auto ? .detect(fileExtension: fileExtension, text: textView?.string ?? "") : language
    }

    /// Re-colours as soon as possible, e.g. after the text was replaced wholesale or the zoom changed.
    func refresh() { schedulePass(after: .zero) }

    @objc private func textDidChange(_ notification: Notification) {
        schedulePass(after: Self.typingPause)
    }

    private func schedulePass(after delay: Duration) {
        pendingPass?.cancel()
        pendingPass = Task { [weak self] in
            if delay > .zero {
                do { try await Task.sleep(for: delay) } catch { return }
            }
            guard let self, let text = textView?.string else { return }
            let language = effectiveLanguage
            let tokens = await inBackground { SyntaxTokenizer.tokens(in: text, language: language) }
            guard !Task.isCancelled else { return }
            apply(tokens)
        }
    }

    private func apply(_ tokens: [SyntaxToken]) {
        guard let storage = textView?.textStorage, let layoutManager else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        defer { storage.endEditing() }
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
        resetFontStyles(of: storage, in: fullRange)

        for token in tokens where NSMaxRange(token.range) <= fullRange.length {
            guard let style = SyntaxTheme.styles[token.kind] else { continue }
            layoutManager.addTemporaryAttribute(.foregroundColor, value: style.color, forCharacterRange: token.range)
            if let font = style.font { setFontStyle(font, of: storage, in: token.range) }
        }
    }

    /// Restores the regular font only where something else is set (a previous pass, or text typed
    /// next to bold text), so unchanged text isn't invalidated and laid out again.
    private func resetFontStyles(of storage: NSTextStorage, in range: NSRange) {
        storage.enumerateAttribute(.font, in: range) { value, run, _ in
            if value as? NSFont != regularFont { storage.addAttribute(.font, value: regularFont, range: run) }
        }
        storage.enumerateAttribute(.obliqueness, in: range) { value, run, _ in
            if value != nil { storage.removeAttribute(.obliqueness, range: run) }
        }
    }

    private func setFontStyle(_ style: SyntaxTheme.FontStyle, of storage: NSTextStorage, in range: NSRange) {
        storage.addAttribute(.font, value: style == .bold ? boldFont : regularFont, range: range)
        // The system monospaced font has no italic face, so slant the regular one.
        if style == .italic {
            storage.addAttribute(.obliqueness, value: 0.2, range: range)
        } else {
            storage.removeAttribute(.obliqueness, range: range)
        }
    }
}
