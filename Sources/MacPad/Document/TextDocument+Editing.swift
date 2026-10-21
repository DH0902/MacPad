import AppKit
import MacPadCore

/// Format, View and Language menu actions.
extension TextDocument {
    // MARK: - Pretty print

    @objc func prettyPrintXML(_ sender: Any?) {
        reformatSelection(errorTitle: "Not valid XML", using: XMLFormatter.prettyPrinted)
    }

    @objc func prettyPrintJSON(_ sender: Any?) {
        reformatSelection(errorTitle: "Not valid JSON", using: JSONFormatter.prettyPrinted)
    }

    /// Formats the selection (or the whole document) off the main thread, then swaps it in as one
    /// undoable edit. If the text was edited in the meantime, the stale result is dropped.
    private func reformatSelection(errorTitle: String, using format: @escaping @Sendable (String) throws -> String) {
        guard let textView else { return }
        let range = textView.selectedRange().length > 0 ? textView.selectedRange() : textView.fullRange
        let source = (textView.string as NSString).substring(with: range)

        Task {
            do {
                let formatted = try await inBackground { try format(source) }
                let current = textView.string as NSString
                guard NSMaxRange(range) <= current.length, current.substring(with: range) == source else {
                    NSSound.beep()
                    return
                }
                textView.replaceUndoably([range], with: [formatted])
                textView.setSelectedRange(NSRange(location: range.location, length: 0))
            } catch {
                NSAlert.show(errorTitle, detail: error.localizedDescription, in: textView.window)
            }
        }
    }

    // MARK: - Language

    @objc func setLanguage(_ sender: Any?) {
        guard let tag = (sender as? NSMenuItem)?.tag, let language = SyntaxLanguage(rawValue: tag) else { return }
        highlighter?.language = language
    }

    // MARK: - Zoom

    @objc func zoomIn(_ sender: Any?) {
        setFontSize(max(fontSize + 1, (fontSize * 1.1).rounded()))
    }

    @objc func zoomOut(_ sender: Any?) {
        setFontSize(min(fontSize - 1, (fontSize / 1.1).rounded()))
    }

    @objc func resetZoom(_ sender: Any?) {
        setFontSize(EditorPreferences.defaultFontSize)
    }

    private func setFontSize(_ size: CGFloat) {
        fontSize = size.clamped(to: EditorPreferences.fontSizeRange)
        EditorPreferences.fontSize = fontSize
        textView?.font = EditorPreferences.font(size: fontSize)
        highlighter?.fontSize = fontSize  // re-applies bold/italic at the new size
    }

    // MARK: - Word wrap

    @objc func toggleWordWrap(_ sender: Any?) {
        guard let textView, let scrollView = textView.enclosingScrollView,
              let container = textView.textContainer else { return }
        let wrap = !container.widthTracksTextView
        let unbounded = CGFloat.greatestFiniteMagnitude
        container.widthTracksTextView = wrap
        scrollView.hasHorizontalScroller = !wrap
        textView.isHorizontallyResizable = !wrap
        if wrap {
            textView.frame.size.width = scrollView.contentSize.width
            container.containerSize = NSSize(width: scrollView.contentSize.width, height: unbounded)
        } else {
            container.containerSize = NSSize(width: unbounded, height: unbounded)
            textView.maxSize = NSSize(width: unbounded, height: unbounded)
        }
    }
}
