import Foundation

/// Parsed ToneData scalars and borrowed symbols for one written slot.
public struct VgVoiceDesc: Equatable, Sendable {
    public var type: UInt8 = 0
    public var key: UInt8 = 0
    public var panSweep: UInt8 = 0
    public var attack: UInt8 = 0
    public var decay: UInt8 = 0
    public var sustain: UInt8 = 0
    public var release: UInt8 = 0
    public var wavePointerBits: UInt8 = 0
    public var symbol: ArraySlice<UInt8> = []
    public var tableSymbol: ArraySlice<UInt8> = []
    public var displayName: ArraySlice<UInt8> = []
    var suppressSubgroup = false
    public init() {}
}

/// One bank's slots retain their source through the symbol slices.
public struct VoicegroupText: Sendable {
    public let voices: InlineArray<128, VgVoiceDesc?>
    public let endIndex: Int
    public let continuesIntoIncludedFile: Bool
    private let bytes: [UInt8]

    public init(
        voices: InlineArray<128, VgVoiceDesc?>, endIndex: Int, continuesIntoIncludedFile: Bool, bytes: [UInt8] = []
    ) {
        precondition((0...128).contains(endIndex))
        self.voices = voices
        self.endIndex = endIndex
        self.continuesIntoIncludedFile = continuesIntoIncludedFile
        self.bytes = bytes
    }

    /// Reads directly into the retained byte array, without Data or a second copy.
    public static func read(_ path: String) throws -> [UInt8] {
        guard let bytes = NativeFileSystem.readRegularFile(path) else { throw BankBuildError.unreadable(path) }
        return bytes
    }

    /// Folds the loader grammar without allocating any per-line editor records.
    public static func parse(
        bytes: [UInt8], sectionLabel: String = "", contiguousFill: Bool = false,
        noSubRecurse: Bool = false
    ) throws -> VoicegroupText {
        var voices = InlineArray<128, VgVoiceDesc?>(repeating: nil)
        let monolithic = !sectionLabel.isEmpty
        var active = !monolithic
        var continuation = false
        var slot = 0
        var consumed = 0
        var start = 0
        var lineNumber = 0
        while start < bytes.count && slot < 128 {
            lineNumber += 1
            var end = start
            while end < bytes.count && bytes[end] != 10 { end += 1 }
            let raw = bytes[start..<end]
            start = end + 1
            let text = raw[VoicegroupSource.contentBounds(raw)]
            if text.isEmpty { continue }
            if !active {
                let labelCount = sectionLabel.utf8.count
                guard text.count >= labelCount + 2,
                    matchesLabel(text, sectionLabel),
                    text[text.startIndex + labelCount] == 58,
                    text[text.startIndex + labelCount + 1] == 58,
                    text.count == labelCount + 2 || VoicegroupSource.isSpace(text[text.startIndex + labelCount + 2])
                else { continue }
                active = true
            }
            if monolithic && consumed > 0
                && (VoicegroupSource.hasSectionLabelSeparator(text)
                    || AsmLine.hasPrefix(text, VoicegroupSource.alignPrefix))
            {
                if !contiguousFill { break }
                continuation = true
            }
            do {
                if AsmLine.hasPrefix(text, VoicegroupSource.headerPrefix) {
                    if continuation || noSubRecurse { break }
                    if let index = try VoicegroupSource.headerStartingSlot(text) { slot = index }
                    continue
                }
                var macro: VoiceMacroSpec?
                for index in 0..<VoiceMacroSpec.all.count {
                    if AsmLine.hasPrefix(text, VoiceMacroSpec.all[index].prefix) {
                        macro = VoiceMacroSpec.all[index]
                        break
                    }
                }
                let reverse = AsmLine.hasPrefix(text, VoicegroupSource.cryReversePrefix)
                let cry = reverse || AsmLine.hasPrefix(text, VoicegroupSource.cryPrefix)
                guard macro != nil || cry else { continue }
                var descriptor = voices[slot] ?? VgVoiceDesc()
                let decoded: Bool
                if let macro {
                    decoded = try descriptor.decode(macro, arguments: text[(text.startIndex + macro.prefix.count)...])
                } else {
                    var rest = text[
                        (text.startIndex
                            + (reverse ? VoicegroupSource.cryReversePrefix.count : VoicegroupSource.cryPrefix.count))...
                    ]
                    if let symbol = try VoicegroupSource.extractSymbolBytes(&rest, comma: false) {
                        descriptor.type = reverse ? 0x30 : 0x20
                        descriptor.key = 60
                        descriptor.attack = 255
                        descriptor.decay = 0
                        descriptor.sustain = 255
                        descriptor.release = 0
                        descriptor.wavePointerBits = 0
                        descriptor.symbol = symbol
                        descriptor.displayName = VgVoiceDesc.name(symbol)
                        decoded = true
                    } else {
                        decoded = false
                    }
                }
                if decoded {
                    descriptor.suppressSubgroup = continuation || noSubRecurse
                    voices[slot] = descriptor
                }
                slot += 1
                consumed += 1
            } catch {
                throw VoicegroupTextError.hardFailure(line: lineNumber, reason: "voice symbol is overlong")
            }
        }
        guard active else { throw BankBuildError.unreadable("Label \(sectionLabel):: not found") }
        return VoicegroupText(
            voices: voices, endIndex: slot,
            continuesIntoIncludedFile: contiguousFill && !monolithic && slot > 0 && slot < 128, bytes: bytes)
    }

    private static func matchesLabel(_ text: ArraySlice<UInt8>, _ label: String) -> Bool {
        var index = text.startIndex
        for byte in label.utf8 {
            guard index < text.endIndex && text[index] == byte else { return false }
            index += 1
        }
        return true
    }
}

/// Retains each sub-voicegroup file once until the owning store is rebound.
public final class VoicegroupTextCache {
    private var bytes: [VoicegroupLocation: [UInt8]] = [:]
    private struct ParseKey: Hashable {
        let location: VoicegroupLocation
        let contiguous: Bool
        let noSubRecurse: Bool
    }
    private var parsed: [ParseKey: VoicegroupText] = [:]
    public init() {
        bytes.reserveCapacity(32)
        parsed.reserveCapacity(32)
    }
    public func removeAll() {
        parsed.removeAll()
        bytes.removeAll()
    }
    public func set(_ source: [UInt8], at location: VoicegroupLocation) {
        parsed.removeValue(forKey: ParseKey(location: location, contiguous: false, noSubRecurse: false))
        parsed.removeValue(forKey: ParseKey(location: location, contiguous: false, noSubRecurse: true))
        parsed.removeValue(forKey: ParseKey(location: location, contiguous: true, noSubRecurse: false))
        parsed.removeValue(forKey: ParseKey(location: location, contiguous: true, noSubRecurse: true))
        bytes[location] = source
    }
    public func text(at location: VoicegroupLocation, contiguousFill: Bool, noSubRecurse: Bool) throws -> VoicegroupText
    {
        let key = ParseKey(location: location, contiguous: contiguousFill, noSubRecurse: noSubRecurse)
        if let cached = parsed[key] { return cached }
        let source: [UInt8]
        if let cached = bytes[location] {
            source = cached
        } else {
            source = try VoicegroupText.read(location.filePath)
            bytes[location] = source
        }
        let text = try VoicegroupText.parse(
            bytes: source, sectionLabel: location.sectionLabel,
            contiguousFill: contiguousFill, noSubRecurse: noSubRecurse)
        parsed[key] = text
        return text
    }
}

public enum VoicegroupTextError: Error, Equatable, Sendable {
    case hardFailure(line: Int, reason: String)
}

extension VoicegroupSource {
    public func descriptors(contiguousFill: Bool = false, noSubRecurse: Bool = false) throws -> VoicegroupText {
        try VoicegroupText.parse(
            bytes: sourceBytes(), sectionLabel: sectionLabel,
            contiguousFill: contiguousFill, noSubRecurse: noSubRecurse)
    }
}

extension VgVoiceDesc {
    fileprivate static let displayPrefixes: [[UInt8]] = [
        Array("DirectSoundWaveData_".utf8), Array("ProgrammableWaveData_".utf8), Array("voicegroup_".utf8),
    ]

    fileprivate static func name(_ symbol: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
        for index in 0..<displayPrefixes.count {
            let prefix = displayPrefixes[index]
            if symbol.count > prefix.count && AsmLine.hasPrefix(symbol, prefix) {
                let start = symbol.startIndex + prefix.count
                return symbol[start..<min(symbol.endIndex, start + 47)]
            }
        }
        return symbol[symbol.startIndex..<min(symbol.endIndex, symbol.startIndex + 47)]
    }

    fileprivate mutating func decode(_ spec: VoiceMacroSpec, arguments: ArraySlice<UInt8>) throws -> Bool {
        var rest = arguments
        var next = self
        next.type = vgMacroVoiceType(spec.macro)
        if spec.category == .keysplitAll || spec.category == .keysplit {
            guard let symbol = try VoicegroupSource.extractSymbolBytes(&rest, comma: spec.category == .keysplit) else {
                return false
            }
            next.symbol = symbol
            next.displayName = Self.name(symbol)
            next.wavePointerBits = 0
            if spec.category == .keysplit {
                guard let table = try VoicegroupSource.extractSymbolBytes(&rest, comma: false) else { return false }
                next.tableSymbol = table
            }
            self = next
            return true
        }
        guard let key = VoicegroupSource.nextInteger(&rest), VoicegroupSource.expectComma(&rest),
            let pan = VoicegroupSource.nextInteger(&rest), VoicegroupSource.expectComma(&rest)
        else { return false }
        if spec.symbolField != nil {
            guard let symbol = try VoicegroupSource.extractSymbolBytes(&rest, comma: true) else { return false }
            next.symbol = symbol
            next.displayName = Self.name(symbol)
            next.wavePointerBits = 0
        } else if spec.category == .square1 {
            guard let sweep = VoicegroupSource.nextInteger(&rest), VoicegroupSource.expectComma(&rest),
                let duty = VoicegroupSource.nextInteger(&rest), VoicegroupSource.expectComma(&rest)
            else { return false }
            next.panSweep = UInt8(truncatingIfNeeded: sweep)
            next.wavePointerBits = UInt8(duty & 3)
            next.symbol = []
        } else {
            guard let bits = VoicegroupSource.nextInteger(&rest), VoicegroupSource.expectComma(&rest) else {
                return false
            }
            if spec.category == .square2 { next.panSweep = 0 }
            next.wavePointerBits = UInt8(bits & (spec.category == .square2 ? 3 : 1))
            next.symbol = []
        }
        guard let attack = VoicegroupSource.nextInteger(&rest), VoicegroupSource.expectComma(&rest),
            let decay = VoicegroupSource.nextInteger(&rest), VoicegroupSource.expectComma(&rest),
            let sustain = VoicegroupSource.nextInteger(&rest), VoicegroupSource.expectComma(&rest),
            let release = VoicegroupSource.nextInteger(&rest)
        else { return false }
        let direct = spec.category == .directSound
        if direct { next.panSweep = pan == 0 ? 0 : UInt8(truncatingIfNeeded: 0x80 | pan) }
        next.key = UInt8(truncatingIfNeeded: key)
        next.attack = UInt8(truncatingIfNeeded: direct ? attack : attack & 7)
        next.decay = UInt8(truncatingIfNeeded: direct ? decay : decay & 7)
        next.sustain = UInt8(truncatingIfNeeded: direct ? sustain : sustain & 15)
        next.release = UInt8(truncatingIfNeeded: direct ? release : release & 7)
        self = next
        return true
    }
}
