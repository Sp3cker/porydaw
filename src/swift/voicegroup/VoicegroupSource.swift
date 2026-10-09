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
    var startingSlot: Int?
    var isSectionBoundary = false
    var cryType: UInt8?
    var hardFailure: String?

    public init(raw: [UInt8]) {
        self.raw = raw
    }
}

/// Refusal to rebase or save a source whose on-disk declaration no longer safely matches it.
public struct VoicegroupSourceConflict: Error, LocalizedError {
    let message: String

    public var errorDescription: String? { message }
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
            probes += [
                "\(projectRoot)/sound/voicegroups/\(base).inc",
                "\(projectRoot)/sound/voicegroups/vg_\(base).inc",
            ]
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
        candidates +=
            (try? ProjectFileStore.listRecursive(
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

    /// Opens an exact loader location without changing editor section-boundary semantics.
    public func open(location: VoicegroupLocation, error: inout String?) -> Bool {
        filePath = location.filePath
        sectionLabel = location.sectionLabel
        loadName = sectionLabel.isEmpty ? ProjectFileStore.completeBaseName(filePath) : sectionLabel
        return reload(error: &error)
    }

    func open(
        location: VoicegroupLocation, bytes: [UInt8], projectRoot: String,
        voicegroupArg: String, error: inout String?
    ) -> Bool {
        self.projectRoot = projectRoot
        self.voicegroupArg = voicegroupArg
        filePath = location.filePath
        sectionLabel = location.sectionLabel
        loadName = sectionLabel.isEmpty ? ProjectFileStore.completeBaseName(filePath) : sectionLabel
        guard parse(bytes, error: &error) else { return false }
        pristineSource = bytes
        dirty = false
        return true
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
        guard parse(content, error: &error) else { return false }
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

    struct Declaration {
        var symbol: String
        var isLabel: Bool
    }

    private struct ParsedSource {
        var lines: [SourceLine]
        var slotToLine: [Int]
        var sectionBegin: Int
        var sectionEnd: Int
        var endsWithNewline: Bool
    }

    static let alignPrefix = Array(".align".utf8)
    static let headerPrefix = Array("voice_group ".utf8)
    static let cryReversePrefix = Array("cry_reverse ".utf8)
    static let cryPrefix = Array("cry ".utf8)

    private func select(path: String, declarations: [Declaration], symbol: String) -> Selection {
        guard let declaration = declarations.first(where: { $0.symbol == symbol }) else { return .absent }
        var editorDeclarations = 0
        for candidate in declarations where !candidate.isLabel || candidate.symbol.hasPrefix("voicegroup") {
            editorDeclarations += 1
        }
        if editorDeclarations > 1 {
            guard declaration.isLabel else {
                return .invalid(
                    "\(path) declares \(symbol) with the voice_group macro inside a multi-voicegroup file — not an editable layout."
                )
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

    static func declarations(in content: [UInt8]) -> [Declaration] {
        var found: [Declaration] = []
        for raw in splitLines(content).lines {
            let text = raw[contentBounds(raw)]
            let header = headerPrefix.dropLast()
            if text.starts(with: header),
                text.count == header.count || isSpace(text[text.startIndex + header.count])
            {
                let name = text.dropFirst(header.count).drop(while: isSpace)
                    .prefix { (byte: UInt8) -> Bool in !isSpace(byte) && byte != UInt8(44) }
                if !name.isEmpty {
                    found.append(.init(symbol: "voicegroup_" + String(decoding: name, as: UTF8.self), isLabel: false))
                }
            } else if let colon = text.firstIndex(of: 58), colon > text.startIndex,
                colon + 1 < text.endIndex, text[colon + 1] == 58,
                colon + 2 == text.endIndex || isSpace(text[colon + 2])
            {
                found.append(.init(symbol: String(decoding: text[..<colon], as: UTF8.self), isLabel: true))
            }
        }
        return found
    }

    func parse(_ content: [UInt8], error: inout String?) -> Bool {
        guard let parsed = parsedSource(content) else {
            error = "Label \(sectionLabel):: not found in \(filePath)"
            return false
        }
        lines = parsed.lines
        slotToLine = parsed.slotToLine
        sectionBegin = parsed.sectionBegin
        sectionEnd = parsed.sectionEnd
        endsWithNewline = parsed.endsWithNewline
        return true
    }

    /// Adopts a fresh disk snapshot around the selected section while keeping its local edits.
    /// - Parameter disk: A clean, parsed snapshot of the same source file and section label.
    /// - Returns: Whether the selected section's editable bytes are unchanged. False means disk
    ///   changed a section without local edits; the receiver is left untouched for a fresh load.
    /// - Throws: `VoicegroupSourceConflict` if the identity or baseline no longer matches, or
    ///   if disk and local edits both changed the selected section. The receiver is unchanged.
    func rebasePreservingEdits(from disk: VoicegroupSource) throws -> Bool {
        guard disk.filePath == filePath, disk.sectionLabel == sectionLabel, !disk.dirty else {
            throw VoicegroupSourceConflict(message: "\(filePath) no longer declares \(loadName) where it was loaded.")
        }
        guard let baseline = parsedSource(pristineSource) else {
            throw VoicegroupSourceConflict(message: "The loaded baseline of \(loadName) no longer parses.")
        }
        let local = lines[sectionBegin..<sectionEnd]
        let fresh = disk.lines[disk.sectionBegin..<disk.sectionEnd]
        let prior = baseline.lines[baseline.sectionBegin..<baseline.sectionEnd]
        guard Self.sameRaw(fresh, prior) || Self.sameRaw(fresh, local) else {
            guard Self.sameRaw(local, prior) else {
                throw VoicegroupSourceConflict(
                    message: "\(loadName) changed in \(filePath) while it has unsaved edits.")
            }
            return false
        }
        let offset = disk.sectionBegin - sectionBegin
        var merged: [SourceLine] = []
        merged.reserveCapacity(disk.lines.count - fresh.count + local.count)
        merged.append(contentsOf: disk.lines[..<disk.sectionBegin])
        merged.append(contentsOf: local)
        merged.append(contentsOf: disk.lines[disk.sectionEnd...])
        lines = merged
        slotToLine = slotToLine.map { $0 >= 0 ? $0 + offset : $0 }
        sectionEnd = disk.sectionBegin + local.count
        sectionBegin = disk.sectionBegin
        endsWithNewline = disk.endsWithNewline
        pristineSource = disk.pristineSource
        dirty = sourceBytes() != pristineSource
        return true
    }

    /// Opens the current on-disk snapshot of this source's voicegroup argument.
    /// - Returns: A clean source parsed from the bytes currently on disk.
    /// - Throws: `VoicegroupSourceConflict` when the declaration is missing, invalid, or unreadable.
    func diskSnapshot() throws -> VoicegroupSource {
        let disk = VoicegroupSource()
        var error: String?
        guard disk.open(projectRoot: projectRoot, voicegroupArg: voicegroupArg, error: &error) else {
            throw VoicegroupSourceConflict(message: error ?? "Cannot read \(filePath)")
        }
        return disk
    }

    private static func sameRaw(_ lhs: ArraySlice<SourceLine>, _ rhs: ArraySlice<SourceLine>) -> Bool {
        lhs.elementsEqual(rhs) { $0.raw == $1.raw }
    }

    private func parsedSource(_ content: [UInt8]) -> ParsedSource? {
        guard sectionLabel.utf8.count < 256,
            !sectionLabel.utf8.contains(where: { (byte: UInt8) -> Bool in
                Self.isSpace(byte) || byte == UInt8(58) || byte == UInt8(44)
            })
        else { return nil }
        let split = Self.splitLines(content)
        var parsed = ParsedSource(
            lines: [], slotToLine: [Int](repeating: -1, count: 128),
            sectionBegin: isMonolithic ? -1 : 0, sectionEnd: split.lines.count,
            endsWithNewline: split.endsWithNewline)
        parsed.lines.reserveCapacity(split.lines.count)
        let marker = Array((sectionLabel + "::").utf8)
        var active = !isMonolithic
        var done = false
        var voices = 0
        var nextSlot = 0

        for (index, raw) in split.lines.enumerated() {
            var line = SourceLine(raw: raw)
            let bounds = Self.contentBounds(raw)
            let text = Array(raw[bounds])
            defer { parsed.lines.append(line) }
            if text.isEmpty { continue }
            if !active {
                guard text.starts(with: marker),
                    text.count == marker.count || Self.isSpace(text[marker.count])
                else { continue }
                active = true
                parsed.sectionBegin = index
            }
            line.isSectionBoundary =
                Self.hasSectionLabelSeparator(text[...]) || text.starts(with: Self.alignPrefix)
            if !done && isMonolithic && voices > 0 && line.isSectionBoundary {
                done = true
                parsed.sectionEnd = index
            }
            if text.starts(with: Self.headerPrefix) {
                line.kind = .header
                do {
                    line.startingSlot = try Self.headerStartingSlot(text[...])
                } catch {
                    line.hardFailure = "voice_group symbol is overlong"
                }
                if !done, nextSlot < 128, let startingSlot = line.startingSlot { nextSlot = startingSlot }
                continue
            }
            if !done && nextSlot >= 128 { continue }
            let matchedMacro = VoiceMacroSpec.all.first { text.starts(with: $0.prefix) }
            let reverseCry = text.starts(with: Self.cryReversePrefix)
            let readOnly = reverseCry || text.starts(with: Self.cryPrefix)
            guard matchedMacro != nil || readOnly else { continue }
            if !done {
                line.slot = nextSlot
                nextSlot += 1
                voices += 1
                parsed.slotToLine[line.slot] = index
            }
            do {
                if let definition = matchedMacro {
                    let argumentStart = definition.prefix.count
                    line.indent = Array(raw[..<bounds.lowerBound])
                    line.macroText = Array(text[..<argumentStart])
                    line.tail = Array(raw[bounds.upperBound...])
                    line.argPieces = Self.split(text[argumentStart...], on: 44)
                    if let voice = try Self.decode(definition, arguments: text[argumentStart...]) {
                        line.kind = .editable
                        line.voice = voice
                    } else {
                        line.kind = .broken
                    }
                } else {
                    var arguments = text[(reverseCry ? Self.cryReversePrefix.count : Self.cryPrefix.count)...]
                    if let symbol = try Self.extractSymbol(&arguments, comma: false) {
                        line.kind = .readOnlyVoice
                        line.voice.symbol = symbol
                        line.cryType = reverseCry ? 0x30 : 0x20
                    } else {
                        line.kind = .broken
                    }
                }
            } catch {
                line.kind = .broken
                line.hardFailure = "voice symbol is overlong"
            }
        }
        return parsed.sectionBegin >= 0 ? parsed : nil
    }

    private enum ArgumentError: Error { case overlongSymbol }

    private static func decode(_ spec: VoiceMacroSpec, arguments: ArraySlice<UInt8>) throws -> VgVoice? {
        var rest = arguments
        var voice = VgVoice(macro: spec.macro)
        if spec.category == .keysplitAll {
            guard let symbol = try extractSymbol(&rest, comma: false) else { return nil }
            voice.symbol = symbol
        } else if spec.category == .keysplit {
            guard let symbol = try extractSymbol(&rest, comma: true),
                let table = try extractSymbol(&rest, comma: false)
            else { return nil }
            voice.symbol = symbol
            voice.keysplitTable = table
        } else {
            guard let key = nextInteger(&rest), expectComma(&rest),
                let pan = nextInteger(&rest), expectComma(&rest)
            else { return nil }
            voice.key = key
            voice.pan = pan
            if spec.symbolField != nil {
                guard let symbol = try extractSymbol(&rest, comma: true) else { return nil }
                voice.symbol = symbol
            } else if spec.category == .square1 {
                guard let sweep = nextInteger(&rest), expectComma(&rest),
                    let duty = nextInteger(&rest), expectComma(&rest)
                else { return nil }
                voice.sweep = sweep
                voice.duty = duty
            } else {
                guard let bits = nextInteger(&rest), expectComma(&rest) else { return nil }
                if spec.category == .square2 { voice.duty = bits } else { voice.period = bits }
            }
            guard let attack = nextInteger(&rest), expectComma(&rest),
                let decay = nextInteger(&rest), expectComma(&rest),
                let sustain = nextInteger(&rest), expectComma(&rest),
                let release = nextInteger(&rest)
            else { return nil }
            voice.attack = attack
            voice.decay = decay
            voice.sustain = sustain
            voice.release = release
        }
        return voice
    }

    static func nextInteger(_ rest: inout ArraySlice<UInt8>) -> Int? {
        let source = rest
        let bytes = source.span
        var index = 0
        while index < bytes.count && isSpace(bytes[index]) { index += 1 }
        guard index < bytes.count else { return nil }
        let negative: Bool = bytes[index] == UInt8(45)
        if negative || bytes[index] == UInt8(43) { index += 1 }
        var radix = 10
        if index < bytes.count && bytes[index] == UInt8(48) {
            radix = 8
            if index + 2 < bytes.count && (bytes[index + 1] == UInt8(120) || bytes[index + 1] == UInt8(88)),
                let digit = digitValue(bytes[index + 2]), digit < 16
            {
                radix = 16
                index += 2
            }
        }
        let start = index
        var magnitude = 0
        let limit = negative ? 2_147_483_648 : 2_147_483_647
        while index < bytes.count, let digit = digitValue(bytes[index]), digit < radix {
            guard magnitude <= (limit - digit) / radix else { return nil }
            magnitude = magnitude * radix + digit
            index += 1
        }
        guard index > start else { return nil }
        rest = source[(source.startIndex + index)...]
        return negative ? -magnitude : magnitude
    }

    private static func digitValue(_ byte: UInt8) -> Int? {
        if byte >= 48 && byte <= 57 { return Int(byte - 48) }
        if byte >= 65 && byte <= 70 { return Int(byte - 65) + 10 }
        if byte >= 97 && byte <= 102 { return Int(byte - 97) + 10 }
        return nil
    }

    static func expectComma(_ rest: inout ArraySlice<UInt8>) -> Bool {
        let source = rest
        let bytes = source.span
        var index = 0
        while index < bytes.count && (bytes[index] == UInt8(32) || bytes[index] == UInt8(9)) { index += 1 }
        guard index < bytes.count && bytes[index] == UInt8(44) else { return false }
        rest = source[(source.startIndex + index + 1)...]
        return true
    }

    private static func extractSymbol(_ rest: inout ArraySlice<UInt8>, comma: Bool) throws -> String? {
        try extractSymbolBytes(&rest, comma: comma).map { String(decoding: $0, as: UTF8.self) }
    }

    static func extractSymbolBytes(_ rest: inout ArraySlice<UInt8>, comma: Bool) throws -> ArraySlice<UInt8>? {
        var start = rest.startIndex
        while start < rest.endIndex && isSpace(rest[start]) { start += 1 }
        var end = rest.endIndex
        if comma {
            end = start
            while end < rest.endIndex && rest[end] != 44 { end += 1 }
            guard end < rest.endIndex else { return nil }
        }
        var symbolEnd = end
        while symbolEnd > start && isSpace(rest[symbolEnd - 1]) { symbolEnd -= 1 }
        guard symbolEnd > start else { return nil }
        guard symbolEnd - start < 256 else { throw ArgumentError.overlongSymbol }
        let symbol = rest[start..<symbolEnd]
        rest = rest[(comma ? end + 1 : end)...]
        return symbol
    }

    static func isSpace(_ byte: UInt8) -> Bool { byte == 32 || (byte >= 9 && byte <= 13) }

    static func headerStartingSlot(_ text: ArraySlice<UInt8>) throws -> Int? {
        var arguments = text[(text.startIndex + 12)...]
        guard try extractSymbolBytes(&arguments, comma: true) != nil,
            let slot = nextInteger(&arguments), (1..<128).contains(slot)
        else { return nil }
        return slot
    }

    static func contentBounds(_ raw: ArraySlice<UInt8>) -> Range<Int> {
        let bytes = raw.span
        var end = bytes.count
        var index = 0
        while index < end {
            let byte: UInt8 = bytes[index]
            if byte == UInt8(64) || byte == UInt8(0)
                || (byte == UInt8(47) && index + 1 < end && bytes[index + 1] == UInt8(47))
            {
                end = index
                break
            }
            index += 1
        }
        while end > 0 && isSpace(bytes[end - 1]) { end -= 1 }
        var start = 0
        while start < end && isSpace(bytes[start]) { start += 1 }
        return (raw.startIndex + start)..<(raw.startIndex + end)
    }

    static func contentBounds(_ raw: [UInt8]) -> Range<Int> { contentBounds(raw[...]) }

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

    static func hasSectionLabelSeparator(_ bytes: ArraySlice<UInt8>) -> Bool {
        guard bytes.count >= 2 else { return false }
        for index in bytes.startIndex..<(bytes.endIndex - 1)
        where bytes[index] == UInt8(58) && bytes[index + 1] == UInt8(58) {
            return index > bytes.startIndex
        }
        return false
    }
}
