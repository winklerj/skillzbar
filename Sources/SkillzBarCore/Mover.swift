import Foundation

/// Moves an entry into the cold root (`Config.coldRoot`). Pure over `SkillFileSystem` so tests run on a tmp dir.
///
/// - skill: the whole skill directory moves to `<cold>/<dirname>`.
/// - command: the single `.md` moves to `<cold>/commands/<path relative to its commands root>`, creating
///   intermediate directories so the `ns:sub:stem` name is preserved; `<cold>/commands` is added to
///   `config.roots` (kind command) if absent so the moved command stays discoverable.
///
/// Refuses (never overwrites, never surprises): manual entries, entries whose real path is outside their
/// root (reached through a symlink), entries already under the cold root, and existing destinations.
/// Migrates `config.visibility` and `usage.stats` keys from the old `SkillID` to the new one.
public enum Mover {
    public static let commandsSubdir = "commands"

    public static func move(_ e: SkillEntry, config: inout Config, usage: inout Usage, fs: SkillFileSystem) throws -> MoveResult {
        guard case .discovered(let root) = e.source else {
            throw SkillzError.moveRefused(path: e.id.path, reason: "manual entry; edit manualSkills in Settings instead")
        }
        let cold = AppPaths.expand(config.coldRoot)
        try fs.makeDirectory(cold)
        let coldReal = try fs.realpath(cold)
        let rootReal = try fs.realpath(AppPaths.expand(root))
        let from: String, to: String
        switch e.kind {
        case .skill:
            from = e.id.directory
            to = coldReal + "/" + (from as NSString).lastPathComponent
        case .command:
            from = e.id.path
            to = coldReal + "/" + commandsSubdir + "/" + from.dropFirst(rootReal.count + 1)
        }
        guard from.hasPrefix(rootReal + "/") else {
            throw SkillzError.moveRefused(path: from, reason: "not inside its root \(rootReal) (reached through a symlink); move it by hand")
        }
        guard !from.hasPrefix(coldReal + "/") else { throw SkillzError.moveRefused(path: from, reason: "already under cold root \(coldReal)") }
        guard !fs.exists(to) else { throw SkillzError.moveRefused(path: from, reason: "destination exists: \(to)") }
        try fs.makeDirectory((to as NSString).deletingLastPathComponent)
        try fs.move(from, to: to)

        let newID = SkillID(path: e.kind == .skill ? to + "/" + skillFileName : to)
        if let v = config.visibility.removeValue(forKey: e.id.path) { config.visibility[newID.path] = v }
        if let s = usage.stats.removeValue(forKey: e.id.path) { usage.stats[newID.path] = s }
        if e.kind == .command {
            let coldCommands = cold + "/" + commandsSubdir
            if !config.roots.contains(where: { $0.kind == .command && AppPaths.expand($0.path) == coldCommands }) {
                config.roots.append(ScanRoot(config.coldRoot + "/" + commandsSubdir, kind: .command))
            }
        }
        return MoveResult(name: e.name, kind: e.kind, from: from, to: to, id: newID, duplicatePaths: e.duplicatePaths)
    }
}
