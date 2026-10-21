import Testing
@testable import MacPadCore

struct CSVLinterTests {
    private func summary(_ result: CSVLintResult) -> [String] {
        result.issues.map { "\($0.severity) L\($0.line):C\($0.column) @\($0.offset) \($0.message)" }
    }

    @Test func cleanFileWithQuotedCommasAndNewlines() {
        let result = CSVLinter.lint("id,name,note\n1,Ann,\"hi, there\"\n2,Bob,\"multi\nline \"\"q\"\"\"\n")
        #expect(result.issues.isEmpty)
        #expect(result.columnCount == 3)
        #expect(result.rowCount == 2)
    }

    @Test func reportsEachKindOfProblem() {
        let result = CSVLinter.lint("id,name,id,\n1,Ann,x,y\n2,Bo\"b,z\n\n3,\"Cy\"x,1,2\n4,5\n")
        #expect(summary(result) == [
            #"warning L1:C1 @0 Duplicate column name "id" (columns 1 and 3)."#,
            "warning L1:C1 @0 Column 4 has an empty header name.",
            "error L3:C1 @22 Row has 3 fields; the header has 4.",
            #"warning L3:C5 @26 Quote inside an unquoted field; quote the field and double the quote ("")."#,
            "warning L4:C1 @31 Empty line.",
            "error L5:C7 @38 Unexpected text after closing quote.",
            "error L6:C1 @44 Row has 2 fields; the header has 4.",
        ])
        #expect(result.errorCount == 3)
    }

    @Test func unterminatedQuoteStopsParsing() {
        let result = CSVLinter.lint("a,b\n1,\"open\n2,3\n")
        #expect(summary(result) == [#"error L2:C3 @6 Quoted field is never closed (missing ")."#])
    }

    @Test func handlesCRLFLineEndings() {
        let result = CSVLinter.lint("a,b\r\n1,2\r\n3\r\n")
        #expect(summary(result) == ["error L3:C1 @10 Row has 1 field; the header has 2."])
    }

    @Test func columnsCountScalarsAndOffsetsCountUTF16() {
        let result = CSVLinter.lint("a,b\n😀😀,\"x\"y\n")
        #expect(summary(result) == ["error L2:C7 @12 Unexpected text after closing quote."])
    }

    @Test func trailingDelimiterAtEndOfFileCountsAsField() {
        #expect(CSVLinter.lint("a,b\n1,").issues.isEmpty)
    }

    @Test(arguments: [("a;b;c\n1;2;3\n", CSVDelimiter.semicolon), ("a\tb\n1\t2\n", .tab),
                      ("a|b\n1|2\n", .pipe), ("a,b\n\"x;y\",2\n", .comma), ("single\n", .comma)])
    func detectsDelimiter(text: String, expected: CSVDelimiter) {
        #expect(CSVLinter.detectDelimiter(in: text) == expected)
    }

    @Test func capsIssueCount() {
        let text = "a,b\n" + String(repeating: "1\n", count: CSVLinter.maxIssues + 5)
        let result = CSVLinter.lint(text)
        #expect(result.issues.count == CSVLinter.maxIssues)
        #expect(result.hiddenIssueCount == 5)
    }
}
