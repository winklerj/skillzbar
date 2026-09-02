import Foundation

public struct LogRecord: Codable {
    public var ts: Date
    public var level: String      // info | warn | error
    public var op: String
    public var msg: String
    public var file: String
    public var line: Int
    public var errorType: String?
    public var errorDomain: String?
    public var errorCode: Int?
    public var paths: [String]?
}

/// Append-only JSON-lines log. Every error carries enough to hand to a coding agent.
public final class Log {
    public static let shared = Log(path: AppPaths.logFile)
    private let path: String
    private let lock = NSLock()
    private let enc: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    public var alsoStderr = false

    public init(path: String) { self.path = path }

    public func info(_ op: String, _ msg: String, paths: [String]? = nil, file: String = #fileID, line: Int = #line) {
        write(LogRecord(ts: Date(), level: "info", op: op, msg: msg, file: file, line: line, paths: paths))
    }
    public func warn(_ op: String, _ msg: String, paths: [String]? = nil, file: String = #fileID, line: Int = #line) {
        write(LogRecord(ts: Date(), level: "warn", op: op, msg: msg, file: file, line: line, paths: paths))
    }
    public func error(_ op: String, _ error: Error, paths: [String]? = nil, file: String = #fileID, line: Int = #line) {
        let ns = error as NSError
        write(LogRecord(ts: Date(), level: "error", op: op, msg: "\(error)", file: file, line: line,
                        errorType: String(reflecting: type(of: error)), errorDomain: ns.domain, errorCode: ns.code, paths: paths))
    }
    public func error(_ op: String, _ msg: String, paths: [String]? = nil, file: String = #fileID, line: Int = #line) {
        write(LogRecord(ts: Date(), level: "error", op: op, msg: msg, file: file, line: line, paths: paths))
    }

    private func write(_ r: LogRecord) {
        guard let data = try? enc.encode(r) else { return }
        lock.lock(); defer { lock.unlock() }
        AppPaths.ensureDirs()
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile(); h.write(data); h.write(Data([0x0a])); try? h.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: data + Data([0x0a]))
        }
        if alsoStderr { FileHandle.standardError.write(data + Data([0x0a])) }
    }

    public func tail(_ n: Int, level: String? = nil) -> [LogRecord] {
        guard let data = FileManager.default.contents(atPath: path), let text = String(data: data, encoding: .utf8) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        var out: [LogRecord] = []
        for line in text.split(separator: "\n").reversed() {
            guard let r = try? dec.decode(LogRecord.self, from: Data(line.utf8)) else { continue }
            if let level, r.level != level { continue }
            out.append(r)
            if out.count == n { break }
        }
        return out.reversed()
    }
}
