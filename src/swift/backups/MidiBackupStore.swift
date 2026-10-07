import Foundation

/// Persists first-seen originals and numbered MIDI snapshots in shared song folders.
public actor MidiBackupStore {
    public static let shared = MidiBackupStore()

    private let root: URL?
    private let files = FileManager.default

    private enum StoreError: LocalizedError {
        case failure(String, String)

        var errorDescription: String? {
            switch self {
            case .failure(let operation, let detail): "\(operation): \(detail)"
            }
        }
    }

    private struct Record {
        let url: URL
        let increment: Int
        let modifiedAt: Date
    }

    /// Uses an explicit root ahead of the harness override and platform app-data location.
    public init(root: URL? = nil) {
        self.root = root
    }

    /// Creates and returns the backup root, throwing contextual filesystem errors.
    public func directory() throws -> URL {
        do {
            let resolved = try resolvedRoot()
            try files.createDirectory(at: resolved, withIntermediateDirectories: true)
            return resolved
        } catch {
            throw StoreError.failure("Cannot open MIDI backup directory", error.localizedDescription)
        }
    }

    /// Preserves the first raw source bytes without ever replacing a committed original.
    public func preserveOriginal(songName: String, bytes: [UInt8], at: Date = Date()) throws {
        do {
            try Task.checkCancellation()
            let bucket = try bucket(for: songName)
            let original = bucket.appendingPathComponent("\(bucket.lastPathComponent)1.mid")
            if try fileType(original) == .typeRegular { return }
            try commit(bytes: bytes, at: at, destination: original)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw StoreError.failure("Cannot preserve original MIDI for \(songName)", error.localizedDescription)
        }
    }

    /// Commits distinct bytes, then retains recent and active-day snapshots by modification date.
    public func record(songName: String, bytes: [UInt8], at: Date = Date()) throws {
        do {
            try Task.checkCancellation()
            guard at.timeIntervalSince1970.isFinite else {
                throw StoreError.failure("Invalid backup timestamp", songName)
            }
            let bucket = try bucket(for: songName)
            var records = try snapshots(in: bucket)
            let latest = records.max { $0.increment < $1.increment }
            if let latest,
                let previous = try? Data(contentsOf: latest.url),
                previous.elementsEqual(bytes)
            {
                return
            }
            let previousIncrement = latest?.increment ?? 0
            guard previousIncrement < Int.max else {
                throw StoreError.failure("Backup increment exhausted", bucket.path)
            }
            let increment = previousIncrement + 1
            let destination = bucket.appendingPathComponent("\(bucket.lastPathComponent)\(increment).mid")
            try commit(bytes: bytes, at: at, destination: destination)
            let attributes = try files.attributesOfItem(atPath: destination.path)
            guard let modifiedAt = attributes[.modificationDate] as? Date else {
                throw StoreError.failure("Cannot read MIDI backup modification date", destination.path)
            }
            records.append(Record(url: destination, increment: increment, modifiedAt: modifiedAt))
            try prune(records)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw StoreError.failure("Cannot record MIDI backup for \(songName)", error.localizedDescription)
        }
    }

    private func resolvedRoot() throws -> URL {
        if let root {
            guard root.isFileURL, Self.isAbsolutePath(root.path) else {
                throw StoreError.failure("Backup root must be an absolute file URL", root.absoluteString)
            }
            return root.standardizedFileURL
        }
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["PORYDAW_BACKUP_ROOT"], !override.isEmpty {
            guard Self.isAbsolutePath(override) else {
                throw StoreError.failure("PORYDAW_BACKUP_ROOT must be absolute", override)
            }
            return URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        }
        let data: URL
        #if os(macOS)
            data = files.homeDirectoryForCurrentUser.appendingPathComponent(
                "Library/Application Support", isDirectory: true)
        #elseif os(Windows)
            guard let local = environment["LOCALAPPDATA"], Self.isAbsolutePath(local) else {
                throw StoreError.failure("Cannot resolve local application data", "LOCALAPPDATA is missing or relative")
            }
            data = URL(fileURLWithPath: local, isDirectory: true)
        #else
            if let xdg = environment["XDG_DATA_HOME"], Self.isAbsolutePath(xdg) {
                data = URL(fileURLWithPath: xdg, isDirectory: true)
            } else {
                data = files.homeDirectoryForCurrentUser.appendingPathComponent(".local/share", isDirectory: true)
            }
        #endif
        return data.appendingPathComponent("porydaw/Backups", isDirectory: true)
    }

    private func bucket(for label: String) throws -> URL {
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:*?\"<>|"))
        var name = ""
        for scalar in label.unicodeScalars {
            name.unicodeScalars.append(forbidden.contains(scalar) ? "_" : scalar)
        }
        guard !name.isEmpty, !name.allSatisfy({ $0 == "." }) else {
            throw StoreError.failure("Invalid MIDI backup song name", label)
        }
        let destination = try directory().appendingPathComponent(name, isDirectory: true)
        try Task.checkCancellation()
        try files.createDirectory(at: destination, withIntermediateDirectories: true)
        guard try fileType(destination) == .typeDirectory else {
            throw StoreError.failure("MIDI backup song folder is not a directory", destination.path)
        }
        return destination
    }

    private func commit(bytes: [UInt8], at: Date, destination: URL) throws {
        guard at.timeIntervalSince1970.isFinite else {
            throw StoreError.failure("Invalid backup timestamp", destination.path)
        }
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".staging-\(UUID().uuidString)")
        try Task.checkCancellation()
        defer { try? files.removeItem(at: temporary) }
        try Data(bytes).write(to: temporary, options: .withoutOverwriting)
        try files.setAttributes([.modificationDate: at], ofItemAtPath: temporary.path)
        try Task.checkCancellation()
        // A hard link publishes the complete file atomically and refuses an occupied name.
        try files.linkItem(at: temporary, to: destination)
    }

    private func snapshots(in bucket: URL) throws -> [Record] {
        let label = bucket.lastPathComponent
        let prefixLength = label.count
        var records: [Record] = []
        for candidate in try files.contentsOfDirectory(at: bucket, includingPropertiesForKeys: nil) {
            try Task.checkCancellation()
            let name = candidate.lastPathComponent
            guard name.hasPrefix(label), name.hasSuffix(".mid") else { continue }
            let incrementText = name.dropFirst(prefixLength).dropLast(4)
            guard let increment = Int(incrementText), increment > 0,
                name == "\(label)\(increment).mid"
            else { continue }
            let attributes = try files.attributesOfItem(atPath: candidate.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { continue }
            guard let modifiedAt = attributes[.modificationDate] as? Date,
                modifiedAt.timeIntervalSince1970.isFinite
            else {
                throw StoreError.failure("Cannot read MIDI backup modification date", candidate.path)
            }
            records.append(Record(url: candidate, increment: increment, modifiedAt: modifiedAt))
        }
        return records
    }

    private func prune(_ records: [Record]) throws {
        var snapshots = records.filter { $0.increment != 1 }
        snapshots.sort { $0.increment < $1.increment }
        var retained = Set(snapshots.suffix(10).lazy.map(\.url))
        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(secondsFromGMT: 0) else {
            preconditionFailure("UTC time zone is unavailable")
        }
        calendar.timeZone = utc
        var firstByDay: [Date: URL] = [:]
        for record in snapshots {
            let day = calendar.startOfDay(for: record.modifiedAt)
            if firstByDay[day] == nil { firstByDay[day] = record.url }
        }
        for day in firstByDay.keys.sorted().suffix(30) {
            if let url = firstByDay[day] { retained.insert(url) }
        }
        for record in snapshots where !retained.contains(record.url) {
            try Task.checkCancellation()
            guard try fileType(record.url) == .typeRegular else { continue }
            try files.removeItem(at: record.url)
        }
    }

    private func fileType(_ url: URL) throws -> FileAttributeType? {
        do {
            return try files.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    private static func isAbsolutePath(_ path: String) -> Bool {
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
}
