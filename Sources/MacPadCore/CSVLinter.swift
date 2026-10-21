import Foundation

public enum CSVDelimiter: String, CaseIterable, Sendable {
    case comma = ",", semicolon = ";", tab = "\t", pipe = "|"

    public var name: String {
        switch self {
        case .comma: "Comma"
        case .semicolon: "Semicolon"
        case .tab: "Tab"
        case .pipe: "Pipe"
        }
    }

    var codeUnit: UInt16 { rawValue.utf16.first! }
}

public struct CSVIssue: Sendable, Equatable {
    public enum Severity: Sendable { case error, warning }

    public let severity: Severity
    public let line: Int      // 1-based
    public let column: Int    // 1-based, in Unicode scalars
    public let offset: Int    // UTF-16 offset into the text, for selecting the issue in a text view
    public let message: String
}

public struct CSVLintResult: Sendable {
    public var delimiter: CSVDelimiter
    public var rowCount = 0        // data rows, excluding the header
    public var columnCount = 0
    public var issues: [CSVIssue] = []
    public var hiddenIssueCount = 0  // issues beyond `CSVLinter.maxIssues`

    public var errorCount: Int { issues.count { $0.severity == .error } }
    public var warningCount: Int { issues.count - errorCount }
}

/// RFC 4180-style CSV validator: quoting, field counts, blank lines and header names.
public enum CSVLinter {
    public static let maxIssues = 1000

    /// Picks the delimiter whose count is non-zero and most consistent across the first lines.
    public static func detectDelimiter(in text: String) -> CSVDelimiter {
        let sample = text.prefix(65_536).split(whereSeparator: \.isNewline).prefix(50)
        var best: (delimiter: CSVDelimiter, score: Int)?
        for delimiter in CSVDelimiter.allCases {
            let target = Character(delimiter.rawValue)
            let counts = sample.map { line in
                var inQuotes = false
                var count = 0
                for ch in line {
                    if ch == "\"" { inQuotes.toggle() } else if ch == target && !inQuotes { count += 1 }
                }
                return count
            }
            guard let first = counts.first, first > 0 else { continue }
            let score = counts.count { $0 == first } * 1000 + first
            if score > best?.score ?? -1 { best = (delimiter, score) }
        }
        return best?.delimiter ?? .comma
    }

    public static func lint(_ text: String, delimiter: CSVDelimiter? = nil) -> CSVLintResult {
        var parser = Parser(units: Array(text.utf16), delimiter: delimiter ?? detectDelimiter(in: text))
        parser.run()
        parser.result.issues.sort { ($0.line, $0.column) < ($1.line, $1.column) }
        return parser.result
    }
}

/// Single pass over UTF-16 code units, so issue offsets map directly onto `NSString`/`NSTextView` ranges.
private struct Parser {
    private static let quote = UInt16(UInt8(ascii: "\"")), lineFeed = UInt16(UInt8(ascii: "\n")), carriageReturn = UInt16(UInt8(ascii: "\r"))

    private struct Position { let line, lineStart, offset: Int }
    private struct Field { let range: Range<Int>; let quoted: Bool }

    let units: [UInt16]
    let delimiter: UInt16
    var result: CSVLintResult
    private var i = 0
    private var line = 1
    private var lineStart = 0

    init(units: [UInt16], delimiter: CSVDelimiter) {
        self.units = units
        self.delimiter = delimiter.codeUnit
        result = CSVLintResult(delimiter: delimiter)
    }

    private var position: Position { Position(line: line, lineStart: lineStart, offset: i) }
    private var atEnd: Bool { i >= units.count }
    private var atFieldEnd: Bool {
        atEnd || units[i] == delimiter || units[i] == Self.lineFeed || units[i] == Self.carriageReturn
    }

    mutating func run() {
        var haveHeader = false
        while !atEnd {
            let recordStart = i
            let recordPosition = position
            var fieldCount = 0
            var headerFields: [Field] = []

            while true {
                guard let field = parseField() else { return }  // unterminated quote: nothing after it is reliable
                fieldCount += 1
                if !haveHeader { headerFields.append(field) }
                guard !atEnd, units[i] == delimiter else { break }
                advance()
            }

            let isBlank = i == recordStart
            consumeLineBreak()

            if isBlank {
                report(.warning, at: recordPosition, "Empty line.")
            } else if !haveHeader {
                haveHeader = true
                result.columnCount = fieldCount
                checkHeader(headerFields.map(text(of:)), at: recordPosition)
            } else {
                result.rowCount += 1
                if fieldCount != result.columnCount {
                    report(.error, at: recordPosition,
                           "Row has \(fieldCount) field\(fieldCount == 1 ? "" : "s"); the header has \(result.columnCount).")
                }
            }
        }
    }

    private mutating func parseField() -> Field? {
        guard !atEnd, units[i] == Self.quote else { return parseUnquotedField() }
        let opening = position
        advance()
        let start = i
        while !atEnd {
            guard units[i] == Self.quote else { advance(); continue }
            if i + 1 < units.count, units[i + 1] == Self.quote {  // "" is an escaped quote
                advance()
                advance()
                continue
            }
            let end = i
            advance()
            if !atFieldEnd {
                report(.error, at: position, "Unexpected text after closing quote.")
                while !atFieldEnd { advance() }
            }
            return Field(range: start..<end, quoted: true)
        }
        report(.error, at: opening, "Quoted field is never closed (missing \").")
        return nil
    }

    private mutating func parseUnquotedField() -> Field {
        let start = i
        var warned = false
        while !atFieldEnd {
            if units[i] == Self.quote && !warned {
                report(.warning, at: position, "Quote inside an unquoted field; quote the field and double the quote (\"\").")
                warned = true
            }
            advance()
        }
        return Field(range: start..<i, quoted: false)
    }

    private mutating func checkHeader(_ names: [String], at position: Position) {
        var seen: [String: Int] = [:]
        for (index, name) in names.enumerated() {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                report(.warning, at: position, "Column \(index + 1) has an empty header name.")
            } else if let first = seen[trimmed] {
                report(.warning, at: position, "Duplicate column name \"\(trimmed)\" (columns \(first + 1) and \(index + 1)).")
            } else {
                seen[trimmed] = index
            }
        }
    }

    private func text(of field: Field) -> String {
        let raw = String(decoding: units[field.range], as: UTF16.self)
        return field.quoted ? raw.replacingOccurrences(of: "\"\"", with: "\"") : raw
    }

    /// Moves past one code unit, counting LF, CRLF and lone CR each as one line break.
    private mutating func advance() {
        let unit = units[i]
        i += 1
        if unit == Self.lineFeed || (unit == Self.carriageReturn && (atEnd || units[i] != Self.lineFeed)) {
            line += 1
            lineStart = i
        }
    }

    private mutating func consumeLineBreak() {
        if !atEnd, units[i] == Self.carriageReturn { advance() }
        if !atEnd, units[i] == Self.lineFeed { advance() }
    }

    private mutating func report(_ severity: CSVIssue.Severity, at position: Position, _ message: String) {
        guard result.issues.count < CSVLinter.maxIssues else {
            result.hiddenIssueCount += 1
            return
        }
        // Count Unicode scalars, so a surrogate pair (e.g. an emoji) is a single column.
        let column = units[position.lineStart..<position.offset].count { !UTF16.isTrailSurrogate($0) } + 1
        result.issues.append(CSVIssue(severity: severity, line: position.line, column: column,
                                      offset: position.offset, message: message))
    }
}
