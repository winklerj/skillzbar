import Foundation

/// Line-delimited JSON over a Unix domain socket. One request per connection.
public struct CtlRequest: Codable {
    public var command: String       // list | menu | panel | rescan | errors | copy | move | status | ping | show | hide | ui | key | snapshot
    public var arg: String?
    public var contents: Bool?
    public var all: Bool?
    public init(command: String, arg: String? = nil, contents: Bool? = nil, all: Bool? = nil) {
        self.command = command; self.arg = arg; self.contents = contents; self.all = all
    }
}

public struct CtlFailure: Codable { public let ok: Bool; public let error: String; public init(error: String) { ok = false; self.error = error } }

public enum CtlClient {
    public static func send(_ req: CtlRequest, socketPath: String = AppPaths.ctlSocket) throws -> String {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SkillzError.posix(op: "socket", path: socketPath, errno: errno) }
        defer { close(fd) }
        var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
        guard socketPath.utf8.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw SkillzError.ctl("socket path too long") }
        withUnsafeMutablePointer(to: &addr.sun_path) { $0.withMemoryRebound(to: CChar.self, capacity: 104) { _ = strcpy($0, socketPath) } }
        let rc = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard rc == 0 else { throw SkillzError.ctl("cannot connect to \(socketPath) (is SkillzBar running?): \(String(cString: strerror(errno)))") }
        let body = try JSONEncoder().encode(req) + Data([0x0a])
        _ = body.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        var out = Data(); var buf = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            out.append(buf, count: n)
        }
        return String(decoding: out, as: UTF8.self)
    }
}
