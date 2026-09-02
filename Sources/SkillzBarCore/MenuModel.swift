import Foundation

public enum ScreenSource: String, Codable { case mouseScreen, mainScreen, fallbackDefault }

public struct MenuRow: Codable {
    public enum Reason: Codable, Equatable { case pinned, usage(count: Int), alphabetical }
    public let entry: SkillEntry
    public let reason: Reason
    public let shortcut: Int?     // 1...9
    public init(entry: SkillEntry, reason: Reason, shortcut: Int?) { self.entry = entry; self.reason = reason; self.shortcut = shortcut }
}

public struct MenuPlan: Codable {
    public let rows: [MenuRow]
    public let cut: [SkillEntry]          // visible but did not fit
    public let hiddenCount: Int
    public let capacity: Int              // rows actually allowed
    public let fitRows: Int?              // rows that fit the screen, nil if screen unknown
    public let maxQuickRows: Int
    public let screenHeight: Double?
    public let screenSource: ScreenSource
    public let rowHeight: Double
    public let fixedRows: Int
}

public enum MenuModel {
    public static let rowHeight: Double = 22
    public static let fallbackRows = 15

    /// Ordering: pinned (by usage desc, name), then normal by usage desc, name. Hidden excluded.
    public static func ordered(_ entries: [SkillEntry], config: Config, usage: Usage) -> [MenuRow] {
        func byUsage(_ a: SkillEntry, _ b: SkillEntry) -> Bool {
            let ca = usage.count(a.id), cb = usage.count(b.id)
            return ca != cb ? ca > cb : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        let visible = entries.filter { config.visibility(of: $0.id) != .hidden }
        let pinned = visible.filter { config.visibility(of: $0.id) == .pinned }.sorted(by: byUsage)
        let rest = visible.filter { config.visibility(of: $0.id) != .pinned }.sorted(by: byUsage)
        var rows: [MenuRow] = pinned.map { MenuRow(entry: $0, reason: .pinned, shortcut: nil) }
        rows += rest.map { e in
            let c = usage.count(e.id)
            return MenuRow(entry: e, reason: c > 0 ? .usage(count: c) : .alphabetical, shortcut: nil)
        }
        return rows
    }

    public static func plan(_ entries: [SkillEntry], config: Config, usage: Usage,
                            screenHeight: Double?, screenSource: ScreenSource, fixedRows: Int) -> MenuPlan {
        let all = ordered(entries, config: config, usage: usage)
        let fit: Int? = screenHeight.map { max(1, Int(($0 - Double(fixedRows) * rowHeight - 40) / rowHeight)) }
        let capacity = max(1, min(config.maxQuickRows, fit ?? fallbackRows))
        let shown = Array(all.prefix(capacity)).enumerated().map { i, r in
            MenuRow(entry: r.entry, reason: r.reason, shortcut: i < 9 ? i + 1 : nil)
        }
        return MenuPlan(rows: shown, cut: all.dropFirst(capacity).map(\.entry),
                        hiddenCount: entries.count - all.count, capacity: capacity, fitRows: fit,
                        maxQuickRows: config.maxQuickRows, screenHeight: screenHeight, screenSource: screenSource,
                        rowHeight: rowHeight, fixedRows: fixedRows)
    }
}
