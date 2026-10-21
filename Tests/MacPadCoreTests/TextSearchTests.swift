import Foundation
import Testing
@testable import MacPadCore

struct TextSearchTests {
    private let regex = TextSearch.Options(isRegex: true)

    @Test func literalSearchEscapesRegexCharacters() throws {
        let search = try TextSearch(query: "a.b", options: .init())
        #expect(try search.count(in: "a.b axb A.B") == 2)  // case-insensitive by default
    }

    @Test func regexReplacementSupportsGroupsAndEscapes() throws {
        let search = try TextSearch(query: #"(\w+)@(\w+)"#, replacement: #"$2\t$1\n"#, options: regex)
        let replacements = try search.replacements(in: "ann@home bob@work")
        #expect(replacements.map(\.replacement) == ["home\tann\n", "work\tbob\n"])
    }

    @Test func literalReplacementIsNotATemplate() throws {
        let search = try TextSearch(query: "x", replacement: "$1\\n", options: .init())
        #expect(try search.replacements(in: "x").map(\.replacement) == ["$1\\n"])
    }

    @Test func nextMatchWrapsAndSkipsEmptyMatchAtCursor() throws {
        let search = try TextSearch(query: "^", options: regex)
        let text = "a\nb"
        let first = try #require(try search.nextMatch(in: text, after: NSRange(location: 0, length: 0), wrap: true))
        #expect(first.range == NSRange(location: 2, length: 0))
        let wrapped = try #require(try search.nextMatch(in: text, after: first.range, wrap: true))
        #expect(wrapped == (NSRange(location: 0, length: 0), true))
    }

    @Test func anchorsAndWordBoundariesRespectTextBeforeCursor() throws {
        let search = try TextSearch(query: #"\bcat"#, options: regex)
        // Starting the search in the middle of "concat" must not treat "cat" as a word start.
        let match = try search.nextMatch(in: "concat cat", after: NSRange(location: 3, length: 0), wrap: false)
        #expect(match?.range == NSRange(location: 7, length: 3))
    }

    @Test func previousMatchSearchesBackwards() throws {
        let search = try TextSearch(query: "o", options: .init())
        let text = "foo boo"
        let match = try #require(try search.previousMatch(in: text, before: NSRange(location: 5, length: 1), wrap: false))
        #expect(match.range == NSRange(location: 2, length: 1))
        #expect(try search.previousMatch(in: text, before: NSRange(location: 0, length: 0), wrap: false) == nil)
    }

    @Test func replaceOnlyAppliesToExactMatch() throws {
        let search = try TextSearch(query: "cat", replacement: "dog", options: .init())
        #expect(try search.replacement(forExactMatch: NSRange(location: 4, length: 3), in: "the cat") == "dog")
        #expect(try search.replacement(forExactMatch: NSRange(location: 0, length: 3), in: "the cat") == nil)
    }

    @Test func rejectsEmptyAndInvalidQueries() {
        #expect(throws: TextSearch.Failure.emptyQuery) { try TextSearch(query: "", options: regex) }
        #expect(throws: TextSearch.Failure.invalidPattern) { try TextSearch(query: "(", options: regex) }
    }

    @Test func catastrophicPatternTimesOutInsteadOfHanging() throws {
        let search = try TextSearch(query: "(a+)+$", options: regex, timeLimit: .milliseconds(200))
        let text = String(repeating: "a", count: 40) + "!"
        let start = ContinuousClock.now
        #expect(throws: TextSearch.Failure.timedOut) { try search.count(in: text) }
        #expect(ContinuousClock.now - start < .seconds(2))
    }
}
