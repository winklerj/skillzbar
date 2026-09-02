import Foundation
import SkillzBarCore

/// Unix-socket server exposing live app state to `skillzbar ctl`. Handlers run on the main thread.
final class CtlServer {
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private let handle: (CtlRequest) -> String

    init(path: String = AppPaths.ctlSocket, handle: @escaping (CtlRequest) -> String) {
        self.handle = handle
        AppPaths.ensureDirs()
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { Log.shared.error("ctl.listen", "socket() failed: \(String(cString: strerror(errno)))"); return }
        var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { $0.withMemoryRebound(to: CChar.self, capacity: 104) { _ = strcpy($0, path) } }
        let rc = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard rc == 0, listen(fd, 8) == 0 else {
            Log.shared.error("ctl.listen", "bind/listen failed on \(path): \(String(cString: strerror(errno)))"); close(fd); fd = -1; return
        }
        chmod(path, 0o600)
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "skillzbar.ctl"))
        src.setEventHandler { [weak self] in self?.accept() }
        src.resume()
        source = src
        Log.shared.info("ctl.listen", "listening on \(path)")
    }

    private func accept() {
        let c = Darwin.accept(fd, nil, nil)
        guard c >= 0 else { return }
        var data = Data(); var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(c, &buf, buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
            if data.last == 0x0a { break }
        }
        let response: String
        if let req = try? JSONDecoder().decode(CtlRequest.self, from: data) {
            // RunLoop.perform in .common modes runs even while a menu is tracking (DispatchQueue.main.sync would hang there).
            let sem = DispatchSemaphore(value: 0)
            var result: String?
            let h = handle
            RunLoop.main.perform(inModes: [.common]) { result = h(req); sem.signal() }
            CFRunLoopWakeUp(CFRunLoopGetMain())
            if sem.wait(timeout: .now() + 5) == .timedOut {
                response = JSON.string(CtlFailure(error: "main thread did not respond within 5s (modal dialog open?)"))
            } else { response = result ?? JSON.string(CtlFailure(error: "no result")) }
        } else {
            response = JSON.string(CtlFailure(error: "malformed request: \(String(decoding: data, as: UTF8.self))"))
        }
        let out = Data((response + "\n").utf8)
        _ = out.withUnsafeBytes { write(c, $0.baseAddress, $0.count) }
        close(c)
    }

    deinit { source?.cancel(); if fd >= 0 { close(fd) }; unlink(AppPaths.ctlSocket) }
}
