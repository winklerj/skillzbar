import Foundation
import Darwin

@inline(__always) private func posixStat(_ path: String, _ st: inout stat) -> Int32 { stat(path, &st) }

public enum EntryKind { case file, directory, symlink, other }

public struct DirEntry {
    public let name: String
    public let kind: EntryKind
    public let size: Int64
    public let modifiedNs: Int64
    public let inode: UInt64
    public let device: UInt32
}

public struct FileStat {
    public let kind: EntryKind
    public let size: Int64
    public let modifiedNs: Int64
    public let inode: UInt64
    public let device: UInt32
}

/// All file access in Core goes through this so a sandboxed/bookmark-based implementation can replace it.
public protocol SkillFileSystem {
    func list(directory: String) throws -> [DirEntry]
    func stat(_ path: String) throws -> FileStat
    func realpath(_ path: String) throws -> String
    func read(_ path: String) throws -> Data
}

/// Direct POSIX implementation. Directory listing uses getattrlistbulk(2): one syscall returns
/// name, type, size, mtime, inode, device for a whole directory, so no per-entry stat is needed.
public struct DirectFileSystem: SkillFileSystem {
    public init() {}

    public func list(directory: String) throws -> [DirEntry] {
        do { return try listBulk(directory) }
        catch { return try listReaddir(directory) }   // fallback for volumes without bulk support
    }

    public func stat(_ path: String) throws -> FileStat {
        var st = Darwin.stat()
        guard posixStat(path, &st) == 0 else { throw SkillzError.posix(op: "stat", path: path, errno: errno) }
        return FileStat(kind: kind(ofMode: st.st_mode), size: Int64(st.st_size),
                        modifiedNs: Int64(st.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(st.st_mtimespec.tv_nsec),
                        inode: UInt64(st.st_ino), device: UInt32(bitPattern: st.st_dev))
    }

    public func realpath(_ path: String) throws -> String {
        guard let r = Darwin.realpath(path, nil) else { throw SkillzError.posix(op: "realpath", path: path, errno: errno) }
        defer { free(r) }
        return String(cString: r)
    }

    public func read(_ path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
    }

    private func kind(ofMode m: mode_t) -> EntryKind {
        switch m & S_IFMT {
        case S_IFREG: return .file
        case S_IFDIR: return .directory
        case S_IFLNK: return .symlink
        default: return .other
        }
    }

    // MARK: getattrlistbulk

    private static let cmnReturnedAttrs: UInt32 = 0x8000_0000
    private static let cmnName: UInt32 = 0x0000_0001
    private static let cmnDevID: UInt32 = 0x0000_0002
    private static let cmnObjType: UInt32 = 0x0000_0008
    private static let cmnModTime: UInt32 = 0x0000_0400
    private static let cmnFileID: UInt32 = 0x0200_0000
    private static let cmnError: UInt32 = 0x2000_0000
    private static let fileDataLength: UInt32 = 0x0000_0002
    private static let vREG: UInt32 = 1, vDIR: UInt32 = 2, vLNK: UInt32 = 5

    private func listBulk(_ directory: String) throws -> [DirEntry] {
        let fd = open(directory, O_RDONLY | O_DIRECTORY)
        guard fd >= 0 else { throw SkillzError.posix(op: "open", path: directory, errno: errno) }
        defer { close(fd) }

        var attrs = attrlist()
        attrs.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attrs.commonattr = Self.cmnReturnedAttrs | Self.cmnName | Self.cmnError | Self.cmnDevID | Self.cmnObjType | Self.cmnModTime | Self.cmnFileID
        attrs.fileattr = Self.fileDataLength

        let bufSize = 64 * 1024
        let buf = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 8)
        defer { buf.deallocate() }
        var out: [DirEntry] = []

        while true {
            let n = getattrlistbulk(fd, &attrs, buf, bufSize, 0)
            if n < 0 { throw SkillzError.posix(op: "getattrlistbulk", path: directory, errno: errno) }
            if n == 0 { break }
            var p = buf
            for _ in 0..<Int(n) {
                let entryLen = Int(p.loadUnaligned(as: UInt32.self))
                var f = p + 4
                let returned = f.loadUnaligned(as: attribute_set_t.self); f += MemoryLayout<attribute_set_t>.size
                var name = "", kind = EntryKind.other, size: Int64 = 0, mtime: Int64 = 0, ino: UInt64 = 0, dev: UInt32 = 0
                var entryError: UInt32 = 0
                if returned.commonattr & Self.cmnError != 0 { entryError = f.loadUnaligned(as: UInt32.self); f += 4 }
                if returned.commonattr & Self.cmnName != 0 {
                    let off = Int(f.loadUnaligned(as: Int32.self))
                    name = String(cString: (f + off).assumingMemoryBound(to: CChar.self)); f += 8
                }
                if returned.commonattr & Self.cmnDevID != 0 { dev = f.loadUnaligned(as: UInt32.self); f += 4 }
                if returned.commonattr & Self.cmnObjType != 0 {
                    let t = f.loadUnaligned(as: UInt32.self); f += 4
                    kind = t == Self.vREG ? .file : t == Self.vDIR ? .directory : t == Self.vLNK ? .symlink : .other
                }
                if returned.commonattr & Self.cmnModTime != 0 {
                    let ts = f.loadUnaligned(as: timespec.self); f += MemoryLayout<timespec>.size
                    mtime = Int64(ts.tv_sec) * 1_000_000_000 + Int64(ts.tv_nsec)
                }
                if returned.commonattr & Self.cmnFileID != 0 { ino = f.loadUnaligned(as: UInt64.self); f += 8 }
                if returned.fileattr & Self.fileDataLength != 0 { size = f.loadUnaligned(as: Int64.self); f += 8 }
                if entryError == 0, !name.isEmpty {
                    out.append(DirEntry(name: name, kind: kind, size: size, modifiedNs: mtime, inode: ino, device: dev))
                }
                p += entryLen
            }
        }
        return out
    }

    private func listReaddir(_ directory: String) throws -> [DirEntry] {
        guard let dir = opendir(directory) else { throw SkillzError.posix(op: "opendir", path: directory, errno: errno) }
        defer { closedir(dir) }
        var out: [DirEntry] = []
        while let ent = readdir(dir) {
            let name = withUnsafePointer(to: ent.pointee.d_name) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) } }
            if name == "." || name == ".." { continue }
            var st = Darwin.stat()
            guard fstatat(dirfd(dir), name, &st, AT_SYMLINK_NOFOLLOW) == 0 else { continue }
            out.append(DirEntry(name: name, kind: kind(ofMode: st.st_mode), size: Int64(st.st_size),
                                modifiedNs: Int64(st.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(st.st_mtimespec.tv_nsec),
                                inode: UInt64(st.st_ino), device: UInt32(bitPattern: st.st_dev)))
        }
        return out
    }
}
