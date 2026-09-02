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
    func config(roots: [String], manual: [String] = []) -> Config {
        var c = Config.defaults; c.roots = roots; c.manualSkills = manual; c.excludePathPrefixes = []; return c
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
        var c = Config.defaults; c.roots = ["~/skillz"]; c.setVisibility(.pinned, for: SkillID(path: "/p/SKILL.md"))
        try c.save(path: p)
        XCTAssertEqual(try Config.load(path: p), c)
        try #"{"roots":["/only"]}"#.write(toFile: p, atomically: true, encoding: .utf8)
        let partial = try Config.load(path: p)
        XCTAssertEqual(partial.roots, ["/only"]); XCTAssertEqual(partial.hotkey, .default)
    }
}
