import Foundation

/// Side-by-side line diff, in the style of Notepad++'s Compare plugin.
public enum LineDiff {
    public enum Kind: Sendable { case same, changed, added, removed }

    /// One aligned row; `left` / `right` are 0-based line indices, nil where that side has a gap.
    public struct Row: Sendable, Equatable {
        public let kind: Kind
        public let left: Int?
        public let right: Int?
    }

    public static func lines(of text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if lines.last == "" { lines.removeLast() }  // a trailing newline isn't an extra line
        return lines
    }

    /// Aligns two files line by line, pairing removed+inserted runs as "changed".
    /// Common leading and trailing lines are matched directly, so the Myers diff (whose cost grows
    /// with the number of differences) only runs on the region that actually differs.
    public static func align(_ old: [String], _ new: [String]) -> [Row] {
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }

        // Diff small integer ids instead of strings: cheaper to compare.
        var ids: [String: Int] = [:]
        func id(_ line: String) -> Int {
            if let existing = ids[line] { return existing }
            ids[line] = ids.count
            return ids.count - 1
        }
        let oldMiddle = old[prefix..<(old.count - suffix)].map(id)
        let newMiddle = new[prefix..<(new.count - suffix)].map(id)

        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in newMiddle.difference(from: oldMiddle) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var rows = (0..<prefix).map { Row(kind: .same, left: $0, right: $0) }
        var i = 0
        var j = 0
        while i < oldMiddle.count || j < newMiddle.count {
            if i < oldMiddle.count, j < newMiddle.count, !removed.contains(i), !inserted.contains(j) {
                rows.append(Row(kind: .same, left: prefix + i, right: prefix + j))
                i += 1
                j += 1
                continue
            }
            var leftRun: [Int] = []
            var rightRun: [Int] = []
            while i < oldMiddle.count, removed.contains(i) { leftRun.append(prefix + i); i += 1 }
            while j < newMiddle.count, inserted.contains(j) { rightRun.append(prefix + j); j += 1 }
            if leftRun.isEmpty && rightRun.isEmpty { break }  // impossible for a valid diff; never loop forever
            for k in 0..<max(leftRun.count, rightRun.count) {
                let left = k < leftRun.count ? leftRun[k] : nil
                let right = k < rightRun.count ? rightRun[k] : nil
                let kind: Kind = left != nil && right != nil ? .changed : (left != nil ? .removed : .added)
                rows.append(Row(kind: kind, left: left, right: right))
            }
        }
        rows += (0..<suffix).map { Row(kind: .same, left: old.count - suffix + $0, right: new.count - suffix + $0) }
        return rows
    }

    /// Indices of the first row of each run of differing rows.
    public static func hunkStarts(in rows: [Row]) -> [Int] {
        rows.indices.filter { rows[$0].kind != .same && ($0 == 0 || rows[$0 - 1].kind == .same) }
    }

    /// The differing middle part of two changed lines (after their common prefix and suffix),
    /// as a range in each line; nil if the lines are equal.
    public static func inlineChange(_ left: String, _ right: String) -> (left: NSRange, right: NSRange)? {
        let a = Array(left), b = Array(right)
        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < a.count - prefix, suffix < b.count - prefix,
              a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        guard prefix + suffix < max(a.count, b.count) else { return nil }

        func middle(of line: String) -> NSRange {
            let start = line.index(line.startIndex, offsetBy: prefix)
            let end = line.index(line.endIndex, offsetBy: -suffix)
            return NSRange(start..<end, in: line)
        }
        return (middle(of: left), middle(of: right))
    }
}
