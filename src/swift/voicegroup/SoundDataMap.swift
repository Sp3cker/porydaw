import BinaryParsing
import Foundation

public enum SoundDataEntry: Equatable, Sendable {
    case sample(relativePath: String)
    case synth([UInt8])
}

public enum SoundDataMapError: Error, Equatable, Sendable {
    case labelTooLong(path: String)
}

/// First definition wins, including sample/synth collisions (voicegroup_loader.c:789–815).
public struct SoundDataMap: Sendable {
    public var entries: [SymbolKey: SoundDataEntry]

    /// Parses in file order; unreadable files and oversized labels fail the map load.
    public static func parse(files: [String]) throws -> SoundDataMap {
        SoundDataMap(entries: try SoundMapParser.parse(files: files, synths: true))
    }

    public subscript(symbol: ArraySlice<UInt8>) -> SoundDataEntry? { entries[SymbolKey(symbol)] }
}

/// First definition wins, as in voicegroup_loader.c:789–799.
public struct ProgWaveMap: Sendable {
    public var entries: [SymbolKey: String]

    /// Parses labels and incbins without consuming labels on synth directives.
    public static func parse(files: [String]) throws -> ProgWaveMap {
        let parsed = try SoundMapParser.parse(files: files, synths: false)
        var entries: [SymbolKey: String] = [:]
        entries.reserveCapacity(parsed.count)
        for (symbol, entry) in parsed {
            if case .sample(let path) = entry { entries[symbol] = path }
        }
        return ProgWaveMap(entries: entries)
    }

    public subscript(symbol: ArraySlice<UInt8>) -> String? { entries[SymbolKey(symbol)] }
}

private enum SoundMapParser {
    private static let incbin = Array(".incbin".utf8)
    private static let macros: [(name: [UInt8], type: UInt8, params: Bool)] = [
        (Array("set_synth_custom".utf8), 0, true),
        (Array("set_synth_pulse".utf8), 0, true),
        (Array("set_synth_25".utf8), 1, false),
        (Array("set_synth_saw".utf8), 1, false),
        (Array("set_synth_50".utf8), 2, false),
        (Array("set_synth_triangle".utf8), 2, false),
    ]

    static func parse(files: [String], synths: Bool) throws -> [SymbolKey: SoundDataEntry] {
        var entries: [SymbolKey: SoundDataEntry] = [:]
        for path in files {
            guard let lines = AsmLine.lines(path) else { throw ProjectFileStoreError.cannotRead(path: path) }
            var pending: ArraySlice<UInt8>?
            for raw in lines {
                // fgets uses MAX_LINE=1024; oversized physical lines are separate parser chunks.
                var start = raw.startIndex
                repeat {
                    let end = min(start + 1023, raw.endIndex)
                    let line = AsmLine.content(raw[start..<end])
                    var cursor = AsmLine(line)
                    if let name = cursor.word(), cursor.consume(UInt8(58)) {
                        guard name.count < 256 else { throw SoundDataMapError.labelTooLong(path: path) }
                        pending = name
                    } else if let symbol = pending {
                        if AsmLine.contains(line, incbin) {
                            var quotes = AsmLine(line)
                            if quotes.until(34) != nil, let value = quotes.until(34), entries[SymbolKey(symbol)] == nil
                            {
                                entries[SymbolKey(symbol)] = .sample(relativePath: AsmLine.text(value.prefix(511)))
                            }
                            pending = nil
                        } else if synths, let descriptor = synth(line) {
                            if entries[SymbolKey(symbol)] == nil { entries[SymbolKey(symbol)] = .synth(descriptor) }
                            pending = nil
                        }
                    }
                    start = end
                } while start < raw.endIndex
            }
        }
        return entries
    }

    private static func synth(_ line: AsmLine.Bytes) -> [UInt8]? {
        for macro in macros {
            guard AsmLine.hasPrefix(line, macro.name) else { continue }
            let index = line.startIndex + macro.name.count
            if index < line.endIndex, line[index] != 32, line[index] != 9 { continue }
            var result: [UInt8] = [0x80, macro.type, 0, 0, 0, 0]
            if macro.params {
                let parameters = line[index...]
                var cursor = ParserSpan(parameters.span.bytes)
                for parameter in 2..<6 {
                    while !cursor.isEmpty {
                        let byte = cursor.bytes.load(fromByteOffset: 0, as: UInt8.self)
                        guard byte == 32 || byte == 9 || byte == 44 else { break }
                        advance(&cursor, count: 1)
                    }
                    guard !cursor.isEmpty else { break }
                    result[parameter] = UInt8(truncatingIfNeeded: unsignedInteger(&cursor))
                }
            }
            return result
        }
        return nil
    }

    private static func unsignedInteger(_ cursor: inout ParserSpan) -> UInt64 {
        let source = cursor.bytes
        var index = 0
        while index < source.byteCount && VoicegroupSource.isSpace(source.load(fromByteOffset: index, as: UInt8.self)) {
            index += 1
        }
        guard index < source.byteCount else { return 0 }
        let sign = source.load(fromByteOffset: index, as: UInt8.self)
        let negative = sign == 45
        if negative || sign == 43 { index += 1 }
        func digit(_ index: Int) -> UInt64? {
            guard index < source.byteCount else { return nil }
            let byte = source.load(fromByteOffset: index, as: UInt8.self)
            if byte >= 48 && byte <= 57 { return UInt64(byte - 48) }
            if byte >= 65 && byte <= 70 { return UInt64(byte - 65) + 10 }
            if byte >= 97 && byte <= 102 { return UInt64(byte - 97) + 10 }
            return nil
        }
        var radix: UInt64 = 10
        if index < source.byteCount && source.load(fromByteOffset: index, as: UInt8.self) == 48 {
            radix = 8
            if index + 2 < source.byteCount {
                let x = source.load(fromByteOffset: index + 1, as: UInt8.self)
                if (x == 120 || x == 88), let value = digit(index + 2), value < 16 { radix = 16; index += 2 }
            }
        }
        let start = index
        var magnitude: UInt64 = 0
        var overflow = false
        while let value = digit(index), value < radix {
            if magnitude > (UInt64.max - value) / radix { overflow = true }
            if !overflow { magnitude = magnitude * radix + value }
            index += 1
        }
        guard index > start else { return 0 }
        advance(&cursor, count: index)
        if overflow { return UInt64.max }
        return negative ? 0 &- magnitude : magnitude
    }

    private static func advance(_ cursor: inout ParserSpan, count: Int) {
        for _ in 0..<count {
            do { _ = try UInt8(parsing: &cursor) } catch {
                preconditionFailure("Checked synth cursor unexpectedly ran out of bytes")
            }
        }
    }
}
