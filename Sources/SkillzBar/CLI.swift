import AppKit
import SkillzBarCore

enum CLI {
    static let help = """
    skillzbar — menu bar manager for cold agent skills (\(skillzBarVersion))

    USAGE: skillzbar <command> [args]

    Skills (no running app needed):
      list [--json] [--all]        known skills (hidden included with --all)
      find <query>                 fuzzy match, JSON candidates with scores
      path <name|path>             print absolute path of SKILL.md
      cat <name|path>              print "<path>\\n\\n<contents>" (same as Option-click)
      copy <name|path> [--contents] put path (or contents payload) on the clipboard
      scan [--json]                rescan roots now; report entries, merges, skips
      status [--json]              version, paths, config, last scan, stale pins, recent errors
      log [--tail N] [--errors]    JSON-lines log records
      diagnostics                  status + last 50 log lines (what "Copy Diagnostics" copies)

    Running app (via ctl socket):
      ctl ping|status|list|menu|panel|rescan|errors|show|hide|open-menu|close-menu|ui
      ctl key "dia @down @return"     synthesize keys into the shown panel (@down @up @return @opt-return @esc)
      ctl copy <name|path> [--contents]
    """

    static func run(_ args: [String]) -> Int32 {
        let cmd = args[0]
        let rest = Array(args.dropFirst())
        let json = rest.contains("--json")
        let store = SkillStore()
        func out(_ s: String) { print(s) }
        func fail(_ s: String) -> Int32 { FileHandle.standardError.write(Data(("error: " + s + "\n").utf8)); return 1 }
        func positional() -> String? { rest.first { !$0.hasPrefix("--") } }

        switch cmd {
        case "help", "--help", "-h": out(help); return 0
        case "version", "--version": out(skillzBarVersion); return 0

        case "scan":
            let r = store.rescan()
            if json { out(JSON.string(r)) } else {
                out("\(r.entries.count) skills, \(r.candidates) candidates, \(r.merged.count) merged, \(r.skipped.count) skipped, \(r.directoriesVisited) dirs, \(String(format: "%.1f", r.durationMs)) ms")
                for e in r.entries { out("  \(e.name)  \(AppPaths.abbreviate(e.id.path))  \(e.byteSize)B") }
                for m in r.rootsMissing { out("  missing root: \(m)") }
                for e in r.errors { out("  ERROR \(e)") }
            }
            return 0

        case "list":
            store.rescan()
            let c = store.config
            var es = store.entries
            if !rest.contains("--all") { es = es.filter { c.visibility(of: $0.id) != .hidden } }
            if json { out(JSON.string(es)) } else { for e in es { out("\(e.name)\t\(e.id.path)\t\(e.byteSize)") } }
            return 0

        case "find":
            guard let q = positional() else { return fail("find needs a query") }
            store.rescan()
            struct Hit: Codable { let name: String; let path: String; let score: Int }
            let hits = Fuzzy.rank(q, entries: store.entries).prefix(10).map { Hit(name: $0.entry.name, path: $0.entry.id.path, score: $0.score) }
            out(JSON.string(Array(hits)))
            return hits.isEmpty ? 2 : 0

        case "path", "cat", "copy":
            guard let q = positional() else { return fail("\(cmd) needs a skill name or path") }
            store.rescan()
            do {
                let e = try store.resolve(q)
                switch cmd {
                case "path": out(e.id.path)
                case "cat": out(try store.contentsPayload(e)); store.recordCopy(e.id, kind: .contents)
                default:
                    let contents = rest.contains("--contents")
                    Clipboard.set(contents ? try store.contentsPayload(e) : e.id.path)
                    store.recordCopy(e.id, kind: contents ? .contents : .path)
                    out("copied \(contents ? "contents" : "path") of \(e.name)")
                }
                return 0
            } catch { return fail("\(error)") }

        case "status":
            store.rescan()
            let s = store.status()
            if json { out(JSON.string(s)) } else {
                out("SkillzBar \(s.version)  entries=\(s.entryCount)  config=\(s.configPath)")
                out("log=\(s.logPath)")
                if let l = s.lastScan { out("last scan: \(l.entries.count) entries, \(String(format: "%.1f", l.durationMs))ms, roots missing: \(l.rootsMissing)") }
                if !s.stalePinnedOrHidden.isEmpty { out("stale pinned/hidden: \(s.stalePinnedOrHidden)") }
                for e in s.recentErrors.suffix(5) { out("ERR \(e.ts) \(e.op): \(e.msg) [\(e.file):\(e.line)]") }
            }
            return 0

        case "log":
            var n = 50
            if let i = rest.firstIndex(of: "--tail"), i + 1 < rest.count, let v = Int(rest[i+1]) { n = v }
            for r in Log.shared.tail(n, level: rest.contains("--errors") ? "error" : nil) { out(JSON.string(r, pretty: false)) }
            return 0

        case "diagnostics":
            store.rescan()
            out(Diagnostics.text(store: store))
            return 0

        case "ctl":
            guard let sub = rest.first else { return fail("ctl needs a subcommand") }
            let arg = rest.dropFirst().first { !$0.hasPrefix("--") }
            do {
                let resp = try CtlClient.send(CtlRequest(command: sub, arg: arg, contents: rest.contains("--contents"), all: rest.contains("--all")))
                out(resp.trimmingCharacters(in: .whitespacesAndNewlines))
                return resp.contains("\"ok\":false") ? 1 : 0
            } catch { return fail("\(error)") }

        default:
            return fail("unknown command '\(cmd)'\n\n\(help)")
        }
    }
}

enum Diagnostics {
    static func text(store: SkillStore) -> String {
        var s = "# SkillzBar diagnostics\n\n## status\n"
        s += JSON.string(store.status())
        s += "\n\n## last 50 log lines\n"
        s += Log.shared.tail(50).map { JSON.string($0, pretty: false) }.joined(separator: "\n")
        s += "\n\n## environment\nmacOS \(ProcessInfo.processInfo.operatingSystemVersionString)\nexecutable \(Bundle.main.executablePath ?? "?")\nbundle \(Bundle.main.bundleIdentifier ?? "none (bare executable)")\n"
        return s
    }
}
