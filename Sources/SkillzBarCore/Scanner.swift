import Foundation

public struct Candidate: Hashable {
    public let path: String        // resolved absolute path to SKILL.md
    public let size: Int64
    public let modifiedNs: Int64
    public let inode: UInt64
    public let device: UInt32
    public let source: SkillSource
}

public struct ScanReport: Codable {
    public struct Skipped: Codable { public let path: String; public let reason: String }
    public struct Merged: Codable { public let kept: String; public let dropped: String; public let reason: String }
    public var startedAt: Date
    public var durationMs: Double
    public var rootsScanned: [String]
    public var rootsMissing: [String]
    public var directoriesVisited: Int
    public var candidates: Int
    public var filesHashed: Int
    public var entries: [SkillEntry]
    public var merged: [Merged]
    public var skipped: [Skipped]
    public var errors: [String]
}

public struct Scanner {
    public var fs: SkillFileSystem
    public var maxDepth = 12
    public init(fs: SkillFileSystem = DirectFileSystem()) { self.fs = fs }

    public func scan(config: Config, cache: inout HashCache) -> ScanReport {
        let t0 = DispatchTime.now()
        var report = ScanReport(startedAt: Date(), durationMs: 0, rootsScanned: [], rootsMissing: [], directoriesVisited: 0,
                                candidates: 0, filesHashed: 0, entries: [], merged: [], skipped: [], errors: [])
        let excludeNames = Set(config.excludeDirNames)
        let excludePrefixes = config.excludePathPrefixes.map { AppPaths.expand($0) }

        // Walk roots concurrently; each root gets its own accumulator.
        let roots = config.roots.map { AppPaths.expand($0) }
        var perRoot = [RootResult](repeating: RootResult(), count: roots.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: roots.count) { i in
            let r = walkRoot(roots[i], excludeNames: excludeNames, excludePrefixes: excludePrefixes)
            lock.lock(); perRoot[i] = r; lock.unlock()
        }
        var candidates: [Candidate] = []
        for (i, r) in perRoot.enumerated() {
            if r.missing { report.rootsMissing.append(roots[i]) } else { report.rootsScanned.append(roots[i]) }
            report.directoriesVisited += r.dirs
            report.errors += r.errors
            report.skipped += r.skipped
            candidates += r.candidates
        }
        for m in config.manualSkills {
            let p = AppPaths.expand(m)
            do {
                let real = try fs.realpath(p)
                let st = try fs.stat(real)
                guard st.kind == .file else { report.skipped.append(.init(path: p, reason: "manual entry is not a regular file")); continue }
                candidates.append(Candidate(path: real, size: st.size, modifiedNs: st.modifiedNs, inode: st.inode, device: st.device, source: .manual))
            } catch { report.skipped.append(.init(path: p, reason: "manual entry unreadable: \(error)")) }
        }
        report.candidates = candidates.count

        let dedup = Self.dedup(candidates, rootOrder: roots, cache: &cache, fs: fs)
        report.entries = dedup.entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        report.merged = dedup.merged
        report.filesHashed = dedup.hashed
        report.errors += dedup.errors
        report.durationMs = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6
        return report
    }

    private struct RootResult {
        var missing = false; var dirs = 0; var candidates: [Candidate] = []; var errors: [String] = []; var skipped: [ScanReport.Skipped] = []
    }

    private func walkRoot(_ root: String, excludeNames: Set<String>, excludePrefixes: [String]) -> RootResult {
        var r = RootResult()
        guard let real = try? fs.realpath(root), let st = try? fs.stat(real), st.kind == .directory else { r.missing = true; return r }
        var visited: Set<UInt64> = [st.inode]     // cycle protection for symlinked directories
        var stack: [(path: String, depth: Int)] = [(real, 0)]
        let source = SkillSource.discovered(root: root)
        while let (dir, depth) = stack.popLast() {
            r.dirs += 1
            let entries: [DirEntry]
            do { entries = try fs.list(directory: dir) } catch { r.errors.append("\(error)"); continue }
            for e in entries {
                let full = dir + "/" + e.name
                switch e.kind {
                case .file where e.name == skillFileName:
                    r.candidates.append(Candidate(path: full, size: e.size, modifiedNs: e.modifiedNs, inode: e.inode, device: e.device, source: source))
                case .directory:
                    if excludeNames.contains(e.name) { r.skipped.append(.init(path: full, reason: "excluded dir name")); continue }
                    if excludePrefixes.contains(where: { full.hasPrefix($0) }) { r.skipped.append(.init(path: full, reason: "excluded path prefix")); continue }
                    if depth + 1 > maxDepth { r.skipped.append(.init(path: full, reason: "max depth")); continue }
                    if !visited.insert(e.inode).inserted { continue }
                    stack.append((full, depth + 1))
                case .symlink:
                    guard let target = try? fs.realpath(full), let ts = try? fs.stat(target) else { continue }
                    if excludePrefixes.contains(where: { target.hasPrefix($0) }) { r.skipped.append(.init(path: full, reason: "symlink target excluded")); continue }
                    if ts.kind == .file, e.name == skillFileName {
                        r.candidates.append(Candidate(path: target, size: ts.size, modifiedNs: ts.modifiedNs, inode: ts.inode, device: ts.device, source: source))
                    } else if ts.kind == .directory, depth + 1 <= maxDepth, visited.insert(ts.inode).inserted, !excludeNames.contains(e.name) {
                        stack.append((target, depth + 1))
                    }
                default: continue
                }
            }
        }
        return r
    }

    /// Cheapest-first dedup: same (dev, inode) → same file; different size → distinct; equal size → hash.
    static func dedup(_ cands: [Candidate], rootOrder: [String], cache: inout HashCache, fs: SkillFileSystem)
        -> (entries: [SkillEntry], merged: [ScanReport.Merged], hashed: Int, errors: [String]) {
        func rank(_ c: Candidate) -> Int {          // manual beats discovered; earlier root beats later
            switch c.source { case .manual: return -1; case .discovered(let r): return rootOrder.firstIndex(of: AppPaths.expand(r)) ?? Int.max }
        }
        // Deterministic preference order
        let sorted = cands.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            return ra != rb ? ra < rb : a.path < b.path
        }
        var merged: [ScanReport.Merged] = []
        var errors: [String] = []

        // Stage 1: identical file (hard link / same target)
        var byInode: [String: Candidate] = [:]; var inodeDups: [String: [String]] = [:]
        var order: [String] = []
        for c in sorted {
            let k = "\(c.device):\(c.inode)"
            if let kept = byInode[k] {
                if kept.path != c.path { merged.append(.init(kept: kept.path, dropped: c.path, reason: "same inode")); inodeDups[k, default: []].append(c.path) }
            } else { byInode[k] = c; order.append(k) }
        }
        let unique = order.map { byInode[$0]! }

        // Stage 2: size buckets; Stage 3: hash only buckets with >1 member
        var bySize: [Int64: [Candidate]] = [:]
        for c in unique { bySize[c.size, default: []].append(c) }
        var hashed = 0
        var hashes: [String: String] = [:]
        var kept: [Candidate] = []
        var dups: [String: [String]] = [:]   // kept path -> dropped paths
        for c in unique {
            let bucket = bySize[c.size]!
            if bucket.count == 1 { kept.append(c); continue }
            do {
                let h = try cache.hash(path: c.path, size: c.size, modifiedNs: c.modifiedNs, inode: c.inode, fs: fs)
                hashed += 1
                if let first = bucket.first(where: { hashes["\($0.device):\($0.inode)"] == h }), first.path != c.path {
                    merged.append(.init(kept: first.path, dropped: c.path, reason: "same content"))
                    dups[first.path, default: []].append(c.path)
                } else {
                    hashes["\(c.device):\(c.inode)"] = h
                    kept.append(c)
                }
            } catch { errors.append("hash \(c.path): \(error)"); kept.append(c) }
        }
        let entries = kept.map { c in
            SkillEntry(id: SkillID(path: c.path), name: (c.path as NSString).deletingLastPathComponent.split(separator: "/").last.map(String.init) ?? c.path,
                       byteSize: c.size, modifiedNs: c.modifiedNs, contentHash: hashes["\(c.device):\(c.inode)"], source: c.source,
                       duplicatePaths: (inodeDups["\(c.device):\(c.inode)"] ?? []) + (dups[c.path] ?? []))
        }
        return (entries, merged, hashed, errors)
    }
}
