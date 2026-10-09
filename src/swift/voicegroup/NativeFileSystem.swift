import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// Loader-order filesystem probes: POSIX stat/readdir/read, Foundation on Windows (no dirent).
enum NativeFileSystem {
    enum Kind { case directory, regular, other }

    /// nil when the path cannot be stat'ed.
    static func kind(_ path: String) -> Kind? {
        #if os(Windows)
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &directory) else { return nil }
            return directory.boolValue ? .directory : .regular
        #else
            var info = stat()
            guard stat(path, &info) == 0 else { return nil }
            switch info.st_mode & mode_t(S_IFMT) {
            case mode_t(S_IFDIR): return .directory
            case mode_t(S_IFREG): return .regular
            default: return .other
            }
        #endif
    }

    /// Entry names in native directory order, never `.` or `..`.
    static func names(_ path: String, skippingDotFiles: Bool) -> [String] {
        #if os(Windows)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            return skippingDotFiles ? names.filter { !$0.hasPrefix(".") } : names
        #else
            guard let directory = opendir(path) else { return [] }
            defer { closedir(directory) }
            var result: [String] = []
            while let entry = readdir(directory) {
                let capacity = MemoryLayout.size(ofValue: entry.pointee.d_name)
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
                }
                if skippingDotFiles ? !name.hasPrefix(".") : (name != "." && name != "..") { result.append(name) }
            }
            return result
        #endif
    }

    /// Whole regular file read straight into the returned array; nil on any failure.
    static func readRegularFile(_ path: String) -> [UInt8]? {
        #if os(Windows)
            guard kind(path) == .regular, let data = FileManager.default.contents(atPath: path) else { return nil }
            return [UInt8](data)
        #else
            let fd = path.withCString { open($0, O_RDONLY) }
            guard fd >= 0 else { return nil }
            defer { close(fd) }
            var info = stat()
            guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
                info.st_size >= 0, info.st_size <= Int.max
            else { return nil }
            let count = Int(info.st_size)
            var failed = false
            var bytes = [UInt8](repeating: 0, count: count)
            // POSIX read borrows the bounded mutable span only for the syscall.
            var destination = bytes.mutableSpan
            destination.withUnsafeMutableBufferPointer { buffer in
                var offset = 0
                while offset < count {
                    guard let base = buffer.baseAddress else { preconditionFailure("File buffer has no storage") }
                    let received = read(fd, base.advanced(by: offset), count - offset)
                    if received < 0 && errno == EINTR { continue }
                    guard received > 0 else {
                        failed = true
                        return
                    }
                    offset += received
                }
            }
            return failed ? nil : bytes
        #endif
    }
}
