import Foundation

public enum SyntaxLanguage: Int, CaseIterable, Sendable {
    case auto, plainText, xml, json

    public var title: String {
        switch self {
        case .auto: "Auto Detect"
        case .plainText: "Plain Text"
        case .xml: "XML"
        case .json: "JSON"
        }
    }

    private static let xmlExtensions: Set = ["xml", "xsd", "xsl", "xslt", "svg", "plist", "config", "csproj",
                                             "resx", "wsdl", "xaml", "xhtml", "html", "htm", "pom", "gpx", "kml"]
    private static let jsonExtensions: Set = ["json", "geojson", "jsonc", "har", "webmanifest"]

    /// Guesses the language from the file extension, then from the first non-blank character.
    public static func detect(fileExtension: String?, text: String) -> SyntaxLanguage {
        if let ext = fileExtension?.lowercased() {
            if xmlExtensions.contains(ext) { return .xml }
            if jsonExtensions.contains(ext) { return .json }
        }
        switch text.prefix(4096).first(where: { !$0.isWhitespace }) {
        case "<": return .xml
        case "{", "[": return .json
        default: return .plainText
        }
    }
}

public enum SyntaxTokenKind: Sendable, CaseIterable {
    case tag, attributeName, attributeValue, entity, declaration, cdata, comment  // XML
    case number, literal, string, key                                            // JSON
}

public struct SyntaxToken: Sendable, Equatable {
    public let kind: SyntaxTokenKind
    public let range: NSRange
}

/// Regex-based tokenizer for syntax colouring. Pure and thread-safe, so it runs off the main thread.
public enum SyntaxTokenizer {
    /// Larger documents are left plain to keep the editor responsive.
    public static let maxLength = 5_000_000

    // NSRegularExpression is immutable and documented as thread-safe.
    private struct Rule: @unchecked Sendable {
        let regex: NSRegularExpression
        let kind: SyntaxTokenKind
        var group = 0
        var inner: [Rule] = []  // matched only inside this rule's match (e.g. attributes inside a tag)

        init(_ pattern: String, _ kind: SyntaxTokenKind, group: Int = 0, dotAll: Bool = false, inner: [Rule] = []) {
            regex = try! NSRegularExpression(pattern: pattern, options: dotAll ? [.dotMatchesLineSeparators] : [])
            self.kind = kind
            self.group = group
            self.inner = inner
        }
    }

    // Later rules win where tokens overlap, so comments and strings come last.
    private static let xmlRules = [
        Rule(#"</?[A-Za-z_][\w:.\-]*(?:"[^"]*"|'[^']*'|[^'"<>])*>"#, .tag, inner: [
            Rule(#"([\w:.\-]+)\s*="#, .attributeName, group: 1),
            Rule(#""[^"]*"|'[^']*'"#, .attributeValue),
        ]),
        Rule(#"&(?:#\d+|#x[0-9A-Fa-f]+|\w+);"#, .entity),
        Rule(#"<\?.*?\?>|<!DOCTYPE[^>]*>"#, .declaration, dotAll: true),
        Rule(#"<!\[CDATA\[.*?\]\]>"#, .cdata, dotAll: true),
        Rule(#"<!--.*?-->"#, .comment, dotAll: true),
    ]

    private static let jsonRules = [
        Rule(#"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, .number),
        Rule(#"\b(?:true|false|null)\b"#, .literal),
        Rule(#""(?:[^"\\\n]|\\.)*""#, .string),
        Rule(#"("(?:[^"\\\n]|\\.)*")\s*:"#, .key, group: 1),
    ]

    /// Tokens in application order: where tokens overlap, later ones override earlier ones.
    /// Stops early (returning a partial list) if the current task is cancelled.
    public static func tokens(in text: String, language: SyntaxLanguage) -> [SyntaxToken] {
        let length = text.utf16.count
        guard length <= maxLength else { return [] }
        let rules: [Rule] = switch language {
        case .xml: xmlRules
        case .json: jsonRules
        case .auto, .plainText: []
        }
        var tokens: [SyntaxToken] = []
        collect(rules, in: NSRange(location: 0, length: length), of: text, into: &tokens)
        return tokens
    }

    private static func collect(_ rules: [Rule], in range: NSRange, of text: String, into tokens: inout [SyntaxToken]) {
        for rule in rules {
            guard !Task.isCancelled else { return }
            rule.regex.enumerateMatches(in: text, options: .reportProgress, range: range) { match, _, stop in
                if Task.isCancelled { stop.pointee = true; return }
                guard let match else { return }
                let target = match.range(at: rule.group)
                guard target.location != NSNotFound else { return }
                tokens.append(SyntaxToken(kind: rule.kind, range: target))
                if !rule.inner.isEmpty { collect(rule.inner, in: match.range, of: text, into: &tokens) }
            }
        }
    }
}
