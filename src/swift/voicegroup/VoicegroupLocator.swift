import Foundation
#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

public struct VoicegroupLocation: Hashable, Sendable {
    public let filePath: String
    public let sectionLabel: String
    public init(filePath: String, sectionLabel: String) {
        self.filePath = filePath
        self.sectionLabel = sectionLabel
    }
}

/// Ordered native probes, memoized only for subgroup symbols.
public final class VoicegroupLocator {
    private let layout: ProjectLayout
    private var subgroups: [SymbolKey: VoicegroupLocation?] = [:]
    private let includedFiles: [Substring: String?]
    public init(layout: ProjectLayout) {
        self.layout = layout
        includedFiles = Self.includeOrder(projectRoot: layout.projectRoot)
    }
    public func removeAll() { subgroups.removeAll() }

    public func locate(voicegroupArg: String) -> VoicegroupLocation? {
        let argument = voicegroupArg.isEmpty ? "_dummy" : voicegroupArg
        let base = Array(argument.drop(while: { $0 == "_" }).utf8)[...]
        let label = Array(("voicegroup" + argument).utf8)[...]
        if let found = probe(base: base, label: label, layout: layout) { return found }
        if let found = probe(base: base, label: label, layout: layout.ensuringDeepScan()) { return found }
        // Hub indices may contain both includes and declarations, which native
        // monolithic discovery excludes. Preserve the top-level source fallback.
        for relative in ["sound/voice_groups.inc", "sound/voicegroups.inc"] {
            let path = layout.projectRoot + "/" + relative
            if declares(path, symbol: label, isLabel: true) {
                return VoicegroupLocation(filePath: path, sectionLabel: String(decoding: label, as: UTF8.self))
            }
        }
        return nil
    }

    public func locateKeysplitTarget(symbol: String) -> VoicegroupLocation? {
        guard let base = Self.subgroupName(Array(symbol.utf8)[...], infix: "_keysplit", preserveTail: false) else {
            return nil
        }
        if let found = subdirectory("keysplits", name: base, layout: layout) { return found }
        return subdirectory("keysplits", name: base, layout: layout.ensuringDeepScan())
    }

    public func locateDrumsetTarget(symbol: String) -> VoicegroupLocation? {
        guard let base = Self.subgroupName(Array(symbol.utf8)[...], infix: "_drumset", preserveTail: true) else {
            return nil
        }
        if let found = subdirectory("drumsets", name: base, layout: layout) { return found }
        return subdirectory("drumsets", name: base, layout: layout.ensuringDeepScan())
    }

    public func locateSubgroup(symbol: ArraySlice<UInt8>) -> VoicegroupLocation? {
        if let cached = subgroups[SymbolKey(symbol)] { return cached }
        let name = Self.matches(symbol, "voicegroup_") ? symbol[(symbol.startIndex + 11)...] : symbol
        let found =
            probe(base: name, label: name, layout: layout)
            ?? probe(base: name, label: name, layout: layout.ensuringDeepScan())
        subgroups[SymbolKey(symbol)] = .some(found)
        return found
    }

    public func nextIncludedFile(after filePath: String) -> String? {
        let currentBytes = filePath.utf8
        let current = currentBytes.span
        var currentStart = 0
        for index in 0..<current.count {
            let byte: UInt8 = current[index]
            if byte == UInt8(47) || byte == UInt8(92) { currentStart = index + 1 }
        }
        let start = currentBytes.index(currentBytes.startIndex, offsetBy: currentStart)
        guard let recorded = includedFiles[filePath[start...]], let next = recorded,
            next.utf8.count < 512
        else { return nil }
        let status: Int32 = next.withCString { pointer -> Int32 in access(pointer, F_OK) }
        guard status == 0
        else { return nil }
        return next
    }

    private static func includeOrder(projectRoot: String) -> [Substring: String?] {
        var result: [Substring: String?] = [:]
        for relative in ["sound/voice_groups.inc", "sound/voicegroups.inc"] {
            guard let bytes = try? VoicegroupText.read(projectRoot + "/" + relative) else { continue }
            var previous: Substring?
            var start = 0
            while start < bytes.count {
                var end = start
                while end < bytes.count && bytes[end] != 10 { end += 1 }
                let raw = bytes[start..<end]
                start = end + 1
                let text = raw[VoicegroupSource.contentBounds(raw)]
                guard Self.matches(text, ".include") else { continue }
                var first = text.startIndex + 8
                while first < text.endIndex && VoicegroupSource.isSpace(text[first]) { first += 1 }
                guard first < text.endIndex && text[first] == UInt8(34) else { continue }
                first += 1
                var quote = first
                while quote < text.endIndex && text[quote] != 34 { quote += 1 }
                guard quote < text.endIndex else { continue }
                let included = text[first..<quote]
                guard !included.isEmpty, included.count <= 511 else { continue }
                let name = String(decoding: included, as: UTF8.self).replacingOccurrences(of: "\\", with: "/")
                let path = projectRoot + "/" + name
                if let previous, result[previous] == nil { result[previous] = .some(path) }
                var basenameStart = 0
                let nameBytes = name.utf8
                let nameSpan = nameBytes.span
                for index in 0..<nameSpan.count {
                    if nameSpan[index] == UInt8(47) { basenameStart = index + 1 }
                }
                previous = name[nameBytes.index(nameBytes.startIndex, offsetBy: basenameStart)...]
            }
            if let previous, result[previous] == nil { result[previous] = .some(nil) }
        }
        return result
    }

    private func probe(base: ArraySlice<UInt8>, label: ArraySlice<UInt8>, layout: ProjectLayout) -> VoicegroupLocation?
    {
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
            if let found = file(directory: directory, name: base, prefix: "vg_") { return found }
        }
        if label.count < 256 {
            for path in layout.monolithicFiles where declares(path, symbol: label, isLabel: true) {
                return VoicegroupLocation(filePath: path, sectionLabel: String(decoding: label, as: UTF8.self))
            }
        }
        guard !base.isEmpty, base.count < 256 else { return nil }
        for directory in layout.voicegroupDirectories {
            guard let stream = directory.withCString({ opendir($0) }) else { continue }
            defer { closedir(stream) }
            while let entry = readdir(stream) {
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) }
                }
                let nameBytes = name.utf8
                let extensionBytes = nameBytes.span
                let count = extensionBytes.count
                // C declared-name fallback: voicegroup_loader.c:2175 accepts .S/.INC too.
                var assembly: Bool = false
                if count >= 2, extensionBytes[count - 2] == UInt8(46) {
                    let last: UInt8 = extensionBytes[count - 1]
                    assembly = last == UInt8(115) || last == UInt8(83)
                }
                var include: Bool = false
                if count >= 4, extensionBytes[count - 4] == UInt8(46) {
                    let first: UInt8 = extensionBytes[count - 3] | UInt8(32)
                    let middle: UInt8 = extensionBytes[count - 2] | UInt8(32)
                    let last: UInt8 = extensionBytes[count - 1] | UInt8(32)
                    include = first == UInt8(105) && middle == UInt8(110) && last == UInt8(99)
                }
                guard assembly || include else { continue }
                let path = directory + "/" + name
                guard path.utf8.count < 512 else { continue }
                var info = stat()
                let status: Int32 = path.withCString { pointer -> Int32 in stat(pointer, &info) }
                guard status == 0, (info.st_mode & S_IFMT) != S_IFDIR else { continue }
                if declares(path, symbol: base, isLabel: false) {
                    return VoicegroupLocation(filePath: path, sectionLabel: "")
                }
            }
        }
        return nil
    }

    private func declares(_ path: String, symbol: ArraySlice<UInt8>, isLabel: Bool) -> Bool {
        guard let bytes = try? VoicegroupText.read(path) else { return false }
        var start = 0
        while start < bytes.count {
            var end = start
            while end < bytes.count && bytes[end] != 10 { end += 1 }
            let raw = bytes[start..<end]
            start = end + 1
            let text = raw[VoicegroupSource.contentBounds(raw)]
            if isLabel {
                if text.count >= symbol.count + 2, Self.equalPrefix(text, symbol),
                    text[text.startIndex + symbol.count] == UInt8(58),
                    text[text.startIndex + symbol.count + 1] == UInt8(58),
                    text.count == symbol.count + 2 || VoicegroupSource.isSpace(text[text.startIndex + symbol.count + 2])
                {
                    return true
                }
            } else if Self.matches(text, "voice_group ") {
                var first = text.startIndex + 11
                while first < text.endIndex && VoicegroupSource.isSpace(text[first]) { first += 1 }
                var last = first
                while last < text.endIndex && !VoicegroupSource.isSpace(text[last]) && text[last] != UInt8(44) {
                    last += 1
                }
                let name = text[first..<last]
                // C file_declares_voice_group matches the unprefixed declaration (2143–2147).
                if name.count == symbol.count, Self.equalPrefix(name, symbol) { return true }
            }
        }
        return false
    }

    private func subdirectory(
        _ subdirectory: String, name: ArraySlice<UInt8>, layout: ProjectLayout
    ) -> VoicegroupLocation? {
        for directory in layout.voicegroupDirectories {
            if let found = file(directory: directory, name: name, prefix: subdirectory + "/") { return found }
        }
        for directory in layout.voicegroupDirectories where Self.basename(directory) == subdirectory {
            if let found = file(directory: directory, name: name) { return found }
        }
        return nil
    }

    private func file(directory: String, name: ArraySlice<UInt8>, prefix: String = "") -> VoicegroupLocation? {
        let directoryBytes = directory.utf8
        let directorySpan = directoryBytes.span
        let prefixBytes = prefix.utf8
        let prefixSpan = prefixBytes.span
        for suffixIndex in 0..<2 {
            let suffix = suffixIndex == 0 ? ".inc" : ".s"
            let suffixBytes = suffix.utf8
            let suffixSpan = suffixBytes.span
            let count = directorySpan.count + 1 + prefixSpan.count + name.count + suffixSpan.count
            guard count < 512 else { continue }
            var storage = InlineArray<512, UInt8>(repeating: 0)
            do {
                var path = storage.mutableSpan
                let symbol = name.span
                var index = 0
                for offset in 0..<directorySpan.count { path[index] = directorySpan[offset]; index += 1 }
                path[index] = 47; index += 1
                for offset in 0..<prefixSpan.count { path[index] = prefixSpan[offset]; index += 1 }
                for offset in 0..<symbol.count {
                    let byte = symbol[offset]
                    path[index] = byte == 92 ? 47 : byte; index += 1
                }
                for offset in 0..<suffixSpan.count { path[index] = suffixSpan[offset]; index += 1 }
            }
            let bytes = storage.span
            // POSIX access borrows the bounded, NUL-terminated path only for the syscall.
            let exists = bytes.withUnsafeBufferPointer {
                guard let base = $0.baseAddress else { preconditionFailure("Inline path is nonempty") }
                return access(UnsafeRawPointer(base).assumingMemoryBound(to: CChar.self), F_OK) == 0
            }
            if exists {
                return VoicegroupLocation(filePath: AsmLine.text(bytes.extracting(0..<count)), sectionLabel: "")
            }
        }
        return nil
    }

    private static func subgroupName(
        _ symbol: ArraySlice<UInt8>, infix: String, preserveTail: Bool
    ) -> ArraySlice<UInt8>? {
        let markerBytes = infix.utf8
        let marker = markerBytes.span
        let length = marker.count
        guard symbol.count >= length else { return nil }
        for index in symbol.startIndex...(symbol.endIndex - length) {
            var offset = 0
            while offset < length && symbol[index + offset] == marker[offset] { offset += 1 }
            guard offset == length else { continue }
            guard index > symbol.startIndex else { return nil }
            let head = symbol[..<index]
            if !preserveTail { return head.count < 256 ? head : nil }
            let tail = symbol[(index + length)...]
            if tail.isEmpty { return head.count < 256 ? head : nil }
            guard head.count + tail.count < 256 else { return nil }
            return (Array(head) + tail)[...]
        }
        return nil
    }

    private static func matches(_ bytes: ArraySlice<UInt8>, _ prefix: String) -> Bool {
        let prefixBytes = prefix.utf8
        let literal = prefixBytes.span
        guard bytes.count >= literal.count else { return false }
        var index = 0
        while index < literal.count {
            guard bytes[bytes.startIndex + index] == literal[index] else { return false }
            index += 1
        }
        return true
    }

    private static func equalPrefix(_ bytes: ArraySlice<UInt8>, _ prefix: ArraySlice<UInt8>) -> Bool {
        guard bytes.count >= prefix.count else { return false }
        var index = 0
        while index < prefix.count {
            guard bytes[bytes.startIndex + index] == prefix[prefix.startIndex + index] else { return false }
            index += 1
        }
        return true
    }

    private static func basename(_ path: String) -> String {
        guard let separator = path.lastIndex(where: { $0 == "/" || $0 == "\\" }) else { return path }
        return String(path[path.index(after: separator)...])
    }
}
