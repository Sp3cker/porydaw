import Foundation

/// Absolute source file and optional bare label selected by the loader.
public struct VoicegroupLocation: Equatable, Sendable {
    public let filePath: String
    public let sectionLabel: String

    public init(filePath: String, sectionLabel: String) {
        self.filePath = filePath
        self.sectionLabel = sectionLabel
    }
}

/// Ordered C-loader probes over a project's eager and deferred discovery results.
public struct VoicegroupLocator {
    private let layout: ProjectLayout

    public init(layout: ProjectLayout) { self.layout = layout }

    /// Locates a song argument, retaining the editor's leading-underscore normalization.
    public func locate(voicegroupArg: String) -> VoicegroupLocation? {
        let argument = voicegroupArg.isEmpty ? "_dummy" : voicegroupArg
        let base = String(argument.drop(while: { $0 == "_" }))
        let label = "voicegroup" + argument
        if let found = probe(base: base, label: label, layout: layout) { return found }
        return probe(base: base, label: label, layout: layout.ensuringDeepScan())
    }

    /// Applies the first `_keysplit` truncation and the two directory passes from C §4.
    public func locateKeysplitTarget(symbol: String) -> VoicegroupLocation? {
        guard let base = Self.subgroupName(symbol, infix: "_keysplit", preserveTail: false) else { return nil }
        if let found = subdirectory("keysplits", name: base, layout: layout) { return found }
        return subdirectory("keysplits", name: base, layout: layout.ensuringDeepScan())
    }

    /// Removes the first `_drumset` infix, retaining its tail, per C §4.
    public func locateDrumsetTarget(symbol: String) -> VoicegroupLocation? {
        guard let base = Self.subgroupName(symbol, infix: "_drumset", preserveTail: true) else { return nil }
        if let found = subdirectory("drumsets", name: base, layout: layout) { return found }
        return subdirectory("drumsets", name: base, layout: layout.ensuringDeepScan())
    }

    /// Returns the immediate hub successor; a missing successor ends contiguity.
    public func nextIncludedFile(after filePath: String) -> String? {
        let current = Self.basename(filePath)
        for relative in ["sound/voice_groups.inc", "sound/voicegroups.inc"] {
            guard let index = Self.path(layout.projectRoot, relative),
                let data = try? ProjectFileStore.read(index)
            else { continue }
            var foundCurrent = false
            for raw in ProjectFileStore.splitLines(data).lines {
                let bytes = [UInt8](raw)
                let text = bytes[VoicegroupSource.contentBounds(bytes)]
                let prefix = ".include"
                guard text.starts(with: prefix.utf8) else { continue }
                let rest = text.dropFirst(prefix.utf8.count).drop(while: { $0 == 32 || (9...13).contains($0) })
                guard rest.first == 34, let quote = rest.dropFirst().firstIndex(of: 34) else { continue }
                let included = rest.dropFirst()[..<quote]
                guard !included.isEmpty, included.count <= 511 else { continue }
                let name = String(decoding: included, as: UTF8.self)
                if foundCurrent {
                    guard let path = Self.path(layout.projectRoot, name), ProjectFileStore.exists(path) else {
                        return nil
                    }
                    return path
                }
                if Self.basename(name) == current { foundCurrent = true }
            }
            if foundCurrent { return nil }
        }
        return nil
    }

    private func probe(base: String, label: String, layout: ProjectLayout) -> VoicegroupLocation? {
        for directory in layout.voicegroupDirectories {
            if let found = file(directory: directory, name: base) { return found }
        }
        if let name = Self.subgroupName(base, infix: "_keysplit", preserveTail: false),
            let found = subdirectory("keysplits", name: name, layout: layout)
        {
            return found
        }
        if let name = Self.subgroupName(base, infix: "_drumset", preserveTail: true),
            let found = subdirectory("drumsets", name: name, layout: layout)
        {
            return found
        }
        for directory in layout.voicegroupDirectories {
            if let found = file(directory: directory, name: "vg_" + base) { return found }
        }
        if label.utf8.count < 256 {
            for path in layout.monolithicFiles {
                if declarations(path).contains(where: { $0.isLabel && $0.symbol == label }) {
                    return VoicegroupLocation(filePath: path, sectionLabel: label)
                }
            }
        }
        guard !base.isEmpty, base.utf8.count < 256 else { return nil }
        for directory in layout.voicegroupDirectories {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else { continue }
            for entry in entries {
                let suffix = URL(filePath: entry).pathExtension.lowercased()
                guard suffix == "inc" || suffix == "s", let path = Self.path(directory, entry) else { continue }
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue
                else {
                    continue
                }
                if declarations(path).contains(where: { !$0.isLabel && $0.symbol == "voicegroup_" + base }) {
                    return VoicegroupLocation(filePath: path, sectionLabel: "")
                }
            }
        }
        return nil
    }

    private func declarations(_ path: String) -> [VoicegroupSource.Declaration] {
        guard let data = try? ProjectFileStore.read(path) else { return [] }
        return VoicegroupSource.declarations(in: [UInt8](data))
    }

    private func subdirectory(_ subdirectory: String, name: String, layout: ProjectLayout) -> VoicegroupLocation? {
        for directory in layout.voicegroupDirectories {
            if let nested = Self.path(directory, subdirectory), let found = file(directory: nested, name: name) {
                return found
            }
        }
        for directory in layout.voicegroupDirectories where Self.basename(directory) == subdirectory {
            if let found = file(directory: directory, name: name) { return found }
        }
        return nil
    }

    private func file(directory: String, name: String) -> VoicegroupLocation? {
        for suffix in [".inc", ".s"] {
            if let path = Self.path(directory, name + suffix), ProjectFileStore.exists(path) {
                return VoicegroupLocation(filePath: path, sectionLabel: "")
            }
        }
        return nil
    }

    private static func subgroupName(_ symbol: String, infix: String, preserveTail: Bool) -> String? {
        guard let range = symbol.range(of: infix), range.lowerBound != symbol.startIndex else { return nil }
        var base = String(symbol[..<range.lowerBound])
        if preserveTail { base += symbol[range.upperBound...] }
        return base.utf8.count < 256 ? base : nil
    }

    private static func path(_ directory: String, _ relative: String) -> String? {
        let path = directory + "/" + relative.replacingOccurrences(of: "\\", with: "/")
        return path.utf8.count < 512 ? path : nil
    }

    private static func basename(_ path: String) -> String {
        guard let separator = path.lastIndex(where: { $0 == "/" || $0 == "\\" }) else { return path }
        return String(path[path.index(after: separator)...])
    }
}
