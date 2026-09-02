import Foundation
import CryptoKit

/// Stat-keyed hash cache (git-index technique): rehash only when size/mtime/inode changed.
public struct HashCache: Codable {
    public struct Entry: Codable, Equatable {
        public var size: Int64; public var modifiedNs: Int64; public var inode: UInt64; public var sha256: String
    }
    public var entries: [String: Entry] = [:]
    public init() {}

    public static func load(path: String = AppPaths.cacheFile) -> HashCache {
        guard let d = FileManager.default.contents(atPath: path), let c = try? JSONDecoder().decode(HashCache.self, from: d) else { return HashCache() }
        return c
    }
    public func save(path: String = AppPaths.cacheFile) throws {
        AppPaths.ensureDirs()
        try JSONEncoder().encode(self).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    /// Returns cached hash if stat matches; otherwise reads + hashes and updates the cache.
    public mutating func hash(path: String, size: Int64, modifiedNs: Int64, inode: UInt64, fs: SkillFileSystem) throws -> String {
        if let e = entries[path], e.size == size, e.modifiedNs == modifiedNs, e.inode == inode { return e.sha256 }
        let data = try fs.read(path)
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        entries[path] = Entry(size: size, modifiedNs: modifiedNs, inode: inode, sha256: hex)
        return hex
    }
}
