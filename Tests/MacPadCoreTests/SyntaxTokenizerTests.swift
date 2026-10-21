import Foundation
import Testing
@testable import MacPadCore

struct SyntaxTokenizerTests {
    private func tokens(_ text: String, _ language: SyntaxLanguage) -> [String] {
        SyntaxTokenizer.tokens(in: text, language: language).map {
            "\($0.kind):\((text as NSString).substring(with: $0.range))"
        }
    }

    @Test func tokenizesXML() {
        #expect(tokens(#"<a x="1">&amp;<!-- c --></a>"#, .xml) == [
            #"tag:<a x="1">"#, "attributeName:x", #"attributeValue:"1""#, "tag:</a>",
            "entity:&amp;", "comment:<!-- c -->",
        ])
    }

    @Test func tokenizesJSONKeysSeparatelyFromStrings() {
        #expect(tokens(#"{"k": "v", "n": -1.5e3, "b": null}"#, .json) == [
            "number:-1.5e3", "literal:null",
            #"string:"k""#, #"string:"v""#, #"string:"n""#, #"string:"b""#,
            #"key:"k""#, #"key:"n""#, #"key:"b""#,
        ])
    }

    @Test func plainTextHasNoTokens() {
        #expect(tokens("<a>", .plainText).isEmpty)
    }

    @Test(arguments: [(String?("x.json"), "", SyntaxLanguage.json), ("x.SVG", "", .xml), (nil, "  <a/>", .xml),
                      (nil, "\n[1]", .json), ("notes.txt", "hello", .plainText)])
    func detectsLanguage(fileName: String?, text: String, expected: SyntaxLanguage) {
        let ext = fileName.map { ($0 as NSString).pathExtension }
        #expect(SyntaxLanguage.detect(fileExtension: ext, text: text) == expected)
    }
}
