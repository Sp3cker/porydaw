import Foundation

/// Synth definitions in sound-data file order and the assembler macros available to define more.
public struct VgSynthCatalog: Sendable {
    public var defs: [(symbol: String, descriptor: VgSynthDesc)]
    public var macroWords: [String]

    public init(defs: [(symbol: String, descriptor: VgSynthDesc)] = [], macroWords: [String] = []) {
        self.defs = defs
        self.macroWords = macroWords
    }

    public func available() -> Bool { !defs.isEmpty || !macroWords.isEmpty }
    public func creatable() -> Bool { !macroWords.isEmpty }
    public func find(_ symbol: String) -> VgSynthDesc? { defs.first { $0.symbol == symbol }?.descriptor }
    public func symbolFor(_ descriptor: VgSynthDesc) -> String {
        defs.first { $0.descriptor == descriptor }?.symbol ?? ""
    }
}

/// Four voicegroup datasets extracted together from a single read of each file.
public struct VgCatalogScan: Sendable {
    public var groupArgs: [String] = []
    public var keysplits: [(symbol: String, table: String)] = []
    public var drumkits: [String] = []
    public var typicalAdsr = VgAdsrDefaults()

    public init() {}
}

/// Sample symbols and synth definitions extracted from the same sound-data reads.
public struct VgDirectSoundScan: Sendable {
    public var directSound: [String] = []
    public var synths = VgSynthCatalog()

    public init() {}
}

private enum CatalogLines {
    static let label = regex(#"^(\w+)::?"#)
    static let incbin = regex(#"^\s*\.incbin\s+"([^"]+)""#)
    static let macro = regex(#"^\s*\.macro\s+(set_synth_\w+)"#)
    static let groupMacro = regex(#"^\s*voice_group\s+(\w+)"#)
    static let groupLabel = regex(#"^\s*(voicegroup\w+)::"#)
    static let keysplit = regex(#"^\s*voice_keysplit\s+(\w+)\s*,\s*(\w+)"#)
    static let drumkit = regex(#"^\s*voice_keysplit_all\s+(\w+)"#)

    static func regex(_ pattern: String) -> NSRegularExpression {
        guard let value = try? NSRegularExpression(pattern: pattern) else {
            preconditionFailure("Invalid catalog source pattern: \(pattern)")
        }
        return value
    }

    static func captures(_ expression: NSRegularExpression, in line: String) -> [String]? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = expression.firstMatch(in: line, range: range) else { return nil }
        return (1..<match.numberOfRanges).compactMap {
            Range(match.range(at: $0), in: line).map { String(line[$0]) }
        }
    }

    static func lines(_ bytes: Data) -> [String] {
        // Swift's Character split treats CRLF as one grapheme; split on the LF
        // scalar so CRLF files yield the same lines as the byte split upstream.
        String(decoding: bytes, as: UTF8.self).unicodeScalars
            .split(separator: Unicode.Scalar(10), omittingEmptySubsequences: false)
            .map { String(String.UnicodeScalarView($0)) }
    }

    static func content(_ line: String) -> String {
        var end = line.endIndex
        if let at = line.firstIndex(of: "@") { end = min(end, at) }
        if let comment = line.range(of: "//") { end = min(end, comment.lowerBound) }
        return String(line[..<end].trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func readLines(_ path: String) -> [String]? {
        guard let data = try? ProjectFileStore.read(path) else { return nil }
        return lines(data)
    }

    static func files(_ directory: String, recursive: Bool) -> [String] {
        if recursive {
            return (try? ProjectFileStore.listRecursive(url: URL(filePath: directory), ext: ".inc")) ?? []
        }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: URL(filePath: directory), includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return entries.filter {
            $0.lastPathComponent.hasSuffix(".inc") &&
                (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.map(\.path)
    }

    static func voicegroupFiles(_ root: String) -> [String] {
        let indices = ["\(root)/sound/voice_groups.inc", "\(root)/sound/voicegroups.inc"]
        return indices.filter(ProjectFileStore.exists) + files("\(root)/sound/voicegroups", recursive: true)
    }

    static func synthDescriptor(_ content: String) -> VgSynthDesc? {
        let words: [(String, Int, Bool)] = [
            ("set_synth_custom", 0, true), ("set_synth_pulse", 0, true),
            ("set_synth_25", 1, false), ("set_synth_saw", 1, false),
            ("set_synth_50", 2, false), ("set_synth_triangle", 2, false),
        ]
        for (word, waveform, hasParams) in words where content.hasPrefix(word) {
            let suffix = content.dropFirst(word.count)
            guard suffix.isEmpty || suffix.first == " " || suffix.first == "\t" else { continue }
            if !hasParams { return VgSynthDesc(waveform: waveform, baseDuty: 0) }
            var fields = [Int](repeating: 0, count: 4)
            var remaining = suffix[...]
            for index in fields.indices {
                remaining = remaining.drop(while: { $0 == " " || $0 == "\t" || $0 == "," })
                if remaining.isEmpty { break }
                let negative = remaining.first == "-"
                let signed = negative || remaining.first == "+"
                let unsigned = remaining.dropFirst(signed ? 1 : 0)
                let hex = unsigned.hasPrefix("0x") || unsigned.hasPrefix("0X")
                let octal = !hex && unsigned.first == "0"
                let digits = unsigned.dropFirst(hex ? 2 : 0)
                    .prefix { ("0"..."9").contains($0) || (hex && ("a"..."f").contains($0.lowercased())) }
                let radix = hex ? 16 : octal ? 8 : 10
                let validDigits = octal && !hex ? digits.prefix { ("0"..."7").contains($0) } : digits
                if validDigits.isEmpty { break }
                let magnitude = UInt64(validDigits, radix: radix) ?? UInt64.max
                fields[index] = Int(UInt8(truncatingIfNeeded: negative ? 0 &- magnitude : magnitude))
                remaining = remaining.dropFirst((signed ? 1 : 0) + (hex ? 2 : 0) + validDigits.count)
            }
            return VgSynthDesc(waveform: waveform, baseDuty: fields[0], dutyStep: fields[1],
                               modDepth: fields[2], phase: fields[3])
        }
        return nil
    }

    static func scanSoundData(_ root: String) -> VgDirectSoundScan {
        var samples: [String] = []
        var result = VgDirectSoundScan()
        for path in ["\(root)/sound/direct_sound_data.inc", "\(root)/sound/direct_sound_synth_data.inc"] {
            guard let lines = readLines(path) else { continue }
            var samplePending: String?
            var synthPending: String?
            for raw in lines {
                let line = raw
                if let label = captures(label, in: line)?.first {
                    if let samplePending { samples.append(samplePending) }
                    samplePending = label
                } else if let incbin = captures(incbin, in: line)?.first, let symbol = samplePending {
                    if !incbin.contains("cries/") { samples.append(symbol) }
                    samplePending = nil
                }
                let text = content(raw)
                if let label = captures(label, in: text)?.first {
                    synthPending = label
                } else if synthPending != nil && text.contains(".incbin") {
                    synthPending = nil
                } else if let symbol = synthPending, let descriptor = synthDescriptor(text) {
                    result.synths.defs.append((symbol, descriptor))
                    synthPending = nil
                }
            }
            if let samplePending { samples.append(samplePending) }
        }
        let synthNames = Set(result.synths.defs.map(\.symbol))
        let sorted = Set(samples).sorted()
        result.directSound = sorted.filter { !synthNames.contains($0) && !$0.contains("Phoneme") } +
            sorted.filter { !synthNames.contains($0) && $0.contains("Phoneme") }
        var seen: Set<String> = []
        for path in files("\(root)/asm/macros", recursive: false) {
            guard let lines = readLines(path) else { continue }
            for line in lines {
                guard let word = captures(macro, in: String(line))?.first, seen.insert(word).inserted else { continue }
                result.synths.macroWords.append(word)
            }
        }
        return result
    }

    static func scanVoicegroups(_ root: String) -> VgCatalogScan {
        var result = VgCatalogScan()
        var groups: Set<String> = []
        var pairs: [String: String] = [:]
        var drums: Set<String> = []
        var families: [Int: [UInt32: Int]] = [:]
        var symbols: [String: [UInt32: Int]] = [:]
        let macros: [(VgMacro, String, Bool)] = [
            (.directSoundNoResample, "voice_directsound_no_resample", true),
            (.directSoundAlt, "voice_directsound_alt", true), (.directSound, "voice_directsound", true),
            (.square1Alt, "voice_square_1_alt", true), (.square1, "voice_square_1", true),
            (.square2Alt, "voice_square_2_alt", true), (.square2, "voice_square_2", true),
            (.progWaveAlt, "voice_programmable_wave_alt", false),
            (.progWave, "voice_programmable_wave", false),
            (.noiseAlt, "voice_noise_alt", true), (.noise, "voice_noise", true),
        ]
        for path in voicegroupFiles(root) {
            guard let lines = readLines(path) else { continue }
            for raw in lines {
                let line = String(raw)
                if let name = captures(groupMacro, in: line)?.first {
                    groups.insert("voicegroup_" + name)
                } else if let name = captures(groupLabel, in: line)?.first {
                    groups.insert(name)
                }
                if let pair = captures(keysplit, in: line), pairs[pair[0]] == nil {
                    pairs[pair[0]] = pair[1]
                }
                if let name = captures(drumkit, in: line)?.first { drums.insert(name) }
                let text = content(raw)
                guard let (type, word, _) = macros.first(where: { candidate in
                    text.hasPrefix(candidate.1) &&
                        (!candidate.2 || text.dropFirst(candidate.1.count).first == " ")
                }) else { continue }
                let args = text.dropFirst(word.count).split(separator: ",", omittingEmptySubsequences: false)
                let expected = type == .square1 || type == .square1Alt ? 8 : 7
                guard args.count == expected else { continue }
                let values = args.suffix(4).compactMap { arg -> Int? in
                    let number = arg.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !number.isEmpty else { return nil }
                    let digits = number.dropFirst(number.first == "-" || number.first == "+" ? 1 : 0)
                    guard !digits.isEmpty, digits.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
                    return Int(number) ?? 0 // QByteArray::toInt returns zero on overflow.
                }
                guard values.count == 4 else { continue }
                let cgb = vgMacroIsCgb(type)
                let attack = cgb ? values[0] & 7 : values[0] & 255
                let decay = cgb ? values[1] & 7 : values[1] & 255
                let sustain = cgb ? values[2] & 15 : values[2] & 255
                let release = cgb ? values[3] & 7 : values[3] & 255
                guard release != 0, cgb || attack != 0 else { continue }
                let code = UInt32(attack) << 24 | UInt32(decay) << 16 |
                    UInt32(sustain) << 8 | UInt32(release)
                families[vgAdsrFamily(type), default: [:]][code, default: 0] += 1
                if vgMacroHasSymbol(type) {
                    let symbol = args[2].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !symbol.isEmpty { symbols[symbol, default: [:]][code, default: 0] += 1 }
                }
            }
        }
        result.groupArgs = groups.map { String($0.dropFirst(10)) }.sorted()
        result.keysplits = pairs.keys.sorted().compactMap { key in
            pairs[key].map { (symbol: key, table: $0) }
        }
        result.drumkits = drums.sorted()
        func mode(_ counts: [UInt32: Int]) -> VgAdsr {
            let code = counts.max { lhs, rhs in
                lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
            }?.key ?? 0
            return VgAdsr(attack: Int(code >> 24), decay: Int((code >> 16) & 255),
                          sustain: Int((code >> 8) & 255), release: Int(code & 255))
        }
        for (family, counts) in families { result.typicalAdsr.byFamily[family] = mode(counts) }
        for (symbol, counts) in symbols { result.typicalAdsr.bySymbol[symbol] = mode(counts) }
        return result
    }
}

extension VoicegroupSource {
    public static func directSoundSymbols(_ projectRoot: String) -> [String] {
        CatalogLines.scanSoundData(projectRoot).directSound
    }

    public static func progWaveSymbols(_ projectRoot: String) -> [String] {
        guard let lines = CatalogLines.readLines("\(projectRoot)/sound/programmable_wave_data.inc") else { return [] }
        var symbols: [String] = []
        var pending: String?
        for line in lines {
            let text = String(line)
            if let label = CatalogLines.captures(CatalogLines.label, in: text)?.first {
                if let pending { symbols.append(pending) }
                pending = label
            } else if let incbin = CatalogLines.captures(CatalogLines.incbin, in: text)?.first,
                      let symbol = pending {
                if !incbin.contains("cries/") { symbols.append(symbol) }
                pending = nil
            }
        }
        if let pending { symbols.append(pending) }
        return Array(Set(symbols)).sorted()
    }

    public static func synthInstruments(_ projectRoot: String) -> VgSynthCatalog {
        CatalogLines.scanSoundData(projectRoot).synths
    }

    public static func keysplitInstruments(_ projectRoot: String) -> [(symbol: String, table: String)] {
        catalogScan(projectRoot).keysplits
    }

    public static func drumkitInstruments(_ projectRoot: String) -> [String] {
        catalogScan(projectRoot).drumkits
    }

    public static func typicalAdsr(_ projectRoot: String) -> VgAdsrDefaults {
        catalogScan(projectRoot).typicalAdsr
    }

    public static func catalogScan(_ projectRoot: String) -> VgCatalogScan {
        CatalogLines.scanVoicegroups(projectRoot)
    }

    public static func directSoundCatalog(_ projectRoot: String) -> VgDirectSoundScan {
        CatalogLines.scanSoundData(projectRoot)
    }
}
