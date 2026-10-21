import Foundation
import Testing
@testable import MacPadCore

struct JSONFormatterTests {
    @Test func indentsAndKeepsKeyOrderAndEscapes() throws {
        let source = #"{"zeta":1,"alpha":{"url":"http://x/y","q":"say \"{[,:]}\"","e":{},"a":[ ]},"n":[2.5e3,true,null]}"#
        let expected = """
        {
            "zeta": 1,
            "alpha": {
                "url": "http://x/y",
                "q": "say \\"{[,:]}\\"",
                "e": {},
                "a": []
            },
            "n": [
                2.5e3,
                true,
                null
            ]
        }
        """
        #expect(try JSONFormatter.prettyPrinted(source) == expected)
    }

    @Test func keepsNonASCIIText() throws {
        #expect(try JSONFormatter.prettyPrinted(#"{"k":"héllo 😀"}"#) == "{\n    \"k\": \"héllo 😀\"\n}")
    }

    @Test func rejectsInvalidJSON() {
        #expect(throws: (any Error).self) { try JSONFormatter.prettyPrinted(#"{"a": }"#) }
    }
}

struct XMLFormatterTests {
    @Test func indentsWithoutAddingDeclaration() throws {
        let output = try XMLFormatter.prettyPrinted(#"<root><a x="1"><b>hi</b></a><!-- c --></root>"#)
        #expect(output == """
        <root>
            <a x="1">
                <b>hi</b>
            </a>
            <!-- c -->
        </root>
        """)
    }

    @Test func rejectsInvalidXML() {
        #expect(throws: (any Error).self) { try XMLFormatter.prettyPrinted("<a><b></a>") }
    }

    @Test func neverLoadsExternalEntities() throws {
        let secret = FileManager.default.temporaryDirectory.appendingPathComponent("macpad-xxe-\(UUID()).txt")
        try "TOP-SECRET".write(to: secret, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: secret) }

        let attack = """
        <?xml version="1.0"?>
        <!DOCTYPE r [<!ENTITY x SYSTEM "\(secret.absoluteString)">]>
        <r>&x;</r>
        """
        let output = (try? XMLFormatter.prettyPrinted(attack)) ?? ""
        #expect(!output.contains("TOP-SECRET"))
    }
}
