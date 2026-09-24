import Foundation

/// One source line without its LF terminator; an existing CR remains in `raw`.
public struct SourceLine: Sendable {
    public var raw: [UInt8]
    public var kind: VgLineKind = .other
    public var slot = -1
    public var voice = VgVoice()
    public var indent: [UInt8] = []
    public var macroText: [UInt8] = []
    public var argPieces: [[UInt8]] = []
    public var tail: [UInt8] = []

    public init(raw: [UInt8]) {
        self.raw = raw
    }
}

/// Byte-preserving source model for a single voicegroup, whether standalone or in an index file.
public final class VoicegroupSource {
    public private(set) var filePath = ""
    public private(set) var loadName = ""
    public var isMonolithic: Bool { !sectionLabel.isEmpty }
    public private(set) var sectionLabel = ""
    public private(set) var projectRoot = ""
    public private(set) var voicegroupArg = ""
    public internal(set) var lines: [SourceLine] = []
    public internal(set) var slotToLine = [Int](repeating: -1, count: 128)
    public internal(set) var sectionBegin = 0
    public internal(set) var sectionEnd = 0
    public internal(set) var endsWithNewline = true
    public internal(set) var pristineSource: [UInt8] = []
    public internal(set) var dirty = false

    public init() {}

    /// Locates the declaration and parses its source. Empty `voicegroupArg` means `_dummy`.
    /// - Parameters:
    ///   - projectRoot: Root containing the `sound` directory.
    ///   - voicegroupArg: The song's `-G` argument.
    ///   - error: Receives a diagnostic when the source cannot be opened.
    /// - Returns: Whether a supported declaration was found and parsed.
    public func open(projectRoot: String, voicegroupArg: String, error: inout String?) -> Bool {
        self.projectRoot = projectRoot
        self.voicegroupArg = voicegroupArg.isEmpty ? "_dummy" : voicegroupArg
        filePath = ""
        loadName = ""
        sectionLabel = ""
        let symbol = "voicegroup" + self.voicegroupArg
        let base = String(self.voicegroupArg.drop(while: { $0 == "_" }))
        let indices = ["\(projectRoot)/sound/voice_groups.inc", "\(projectRoot)/sound/voicegroups.inc"]
        var probes = indices
        if !base.isEmpty {
            probes += ["\(projectRoot)/sound/voicegroups/\(base).inc",
                       "\(projectRoot)/sound/voicegroups/vg_\(base).inc"]
        }
        for path in probes where ProjectFileStore.exists(path) {
            guard let bytes = try? ProjectFileStore.read(path) else { continue }
            switch select(path: path, declarations: Self.declarations(in: [UInt8](bytes)), symbol: symbol) {
            case .found: return reload(error: &error)
            case .invalid(let diagnostic): error = diagnostic; return false
            case .absent: break
            }
        }

        // Index files win even when the corresponding per-file source is found by the scan.
        var candidates = indices.filter { ProjectFileStore.exists($0) }
        candidates += (try? ProjectFileStore.listRecursive(
            url: URL(filePath: "\(projectRoot)/sound/voicegroups"), ext: ".inc")) ?? []
        let needle = Array(base.utf8)
        for path in candidates {
            guard let bytes = try? ProjectFileStore.read(path) else { continue }
            let content = [UInt8](bytes)
            if !needle.isEmpty && !Self.contains(content, needle) { continue }
            switch select(path: path, declarations: Self.declarations(in: content), symbol: symbol) {
            case .found: return reload(error: &error)
            case .invalid(let diagnostic): error = diagnostic; return false
            case .absent: break
            }
        }
        error = "No voicegroup file declares \(symbol)."
        return false
    }

    /// Re-reads the located file, discarding unsaved edits and resetting pristine bytes.
    /// - Parameter error: Receives a diagnostic if reading or parsing fails.
    /// - Returns: Whether the file was read and its section found.
    public func reload(error: inout String?) -> Bool {
        guard let bytes = try? ProjectFileStore.read(filePath) else {
            error = "Cannot read \(filePath)"
            return false
        }
        let content = [UInt8](bytes)
        guard parse(content, error: &error) else {
            dirty = sourceBytes() != pristineSource
            return false
        }
        pristineSource = content
        dirty = false
        return true
    }

    /// Returns the parsed category for any bank slot, or `.none` outside the source.
    /// - Parameter slot: A zero-based voice slot.
    /// - Returns: The source-line category.
    public func kindAt(slot: Int) -> VgLineKind {
        guard (0..<128).contains(slot), slotToLine[slot] >= 0 else { return .none }
        return lines[slotToLine[slot]].kind
    }

    /// Reports whether this slot contains an editable voice.
    /// - Parameter slot: A zero-based voice slot.
    /// - Returns: Whether the source has parsed editable arguments.
    public func isEditable(slot: Int) -> Bool { kindAt(slot: slot) == .editable }

    /// Returns the parsed voice only for editable slots.
    /// - Parameter slot: A zero-based voice slot.
    /// - Returns: A value copy of the parsed voice, if editable.
    public func voiceAt(slot: Int) -> VgVoice? {
        guard kindAt(slot: slot) == .editable else { return nil }
        return lines[slotToLine[slot]].voice
    }

    /// Returns the current editable voice or the supplied template for a blank slot.
    /// - Parameters:
    ///   - slot: A zero-based voice slot.
    ///   - blank: The caller's template for an unoccupied slot.
    /// - Returns: No draft for invalid, read-only, or broken slots.
    public func voiceDraft(slot: Int, blank: VgVoice) -> VgVoiceDraft? {
        guard (0..<128).contains(slot) else { return nil }
        switch kindAt(slot: slot) {
        case .editable: return VgVoiceDraft(voice: lines[slotToLine[slot]].voice)
        case .none: return VgVoiceDraft(voice: blank, materializesBlank: true)
        case .other, .header, .readOnlyVoice, .broken: return nil
        }
    }

    private enum Selection {
        case absent
        case found
        case invalid(String)
    }

    private struct Declaration {
        var symbol: String
        var isLabel: Bool
    }

    private struct MacroDefinition: Sendable {
        let macro: VgMacro
        let prefix: [UInt8]
    }

    // Ordered exactly as the C loader dispatches overlapping voice prefixes.
    private static let macros: [MacroDefinition] = [
        .init(macro: .directSoundNoResample, prefix: Array("voice_directsound_no_resample ".utf8)),
        .init(macro: .directSoundAlt, prefix: Array("voice_directsound_alt ".utf8)),
        .init(macro: .directSound, prefix: Array("voice_directsound ".utf8)),
        .init(macro: .square1Alt, prefix: Array("voice_square_1_alt ".utf8)),
        .init(macro: .square1, prefix: Array("voice_square_1 ".utf8)),
        .init(macro: .square2Alt, prefix: Array("voice_square_2_alt ".utf8)),
        .init(macro: .square2, prefix: Array("voice_square_2 ".utf8)),
        .init(macro: .progWaveAlt, prefix: Array("voice_programmable_wave_alt".utf8)),
        .init(macro: .progWave, prefix: Array("voice_programmable_wave".utf8)),
        .init(macro: .noiseAlt, prefix: Array("voice_noise_alt ".utf8)),
        .init(macro: .noise, prefix: Array("voice_noise ".utf8)),
        .init(macro: .keysplitAll, prefix: Array("voice_keysplit_all ".utf8)),
        .init(macro: .keysplit, prefix: Array("voice_keysplit ".utf8)),
    ]
    private static let alignPrefix = Array(".align".utf8)
    private static let headerPrefix = Array("voice_group ".utf8)
    private static let cryReversePrefix = Array("cry_reverse ".utf8)
    private static let cryPrefix = Array("cry ".utf8)
    private static let doubleColon: [UInt8] = [58, 58]

    private static let macroDeclaration: NSRegularExpression = {
        guard let expression = try? NSRegularExpression(pattern: #"^\s*voice_group\s+(\w+)"#) else {
            preconditionFailure("The voice_group declaration pattern must compile")
        }
        return expression
    }()
    private static let labelDeclaration: NSRegularExpression = {
        guard let expression = try? NSRegularExpression(pattern: #"^\s*(voicegroup\w+)::"#) else {
            preconditionFailure("The voicegroup label pattern must compile")
        }
        return expression
    }()

    private func select(path: String, declarations: [Declaration], symbol: String) -> Selection {
        guard let declaration = declarations.first(where: { $0.symbol == symbol }) else { return .absent }
        if declarations.count > 1 {
            guard declaration.isLabel else {
                return .invalid("\(path) declares \(symbol) with the voice_group macro inside a multi-voicegroup file — not an editable layout.")
            }
            sectionLabel = symbol
            loadName = symbol
        } else {
            sectionLabel = ""
            loadName = ProjectFileStore.completeBaseName(path)
        }
        filePath = path
        return .found
    }

    private static func declarations(in content: [UInt8]) -> [Declaration] {
        var found: [Declaration] = []
        for raw in splitLines(content).lines {
            let end = raw.last == 13 ? raw.count - 1 : raw.count
            let line = String(decoding: raw[..<end], as: UTF8.self)
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = macroDeclaration.firstMatch(in: line, range: range),
               let name = Range(match.range(at: 1), in: line) {
                found.append(.init(symbol: "voicegroup_" + String(line[name]), isLabel: false))
            } else if let match = labelDeclaration.firstMatch(in: line, range: range),
                      let name = Range(match.range(at: 1), in: line) {
                found.append(.init(symbol: String(line[name]), isLabel: true))
            }
        }
        return found
    }

    func parse(_ content: [UInt8], error: inout String?) -> Bool {
        let split = Self.splitLines(content)
        lines = []
        lines.reserveCapacity(split.lines.count)
        slotToLine = [Int](repeating: -1, count: 128)
        endsWithNewline = split.endsWithNewline
        sectionBegin = isMonolithic ? -1 : 0
        sectionEnd = split.lines.count
        let marker = Array((sectionLabel + "::").utf8)
        var active = !isMonolithic
        var done = false
        var voices = 0
        var nextSlot = 0

        for (index, raw) in split.lines.enumerated() {
            var line = SourceLine(raw: raw)
            let bounds = Self.contentBounds(raw)
            let text = Array(raw[bounds])
            defer { lines.append(line) }
            if done || text.isEmpty { continue }
            if !active {
                guard text.starts(with: marker) else { continue }
                active = true
                sectionBegin = index
            } else if isMonolithic && voices > 0 &&
                        (Self.containsAfterFirst(text, Self.doubleColon) || text.starts(with: Self.alignPrefix)) {
                done = true
                sectionEnd = index
                continue
            }
            if nextSlot >= 128 { continue }
            if text.starts(with: Self.headerPrefix) {
                line.kind = .header
                if let startingSlot = Self.headerStartingSlot(text) { nextSlot = startingSlot }
                continue
            }
            let matchedMacro = Self.macros.first(where: { text.starts(with: $0.prefix) })
            let readOnly = text.starts(with: Self.cryReversePrefix) ||
                text.starts(with: Self.cryPrefix)
            guard matchedMacro != nil || readOnly else { continue }
            line.slot = nextSlot
            nextSlot += 1
            voices += 1
            if let definition = matchedMacro {
                line.indent = Array(raw[..<bounds.lowerBound])
                line.macroText = Array(text[..<definition.prefix.count])
                line.tail = Array(raw[bounds.upperBound...])
                line.argPieces = Self.split(text[definition.prefix.count...], on: 44)
                if let voice = Self.decode(definition.macro, pieces: line.argPieces) {
                    line.kind = .editable
                    line.voice = voice
                } else {
                    line.kind = .broken
                }
            } else {
                line.kind = .readOnlyVoice
            }
            if line.slot < 128 { slotToLine[line.slot] = index }
        }
        guard !isMonolithic || sectionBegin >= 0 else {
            error = "Label \(sectionLabel):: not found in \(filePath)"
            return false
        }
        return true
    }

    private static func decode(_ macro: VgMacro, pieces: [[UInt8]]) -> VgVoice? {
        let expected = macro == .keysplitAll ? 1 : macro == .keysplit ? 2 :
            (macro == .square1 || macro == .square1Alt ? 8 : 7)
        guard pieces.count == expected else { return nil }
        let values = pieces.map { piece in
            var start = 0
            var end = piece.count
            while start < end && isSpace(piece[start]) { start += 1 }
            while end > start && isSpace(piece[end - 1]) { end -= 1 }
            return Array(piece[start..<end])
        }
        for (index, value) in values.enumerated() {
            let symbol = macro == .keysplit || macro == .keysplitAll ||
                (vgMacroHasSymbol(macro) && index == 2)
            guard symbol ? !value.isEmpty : isInteger(value) else { return nil }
        }
        var voice = VgVoice(macro: macro)
        if macro == .keysplitAll {
            voice.symbol = String(decoding: values[0], as: UTF8.self)
        } else if macro == .keysplit {
            voice.symbol = String(decoding: values[0], as: UTF8.self)
            voice.keysplitTable = String(decoding: values[1], as: UTF8.self)
        } else {
            voice.key = number(values[0])
            voice.pan = number(values[1])
            var index = 2
            if vgMacroHasSymbol(macro) {
                voice.symbol = String(decoding: values[index], as: UTF8.self)
                index += 1
            } else if macro == .square1 || macro == .square1Alt {
                voice.sweep = number(values[index]); index += 1
                voice.duty = number(values[index]); index += 1
            } else if macro == .square2 || macro == .square2Alt {
                voice.duty = number(values[index]); index += 1
            } else {
                voice.period = number(values[index]); index += 1
            }
            voice.attack = number(values[index]); index += 1
            voice.decay = number(values[index]); index += 1
            voice.sustain = number(values[index]); index += 1
            voice.release = number(values[index])
        }
        return voice
    }

    private static func number(_ bytes: [UInt8]) -> Int { Int(String(decoding: bytes, as: UTF8.self)) ?? 0 }
    private static func isInteger(_ bytes: [UInt8]) -> Bool {
        guard !bytes.isEmpty else { return false }
        let start = bytes[0] == 43 || bytes[0] == 45 ? 1 : 0
        return start < bytes.count && bytes[start...].allSatisfy { (48...57).contains($0) }
    }
    private static func isSpace(_ byte: UInt8) -> Bool { byte == 32 || (9...13).contains(byte) }

    private static func headerStartingSlot(_ text: [UInt8]) -> Int? {
        guard let comma = text[12...].firstIndex(of: 44) else { return nil }
        let rest = text[(comma + 1)...].drop(while: isSpace)
        let signed = rest.first == 43 || rest.first == 45
        let digits = rest.dropFirst(signed ? 1 : 0).prefix { (48...57).contains($0) }
        guard !digits.isEmpty else { return nil }
        let number = Array(rest.prefix(digits.count + (signed ? 1 : 0)))
        // The C loader accepts a decimal prefix, ignoring later comment or text.
        guard let slot = Int(String(decoding: number, as: UTF8.self)), (1..<128).contains(slot) else { return nil }
        return slot
    }

    private static func contentBounds(_ raw: [UInt8]) -> Range<Int> {
        var end = raw.firstIndex(of: 64) ?? raw.count
        if raw.count >= 2 {
            for index in 0..<(raw.count - 1) where raw[index] == 47 && raw[index + 1] == 47 {
                end = min(end, index)
                break
            }
        }
        while end > 0 && isSpace(raw[end - 1]) { end -= 1 }
        var start = 0
        while start < end && isSpace(raw[start]) { start += 1 }
        return start..<end
    }

    private static func splitLines(_ bytes: [UInt8]) -> (lines: [[UInt8]], endsWithNewline: Bool) {
        let endsWithNewline = bytes.isEmpty || bytes.last == 10
        var lines = split(bytes[...], on: 10)
        if endsWithNewline { lines.removeLast() }
        return (lines, endsWithNewline)
    }

    private static func split(_ bytes: ArraySlice<UInt8>, on separator: UInt8) -> [[UInt8]] {
        var pieces: [[UInt8]] = []
        var start = bytes.startIndex
        for index in bytes.indices where bytes[index] == separator {
            pieces.append(Array(bytes[start..<index]))
            start = index + 1
        }
        pieces.append(Array(bytes[start..<bytes.endIndex]))
        return pieces
    }

    private static func contains(_ bytes: [UInt8], _ needle: [UInt8], startingAt start: Int = 0) -> Bool {
        guard !needle.isEmpty, bytes.count - start >= needle.count else { return false }
        for index in start...(bytes.count - needle.count) {
            if bytes[index..<(index + needle.count)].elementsEqual(needle) { return true }
        }
        return false
    }

    private static func containsAfterFirst(_ bytes: [UInt8], _ needle: [UInt8]) -> Bool {
        contains(bytes, needle, startingAt: 1)
    }
}
