import AppKit

/// User-adjustable editor settings that persist across launches.
enum EditorPreferences {
    static let defaultFontSize: CGFloat = 13
    static let fontSizeRange: ClosedRange<CGFloat> = 8...72
    private static let fontSizeKey = "EditorFontSize"

    /// New windows open at the last zoom level used.
    static var fontSize: CGFloat {
        get {
            let saved = CGFloat(UserDefaults.standard.double(forKey: fontSizeKey))
            return saved > 0 ? saved.clamped(to: fontSizeRange) : defaultFontSize
        }
        set { UserDefaults.standard.set(Double(newValue.clamped(to: fontSizeRange)), forKey: fontSizeKey) }
    }

    static func font(size: CGFloat, bold: Bool = false) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    /// A plain-text code editor: monospaced, no smart substitutions, undo enabled.
    @MainActor
    static func makeEditor(fontSize: CGFloat) -> (scrollView: NSScrollView, textView: NSTextView) {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = font(size: fontSize)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        return (scrollView, textView)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
