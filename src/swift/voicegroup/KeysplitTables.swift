import Foundation

public struct KeysplitParseError: Error, Equatable {
    public let file: String
    public let line: Int
    public let reason: String
}

public struct KeysplitTable: Equatable, Sendable {
    public let name: String
    public let startingNote: Int
    public let maxNote: Int
    public let table: [UInt8]
}

public struct KeysplitTables: Sendable {
    public let tables: [KeysplitTable]

    private static let macroPrefix = Array("keysplit ".utf8)
    private static let setPrefix = Array(".set ".utf8)
    private static let splitPrefix = Array("split ".utf8)
    private static let bytesPrefix = Array(".byte ".utf8)

    /// Returns the first table with the stored name.
    public func table(named: String) -> KeysplitTable? {
        tables.first { $0.name == named }
    }

    /// Parses files in order, preserving duplicate definitions.
    /// - Throws: `KeysplitParseError` for invalid lines or unreadable files.
    public static func parse(files: [String]) throws -> KeysplitTables {
        var tables: [KeysplitTable] = []
        for file in files {
            guard let lines = AsmLine.lines(file) else {
                throw KeysplitParseError(file: file, line: 0, reason: "Cannot read file")
            }
            var current: KeysplitDefinition?
            for (offset, raw) in lines.enumerated() {
                var cursor = KeysplitCursor(AsmLine.content(raw))
                let error = KeysplitParseError(file: file, line: offset + 1, reason: "Invalid keysplit directive")
                let macro = cursor.line.consume(macroPrefix)
                let set = !macro && cursor.line.consume(setPrefix)
                if macro || set {
                    guard let rawName = cursor.line.until(44) else { throw error }
                    let name = AsmLine.trimmed(rawName)
                    guard !name.isEmpty, name.count < (macro ? 247 : 256) else { throw error }
                    if set {
                        cursor.skipHorizontalSpace()
                        guard cursor.line.consume(46) else { throw error }
                        cursor.skipHorizontalSpace()
                        guard cursor.line.consume(45) else { throw error }
                    }
                    guard let start = cursor.integer(), (0...127).contains(start), cursor.finished else { throw error }
                    if let current { tables.append(current.value) }
                    current = KeysplitDefinition(name: (macro ? "keysplit_" : "") + AsmLine.text(name), start: start)
                } else if cursor.line.consume(splitPrefix) {
                    guard var definition = current else { continue }
                    current = nil
                    defer { current = definition }
                    guard let index = cursor.integer() else { throw error }
                    cursor.skipHorizontalSpace()
                    guard cursor.line.consume(44), let end = cursor.integer(), cursor.finished,
                        (0...127).contains(index), (0...128).contains(end),
                        end >= definition.lastNote
                    else { throw error }
                    for note in definition.lastNote..<end { definition.table[note] = UInt8(index) }
                    definition.lastNote = end
                    definition.maxNote = max(definition.maxNote, end)
                } else if cursor.line.consume(bytesPrefix) {
                    guard var definition = current else { continue }
                    current = nil
                    defer { current = definition }
                    while true {
                        cursor.skipHorizontalSpace()
                        if cursor.line.consume(44) { continue }
                        if cursor.finished { break }
                        guard let value = cursor.integer(), (0...127).contains(value),
                            definition.lastNote < 128
                        else { throw error }
                        let note = definition.lastNote
                        definition.table[note] = UInt8(value)
                        definition.maxNote = max(definition.maxNote, note)
                        definition.lastNote += 1
                    }
                }
            }
            if let current { tables.append(current.value) }
        }
        return KeysplitTables(tables: tables)
    }
}

private struct KeysplitDefinition {
    let name: String
    let start: Int
    var lastNote: Int
    var maxNote = 0
    var table = [UInt8](repeating: 0, count: 128)

    init(name: String, start: Int) {
        self.name = name
        self.start = start
        lastNote = start
    }

    var value: KeysplitTable {
        KeysplitTable(name: name, startingNote: start, maxNote: maxNote, table: table)
    }
}

private struct KeysplitCursor {
    var line: AsmLine

    init(_ bytes: AsmLine.Bytes) { line = AsmLine(bytes) }

    mutating func skipHorizontalSpace() {
        while line.consume(32) || line.consume(9) {}
    }

    var finished: Bool {
        mutating get {
            skipHorizontalSpace()
            return line.position == line.bytes.endIndex
        }
    }

    mutating func integer() -> Int? {
        line.skipSpaces()
        let negative = line.consume(45)
        if !negative { _ = line.consume(43) }
        var radix = 10
        var digits = 0
        var value = 0
        if line.consume(48) {
            radix = 8
            digits = 1
            let p = line.position
            if p + 1 < line.bytes.endIndex,
                line.bytes[p] == 120 || line.bytes[p] == 88,
                let digit = Self.digit(line.bytes[p + 1]), digit < 16
            {
                _ = line.consume(line.bytes[p])
                radix = 16
                digits = 0
            }
        }
        while line.position < line.bytes.endIndex,
            let digit = Self.digit(line.bytes[line.position]), digit < radix
        {
            guard value <= (2_147_483_648 - digit) / radix else { return nil }
            value = value * radix + digit
            _ = line.consume(line.bytes[line.position])
            digits += 1
        }
        guard digits > 0, negative || value <= 2_147_483_647 else { return nil }
        return negative ? -value : value
    }

    private static func digit(_ byte: UInt8) -> Int? {
        switch byte {
        case 48...57: Int(byte - 48)
        case 65...70: Int(byte - 65) + 10
        case 97...102: Int(byte - 97) + 10
        default: nil
        }
    }
}
