import Foundation

public enum JSONFormatter {
    /// Validates `source` as JSON, then re-indents it. Unlike `JSONSerialization` output, key order,
    /// number spelling and string escapes are kept exactly as written.
    public static func prettyPrinted(_ source: String) throws -> String {
        let bytes = Array(source.utf8)
        _ = try JSONSerialization.jsonObject(with: Data(bytes), options: .fragmentsAllowed)
        return reindent(bytes)
    }

    /// Works on UTF-8 bytes: every structural JSON character is ASCII, and multi-byte UTF-8
    /// sequences never contain ASCII bytes, so no decoding is needed.
    static func reindent(_ bytes: [UInt8], indent: [UInt8] = Array("    ".utf8)) -> String {
        let quote = UInt8(ascii: "\""), backslash = UInt8(ascii: "\\")
        let whitespace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count * 2)
        var depth = 0
        var inString = false
        var escaped = false

        func newline() {
            out.append(0x0A)
            for _ in 0..<depth { out.append(contentsOf: indent) }
        }

        var i = 0
        while i < bytes.count {
            let byte = bytes[i]
            defer { i += 1 }
            if inString {
                out.append(byte)
                if escaped { escaped = false } else if byte == backslash { escaped = true } else if byte == quote { inString = false }
                continue
            }
            switch byte {
            case quote:
                inString = true
                out.append(byte)
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                // Keep empty containers compact: {} and []
                let close = byte == UInt8(ascii: "{") ? UInt8(ascii: "}") : UInt8(ascii: "]")
                var next = i + 1
                while next < bytes.count, whitespace.contains(bytes[next]) { next += 1 }
                out.append(byte)
                if next < bytes.count, bytes[next] == close {
                    out.append(close)
                    i = next
                } else {
                    depth += 1
                    newline()
                }
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth = max(depth - 1, 0)
                newline()
                out.append(byte)
            case UInt8(ascii: ","):
                out.append(byte)
                newline()
            case UInt8(ascii: ":"):
                out.append(contentsOf: [byte, 0x20])
            case _ where whitespace.contains(byte):
                break
            default:
                out.append(byte)
            }
        }
        return String(decoding: out, as: UTF8.self)
    }
}

public enum XMLFormatter {
    /// Pretty-prints XML with 4-space indentation. External entities and DTDs are never loaded,
    /// so a crafted document can't make the formatter read local files or the network (XXE).
    public static func prettyPrinted(_ source: String) throws -> String {
        let document = try XMLDocument(xmlString: source, options: [
            .nodeLoadExternalEntitiesNever, .nodePreserveCDATA, .nodePreserveEmptyElements,
        ])
        var output = document.xmlString(options: [.nodePrettyPrint, .nodePreserveCDATA, .nodePreserveEmptyElements])
        // Don't add an XML declaration the original didn't have.
        if !source.drop(while: \.isWhitespace).hasPrefix("<?xml"),
           output.hasPrefix("<?xml"), let newline = output.firstIndex(of: "\n") {
            output = String(output[output.index(after: newline)...])
        }
        return output
    }
}
