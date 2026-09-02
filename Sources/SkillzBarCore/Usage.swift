import Foundation

public struct Usage: Codable {
    public var stats: [String: UsageStat] = [:]   // key: SkillID.path
    public init() {}
    public static func load(path: String = AppPaths.usageFile) -> Usage {
        guard let d = FileManager.default.contents(atPath: path) else { return Usage() }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(Usage.self, from: d)) ?? Usage()
    }
    public func save(path: String = AppPaths.usageFile) throws {
        AppPaths.ensureDirs()
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try enc.encode(self).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    public mutating func record(_ id: SkillID, at date: Date = Date()) {
        var s = stats[id.path] ?? UsageStat(count: 0, lastCopiedAt: date)
        s.count += 1; s.lastCopiedAt = date
        stats[id.path] = s
    }
    public func count(_ id: SkillID) -> Int { stats[id.path]?.count ?? 0 }
}
