import Foundation

public enum Fuzzy {
    /// Optimal-alignment subsequence match (fzf-v2 style DP, not greedy): maximizes
    /// word-start and adjacency bonuses over all alignments. nil = no match.
    public static func score(_ query: String, in text: String) -> Int? {
        if query.isEmpty { return 0 }
        let q = Array(query.lowercased()), t = Array(text.lowercased())
        let m = q.count, n = t.count
        if m > n { return nil }
        let none = Int.min / 4
        func bonus(_ j: Int) -> Int { (j == 0 || !(t[j-1].isLetter || t[j-1].isNumber)) ? 4 : 0 }
        // prev[j] = best score with q[0..<i] matched, last match at t[j]
        var prev = [Int](repeating: none, count: n)
        for j in 0..<n where t[j] == q[0] { prev[j] = 1 + bonus(j) }
        for i in 1..<m {
            var cur = [Int](repeating: none, count: n)
            var bestBefore = none            // max prev[k] for k < j-1 (non-adjacent)
            for j in 1..<n {
                if j >= 2 { bestBefore = max(bestBefore, prev[j-2]) }
                guard t[j] == q[i] else { continue }
                let adjacent = prev[j-1] == none ? none : prev[j-1] + 3
                let best = max(adjacent, bestBefore)
                if best != none { cur[j] = best + 1 + bonus(j) }
            }
            prev = cur
        }
        guard var score = prev.max(), score != none else { return nil }
        let tl = text.lowercased(), ql = query.lowercased()
        if tl == ql { score += 50 } else if tl.hasPrefix(ql) { score += 10 }
        return score - (n - m) / 8
    }

    public static func rank(_ query: String, entries: [SkillEntry]) -> [(entry: SkillEntry, score: Int)] {
        entries.compactMap { e in
            let byName = score(query, in: e.name)
            let byPath = score(query, in: AppPaths.abbreviate(e.id.path)).map { $0 - 6 }
            guard let best = [byName, byPath].compactMap({ $0 }).max() else { return nil }
            return (e, best)
        }.sorted { $0.score != $1.score ? $0.score > $1.score : $0.entry.name < $1.entry.name }
    }
}
