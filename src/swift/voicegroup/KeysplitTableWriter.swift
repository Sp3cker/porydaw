import Foundation

public struct KeysplitWriteError: Error, Equatable {
    public let message: String
}

public enum KeysplitTableWriter {
    private static let macroPrefix = Array("keysplit ".utf8)
    private static let setPrefix = Array(".set ".utf8)
    private static let splitPrefix = Array("split ".utf8)
    private static let bytesPrefix = Array(".byte ".utf8)
    private static let alignPrefix = Array(".align ".utf8)

    /// Replaces a run-form definition in place, or appends one, preserving file style.
    /// - Throws: `KeysplitWriteError` naming an unreadable, invalid, or unwritable file.
    public static func replace(table: KeysplitTable, inFile path: String) throws(KeysplitWriteError) {
        let bytes: Data
        do {
            bytes = try ProjectFileStore.read(path)
        } catch {
            throw KeysplitWriteError(message: "Cannot read \(path)")
        }
        let output = try rendered(table: table, bytes: bytes, path: path)
        do {
            try ProjectFileStore.writeAtomic(path, data: output)
        } catch {
            throw KeysplitWriteError(message: "Cannot write \(path)")
        }
    }

    private static func rendered(table: KeysplitTable, bytes: Data, path: String) throws(KeysplitWriteError) -> Data {
        guard table.table.count == 128, (0..<128).contains(table.startingNote),
            (0...128).contains(table.maxNote),
            table.table.allSatisfy({ $0 < 128 })
        else {
            throw KeysplitWriteError(message: "Invalid keysplit table for \(path)")
        }
        let split = ProjectFileStore.splitLines(bytes)
        var lines = split.lines
        var definition: Int?
        var runLines: [Int] = []
        var headerIndent = Data()
        var runIndent = Data([9])
        var alignIndent = Data([9])
        for (index, raw) in lines.enumerated() {
            let content = AsmLine.content(Array(raw)[...])
            var cursor = AsmLine(content)
            let macro = cursor.consume(macroPrefix)
            let set = !macro && cursor.consume(setPrefix)
            if macro || set, let rawName = cursor.until(44) {
                if definition != nil { break }
                headerIndent = indentation(raw)
                let name = (macro ? "keysplit_" : "") + AsmLine.text(AsmLine.trimmed(rawName))
                if name == table.name { definition = index }
            } else if isRun(content) {
                runIndent = indentation(raw)
                if definition != nil { runLines.append(index) }
            } else if cursor.consume(alignPrefix) {
                alignIndent = indentation(raw)
            }
        }
        let base = table.name.hasPrefix("keysplit_") ? String(table.name.dropFirst(9)) : table.name
        var replacement = [headerIndent + Data("keysplit \(base), \(table.startingNote)".utf8)]
        var note = table.startingNote
        while note < table.maxNote {
            let value = table.table[note]
            var end = note + 1
            while end < table.maxNote, table.table[end] == value { end += 1 }
            replacement.append(runIndent + Data("split \(value), \(end)".utf8))
            note = end
        }
        if split.crlf {
            for index in replacement.indices { replacement[index].append(13) }
        }
        if let definition {
            for index in runLines.reversed() { lines.remove(at: index) }
            lines.replaceSubrange(definition...definition, with: replacement)
        } else {
            if split.crlf, !lines.isEmpty, lines.last?.last != 13 {
                lines[lines.count - 1].append(13)
            }
            var align = alignIndent + Data(".align 2".utf8)
            if split.crlf { align.append(13) }
            lines.append(align)
            lines.append(contentsOf: replacement)
        }
        if !split.endsWithNewline, split.crlf, lines.last?.last == 13 {
            lines[lines.count - 1].removeLast()
        }
        var output = Data()
        for (index, line) in lines.enumerated() {
            if index > 0 { output.append(10) }
            output.append(line)
        }
        if split.endsWithNewline, !lines.isEmpty { output.append(10) }
        return output
    }

    private static func isRun(_ content: AsmLine.Bytes) -> Bool {
        AsmLine.hasPrefix(content, splitPrefix) || AsmLine.hasPrefix(content, bytesPrefix)
    }

    private static func indentation(_ line: Data) -> Data {
        Data(line.prefix { $0 == 32 || $0 == 9 })
    }
}
