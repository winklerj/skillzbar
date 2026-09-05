import Foundation

public struct Config: Codable, Equatable {
    public var roots: [ScanRoot]
    public var manualSkills: [String]
    public var excludeDirNames: [String]
    public var excludePathPrefixes: [String]
    public var visibility: [String: Visibility]   // key: SkillID.path; absent = normal
    public var groupByRoot: Bool
    public var maxQuickRows: Int
    public var hotkey: HotKeySpec
    public var launchAtLogin: Bool
    /// Where ⇧-select moves entries: skills as `<coldRoot>/<dir>`, commands as `<coldRoot>/commands/<rel>`.
    public var coldRoot: String

    public static let defaults = Config(
        roots: [ScanRoot("~/skillz"), ScanRoot("~/.claude/skills"), ScanRoot("~/.codex/skills"), ScanRoot("~/.agents/skills"),
                ScanRoot("~/.claude/commands", kind: .command), ScanRoot("~/.codex/prompts", kind: .command), ScanRoot("~/skillz/commands", kind: .command)],
        manualSkills: [],
        excludeDirNames: ["node_modules", ".git", ".tmp", ".build", ".system", "DerivedData"],
        excludePathPrefixes: ["~/Library", "~/.claude/plugins", "~/.codex/plugins", "~/.codex/.tmp"],
        visibility: [:],
        groupByRoot: false,
        maxQuickRows: 20,
        hotkey: .default,
        launchAtLogin: false,
        coldRoot: "~/skillz"
    )

    public init(roots: [ScanRoot], manualSkills: [String], excludeDirNames: [String], excludePathPrefixes: [String],
                visibility: [String: Visibility], groupByRoot: Bool, maxQuickRows: Int, hotkey: HotKeySpec, launchAtLogin: Bool, coldRoot: String = "~/skillz") {
        self.roots = roots; self.manualSkills = manualSkills; self.excludeDirNames = excludeDirNames
        self.excludePathPrefixes = excludePathPrefixes; self.visibility = visibility; self.groupByRoot = groupByRoot
        self.maxQuickRows = maxQuickRows; self.hotkey = hotkey; self.launchAtLogin = launchAtLogin; self.coldRoot = coldRoot
    }

    // Tolerant decoding: missing keys fall back to defaults so old config files keep working.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.defaults
        roots = try c.decodeIfPresent([ScanRoot].self, forKey: .roots) ?? d.roots
        manualSkills = try c.decodeIfPresent([String].self, forKey: .manualSkills) ?? d.manualSkills
        excludeDirNames = try c.decodeIfPresent([String].self, forKey: .excludeDirNames) ?? d.excludeDirNames
        excludePathPrefixes = try c.decodeIfPresent([String].self, forKey: .excludePathPrefixes) ?? d.excludePathPrefixes
        visibility = try c.decodeIfPresent([String: Visibility].self, forKey: .visibility) ?? d.visibility
        groupByRoot = try c.decodeIfPresent(Bool.self, forKey: .groupByRoot) ?? d.groupByRoot
        maxQuickRows = try c.decodeIfPresent(Int.self, forKey: .maxQuickRows) ?? d.maxQuickRows
        hotkey = try c.decodeIfPresent(HotKeySpec.self, forKey: .hotkey) ?? d.hotkey
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        coldRoot = try c.decodeIfPresent(String.self, forKey: .coldRoot) ?? d.coldRoot
    }

    public func visibility(of id: SkillID) -> Visibility? { visibility[id.path] }
    public mutating func setVisibility(_ v: Visibility?, for id: SkillID) {
        if let v { visibility[id.path] = v } else { visibility.removeValue(forKey: id.path) }
    }

    public static func load(path: String = AppPaths.configFile) throws -> Config {
        guard FileManager.default.fileExists(atPath: path) else { return .defaults }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(Config.self, from: data)
    }
    public func save(path: String = AppPaths.configFile) throws {
        AppPaths.ensureDirs()
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
