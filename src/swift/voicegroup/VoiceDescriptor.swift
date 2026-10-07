import Foundation

/// Parsed ToneData scalars and unresolved asset symbols for one written slot.
public struct VgVoiceDesc: Equatable, Sendable {
    public var type: UInt8 = 0
    public var key: UInt8 = 0
    public var panSweep: UInt8 = 0
    public var attack: UInt8 = 0
    public var decay: UInt8 = 0
    public var sustain: UInt8 = 0
    public var release: UInt8 = 0
    public var wavePointerBits: UInt8 = 0
    public var symbol = ""
    public var tableSymbol = ""
    public var displayName = ""

    public init() {}
}

/// One bank's parsed slots, with the C sub-bank include-continuation decision.
public struct VoicegroupText: Sendable {
    public let voices: [VgVoiceDesc?]
    public let continuesIntoIncludedFile: Bool

    public init(voices: [VgVoiceDesc?], continuesIntoIncludedFile: Bool) {
        precondition(voices.count == 128)
        self.voices = voices
        self.continuesIntoIncludedFile = continuesIntoIncludedFile
    }
}

/// A source-level HARD_FAIL, distinguished from a consumed malformed voice.
public enum VoicegroupTextError: Error, Equatable, Sendable {
    case hardFailure(line: Int, reason: String)
}

extension VoicegroupSource {
    /// Folds parsed lines without tokenizing again. Top-level loads use both defaults;
    /// sub-banks use contiguousFill, and included successors use noSubRecurse (C :2328/:2360/:3483).
    /// - Throws: `VoicegroupTextError` for an overlong argument symbol (line numbers are one-based).
    public func descriptors(contiguousFill: Bool = false, noSubRecurse: Bool = false) throws -> VoicegroupText {
        var voices = [VgVoiceDesc?](repeating: nil, count: 128)
        var slot = 0
        var consumed = 0
        var inContinuation = false
        let end = contiguousFill ? lines.count : sectionEnd
        // Physical lines remain byte-preserving records, not C's 1023-byte fgets chunks.
        // Oversized lines can therefore differ when another macro begins at a chunk boundary.
        for index in sectionBegin..<end {
            guard slot < 128 else { break }
            let line = lines[index]
            if isMonolithic && consumed > 0 && line.isSectionBoundary {
                if !contiguousFill { break }
                inContinuation = true
            }
            if line.kind == .header {
                if inContinuation || noSubRecurse { break }
                if let reason = line.hardFailure {
                    throw VoicegroupTextError.hardFailure(line: index + 1, reason: reason)
                }
                if let startingSlot = line.startingSlot { slot = startingSlot }
                continue
            }
            if let reason = line.hardFailure {
                throw VoicegroupTextError.hardFailure(line: index + 1, reason: reason)
            }
            switch line.kind {
            case .editable, .readOnlyVoice:
                var descriptor = voices[slot] ?? VgVoiceDesc()
                descriptor.populate(line)
                voices[slot] = descriptor
                slot += 1
                consumed += 1
            case .broken:
                slot += 1
                consumed += 1
            case .none, .other, .header:
                break
            }
        }
        let continues = contiguousFill && !isMonolithic && slot > 0 && slot < 128
        return VoicegroupText(voices: voices, continuesIntoIncludedFile: continues)
    }
}

extension VgVoiceDesc {
    fileprivate static let displayPrefixes = ["DirectSoundWaveData_", "ProgrammableWaveData_", "voicegroup_"]

    fileprivate mutating func populate(_ line: SourceLine) {
        let voice = line.voice
        if let cryType = line.cryType {
            wavePointerBits = 0
            type = cryType
            key = 60
            attack = 255
            decay = 0
            sustain = 255
            release = 0
            symbol = voice.symbol
            displayName = Self.name(voice.symbol)
            return
        }
        type = vgMacroVoiceType(voice.macro)
        switch voice.macro {
        case .keysplit, .keysplitAll:
            wavePointerBits = 0
            symbol = voice.symbol
            displayName = Self.name(voice.symbol)
            if voice.macro == .keysplit { tableSymbol = voice.keysplitTable }
            return
        case .directSound, .directSoundNoResample, .directSoundAlt:
            wavePointerBits = 0
            panSweep = voice.pan == 0 ? 0 : UInt8(truncatingIfNeeded: 0x80 | voice.pan)
            attack = UInt8(truncatingIfNeeded: voice.attack)
            decay = UInt8(truncatingIfNeeded: voice.decay)
            sustain = UInt8(truncatingIfNeeded: voice.sustain)
            release = UInt8(truncatingIfNeeded: voice.release)
            symbol = voice.symbol
            displayName = Self.name(voice.symbol)
        case .square1, .square1Alt, .square2, .square2Alt, .progWave, .progWaveAlt, .noise, .noiseAlt:
            attack = UInt8(voice.attack & 7)
            decay = UInt8(voice.decay & 7)
            sustain = UInt8(voice.sustain & 15)
            release = UInt8(voice.release & 7)
            switch voice.macro {
            case .square1, .square1Alt:
                panSweep = UInt8(truncatingIfNeeded: voice.sweep)
                wavePointerBits = UInt8(voice.duty & 3)
                symbol = ""
            case .square2, .square2Alt:
                panSweep = 0
                wavePointerBits = UInt8(voice.duty & 3)
                symbol = ""
            case .noise, .noiseAlt:
                wavePointerBits = UInt8(voice.period & 1)
                symbol = ""
            case .progWave, .progWaveAlt:
                wavePointerBits = 0
                symbol = voice.symbol
                displayName = Self.name(voice.symbol)
            case .directSound, .directSoundNoResample, .directSoundAlt, .keysplit, .keysplitAll:
                preconditionFailure("Envelope family already dispatched")
            }
        }
        key = UInt8(truncatingIfNeeded: voice.key)
    }

    fileprivate static func name(_ symbol: String) -> String {
        var bytes = symbol.utf8[...]
        for prefix in displayPrefixes {
            if bytes.starts(with: prefix.utf8), bytes.count > prefix.utf8.count {
                bytes = bytes.dropFirst(prefix.utf8.count)
                break
            }
        }
        return String(decoding: bytes.prefix(47), as: UTF8.self)
    }
}
