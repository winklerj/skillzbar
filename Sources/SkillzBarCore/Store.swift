import Foundation

public struct StatusReport: Codable {
    public var version: String
    public var pid: Int32
    public var configPath: String
    public var logPath: String
    public var cachePath: String
    public var ctlSocket: String
    public var config: Config
    public var entryCount: Int
    public var lastScan: ScanReport?
    public var stalePinnedOrHidden: [String]
    public var recentErrors: [LogRecord]
}

/// Facade over config, cache, usage, and scan results. Thread-safe via a serial queue.
public final class SkillStore {
    private let q = DispatchQueue(label: "skillzbar.store")
    private let fs: SkillFileSystem
    private var _config: Config
    private var cache: HashCache
    private var _usage: Usage
    private var _entries: [SkillEntry] = []
    private var _lastScan: ScanReport?
    public var onChange: (() -> Void)?

    public init(fs: SkillFileSystem = DirectFileSystem()) {
        self.fs = fs
        do { _config = try Config.load() } catch { Log.shared.error("config.load", error, paths: [AppPaths.configFile]); _config = .defaults }
        cache = HashCache.load()
        _usage = Usage.load()
    }

    public var config: Config { q.sync { _config } }
    public var usage: Usage { q.sync { _usage } }
    public var entries: [SkillEntry] { q.sync { _entries } }
    public var lastScan: ScanReport? { q.sync { _lastScan } }

    @discardableResult
    public func rescan() -> ScanReport {
        let report: ScanReport = q.sync {
            // Another process (CLI, agent, editor) may have changed config.json since we loaded; a stale
            // in-memory copy would both miss its roots and clobber it on the next Settings save.
            do { _config = try Config.load() } catch { Log.shared.error("config.load", error, paths: [AppPaths.configFile]) }
            let r = Scanner(fs: fs).scan(config: _config, cache: &cache)
            _entries = r.entries; _lastScan = r
            do { try cache.save() } catch { Log.shared.error("cache.save", error, paths: [AppPaths.cacheFile]) }
            for e in r.errors { Log.shared.error("scan", e) }
            Log.shared.info("scan", "\(r.entries.count) skills from \(r.candidates) candidates in \(String(format: "%.1f", r.durationMs))ms; hashed \(r.filesHashed)")
            return r
        }
        onChange?()
        return report
    }

    public func update(_ mutate: (inout Config) -> Void) {
        q.sync {
            mutate(&_config)
            do { try _config.save() } catch { Log.shared.error("config.save", error, paths: [AppPaths.configFile]) }
        }
        onChange?()
    }

    public func recordCopy(_ id: SkillID, kind: CopyKind) {
        q.sync {
            _usage = Usage.load()          // another process (CLI) may have written since we loaded
            _usage.record(id)
            do { try _usage.save() } catch { Log.shared.error("usage.save", error, paths: [AppPaths.usageFile]) }
            Log.shared.info("copy", kind.rawValue, paths: [id.path])
        }
        onChange?()
    }

    public func entry(_ id: SkillID) -> SkillEntry? { q.sync { _entries.first { $0.id == id } } }

    /// Resolve a user-supplied name or path to exactly one entry.
    public func resolve(_ query: String) throws -> SkillEntry {
        let es = entries
        let expanded = AppPaths.expand(query)
        if let e = es.first(where: { $0.id.path == expanded || $0.id.path == (try? fs.realpath(expanded)) }) { return e }
        let byName = es.filter { $0.name.caseInsensitiveCompare(query) == .orderedSame }
        if byName.count == 1 { return byName[0] }
        if byName.count > 1 { throw SkillzError.ambiguous(query: query, candidates: byName.map(\.id.path)) }
        let ranked = Fuzzy.rank(query, entries: es)
        guard let top = ranked.first else { throw SkillzError.notFound(query: query) }
        if ranked.count > 1, ranked[1].score >= top.score - 5 {
            throw SkillzError.ambiguous(query: query, candidates: ranked.prefix(5).map(\.entry.name))
        }
        return top.entry
    }

    /// Option-click / `cat` format: bare path line, blank line, file contents.
    public func contentsPayload(_ e: SkillEntry) throws -> String {
        let text = String(decoding: try fs.read(e.id.path), as: UTF8.self)
        return e.id.path + "\n\n" + text
    }

    public func status() -> StatusReport {
        let c = config, es = entries
        let known = Set(es.map(\.id.path))
        return StatusReport(version: skillzBarVersion, pid: getpid(), configPath: AppPaths.configFile, logPath: AppPaths.logFile,
                            cachePath: AppPaths.cacheFile, ctlSocket: AppPaths.ctlSocket, config: c, entryCount: es.count,
                            lastScan: lastScan, stalePinnedOrHidden: c.visibility.keys.filter { !known.contains($0) }.sorted(),
                            recentErrors: Log.shared.tail(20, level: "error"))
    }
}

public enum JSON {
    public static func string<T: Encodable>(_ v: T, pretty: Bool = true) -> String {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return (try? e.encode(v)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
