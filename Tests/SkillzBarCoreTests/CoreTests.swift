import XCTest
@testable import SkillzBarCore

final class CoreTests: XCTestCase {
    var tmp: String!
    override func setUpWithError() throws {
        tmp = NSTemporaryDirectory() + "skillzbar-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        tmp = try DirectFileSystem().realpath(tmp)   // /var → /private/var; ids are canonical paths
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(atPath: tmp) }

    func mk(_ rel: String, _ content: String) throws {
        let p = tmp + "/" + rel
        try FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try content.write(toFile: p, atomically: true, encoding: .utf8)
    }
    func config(roots: [String], commandRoots: [String] = [], manual: [String] = []) -> Config {
        var c = Config.defaults
        c.roots = roots.map { ScanRoot($0) } + commandRoots.map { ScanRoot($0, kind: .command) }
        c.manualSkills = manual; c.excludePathPrefixes = []; return c
    }

    func testCommandsRootNamesByStemAndSkillRootIgnoresOtherMd() throws {
        try mk("skills/s/SKILL.md", "s"); try mk("skills/s/README.md", "readme"); try mk("skills/s/references/r.md", "ref")
        try mk("cmds/top.md", "t"); try mk("cmds/cl/implement_plan.md", "ip"); try mk("cmds/cl/notes.txt", "n")
        try mk("m/single.md", "manual command")
        var cache = HashCache()
        let r = Scanner().scan(config: config(roots: [tmp + "/skills"], commandRoots: [tmp + "/cmds"], manual: [tmp + "/m/single.md"]), cache: &cache)
        let byName = Dictionary(uniqueKeysWithValues: r.entries.map { ($0.name, $0) })
        XCTAssertEqual(byName.keys.sorted(), ["cl:implement_plan", "s", "single", "top"], "\(r.entries)")
        XCTAssertEqual(byName["s"]?.kind, .skill)
        XCTAssertEqual(byName["cl:implement_plan"]?.kind, .command)
        XCTAssertEqual(byName["cl:implement_plan"]?.id.path, tmp + "/cmds/cl/implement_plan.md")
        XCTAssertEqual(byName["single"]?.kind, .command); XCTAssertEqual(byName["single"]?.source, .manual)
    }

    func testBulkListingMatchesFileManager() throws {
        try mk("a/SKILL.md", "A"); try mk("b/notes.txt", "n"); try mk("c/d/SKILL.md", "CD")
        let fs = DirectFileSystem()
        let names = Set(try fs.list(directory: tmp).map(\.name))
        XCTAssertEqual(names, ["a", "b", "c"])
        let a = try fs.list(directory: tmp + "/a").first!
        XCTAssertEqual(a.kind, .file); XCTAssertEqual(a.size, 1); XCTAssertEqual(a.name, "SKILL.md")
        XCTAssertGreaterThan(a.modifiedNs, 0); XCTAssertGreaterThan(a.inode, 0)
    }

    func testScanFindsPrunesAndDedups() throws {
        try mk("one/SKILL.md", "same content")
        try mk("two/SKILL.md", "same content")            // content dup → merged
        try mk("three/SKILL.md", "different")
        try mk("node_modules/x/SKILL.md", "excluded")      // pruned dir
        try mk("deep/a/b/c/SKILL.md", "deep")
        try FileManager.default.createSymbolicLink(atPath: tmp + "/link", withDestinationPath: tmp + "/three")  // symlinked dir → same inode as three
        var cache = HashCache()
        let r = Scanner().scan(config: config(roots: [tmp]), cache: &cache)
        let names = r.entries.map(\.name).sorted()
        XCTAssertEqual(names, ["c", "one", "three"], "\(r.entries)")
        XCTAssertEqual(r.merged.count, 1); XCTAssertEqual(r.merged[0].reason, "same content")
        XCTAssertEqual(r.filesHashed, 2, "only the equal-size bucket gets hashed")
        XCTAssertTrue(r.skipped.contains { $0.reason == "excluded dir name" })
        XCTAssertEqual(r.entries.first { $0.name == "one" }?.duplicatePaths, [tmp + "/two/SKILL.md"])
        // second scan: cache hit, no rehash
        var r2 = Scanner().scan(config: config(roots: [tmp]), cache: &cache)
        XCTAssertEqual(r2.entries.count, 3)
        XCTAssertEqual(cache.entries.count, 2)
        r2.entries = []
    }

    func testManualBeatsDiscoveredAndRootOrder() throws {
        try mk("r1/s/SKILL.md", "x"); try mk("r2/s/SKILL.md", "x"); try mk("m/SKILL.md", "x")
        var cache = HashCache()
        let r = Scanner().scan(config: config(roots: [tmp + "/r2", tmp + "/r1"], manual: [tmp + "/m/SKILL.md"]), cache: &cache)
        XCTAssertEqual(r.entries.count, 1)
        XCTAssertEqual(r.entries[0].id.path, tmp + "/m/SKILL.md")
        XCTAssertEqual(r.entries[0].source, .manual)
        XCTAssertEqual(Set(r.entries[0].duplicatePaths), [tmp + "/r2/s/SKILL.md", tmp + "/r1/s/SKILL.md"])
    }

    func testMenuPlanOrderingAndCapacity() {
        func e(_ n: String) -> SkillEntry { SkillEntry(id: SkillID(path: "/x/\(n)/SKILL.md"), name: n, byteSize: 1, modifiedNs: 0, contentHash: nil, source: .manual, duplicatePaths: []) }
        let entries = ["a", "b", "c", "d", "e"].map(e)
        var c = Config.defaults; c.maxQuickRows = 3
        c.setVisibility(.pinned, for: SkillID(path: "/x/e/SKILL.md"))
        c.setVisibility(.hidden, for: SkillID(path: "/x/a/SKILL.md"))
        var u = Usage(); u.record(SkillID(path: "/x/d/SKILL.md")); u.record(SkillID(path: "/x/d/SKILL.md")); u.record(SkillID(path: "/x/c/SKILL.md"))
        let p = MenuModel.plan(entries, config: c, usage: u, screenHeight: 900, screenSource: .mainScreen, fixedRows: 6)
        XCTAssertEqual(p.rows.map(\.entry.name), ["e", "d", "c"])
        XCTAssertEqual(p.rows[0].reason, .pinned); XCTAssertEqual(p.rows[1].reason, .usage(count: 2))
        XCTAssertEqual(p.rows.map(\.shortcut), [1, 2, 3])
        XCTAssertEqual(p.cut.map(\.name), ["b"]); XCTAssertEqual(p.hiddenCount, 1); XCTAssertEqual(p.capacity, 3)
        let small = MenuModel.plan(entries, config: Config.defaults, usage: Usage(), screenHeight: 200, screenSource: .mainScreen, fixedRows: 6)
        XCTAssertEqual(small.fitRows, 1); XCTAssertEqual(small.capacity, 1)
        let unknown = MenuModel.plan(entries, config: Config.defaults, usage: Usage(), screenHeight: nil, screenSource: .fallbackDefault, fixedRows: 6)
        XCTAssertEqual(unknown.capacity, 15, "min(fallback 15, maxQuickRows 20)"); XCTAssertEqual(unknown.rows.count, 5); XCTAssertNil(unknown.fitRows)
    }

    func testFuzzy() {
        XCTAssertNotNil(Fuzzy.score("dry", in: "diary"))
        XCTAssertNil(Fuzzy.score("xyz", in: "diary"))
        XCTAssertGreaterThan(Fuzzy.score("diary", in: "diary")!, Fuzzy.score("diary", in: "my-diary-notes")!)
        XCTAssertGreaterThan(Fuzzy.score("rr", in: "research-ranker")!, Fuzzy.score("rr", in: "carrier")!)
    }

    func testConfigRoundTripAndTolerantDecode() throws {
        let p = tmp + "/config.json"
        var c = Config.defaults; c.roots = [ScanRoot("~/skillz"), ScanRoot("~/c", kind: .command)]; c.setVisibility(.pinned, for: SkillID(path: "/p/SKILL.md")); c.coldRoot = "~/cold"
        try c.save(path: p)
        XCTAssertEqual(try Config.load(path: p), c)
        // Pre-typed-roots config: bare strings are skills roots; objects may omit kind.
        try #"{"roots":["/only",{"path":"/c","kind":"command"},{"path":"/k"}]}"#.write(toFile: p, atomically: true, encoding: .utf8)
        let partial = try Config.load(path: p)
        XCTAssertEqual(partial.roots, [ScanRoot("/only"), ScanRoot("/c", kind: .command), ScanRoot("/k")]); XCTAssertEqual(partial.hotkey, .default); XCTAssertEqual(partial.coldRoot, "~/skillz")
    }
    // MARK: move to cold root

    func scanned(_ c: Config) -> [String: SkillEntry] {
        var cache = HashCache()
        return Dictionary(uniqueKeysWithValues: Scanner().scan(config: c, cache: &cache).entries.map { ($0.name, $0) })
    }

    func testMoveSkillMovesWholeDirectoryAndMigratesKeys() throws {
        try mk("hot/diary/SKILL.md", "d"); try mk("hot/diary/references/r.md", "ref")
        var c = config(roots: [tmp + "/hot"]); c.coldRoot = tmp + "/cold"
        let e = try XCTUnwrap(scanned(c)["diary"])
        c.setVisibility(.pinned, for: e.id)
        var u = Usage(); u.record(e.id)
        let r = try Mover.move(e, config: &c, usage: &u, fs: DirectFileSystem())
        XCTAssertEqual(r.from, tmp + "/hot/diary"); XCTAssertEqual(r.to, tmp + "/cold/diary")
        XCTAssertEqual(r.id.path, tmp + "/cold/diary/SKILL.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp + "/cold/diary/references/r.md"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp + "/hot/diary"))
        XCTAssertEqual(c.visibility(of: r.id), .pinned); XCTAssertNil(c.visibility(of: e.id))
        XCTAssertEqual(u.count(r.id), 1); XCTAssertEqual(u.count(e.id), 0)
        XCTAssertEqual(c.roots.count, 1, "skills need no extra root")
        // Rescanning with the cold root registered finds it at the new id.
        c.roots.append(ScanRoot(tmp + "/cold"))
        XCTAssertEqual(scanned(c)["diary"]?.id, r.id)
    }

    func testMoveCommandMirrorsRelativePathAndRegistersColdCommandsRoot() throws {
        try mk("cmds/cl/implement_plan.md", "ip"); try mk("cmds/top.md", "t")
        var c = config(roots: [], commandRoots: [tmp + "/cmds"]); c.coldRoot = tmp + "/cold"
        let e = try XCTUnwrap(scanned(c)["cl:implement_plan"])
        var u = Usage()
        let r = try Mover.move(e, config: &c, usage: &u, fs: DirectFileSystem())
        XCTAssertEqual(r.to, tmp + "/cold/commands/cl/implement_plan.md"); XCTAssertEqual(r.id.path, r.to)
        XCTAssertTrue(FileManager.default.fileExists(atPath: r.to)); XCTAssertFalse(FileManager.default.fileExists(atPath: e.id.path))
        XCTAssertEqual(c.roots.last, ScanRoot(tmp + "/cold/commands", kind: .command))
        // Same name survives the move; a second move does not duplicate the root.
        let after = scanned(c)
        XCTAssertEqual(after["cl:implement_plan"]?.id, r.id); XCTAssertEqual(after["cl:implement_plan"]?.source, .discovered(root: tmp + "/cold/commands"))
        _ = try Mover.move(try XCTUnwrap(after["top"]), config: &c, usage: &u, fs: DirectFileSystem())
        XCTAssertEqual(c.roots.filter { $0.kind == .command }.count, 2)
    }

    func testMoveRefusalsNeverTouchDisk() throws {
        try mk("hot/a/SKILL.md", "a"); try mk("cold/a/SKILL.md", "a"); try mk("cold/b/SKILL.md", "b")   // same-content dup: hot/a is kept (root order)
        try mk("m/single.md", "manual")
        try mk("elsewhere/link/SKILL.md", "linked")
        try FileManager.default.createSymbolicLink(atPath: tmp + "/hot/link", withDestinationPath: tmp + "/elsewhere/link")
        var c = config(roots: [tmp + "/hot", tmp + "/cold"], manual: [tmp + "/m/single.md"]); c.coldRoot = tmp + "/cold"
        let es = scanned(c); var u = Usage(); let fs = DirectFileSystem()
        func refused(_ name: String, _ needle: String, line: UInt = #line) {
            XCTAssertThrowsError(try Mover.move(try XCTUnwrap(es[name]), config: &c, usage: &u, fs: fs), name, line: line) { err in
                XCTAssertTrue("\(err)".contains(needle), "\(err)", line: line)
            }
        }
        XCTAssertEqual(es["a"]?.id.path, tmp + "/hot/a/SKILL.md")
        refused("a", "destination exists")
        refused("b", "already under cold root")
        refused("single", "manual entry")
        refused("link", "reached through a symlink")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp + "/hot/a/SKILL.md"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp + "/elsewhere/link/SKILL.md"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp + "/cold/a/SKILL.md"))
    }
}
