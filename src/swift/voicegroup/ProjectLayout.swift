import Foundation
import Synchronization

#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

/// Discovered paths in native probe order, with a cached, additive deep scan.
public final class ProjectLayout: Sendable {
    public let projectRoot: String
    public let soundDataFiles: [String]
    public let programmableWaveFiles: [String]
    public let keysplitTableFiles: [String]
    public let voicegroupDirectories: [String]
    public let monolithicFiles: [String]
    public let sampleDirectories: [String]
    private let scanned: Bool
    private let deepScan = Mutex<ProjectLayout?>(nil)

    public convenience init(projectRoot: String, extraVoicegroupPaths: [String] = []) {
        let root = URL(filePath: projectRoot.replacingOccurrences(of: "\\", with: "/")).path
        var paths = LayoutPaths()
        for relative in extraVoicegroupPaths.prefix(8) {
            guard let path = LayoutPaths.join(root, relative) else { continue }
            if LayoutPaths.isDirectory(path) {
                LayoutPaths.add(path, to: &paths.voicegroups)
                for name in LayoutPaths.names(path) where LayoutPaths.isAssembly(name) {
                    if let file = LayoutPaths.join(path, name), LayoutPaths.isMonolithic(file) {
                        LayoutPaths.add(file, to: &paths.monolithic)
                    }
                }
                paths.probeKeysplits(path)
            } else if LayoutPaths.isFile(path), LayoutPaths.isMonolithic(path) {
                LayoutPaths.add(path, to: &paths.monolithic)
            }
        }
        for relative in ["sound/direct_sound_data.inc", "sound/direct_sound_synth_data.inc"] {
            if let path = LayoutPaths.join(root, relative), LayoutPaths.isFile(path) {
                LayoutPaths.add(path, to: &paths.sound)
            }
        }
        if let path = LayoutPaths.join(root, "sound/programmable_wave_data.inc"), LayoutPaths.isFile(path) {
            LayoutPaths.add(path, to: &paths.programmable)
        }
        if let path = LayoutPaths.join(root, "sound/keysplit_tables.inc"), LayoutPaths.isFile(path) {
            LayoutPaths.add(path, to: &paths.keysplits)
        }
        if let directory = LayoutPaths.join(root, "sound/voicegroups"), LayoutPaths.isDirectory(directory) {
            LayoutPaths.add(directory, to: &paths.voicegroups)
            for name in ["keysplits", "drumsets"] {
                if let path = LayoutPaths.join(directory, name), LayoutPaths.isDirectory(path) {
                    LayoutPaths.add(path, to: &paths.voicegroups)
                }
            }
        }
        if let path = LayoutPaths.join(root, "sound/voice_groups.inc"), LayoutPaths.isFile(path),
            LayoutPaths.isMonolithic(path)
        {
            LayoutPaths.add(path, to: &paths.monolithic)
        }
        self.init(root: root, paths: paths, scanned: false)
    }

    private init(root: String, paths: LayoutPaths, scanned: Bool) {
        projectRoot = root
        soundDataFiles = paths.sound
        programmableWaveFiles = paths.programmable
        keysplitTableFiles = paths.keysplits
        voicegroupDirectories = paths.voicegroups
        monolithicFiles = paths.monolithic
        sampleDirectories = paths.samples
        self.scanned = scanned
    }

    /// Scans sound/ once, preserving eager paths and first-hit precedence.
    public func ensuringDeepScan() -> ProjectLayout {
        if scanned { return self }
        return deepScan.withLock { cached in
            if let cached { return cached }
            var paths = LayoutPaths(
                sound: soundDataFiles, programmable: programmableWaveFiles,
                keysplits: keysplitTableFiles, voicegroups: voicegroupDirectories,
                monolithic: monolithicFiles, samples: sampleDirectories)
            if let sound = LayoutPaths.join(projectRoot, "sound"), LayoutPaths.isDirectory(sound) {
                paths.scan(sound, depth: 0)
            }
            let result = ProjectLayout(root: projectRoot, paths: paths, scanned: true)
            cached = result
            return result
        }
    }
}

private struct LayoutPaths {
    var sound: [String] = []
    var programmable: [String] = []
    var keysplits: [String] = []
    var voicegroups: [String] = []
    var monolithic: [String] = []
    var samples: [String] = []
    private static let macros = [
        "voice_directsound", "voice_square", "voice_programmable_wave",
        "voice_noise", "voice_keysplit", "voice_group",
    ].map { Array($0.utf8) }

    static func add(_ path: String, to list: inout [String]) {
        if list.count < 32, !list.contains(path) { list.append(path) }
    }

    static func join(_ base: String, _ relative: String) -> String? {
        guard base.utf8.count + 1 + relative.utf8.count < 512 else { return nil }
        return (base + "/" + relative).replacingOccurrences(of: "\\", with: "/")
    }

    static func isDirectory(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0 && (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR)
    }

    static func isFile(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0 && (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG)
    }

    // Native discovery preserves readdir order; sorted catalog listings cannot be reused.
    static func names(_ path: String) -> [String] {
        guard let directory = opendir(path) else { return [] }
        defer { closedir(directory) }
        var result: [String] = []
        while let entry = readdir(directory) {
            let capacity = MemoryLayout.size(ofValue: entry.pointee.d_name)
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: capacity) {
                    String(cString: $0)
                }
            }
            if !name.hasPrefix(".") { result.append(name) }
        }
        return result
    }

    static func isAssembly(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".inc") || lower.hasSuffix(".s")
    }

    static func hasVoiceMacro(_ bytes: AsmLine.Bytes) -> Bool {
        macros.contains { AsmLine.contains(bytes, $0) }
    }

    static func probeLines(_ path: String, limit: Int) -> [AsmLine.Bytes] {
        guard let lines = AsmLine.lines(path) else { return [] }
        var chunks: [AsmLine.Bytes] = []
        for line in lines {
            var start = line.startIndex
            repeat {
                let end = min(start + 1023, line.endIndex)
                chunks.append(line[start..<end])
                if chunks.count == limit { return chunks }
                start = end
            } while start < line.endIndex
            if !line.isEmpty, line.count.isMultiple(of: 1023) {
                chunks.append(line[line.endIndex..<line.endIndex])
                if chunks.count == limit { return chunks }
            }
        }
        return chunks
    }

    static func isMonolithic(_ path: String) -> Bool {
        let lines = probeLines(path, limit: 500)
        var labels = 0
        var voices = 0
        var includes = 0
        for raw in lines.prefix(500) {
            let line = AsmLine.content(raw)
            if line.first != 46, AsmLine.contains(line, [58, 58]) { labels += 1 }
            if hasVoiceMacro(line) { voices += 1 }
            if AsmLine.contains(line, Array(".include".utf8)) { includes += 1 }
        }
        return labels >= 2 && voices > 0 && voices > includes
    }

    mutating func probeKeysplits(_ directory: String) {
        for name in ["keysplit_tables.inc", "keysplit_tables.s"] {
            if let path = Self.join(directory, name), Self.isFile(path) { Self.add(path, to: &keysplits) }
        }
        discoverKeysplitSubdir(directory)
    }

    mutating func discoverKeysplitSubdir(_ directory: String) {
        guard let subdir = Self.join(directory, "keysplits") else { return }
        for name in Self.names(subdir) where Self.isAssembly(name) {
            if let path = Self.join(subdir, name) { Self.add(path, to: &keysplits) }
        }
    }

    mutating func scan(_ directory: String, depth: Int) {
        let names = Self.names(directory)
        var subdirectories: [String] = []
        var candidates: [String] = []
        var hasSamples = false
        var hasInc = false
        var hasS = false
        var hasKeysplits = false
        for name in names {
            guard let path = Self.join(directory, name) else { continue }
            if Self.isDirectory(path) {
                subdirectories.append(path)
                if name == "keysplits" { hasKeysplits = true }
                continue
            }
            let lower = name.lowercased()
            if lower.hasSuffix(".wav") || lower.hasSuffix(".aif") { hasSamples = true }
            if name == "keysplit_tables.inc" { hasInc = true }
            if name == "keysplit_tables.s" { hasS = true }
            if candidates.count < 5, Self.isAssembly(name) { candidates.append(path) }
        }
        for path in candidates {
            if Self.probeLines(path, limit: 50).contains(where: Self.hasVoiceMacro) {
                Self.add(directory, to: &voicegroups)
                break
            }
        }
        if hasSamples { Self.add(directory, to: &samples) }
        if hasInc, let path = Self.join(directory, "keysplit_tables.inc") { Self.add(path, to: &keysplits) }
        if hasS, let path = Self.join(directory, "keysplit_tables.s") { Self.add(path, to: &keysplits) }
        if hasKeysplits { discoverKeysplitSubdir(directory) }
        // C applies facts at depth 3, then stops recursing (voicegroup_loader.c:1071–1088).
        if depth < 3 {
            for path in subdirectories { scan(path, depth: depth + 1) }
        }
    }
}
