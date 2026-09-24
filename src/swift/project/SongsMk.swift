import Foundation

/// Reads and updates the songs.mk flag backend used by projects without midi.cfg.
public enum SongsMk {
    private static let variablePattern = regex(#"^([A-Za-z_][A-Za-z0-9_]*)\s*[:?+]?=\s*(.*)$"#)
    // ICU and Qt both recognize Unicode word characters in \w; their Unicode
    // property tables may differ. A dot or dash is never part of a rule label.
    private static let rulePattern = regex(#"^(?:\$\(MID_SUBDIR\)|sound/songs/midi)/(\w+)\.s\s*:"#)
    private static let referencePattern = regex(#"\$\(([A-Za-z_][A-Za-z0-9_]*)\)"#)

    /// Locates the flag backend under a project root.
    /// - Parameter root: The project directory.
    /// - Returns: The songs.mk file URL.
    public static func path(root: URL) -> URL {
        root.appendingPathComponent("songs.mk")
    }

    /// Parses recipe options, expanding assignments found before each recipe.
    /// - Parameter mkFile: The songs.mk file to read.
    /// - Returns: Flags by label, or an empty map if the file cannot be read.
    public static func parseFlags(mkFile: URL) -> [String: [String]] {
        guard let data = try? ProjectFileStore.read(mkFile.path) else { return [:] }
        var flagsByLabel: [String: [String]] = [:]
        var variables: [String: String] = [:]
        var pendingLabel: String?
        for raw in ProjectFileStore.splitLines(data).lines {
            let line = text(of: raw)
            if line.hasPrefix("\t") {
                if let label = pendingLabel, line.contains("$(MID)") {
                    flagsByLabel[label] = flagsFromRecipe(line, variables: variables)
                    pendingLabel = nil
                }
                continue
            }
            if let label = capture(1, in: line, pattern: rulePattern) {
                pendingLabel = label
                continue
            }
            pendingLabel = nil
            collectVariable(line, into: &variables)
        }
        return flagsByLabel
    }

    /// Changes the first matching rule, retaining the bytes of unrelated lines.
    /// - Parameters:
    ///   - mkFile: The existing songs.mk file.
    ///   - label: The song label to update or append.
    ///   - flags: The expanded option strings to write.
    /// - Throws: A project file error if songs.mk cannot be read or written.
    public static func writeRule(mkFile: URL, label: String, flags: [String]) throws {
        let split = ProjectFileStore.splitLines(try ProjectFileStore.read(mkFile.path))
        var lines = split.lines
        var variables: [String: String] = [:]
        for raw in lines {
            let line = text(of: raw)
            if !line.hasPrefix("\t") { collectVariable(line, into: &variables) }
        }

        let ruleIndex = lines.firstIndex { capture(1, in: text(of: $0), pattern: rulePattern) == label }
        var replaced = false
        if let ruleIndex {
            for index in (ruleIndex + 1)..<lines.count {
                let raw = lines[index]
                let line = text(of: raw)
                guard line.hasPrefix("\t") else { break }
                guard line.contains("$(MID)") else { continue }

                var existing: [String: (spelling: String, expanded: String)] = [:]
                for token in line.split(whereSeparator: \.isWhitespace) {
                    let spelling = String(token)
                    if let letter = flagLetter(spelling) {
                        existing[letter] = (spelling, expandVars(spelling, variables: variables))
                    }
                }
                let spelled = flags.map { flag -> String in
                    guard let letter = flagLetter(flag), let old = existing[letter],
                          old.expanded.compare(flag, options: .caseInsensitive) == .orderedSame
                    else { return flag }
                    return old.spelling
                }
                let prefix = line.range(of: "$@").map { String(line[..<$0.upperBound]) }
                    ?? "\t$(MID) $< $@"
                var updated = Data((prefix + (spelled.isEmpty ? "" : " " + spelled.joined(separator: " "))).utf8)
                if raw.last == 13 { updated.append(13) }
                lines[index] = updated
                replaced = true
                break
            }
        }
        if !replaced {
            let eol = split.crlf ? Data([13]) : Data()
            var recipe = Data(("\t$(MID) $< $@" + (flags.isEmpty ? "" : " " + flags.joined(separator: " "))).utf8)
            recipe.append(eol)
            if let ruleIndex {
                lines.insert(recipe, at: ruleIndex + 1)
            } else {
                if !lines.isEmpty && lines.last != eol { lines.append(eol) }
                var rule = Data("$(MID_SUBDIR)/\(label).s: %.s: %.mid".utf8)
                rule.append(eol)
                lines.append(rule)
                lines.append(recipe)
            }
        }

        var output = Data()
        for index in lines.indices {
            if index != lines.startIndex { output.append(10) }
            output.append(lines[index])
        }
        if split.endsWithNewline { output.append(10) }
        try ProjectFileStore.writeAtomic(mkFile.path, data: output)
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        do { return try NSRegularExpression(pattern: pattern) }
        catch { preconditionFailure("Invalid fixed songs.mk regex: \(error)") }
    }

    private static func text(of raw: Data) -> String {
        String(decoding: raw.last == 13 ? raw.dropLast() : raw[...], as: UTF8.self)
    }

    private static func capture(_ group: Int, in text: String, pattern: NSRegularExpression) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = pattern.firstMatch(in: text, range: range),
              let captured = Range(match.range(at: group), in: text) else { return nil }
        return String(text[captured])
    }

    private static func collectVariable(_ line: String, into variables: inout [String: String]) {
        let uncommented = line.prefix { $0 != "#" }
        let text = String(uncommented)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = variablePattern.firstMatch(in: text, range: range),
              let name = Range(match.range(at: 1), in: text),
              let value = Range(match.range(at: 2), in: text) else { return }
        variables[String(text[name])] = text[value].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func flagsFromRecipe(_ recipe: String, variables: [String: String]) -> [String] {
        recipe.split(whereSeparator: \.isWhitespace).filter { $0.hasPrefix("-") }
            .map { expandVars(String($0), variables: variables) }
    }

    private static func expandVars(_ value: String, variables: [String: String]) -> String {
        var text = value
        for _ in 0..<8 where text.contains("$") {
            let matches = referencePattern.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
            if matches.isEmpty { break }
            for match in matches.reversed() {
                guard let whole = Range(match.range, in: text),
                      let name = Range(match.range(at: 1), in: text) else { continue }
                text.replaceSubrange(whole, with: variables[String(text[name])] ?? "")
            }
        }
        return text
    }

    private static func flagLetter(_ flag: String) -> String? {
        guard flag.first == "-", let letter = flag.dropFirst().first else { return nil }
        return String(letter).uppercased()
    }
}
