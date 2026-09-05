import Foundation

public enum AppPaths {
    public static let bundleID = "dev.robb.SkillzBar"
    /// `SKILLZBAR_HOME` overrides the home directory for every path here (config, log, socket, `~` expansion),
    /// so an agent can exercise the CLI or a second app instance against a scratch tree. `NSHomeDirectory()`
    /// ignores `$HOME`, which is why a plain env override is not enough.
    public static var home: String { ProcessInfo.processInfo.environment["SKILLZBAR_HOME"] ?? NSHomeDirectory() }
    public static var supportDir: String { home + "/Library/Application Support/SkillzBar" }
    public static var logDir: String { home + "/Library/Logs/SkillzBar" }
    public static var configFile: String { supportDir + "/config.json" }
    public static var cacheFile: String { supportDir + "/cache.json" }
    public static var usageFile: String { supportDir + "/usage.json" }
    public static var ctlSocket: String { supportDir + "/ctl.sock" }
    public static var logFile: String { logDir + "/skillzbar.jsonl" }

    public static func ensureDirs() {
        for d in [supportDir, logDir] {
            try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        }
    }

    public static func expand(_ p: String) -> String {
        if p == "~" { return home }
        if p.hasPrefix("~/") { return home + p.dropFirst(1) }
        return p
    }
    public static func abbreviate(_ p: String) -> String {
        p.hasPrefix(home + "/") ? "~" + p.dropFirst(home.count) : p
    }
}
