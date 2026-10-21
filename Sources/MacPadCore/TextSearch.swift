import Foundation

/// A compiled find/replace query. Every scan runs under a time limit, so a pathological user-supplied
/// pattern (catastrophic backtracking, e.g. `(a+)+$`) fails with `.timedOut` instead of hanging the app.
public struct TextSearch {
    public enum Failure: LocalizedError, Equatable {
        case emptyQuery, invalidPattern, timedOut

        public var errorDescription: String? {
            switch self {
            case .emptyQuery: "Enter something to find."
            case .invalidPattern: "Invalid regular expression."
            case .timedOut: "Search stopped: the pattern takes too long on this text."
            }
        }
    }

    public struct Options: Sendable {
        public var isRegex = false
        public var matchCase = false
        public var dotMatchesNewline = false

        public init(isRegex: Bool = false, matchCase: Bool = false, dotMatchesNewline: Bool = false) {
            self.isRegex = isRegex
            self.matchCase = matchCase
            self.dotMatchesNewline = dotMatchesNewline
        }
    }

    public typealias Match = (range: NSRange, wrapped: Bool)

    private let regex: NSRegularExpression
    private let template: String
    private let timeLimit: Duration

    public init(query: String, replacement: String = "", options: Options, timeLimit: Duration = .seconds(2)) throws {
        guard !query.isEmpty else { throw Failure.emptyQuery }
        var regexOptions: NSRegularExpression.Options = [.anchorsMatchLines]
        if !options.matchCase { regexOptions.insert(.caseInsensitive) }
        if options.isRegex && options.dotMatchesNewline { regexOptions.insert(.dotMatchesLineSeparators) }
        let pattern = options.isRegex ? query : NSRegularExpression.escapedPattern(for: query)
        do {
            regex = try NSRegularExpression(pattern: pattern, options: regexOptions)
        } catch {
            throw Failure.invalidPattern
        }
        template = options.isRegex ? Self.unescape(replacement) : NSRegularExpression.escapedTemplate(for: replacement)
        self.timeLimit = timeLimit
    }

    /// The first match after `selection`, wrapping to the top if `wrap` is set.
    public func nextMatch(in text: String, after selection: NSRange, wrap: Bool) throws -> Match? {
        var start = NSMaxRange(selection)
        var match = try firstMatch(in: text, from: start)
        // Don't get stuck on an empty match (e.g. `^`) at the cursor.
        if let found = match, found == selection, found.length == 0, start < text.utf16.count {
            start += 1
            match = try firstMatch(in: text, from: start)
        }
        if let match { return (match, false) }
        guard wrap, let wrapped = try firstMatch(in: text, from: 0) else { return nil }
        return (wrapped, true)
    }

    /// The last match before `selection`, wrapping to the bottom if `wrap` is set.
    public func previousMatch(in text: String, before selection: NSRange, wrap: Bool) throws -> Match? {
        var last: NSRange?
        try enumerate(in: text, range: NSRange(location: 0, length: selection.location)) { match, _ in
            if match.range != selection { last = match.range }
        }
        if let last { return (last, false) }
        guard wrap else { return nil }
        try enumerate(in: text, range: Self.fullRange(of: text)) { match, _ in last = match.range }
        return last.map { ($0, true) }
    }

    public func count(in text: String) throws -> Int {
        var count = 0
        try enumerate(in: text, range: Self.fullRange(of: text)) { _, _ in count += 1 }
        return count
    }

    /// Every match with its replacement text, in document order.
    public func replacements(in text: String) throws -> [(range: NSRange, replacement: String)] {
        var result: [(NSRange, String)] = []
        try enumerate(in: text, range: Self.fullRange(of: text)) { match, _ in
            result.append((match.range, regex.replacementString(for: match, in: text, offset: 0, template: template)))
        }
        return result
    }

    /// The replacement for `range` if it is exactly one match (used by a single "Replace").
    public func replacement(forExactMatch range: NSRange, in text: String) throws -> String? {
        var replacement: String?
        try enumerate(in: text, range: range, options: .anchored) { match, stop in
            if match.range == range {
                replacement = regex.replacementString(for: match, in: text, offset: 0, template: template)
            }
            stop = true
        }
        return replacement
    }

    // MARK: - Private

    private func firstMatch(in text: String, from location: Int) throws -> NSRange? {
        var found: NSRange?
        let range = NSRange(location: location, length: text.utf16.count - location)
        try enumerate(in: text, range: range) { match, stop in
            found = match.range
            stop = true
        }
        return found
    }

    /// Enumerates matches, aborting with `.timedOut` once the time limit passes. `.reportProgress`
    /// makes ICU call back periodically even in the middle of one long match, so this can't hang.
    /// Transparent, non-anchoring bounds make `^`, `$`, `\b` and lookarounds see the text outside
    /// `range`, so searching from the cursor behaves the same as searching the whole document.
    private func enumerate(in text: String, range: NSRange, options: NSRegularExpression.MatchingOptions = [],
                           _ body: (NSTextCheckingResult, inout Bool) -> Void) throws {
        let deadline = ContinuousClock.now + timeLimit
        var timedOut = false
        regex.enumerateMatches(in: text, options: options.union([.reportProgress, .withTransparentBounds, .withoutAnchoringBounds]), range: range) { match, _, stop in
            if let match {
                var shouldStop = false
                body(match, &shouldStop)
                if shouldStop { stop.pointee = true; return }
            }
            if ContinuousClock.now >= deadline {
                timedOut = true
                stop.pointee = true
            }
        }
        if timedOut { throw Failure.timedOut }
    }

    private static func fullRange(of text: String) -> NSRange {
        NSRange(location: 0, length: text.utf16.count)
    }

    /// Turns `\n`, `\t` and `\r` in a regex replacement into real characters, like Notepad++.
    /// Other escapes (`\\`, `\$`) are left for the template engine.
    static func unescape(_ replacement: String) -> String {
        var out = ""
        var chars = replacement.makeIterator()
        while let ch = chars.next() {
            guard ch == "\\", let next = chars.next() else { out.append(ch); continue }
            switch next {
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": out.append("\r")
            default: out.append(ch); out.append(next)
            }
        }
        return out
    }
}
