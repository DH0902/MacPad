import Foundation
import Testing
@testable import MacPadCore

struct TextFileCodecTests {
    @Test func plainUTF8RoundTrips() {
        let data = Data("héllo 😀\r\nworld\n".utf8)
        let (text, format) = TextFileCodec.decode(data)
        #expect(format == .utf8)
        #expect(TextFileCodec.encode(text, as: format).data == data)
    }

    @Test(arguments: [
        (Data([0xEF, 0xBB, 0xBF]) + Data("hi".utf8), String.Encoding.utf8),
        (Data([0xFF, 0xFE, 0x68, 0x00, 0x69, 0x00]), .utf16LittleEndian),
        (Data([0xFE, 0xFF, 0x00, 0x68, 0x00, 0x69]), .utf16BigEndian),
    ])
    func byteOrderMarkFilesRoundTrip(data: Data, encoding: String.Encoding) {
        let (text, format) = TextFileCodec.decode(data)
        #expect(text == "hi")
        #expect(format == TextFileFormat(encoding: encoding, hasByteOrderMark: true))
        #expect(TextFileCodec.encode(text, as: format).data == data)
    }

    @Test func everyByteValueRoundTripsUnchanged() {
        let data = Data((0...255).map(UInt8.init) + [0xC3, 0x28])  // includes invalid UTF-8
        let (text, format) = TextFileCodec.decode(data)
        #expect(format.encoding != .utf8)
        #expect(TextFileCodec.encode(text, as: format).data == data)
    }

    @Test func windows1252SmartQuotesRoundTrip() {
        let data = Data([0x93, 0x68, 0x69, 0x94])  // “hi” in Windows-1252
        let (text, format) = TextFileCodec.decode(data)
        #expect(text == "“hi”")
        #expect(TextFileCodec.encode(text, as: format).data == data)
    }

    @Test func unencodableTextFallsBackToUTF8() {
        let latin1 = TextFileFormat(encoding: .isoLatin1)
        let (data, format) = TextFileCodec.encode("emoji 😀", as: latin1)
        #expect(format == .utf8)
        #expect(String(data: data, encoding: .utf8) == "emoji 😀")
    }
}
