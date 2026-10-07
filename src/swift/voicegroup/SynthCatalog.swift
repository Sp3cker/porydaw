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
    static let keysplit = Array(VoiceMacroSpec.forMacro(.keysplit).word.utf8)
    static let drumkit = Array(VoiceMacroSpec.forMacro(.keysplitAll).word.utf8)
    static let doubleColon = Array("::".utf8)
    static let cries = Array("cries/".utf8)

    static func label(_ line: AsmLine.Bytes) -> String? {
        var cursor = AsmLine(line)
        guard let name = cursor.word(), cursor.consume(UInt8(58)) else { return nil }
        return AsmLine.text(name)
    }

    static func incbin(_ line: AsmLine.Bytes) -> AsmLine.Bytes? {
        var cursor = AsmLine(line)
        cursor.skipSpaces()
        guard cursor.consume(incbinDirective), cursor.skipSpaces(), cursor.consume(UInt8(34)),
            let binary = cursor.until(34), !binary.isEmpty
        else { return nil }
        return binary
    }

    static func synthMacroWord(_ line: AsmLine.Bytes) -> String? {
        var cursor = AsmLine(line)
        cursor.skipSpaces()
        guard cursor.consume(macroDirective), cursor.skipSpaces(), let word = cursor.word(),
            word.count > synthMacroPrefix.count, AsmLine.hasPrefix(word, synthMacroPrefix)
        else { return nil }
        return AsmLine.text(word)
    }

    static func files(_ directory: String, recursive: Bool) -> [String] {
        if recursive {
            return (try? ProjectFileStore.listRecursive(url: URL(filePath: directory), ext: ".inc")) ?? []
        }
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: URL(filePath: directory), includingPropertiesForKeys: [.isRegularFileKey])
        else { return [] }
        return entries.filter {
            $0.lastPathComponent.hasSuffix(".inc")
                && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.map(\.path)
    }

    static func voicegroupFiles(_ root: String) -> [String] {
        let indices = ["\(root)/sound/voice_groups.inc", "\(root)/sound/voicegroups.inc"]
        return indices.filter(ProjectFileStore.exists) + files("\(root)/sound/voicegroups", recursive: true).sorted()
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
            return VgSynthDesc(
                waveform: waveform, baseDuty: fields[0], dutyStep: fields[1],
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
            let lineSpan = lines.span
            for index in lineSpan.indices {
                let raw = lineSpan[index]
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
        result.directSound =
            sorted.filter { !synthNames.contains($0) && !$0.contains("Phoneme") }
            + sorted.filter { !synthNames.contains($0) && $0.contains("Phoneme") }
        var seen: Set<String> = []
        for path in files("\(root)/asm/macros", recursive: false) {
            guard let lines = AsmLine.lines(path) else { continue }
            let lineSpan = lines.span
            for index in lineSpan.indices {
                let line = lineSpan[index]
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
            guard let bytes = try? VoicegroupText.read(path) else { continue }
            var start = 0
            while start < bytes.count {
                var end = start
                while end < bytes.count && bytes[end] != 10 { end += 1 }
                let raw = bytes[start..<end]
                start = end + 1
                var cursor = AsmLine(raw)
                cursor.skipSpaces()
                if let head = cursor.word() {
                    if AsmLine.equals(head, voiceGroup) {
                        if cursor.skipSpaces(), let name = cursor.word() {
                            groups.insert("voicegroup_" + AsmLine.text(name))
                        }
                    } else if head.count > voicegroupPrefix.count, AsmLine.hasPrefix(head, voicegroupPrefix),
                        cursor.consume(doubleColon)
                    {
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
            }
            guard let text = try? VoicegroupText.parse(bytes: bytes) else { continue }
            for index in 0..<text.endIndex {
                guard let voice = text.voices[index] else { continue }
                if voice.type == vgMacroVoiceType(.keysplit) {
                    let symbol = AsmLine.text(voice.symbol)
                    if pairs[symbol] == nil { pairs[symbol] = AsmLine.text(voice.tableSymbol) }
                    continue
                }
                if voice.type == vgMacroVoiceType(.keysplitAll) {
                    drums.insert(AsmLine.text(voice.symbol))
                    continue
                }
                let family: Int
                switch voice.type & 7 {
                case 0: family = Int(VgMacro.directSound.rawValue)
                case 1: family = Int(VgMacro.square1.rawValue)
                case 2: family = Int(VgMacro.square2.rawValue)
                case 3: family = Int(VgMacro.progWave.rawValue)
                case 4: family = Int(VgMacro.noise.rawValue)
                default: continue
                }
                let cgb = family != Int(VgMacro.directSound.rawValue)
                guard voice.release != 0, cgb || voice.attack != 0 else { continue }
                let code =
                    UInt32(voice.attack) << 24 | UInt32(voice.decay) << 16
                    | UInt32(voice.sustain) << 8 | UInt32(voice.release)
                families[family, default: [:]][code, default: 0] += 1
                if !voice.symbol.isEmpty {
                    symbols[AsmLine.text(voice.symbol), default: [:]][code, default: 0] += 1
                }
            }
        }
        result.groupArgs = groups.map { String($0.dropFirst(10)) }.sorted()
        result.keysplits = pairs.keys.sorted().compactMap { key in
            pairs[key].map { (symbol: key, table: $0) }
        }
        result.drumkits = drums.sorted()
        func mode(_ counts: [UInt32: Int]) -> VgAdsr {
            let code =
                counts.max { lhs, rhs in
                    lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
                }?.key ?? 0
            return VgAdsr(
                attack: Int(code >> 24), decay: Int((code >> 16) & 255),
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
        let lineSpan = lines.span
        for index in lineSpan.indices {
            let line = lineSpan[index]
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
