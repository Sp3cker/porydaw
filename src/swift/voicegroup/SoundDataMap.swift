import Foundation

#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

public enum SoundDataEntry: Equatable, Sendable {
    case sample(relativePath: String)
    case synth([UInt8])
}

public enum SoundDataMapError: Error, Equatable, Sendable {
    case labelTooLong(path: String)
}

/// First definition wins, including sample/synth collisions (voicegroup_loader.c:789–815).
public struct SoundDataMap: Sendable {
    public var entries: [String: SoundDataEntry]

    /// Parses in file order; unreadable files and oversized labels fail the map load.
    public static func parse(files: [String]) throws -> SoundDataMap {
        SoundDataMap(entries: try SoundMapParser.parse(files: files, synths: true))
    }

    public subscript(symbol: String) -> SoundDataEntry? { entries[symbol] }
}

/// First definition wins, as in voicegroup_loader.c:789–799.
public struct ProgWaveMap: Sendable {
    public var entries: [String: String]

    /// Parses labels and incbins without consuming labels on synth directives.
    public static func parse(files: [String]) throws -> ProgWaveMap {
        let parsed = try SoundMapParser.parse(files: files, synths: false)
        var entries: [String: String] = [:]
        entries.reserveCapacity(parsed.count)
        for (symbol, entry) in parsed {
            if case .sample(let path) = entry { entries[symbol] = path }
        }
        return ProgWaveMap(entries: entries)
    }

    public subscript(symbol: String) -> String? { entries[symbol] }
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

    static func parse(files: [String], synths: Bool) throws -> [String: SoundDataEntry] {
        var entries: [String: SoundDataEntry] = [:]
        for path in files {
            guard let lines = AsmLine.lines(path) else { throw ProjectFileStoreError.cannotRead(path: path) }
            var pending: String?
            for raw in lines {
                // fgets uses MAX_LINE=1024; oversized physical lines are separate parser chunks.
                var start = raw.startIndex
                repeat {
                    let end = min(start + 1023, raw.endIndex)
                    let line = AsmLine.content(raw[start..<end])
                    var cursor = AsmLine(line)
                    if let name = cursor.word(), cursor.consume(UInt8(58)) {
                        guard name.count < 256 else { throw SoundDataMapError.labelTooLong(path: path) }
                        pending = AsmLine.text(name)
                    } else if let symbol = pending {
                        if AsmLine.contains(line, incbin) {
                            var quotes = AsmLine(line)
                            if quotes.until(34) != nil, let value = quotes.until(34), entries[symbol] == nil {
                                entries[symbol] = .sample(relativePath: AsmLine.text(value.prefix(511)))
                            }
                            pending = nil
                        } else if synths, let descriptor = synth(line) {
                            if entries[symbol] == nil { entries[symbol] = .synth(descriptor) }
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
                // C strtoul supplies exact base-0, sign, overflow and no-progress semantics.
                var parameters = Array(line[index...])
                parameters.append(0)
                parameters.withUnsafeBufferPointer { buffer in
                    guard let address = buffer.baseAddress else {
                        preconditionFailure("NUL-terminated parameters are nonempty")
                    }
                    address.withMemoryRebound(to: CChar.self, capacity: buffer.count) { base in
                        var position = base
                        for parameter in 2..<6 {
                            while position.pointee == 32 || position.pointee == 9 || position.pointee == 44 {
                                position += 1
                            }
                            if position.pointee == 0 { break }
                            var end: UnsafeMutablePointer<CChar>?
                            result[parameter] = UInt8(truncatingIfNeeded: strtoul(position, &end, 0))
                            if let end { position = UnsafePointer(end) }
                        }
                    }
                }
            }
            return result
        }
        return nil
    }
}
