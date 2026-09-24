import Foundation
import PorydawCore

/// Parses midi.cfg and updates song flags without rewriting unrelated file bytes.
public enum MidiCfg {
    /// Parses text-mode midi.cfg lines; the last definition of a label wins.
    public static func parse(_ bytes: Data) -> [String: SongConfig] {
        var configs: [String: SongConfig] = [:]
        for rawLine in ProjectFileStore.splitLines(bytes).lines {
            // QIODevice::Text removes a line's CR before QTextStream reads it.
            let line = rawLine.last == 13 ? rawLine.dropLast() : rawLine[...]
            var text = String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if let hash = text.firstIndex(of: "#") {
                text = String(text[..<hash]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let colon = text.firstIndex(of: ":"), colon != text.startIndex else { continue }
            var name = String(text[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
            if name.lowercased().hasSuffix(".mid") {
                name.removeLast(4)
            }
            let flags = text[text.index(after: colon)...]
                .split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            configs[name] = SongFlags.fromRaw(flags)
        }
        return configs
    }

    /// Changes only the first matching song line, retaining other lines and their line endings.
    public static func writeMidiCfgLine(midiDir: URL, label: String, flags: [String]) throws {
        let path = midiDir.appendingPathComponent("midi.cfg").path
        let content = FileManager.default.fileExists(atPath: path)
            ? try ProjectFileStore.read(path) : Data()
        let split = ProjectFileStore.splitLines(content)
        var lines = split.lines
        let fileName = label + ".mid"
        let flagBytes = Data(flags.joined(separator: " ").utf8)
        var replaced = false

        for index in lines.indices {
            let line = lines[index]
            let hadCr = line.last == 13
            let body = hadCr ? line.dropLast() : line[...]
            guard let colon = body.firstIndex(of: 58), colon != body.startIndex else { continue }
            let name = String(decoding: body[..<colon], as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard name == fileName else { continue }

            // Locate ASCII spaces in the original bytes so even non-UTF-8 name-column
            // bytes remain untouched; only the flag bytes are replaced.
            var flagStart = body.index(after: colon)
            while flagStart < body.endIndex && body[flagStart] == 32 {
                flagStart = body.index(after: flagStart)
            }
            var updated = Data(body[..<flagStart])
            updated.append(flagBytes)
            if hadCr { updated.append(13) }
            lines[index] = updated
            replaced = true
            break
        }
        if !replaced {
            var line = Data((fileName + ": ").utf8)
            line.append(flagBytes)
            if split.crlf { line.append(13) }
            lines.append(line)
        }

        var output = Data()
        for index in lines.indices {
            if index != lines.startIndex { output.append(10) }
            output.append(lines[index])
        }
        if split.endsWithNewline { output.append(10) }
        try ProjectFileStore.writeAtomic(path, data: output)
    }

    /// Uses songs.mk only when midi.cfg is absent and the project has a songs.mk file.
    public static func writeSongFlags(midiDir: URL, label: String, flags: [String]) throws {
        if !FileManager.default.fileExists(atPath: midiDir.appendingPathComponent("midi.cfg").path) {
            let root = midiDir.deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().standardizedFileURL
            let mkFile = SongsMk.path(root: root)
            if FileManager.default.fileExists(atPath: mkFile.path) {
                try SongsMk.writeRule(mkFile: mkFile, label: label, flags: flags)
                return
            }
        }
        try writeMidiCfgLine(midiDir: midiDir, label: label, flags: flags)
    }
}
