import Foundation

/// How a text file's bytes are encoded, so it can be saved back exactly the way it was opened.
public struct TextFileFormat: Sendable, Equatable {
    public var encoding: String.Encoding
    public var hasByteOrderMark: Bool

    public init(encoding: String.Encoding, hasByteOrderMark: Bool = false) {
        self.encoding = encoding
        self.hasByteOrderMark = hasByteOrderMark
    }

    public static let utf8 = TextFileFormat(encoding: .utf8)
}

public enum TextFileError: LocalizedError, Equatable {
    case tooLarge(bytes: Int, limit: Int)

    public var errorDescription: String? {
        switch self {
        case let .tooLarge(bytes, limit):
            let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            let max = ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)
            return "The file is too large to open (\(size); the limit is \(max))."
        }
    }
}

/// Converts between file bytes and text without losing data: text that isn't UTF-8 falls back to
/// Windows-1252 and then Latin-1 (which maps every byte), and saving keeps the original encoding and BOM.
public enum TextFileCodec {
    /// Larger files are refused rather than risk exhausting memory.
    public static let maxFileSize = 256 * 1024 * 1024

    private static let byteOrderMarks: [(bytes: [UInt8], encoding: String.Encoding)] = [
        ([0xEF, 0xBB, 0xBF], .utf8),
        ([0xFF, 0xFE], .utf16LittleEndian),
        ([0xFE, 0xFF], .utf16BigEndian),
    ]

    public static func read(contentsOf url: URL) throws -> (text: String, format: TextFileFormat) {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maxFileSize else { throw TextFileError.tooLarge(bytes: size, limit: maxFileSize) }
        return decode(try Data(contentsOf: url, options: .mappedIfSafe))
    }

    public static func decode(_ data: Data) -> (text: String, format: TextFileFormat) {
        for bom in byteOrderMarks where data.starts(with: bom.bytes) {
            if let text = String(data: data.dropFirst(bom.bytes.count), encoding: bom.encoding) {
                return (text, TextFileFormat(encoding: bom.encoding, hasByteOrderMark: true))
            }
        }
        for encoding in [String.Encoding.utf8, .windowsCP1252] {
            if let text = String(data: data, encoding: encoding) {
                return (text, TextFileFormat(encoding: encoding))
            }
        }
        // Latin-1 decodes any byte sequence, so even binary files round-trip unchanged.
        return (String(data: data, encoding: .isoLatin1) ?? "", TextFileFormat(encoding: .isoLatin1))
    }

    /// Encodes `text` in `format`. If the text no longer fits that encoding (e.g. an emoji typed into a
    /// Latin-1 file) it is written as UTF-8 instead of losing characters; the returned format says so.
    public static func encode(_ text: String, as format: TextFileFormat) -> (data: Data, format: TextFileFormat) {
        guard let body = text.data(using: format.encoding, allowLossyConversion: false) else {
            return (Data(text.utf8), .utf8)
        }
        guard format.hasByteOrderMark,
              let bom = byteOrderMarks.first(where: { $0.encoding == format.encoding }) else {
            return (body, format)
        }
        return (Data(bom.bytes) + body, format)
    }
}
