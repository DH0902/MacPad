import Foundation
import Testing
@testable import MacPadCore

struct LineDiffTests {
    private func describe(_ rows: [LineDiff.Row]) -> [String] {
        rows.map { "\($0.kind) \($0.left.map(String.init) ?? "-") \($0.right.map(String.init) ?? "-")" }
    }

    @Test func alignsChangesAdditionsAndRemovals() {
        let rows = LineDiff.align(["a", "b", "c", "d", "e"], ["a", "B", "c", "e", "f", "g"])
        #expect(describe(rows) == [
            "same 0 0", "changed 1 1", "same 2 2", "removed 3 -", "same 4 3", "added - 4", "added - 5",
        ])
        #expect(LineDiff.hunkStarts(in: rows) == [1, 3, 5])
    }

    @Test func identicalFilesHaveNoHunks() {
        let lines = ["x", "y", "z"]
        #expect(LineDiff.hunkStarts(in: LineDiff.align(lines, lines)).isEmpty)
    }

    @Test func handlesEmptySides() {
        #expect(describe(LineDiff.align([], ["a"])) == ["added - 0"])
        #expect(describe(LineDiff.align(["a"], [])) == ["removed 0 -"])
    }

    @Test func largeFilesWithSmallChangeStayCheap() {
        let old = (0..<200_000).map { "line \($0)" }
        var new = old
        new[100_000] = "edited"
        let rows = LineDiff.align(old, new)
        #expect(rows.count == old.count)
        #expect(LineDiff.hunkStarts(in: rows) == [100_000])
    }

    @Test func splitsLinesIgnoringTrailingNewline() {
        #expect(LineDiff.lines(of: "a\r\nb\n") == ["a", "b"])
        #expect(LineDiff.lines(of: "").isEmpty)
    }

    @Test func inlineChangeFindsDifferingMiddle() throws {
        let change = try #require(LineDiff.inlineChange("let x = 1", "let x = 42"))
        #expect(change.left == NSRange(location: 8, length: 1))
        #expect(change.right == NSRange(location: 8, length: 2))
        #expect(LineDiff.inlineChange("same", "same") == nil)
    }
}
