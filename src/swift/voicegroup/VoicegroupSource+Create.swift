import Foundation

/// Refusal from the per-file voicegroup writer. Refusal paths write nothing.
public struct VoicegroupCreateError: Error, LocalizedError {
    let message: String

    public var errorDescription: String? { message }
}

extension VoicegroupSource {
    /// Writes `sound/voicegroups/<name>.inc`, copying the source file's voice
    /// lines or the 128-line dummy template, in the siblings' header style.
    public static func createVoicegroup(
        projectRoot: String, name: String,
        copyFromFile: String, copySectionLabel: String
    ) throws {
        let dir = projectRoot + "/sound/voicegroups"
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir),
            isDir.boolValue
        else {
            throw VoicegroupCreateError(message: "sound/voicegroups/ does not exist in this project.")
        }
        let target = dir + "/" + name + ".inc"
        guard !ProjectFileStore.exists(target) else {
            throw VoicegroupCreateError(message: "\(target) already exists.")
        }
        let style = siblingHeaderStyle(dir: dir)
        let body: [Data]
        if copyFromFile.isEmpty {
            body = [Data](repeating: Data("\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 0".utf8), count: 128)
        } else {
            let bytes: Data
            do {
                bytes = try ProjectFileStore.read(copyFromFile)
            } catch {
                throw VoicegroupCreateError(message: "Cannot read \(copyFromFile)")
            }
            body = copiedVoicegroupLines(bytes, copySectionLabel: copySectionLabel)
            guard !body.isEmpty else {
                throw VoicegroupCreateError(message: "No voice lines found to copy in \(copyFromFile)")
            }
        }
        var lines: [Data] = []
        if style.labelStyle {
            if style.alignBeforeLabel { lines.append(Data("\t.align 2".utf8)) }
            lines.append(Data("voicegroup_\(name)::".utf8))
        } else {
            lines.append(Data("voice_group \(name)".utf8))
        }
        lines += body
        let eol: Data = style.crlf ? Data([13, 10]) : Data([10])
        var out = Data()
        for line in lines {
            out += line
            out += eol
        }
        do {
            try ProjectFileStore.write(target, data: out)
        } catch {
            throw VoicegroupCreateError(message: "Cannot write \(target)")
        }
    }

    /// Inserts the hub include after the last `.include`, preserving indent,
    /// CRLF and the trailing newline. A missing hub is a success no-op.
    public static func appendIncludeLine(projectRoot: String, name: String) throws {
        let hub = projectRoot + "/sound/voice_groups.inc"
        guard ProjectFileStore.exists(hub) else { return }
        let content: Data
        do {
            content = try ProjectFileStore.read(hub)
        } catch {
            throw VoicegroupCreateError(message: "Cannot read \(hub)")
        }
        let split = ProjectFileStore.splitLines(content)
        var lines = split.lines
        var lastInclude = -1
        var indent = Data()
        for (index, raw) in lines.enumerated() {
            let text = String(decoding: raw.last == 13 ? raw.dropLast() : raw[...], as: UTF8.self)
                .trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix(".include") else { continue }
            lastInclude = index
            indent = leadingWhitespace(raw)
        }
        var newLine = indent + Data(".include \"sound/voicegroups/\(name).inc\"".utf8)
        if split.crlf { newLine.append(13) }
        lines.insert(newLine, at: lastInclude < 0 ? lines.count : lastInclude + 1)
        var joined = Data()
        for (index, line) in lines.enumerated() {
            if index > 0 { joined.append(10) }
            joined += line
        }
        if split.endsWithNewline, !lines.isEmpty { joined.append(10) }
        do {
            try ProjectFileStore.write(hub, data: joined)
        } catch {
            throw VoicegroupCreateError(message: "Cannot write \(hub)")
        }
    }
}

/// Detects the sibling header style from the first `*.inc` by name.
fileprivate func siblingHeaderStyle(dir: String) -> (labelStyle: Bool, alignBeforeLabel: Bool, crlf: Bool) {
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else {
        return (false, false, false)
    }
    let siblings = entries.filter { $0.hasSuffix(".inc") }.sorted()
    guard let first = siblings.first,
        let bytes = try? ProjectFileStore.read(dir + "/" + first)
    else {
        return (false, false, false)
    }
    let crlf = bytes.range(of: Data([13, 10])) != nil
    var alignBeforeLabel = false
    for raw in ProjectFileStore.splitLines(bytes).lines {
        let text = String(decoding: raw.last == 13 ? raw.dropLast() : raw[...], as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
        if text.hasPrefix(".align") { alignBeforeLabel = true }
        if text.range(of: #"^(voicegroup\w+)::"#, options: .regularExpression) != nil {
            return (true, alignBeforeLabel, crlf)
        }
        if text.hasPrefix("voice_group ") { break }
    }
    return (false, alignBeforeLabel, crlf)
}

/// The voice lines copied out of a source file: the whole first declared
/// group, or the labeled section ending at the next `::` or `.align`.
fileprivate func copiedVoicegroupLines(_ content: Data, copySectionLabel: String) -> [Data] {
    let decl = try? NSRegularExpression(pattern: #"^\s*(voice_group\s+\w+|voicegroup\w+::)"#)
    var body: [Data] = []
    var copying = false
    for raw in ProjectFileStore.splitLines(content).lines {
        let line = raw.last == 13 ? raw.dropLast() : raw[...]
        let text = String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        if !copying {
            if copySectionLabel.isEmpty {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                copying = decl?.firstMatch(in: text, range: range) != nil
            } else {
                copying = text.hasPrefix(copySectionLabel + "::")
            }
            continue
        }
        if !copySectionLabel.isEmpty {
            let hitsBoundary = text.contains("::") && !text.hasPrefix("::")
            if text.hasPrefix(".align") || hitsBoundary { break }
        }
        body.append(Data(line))
    }
    while let last = body.last,
        String(decoding: last, as: UTF8.self).trimmingCharacters(in: .whitespaces).isEmpty
    {
        body.removeLast()
    }
    return body
}

/// Leading spaces and tabs of a raw line, mirroring the fork's leadingWs.
fileprivate func leadingWhitespace(_ raw: Data) -> Data {
    var end = raw.startIndex
    while end < raw.endIndex, raw[end] == 32 || raw[end] == 9 {
        end = raw.index(after: end)
    }
    return Data(raw[..<end])
}
