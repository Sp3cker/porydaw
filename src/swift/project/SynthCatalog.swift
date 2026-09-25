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
    static let incbinDirective = Array(".incbin".utf8)
    static let macroDirective = Array(".macro".utf8)
    static let synthMacroPrefix = Array("set_synth_".utf8)
    static let voiceGroup = Array("voice_group".utf8)
    static let voicegroupPrefix = Array("voicegroup".utf8)
    static let keysplit = Array("voice_keysplit".utf8)
    static let drumkit = Array("voice_keysplit_all".utf8)
    static let doubleColon = Array("::".utf8)
    static let cries = Array("cries/".utf8)
    static let voiceMacros: [(type: VgMacro, word: [UInt8], spaced: Bool)] = [
        (.directSoundNoResample, Array("voice_directsound_no_resample".utf8), true),
        (.directSoundAlt, Array("voice_directsound_alt".utf8), true),
        (.directSound, Array("voice_directsound".utf8), true),
        (.square1Alt, Array("voice_square_1_alt".utf8), true), (.square1, Array("voice_square_1".utf8), true),
        (.square2Alt, Array("voice_square_2_alt".utf8), true), (.square2, Array("voice_square_2".utf8), true),
        (.progWaveAlt, Array("voice_programmable_wave_alt".utf8), false),
        (.progWave, Array("voice_programmable_wave".utf8), false),
        (.noiseAlt, Array("voice_noise_alt".utf8), true), (.noise, Array("voice_noise".utf8), true),
    ]

    static func label(_ line: AsmLine.Bytes) -> String? {
        var cursor = AsmLine(line)
        guard let name = cursor.word(), cursor.consume(UInt8(58)) else { return nil }
        return AsmLine.text(name)
    }

    static func incbin(_ line: AsmLine.Bytes) -> AsmLine.Bytes? {
        var cursor = AsmLine(line)
        cursor.skipSpaces()
        guard cursor.consume(incbinDirective), cursor.skipSpaces(), cursor.consume(UInt8(34)),
              let binary = cursor.until(34), !binary.isEmpty else { return nil }
        return binary
    }

    static func synthMacroWord(_ line: AsmLine.Bytes) -> String? {
        var cursor = AsmLine(line)
        cursor.skipSpaces()
        guard cursor.consume(macroDirective), cursor.skipSpaces(), let word = cursor.word(),
              word.count > synthMacroPrefix.count, AsmLine.hasPrefix(word, synthMacroPrefix) else { return nil }
        return AsmLine.text(word)
    }

    static func decimal(_ field: AsmLine.Bytes) -> Int? {
        let number = AsmLine.trimmed(field)
        guard !number.isEmpty else { return nil }
        let first = number[number.startIndex]
        let negative = first == 45
        var index = negative || first == 43 ? number.startIndex + 1 : number.startIndex
        guard index < number.endIndex else { return nil }
        var value = 0
        var overflowed = false
        while index < number.endIndex {
            let digit = number[index]
            guard digit >= 48 && digit <= 57 else { return nil }
            let step = Int(digit - 48)
            let (scaled, scaleOverflow) = value.multipliedReportingOverflow(by: 10)
            let (next, stepOverflow) = negative
                ? scaled.subtractingReportingOverflow(step) : scaled.addingReportingOverflow(step)
            overflowed = overflowed || scaleOverflow || stepOverflow
            value = next
            index += 1
        }
        return overflowed ? 0 : value
    }

    static func voiceMacro(_ text: AsmLine.Bytes) -> (type: VgMacro, arguments: AsmLine.Bytes)? {
        var index = 0
        while index < voiceMacros.count {
            let candidate = voiceMacros[index]
            if AsmLine.hasPrefix(text, candidate.word) {
                let next = text.startIndex + candidate.word.count
                if !candidate.spaced || (next < text.endIndex && text[next] == 32) {
                    return (candidate.type, text[next...])
                }
            }
            index += 1
        }
        return nil
    }

    static func voiceFields(_ arguments: AsmLine.Bytes, count expected: Int)
        -> (symbol: AsmLine.Bytes, attack: Int, decay: Int, sustain: Int, release: Int)? {
        var commas = 0
        var index = arguments.startIndex
        while index < arguments.endIndex {
            if arguments[index] == 44 { commas += 1 }
            index += 1
        }
        guard commas + 1 == expected else { return nil }
        var symbol = arguments[arguments.startIndex..<arguments.startIndex]
        var envelope = (0, 0, 0, 0)
        var field = 0
        var start = arguments.startIndex
        index = arguments.startIndex
        while index <= arguments.endIndex {
            if index == arguments.endIndex || arguments[index] == 44 {
                let value = arguments[start..<index]
                if field == 2 { symbol = AsmLine.trimmed(value) }
                let slot = field - (expected - 4)
                if slot >= 0 {
                    guard let number = decimal(value) else { return nil }
                    switch slot {
                    case 0: envelope.0 = number
                    case 1: envelope.1 = number
                    case 2: envelope.2 = number
                    default: envelope.3 = number
                    }
                }
                field += 1
                start = index + 1
            }
            index += 1
        }
        return (symbol, envelope.0, envelope.1, envelope.2, envelope.3)
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
            guard let lines = AsmLine.lines(path) else { continue }
            var samplePending: String?
            var synthPending: String?
            for raw in lines {
                if let name = label(raw) {
                    if let samplePending { samples.append(samplePending) }
                    samplePending = name
                } else if let binary = incbin(raw), let symbol = samplePending {
                    if !AsmLine.contains(binary, cries) { samples.append(symbol) }
                    samplePending = nil
                }
                let text = AsmLine.content(raw)
                if let name = label(text) {
                    synthPending = name
                } else if synthPending != nil && AsmLine.contains(text, incbinDirective) {
                    synthPending = nil
                } else if let symbol = synthPending, let descriptor = synthDescriptor(AsmLine.text(text)) {
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
            guard let lines = AsmLine.lines(path) else { continue }
            for line in lines {
                guard let word = synthMacroWord(line), seen.insert(word).inserted else { continue }
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
        for path in voicegroupFiles(root) {
            guard let lines = AsmLine.lines(path) else { continue }
            for raw in lines {
                var cursor = AsmLine(raw)
                cursor.skipSpaces()
                if let head = cursor.word() {
                    if AsmLine.equals(head, voiceGroup) {
                        if cursor.skipSpaces(), let name = cursor.word() {
                            groups.insert("voicegroup_" + AsmLine.text(name))
                        }
                    } else if head.count > voicegroupPrefix.count, AsmLine.hasPrefix(head, voicegroupPrefix),
                              cursor.consume(doubleColon) {
                        groups.insert(AsmLine.text(head))
                    } else if AsmLine.equals(head, keysplit) {
                        if cursor.skipSpaces(), let symbol = cursor.word() {
                            cursor.skipSpaces()
                            if cursor.consume(UInt8(44)) {
                                cursor.skipSpaces()
                                if let table = cursor.word() {
                                    let key = AsmLine.text(symbol)
                                    if pairs[key] == nil { pairs[key] = AsmLine.text(table) }
                                }
                            }
                        }
                    } else if AsmLine.equals(head, drumkit) {
                        if cursor.skipSpaces(), let name = cursor.word() { drums.insert(AsmLine.text(name)) }
                    }
                }
                guard let (type, arguments) = voiceMacro(AsmLine.content(raw)),
                      let fields = voiceFields(arguments,
                                               count: type == .square1 || type == .square1Alt ? 8 : 7)
                else { continue }
                let cgb = vgMacroIsCgb(type)
                let attack = cgb ? fields.attack & 7 : fields.attack & 255
                let decay = cgb ? fields.decay & 7 : fields.decay & 255
                let sustain = cgb ? fields.sustain & 15 : fields.sustain & 255
                let release = cgb ? fields.release & 7 : fields.release & 255
                guard release != 0, cgb || attack != 0 else { continue }
                let code = UInt32(attack) << 24 | UInt32(decay) << 16 |
                    UInt32(sustain) << 8 | UInt32(release)
                families[vgAdsrFamily(type), default: [:]][code, default: 0] += 1
                if vgMacroHasSymbol(type), !fields.symbol.isEmpty {
                    symbols[AsmLine.text(fields.symbol), default: [:]][code, default: 0] += 1
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
        guard let lines = AsmLine.lines("\(projectRoot)/sound/programmable_wave_data.inc") else { return [] }
        var symbols: [String] = []
        var pending: String?
        for line in lines {
            if let label = CatalogLines.label(line) {
                if let pending { symbols.append(pending) }
                pending = label
            } else if let binary = CatalogLines.incbin(line), let symbol = pending {
                if !AsmLine.contains(binary, CatalogLines.cries) { symbols.append(symbol) }
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
