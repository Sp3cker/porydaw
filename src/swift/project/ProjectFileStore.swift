import Foundation

public enum ProjectFileStoreError: Error, Equatable, Sendable, LocalizedError {
    case cannotRead(path: String)
    case cannotWrite(path: String)

    public var errorDescription: String? {
        switch self {
        case let .cannotRead(path): "Cannot read \(path)"
        case let .cannotWrite(path): "Cannot write \(path)"
        }
    }
}

public enum ProjectFileStore {
    /// Reads the bytes at `path` without interpreting their encoding.
    /// - Parameter path: The file to read.
    /// - Returns: The file's unmodified bytes.
    /// - Throws: `ProjectFileStoreError.cannotRead` if the file cannot be read.
    public static func read(_ path: String) throws -> Data {
        do {
            let handle = try FileHandle(forReadingFrom: URL(filePath: path))
            defer { try? handle.close() }
            return try handle.readToEnd() ?? Data()
        } catch {
            throw ProjectFileStoreError.cannotRead(path: path)
        }
    }

    /// Creates or truncates a file and writes its bytes without atomic replacement.
    /// - Parameters:
    ///   - path: The file to write.
    ///   - data: The bytes to write.
    /// - Throws: `ProjectFileStoreError.cannotWrite` if the file cannot be written.
    public static func write(_ path: String, data: Data) throws {
        do {
            try data.write(to: URL(filePath: path), options: [])
        } catch {
            throw ProjectFileStoreError.cannotWrite(path: path)
        }
    }

    /// Atomically replaces a file with the supplied bytes.
    /// - Parameters:
    ///   - path: The file to write.
    ///   - data: The bytes to write.
    /// - Throws: `ProjectFileStoreError.cannotWrite` if the replacement fails.
    public static func writeAtomic(_ path: String, data: Data) throws {
        do {
            try data.write(to: URL(filePath: path), options: .atomic)
        } catch {
            throw ProjectFileStoreError.cannotWrite(path: path)
        }
    }

    /// Moves a file without replacing an existing destination.
    /// - Parameters:
    ///   - from: The current path.
    ///   - to: The destination path.
    /// - Throws: `ProjectFileStoreError.cannotWrite` if the move fails.
    public static func move(from: String, to: String) throws {
        guard !FileManager.default.fileExists(atPath: to) else {
            throw ProjectFileStoreError.cannotWrite(path: to)
        }
        do {
            try FileManager.default.moveItem(atPath: from, toPath: to)
        } catch {
            throw ProjectFileStoreError.cannotWrite(path: to)
        }
    }

    /// Removes a file if it exists.
    /// - Parameter path: The file to remove.
    /// - Throws: `ProjectFileStoreError.cannotWrite` if removal fails for a reason other than absence.
    public static func remove(_ path: String) throws {
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            throw ProjectFileStoreError.cannotWrite(path: path)
        }
    }

    /// Creates a directory and any missing parent directories.
    /// - Parameter path: The directory to create.
    /// - Throws: `ProjectFileStoreError.cannotWrite` if creation fails.
    public static func mkpath(_ path: String) throws {
        do {
            try FileManager.default.createDirectory(
                at: URL(filePath: path), withIntermediateDirectories: true)
        } catch {
            throw ProjectFileStoreError.cannotWrite(path: path)
        }
    }

    /// Lists files beneath a directory whose names end in `ext`.
    /// - Parameters:
    ///   - url: The root directory.
    ///   - ext: The case-sensitive file-name suffix.
    /// - Returns: Full paths to matching files.
    /// - Throws: `ProjectFileStoreError.cannotRead` if enumeration fails.
    public static func listRecursive(url: URL, ext: String) throws -> [String] {
        var enumerationFailed = false
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey],
            errorHandler: { _, _ in
                enumerationFailed = true
                return false
            })
        else {
            throw ProjectFileStoreError.cannotRead(path: url.path)
        }
        var paths: [String] = []
        for case let entry as URL in enumerator {
            if enumerationFailed { break }
            guard entry.lastPathComponent.hasSuffix(ext) else { continue }
            do {
                if try entry.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                    paths.append(entry.path)
                }
            } catch {
                throw ProjectFileStoreError.cannotRead(path: url.path)
            }
        }
        if enumerationFailed {
            throw ProjectFileStoreError.cannotRead(path: url.path)
        }
        return paths
    }

    /// Tests whether a file or directory exists at `path`.
    /// - Parameter path: The path to inspect.
    /// - Returns: Whether the item exists.
    public static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// Removes only the last file-name suffix from a path.
    /// - Parameter path: The file path.
    /// - Returns: The final component without its last extension.
    public static func completeBaseName(_ path: String) -> String {
        URL(filePath: path).deletingPathExtension().lastPathComponent
    }

    /// Lexically normalizes separators and dot components without accessing the file system.
    /// - Parameter path: The path to normalize.
    /// - Returns: A cleaned path, or `.` if a nonempty relative path resolves to its root.
    public static func cleanPath(_ path: String) -> String {
        if path.isEmpty { return "" }

        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let unc = path.hasPrefix("\\\\")
        let absolute = normalized.hasPrefix("/")
        let components = normalized.split(separator: "/")
        let driveRoot = !absolute && isAbsolutePath(normalized)
        var resolved: [Substring] = []
        for component in components {
            switch component {
            case ".":
                continue
            case "..":
                if let last = resolved.last, last != "..",
                   !(driveRoot && resolved.count == 1) {
                    resolved.removeLast()
                } else if !absolute && !driveRoot {
                    resolved.append(component)
                }
            default:
                resolved.append(component)
            }
        }

        let joined = resolved.joined(separator: "/")
        if unc { return "//" + joined }
        if absolute { return "/" + joined }
        if driveRoot && resolved.count == 1 { return joined + "/" }
        return joined.isEmpty ? "." : joined
    }

    /// Tests for a POSIX, drive-rooted, or UNC absolute path.
    /// - Parameter path: The path to inspect.
    /// - Returns: Whether its prefix denotes an absolute path.
    public static func isAbsolutePath(_ path: String) -> Bool {
        if path.hasPrefix("/") || path.hasPrefix("\\\\") { return true }
        let bytes = path.utf8
        guard bytes.count >= 3 else { return false }
        let start = bytes.startIndex
        let letter = bytes[start]
        let colon = bytes[bytes.index(after: start)]
        let separator = bytes[bytes.index(start, offsetBy: 2)]
        return ((65...90).contains(letter) || (97...122).contains(letter))
            && colon == 58 && (separator == 47 || separator == 92)
    }

    /// Splits raw bytes on LF without decoding or losing per-line CR markers.
    /// Consumers must strip a trailing CR from each line before decoding for text matching.
    /// - Parameter data: The original file bytes.
    /// - Returns: Raw lines, whether the file ends in LF (including empty files), and whether
    ///   any CRLF occurs in the file.
    public static func splitLines(_ data: Data) -> (lines: [Data], endsWithNewline: Bool, crlf: Bool) {
        var lines: [Data] = []
        var start = data.startIndex
        var crlf = false
        for index in data.indices where data[index] == 10 {
            let line = data[start..<index]
            crlf = crlf || line.last == 13
            lines.append(Data(line))
            start = data.index(after: index)
        }
        if start < data.endIndex {
            lines.append(Data(data[start..<data.endIndex]))
        }
        return (lines, data.isEmpty || data.last == 10, crlf)
    }
}
