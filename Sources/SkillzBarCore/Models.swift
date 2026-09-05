import Foundation

public let skillzBarVersion = "0.1.0"
public let skillFileName = "SKILL.md"

/// What a root (or an entry) holds. A skills root yields one entry per `SKILL.md` (name = parent
/// directory). A commands root yields one entry per `*.md` at any depth (name = `sub:dir:stem`,
/// mirroring `/ns:command` slash-command namespacing). The kind is fixed per root so a skill's own
/// `README.md` / `references/*.md` can never be mistaken for entries.
public enum ContentKind: String, Codable, CaseIterable {
    case skill, command
}

public struct ScanRoot: Hashable, Codable {
    public var path: String
    public var kind: ContentKind
    public init(_ path: String, kind: ContentKind = .skill) { self.path = path; self.kind = kind }
    /// Tolerant: a bare string (pre-typed-roots config files) is a skills root.
    public init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) { path = s; kind = .skill; return }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        kind = try c.decodeIfPresent(ContentKind.self, forKey: .kind) ?? .skill
    }
}

/// Stable identity: the canonical (symlink-resolved) absolute path of the preferred SKILL.md (or command .md).
public struct SkillID: Hashable, Codable, Comparable, CustomStringConvertible {
    public let path: String
    public init(path: String) { self.path = path }
    public init(from decoder: Decoder) throws { path = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(path) }
    public static func < (a: SkillID, b: SkillID) -> Bool { a.path < b.path }
    public var description: String { path }
    /// Skill directory: relative references in SKILL.md resolve from here.
    public var directory: String { (path as NSString).deletingLastPathComponent }
}

public enum SkillSource: Hashable, Codable {
    case discovered(root: String)
    case manual
    public var rootLabel: String {
        switch self {
        case .discovered(let root): return root
        case .manual: return "manual"
        }
    }
}

public struct SkillEntry: Hashable, Codable {
    public let id: SkillID
    public let name: String
    public let kind: ContentKind
    public let byteSize: Int64
    public let modifiedNs: Int64
    /// SHA-256 hex. Only computed when needed for dedup; nil means "not needed, unique by size".
    public let contentHash: String?
    public let source: SkillSource
    public let duplicatePaths: [String]
    public init(id: SkillID, name: String, kind: ContentKind = .skill, byteSize: Int64, modifiedNs: Int64, contentHash: String?, source: SkillSource, duplicatePaths: [String]) {
        self.id = id; self.name = name; self.kind = kind; self.byteSize = byteSize; self.modifiedNs = modifiedNs
        self.contentHash = contentHash; self.source = source; self.duplicatePaths = duplicatePaths
    }
}

/// Absence from Config.visibility means .normal.
public enum Visibility: String, Codable { case pinned, hidden }

public enum CopyKind: String, Codable { case path, contents }

public struct MoveResult: Codable {
    public let name: String
    public let kind: ContentKind
    public let from: String
    public let to: String
    /// New identity after the move (SKILL.md inside the moved directory, or the moved command file).
    public let id: SkillID
    /// Same-content copies in other roots that were NOT moved (dedup kept only `from`); they stay hot.
    public let duplicatePaths: [String]
}

public struct UsageStat: Codable, Equatable {
    public var count: Int
    public var lastCopiedAt: Date
    public init(count: Int, lastCopiedAt: Date) { self.count = count; self.lastCopiedAt = lastCopiedAt }
}

public struct HotKeySpec: Codable, Equatable {
    public var key: String        // single character, e.g. "p"
    public var command: Bool
    public var option: Bool
    public var control: Bool
    public var shift: Bool
    public init(key: String, command: Bool, option: Bool, control: Bool, shift: Bool) {
        self.key = key; self.command = command; self.option = option; self.control = control; self.shift = shift
    }
    public static let `default` = HotKeySpec(key: "p", command: true, option: true, control: false, shift: false)
    public var display: String {
        var s = ""
        if control { s += "⌃" }; if option { s += "⌥" }; if shift { s += "⇧" }; if command { s += "⌘" }
        return s + key.uppercased()
    }
}

public enum SkillzError: Error, CustomStringConvertible {
    case posix(op: String, path: String, errno: Int32)
    case notFound(query: String)
    case ambiguous(query: String, candidates: [String])
    case invalidConfig(String)
    case ctl(String)
    case moveRefused(path: String, reason: String)
    public var description: String {
        switch self {
        case .posix(let op, let path, let e): return "\(op) failed for \(path): \(String(cString: strerror(e))) (errno \(e))"
        case .notFound(let q): return "no skill matches '\(q)'"
        case .ambiguous(let q, let c): return "'\(q)' is ambiguous: \(c.joined(separator: ", "))"
        case .invalidConfig(let m): return "invalid config: \(m)"
        case .ctl(let m): return "ctl: \(m)"
        case .moveRefused(let p, let r): return "not moving \(p): \(r)"
        }
    }
}
