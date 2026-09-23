import Foundation
import PorydawCore

// MARK: - Voice list vocabulary

/// The Type column's per-type glyphs, mirroring voicetypeicons::Glyph
/// (src/ui/voicetypeicons.h). Alt CGB variants reuse the family glyph on a
/// grey chip; the reverse DirectSound reuses the sample glyph rotated.
public enum VoiceListGlyph: Int32, Equatable, Sendable {
    case sample = 0
    case sampleReverse = 1
    case square1 = 2
    case square2 = 3
    case wave = 4
    case noise = 5
    case keysplit = 6
    case drumkit = 7
}

/// The derived content of one stable row of the 128-slot voice list.
/// `title` is column 0 ("NNN  name"), `typeName` is the Type column's
/// tooltip/accessible text (empty when the row publishes no type), `adsr`
/// is column 2, `glyph` is the Type column's icon identity with `altChip`
/// marking the grey-chip alt variants, and `used` is the "used by this
/// song" mark. The controller derives one per slot and applies it to the
/// stable VoiceListRowHandle the QListModel publishes.
public struct VoiceListRow: Equatable, Sendable {
    public var slot: Int
    public var title: String
    public var typeName: String
    public var adsr: String
    public var glyph: VoiceListGlyph?
    public var altChip: Bool
    public var used: Bool

    public init(slot: Int, title: String, typeName: String = "", adsr: String = "",
                glyph: VoiceListGlyph? = nil, altChip: Bool = false, used: Bool = false) {
        self.slot = slot
        self.title = title
        self.typeName = typeName
        self.adsr = adsr
        self.glyph = glyph
        self.altChip = altChip
        self.used = used
    }
}


/// A value draft for editing a slot, mirroring VgVoiceDraft: editable slots
/// edit in place; None-kind slots materialize the blank template;
/// read-only and broken slots have no draft.
public struct VoiceListDraft: Equatable, Sendable {
    public var voice: BankVoice
    public var materializesBlank: Bool

    public init(voice: BankVoice, materializesBlank: Bool) {
        self.voice = voice
        self.materializesBlank = materializesBlank
    }
}

/// What a picker audition row stands for, mirroring VgAuditionKind: samples
/// publish PCM, waves publish CGB wave bytes, keysplits resolve to the
/// sub-voice the audition key lands on.
public enum VoiceListAuditionKind: Int32, Equatable, Sendable {
    case sample = 0
    case wave = 1
    case keysplit = 2
}

/// One ADSR envelope in the raw macro-argument scale of its family,
/// mirroring VgAdsr (CGB: A/D/R 0-7, S 0-15; DirectSound: 0-255 each).
public struct VoiceListAdsr: Equatable, Sendable {
    public var attack: Int32
    public var decay: Int32
    public var sustain: Int32
    public var release: Int32

    public init(attack: Int32 = 0, decay: Int32 = 0, sustain: Int32 = 0, release: Int32 = 0) {
        self.attack = attack
        self.decay = decay
        self.sustain = sustain
        self.release = release
    }
}

/// Project-typical envelopes for blank templates and family crossings,
/// mirroring VgAdsrDefaults: by instrument symbol, then by envelope family,
/// then the full-sustain fallback.
public struct VoiceListAdsrDefaults: Equatable, Sendable {
    public var bySymbol: [String: VoiceListAdsr]
    public var byFamily: [Int32: VoiceListAdsr]

    public init(bySymbol: [String: VoiceListAdsr] = [:],
                byFamily: [Int32: VoiceListAdsr] = [:]) {
        self.bySymbol = bySymbol
        self.byFamily = byFamily
    }
}

// MARK: - List semantics (pure mirrors of the native helpers)

/// Pure row/selector semantics mirrored from src/ui/voicegroupbrowser.cpp,
/// src/core/m4asemantics.cpp, src/project/voicegroupsource.cpp, and
/// src/project/songregistry.cpp. These are the oracle's observable rules,
/// re-expressed over the published BankSlotView/BankVoice values.
public enum VoiceListSemantics {
    /// VOICE_* type bytes (external/poryaaaa .../voicegroup_types.h).
    public static let voiceDirectsound: UInt8 = 0x00
    public static let voiceSquare1: UInt8 = 0x01
    public static let voiceSquare2: UInt8 = 0x02
    public static let voiceProgrammableWave: UInt8 = 0x03
    public static let voiceNoise: UInt8 = 0x04
    public static let voiceDirectsoundNoResample: UInt8 = 0x08
    public static let voiceSquare1Alt: UInt8 = 0x09
    public static let voiceSquare2Alt: UInt8 = 0x0A
    public static let voiceProgrammableWaveAlt: UInt8 = 0x0B
    public static let voiceNoiseAlt: UInt8 = 0x0C
    public static let voiceDirectsoundAlt: UInt8 = 0x10
    public static let voiceCry: UInt8 = 0x20
    public static let voiceCryReverse: UInt8 = 0x30
    public static let voiceKeysplit: UInt8 = 0x40
    public static let voiceKeysplitAll: UInt8 = 0x80
    public static let voiceTypeCgbMask: UInt8 = 0x07
    public static let voiceTypeFix: UInt8 = 0x08

    /// Press-and-hold audition constants (middle C; drumkits play that
    /// key's percussion).
    public static let auditionKey: Int32 = 60
    public static let auditionVelocity: Int32 = 112

    /// vgMacroVoiceType: the VOICE_* byte a macro's line produces.
    public static func voiceType(forMacro macro: Int32) -> UInt8 {
        switch macro {
        case BankVoiceMacro.directSound: return voiceDirectsound
        case BankVoiceMacro.directSoundNoResample: return voiceDirectsoundNoResample
        case BankVoiceMacro.directSoundAlt: return voiceDirectsoundAlt
        case BankVoiceMacro.square1: return voiceSquare1
        case BankVoiceMacro.square1Alt: return voiceSquare1Alt
        case BankVoiceMacro.square2: return voiceSquare2
        case BankVoiceMacro.square2Alt: return voiceSquare2Alt
        case BankVoiceMacro.programmableWave: return voiceProgrammableWave
        case BankVoiceMacro.programmableWaveAlt: return voiceProgrammableWaveAlt
        case BankVoiceMacro.noise: return voiceNoise
        case BankVoiceMacro.noiseAlt: return voiceNoiseAlt
        case BankVoiceMacro.keysplit: return voiceKeysplit
        case BankVoiceMacro.keysplitAll: return voiceKeysplitAll
        default: return voiceDirectsound
        }
    }

    /// vgMacroHasSymbol: the macro takes a sample/wave/sub-voicegroup arg.
    public static func macroHasSymbol(_ macro: Int32) -> Bool {
        switch macro {
        case BankVoiceMacro.directSound, BankVoiceMacro.directSoundNoResample,
             BankVoiceMacro.directSoundAlt, BankVoiceMacro.programmableWave,
             BankVoiceMacro.programmableWaveAlt, BankVoiceMacro.keysplit,
             BankVoiceMacro.keysplitAll:
            return true
        default:
            return false
        }
    }

    /// The DirectSound envelope family (direct, no-resample, reverse):
    /// raw 0-255 ADSR arguments, mirroring the native family's macro set.
    public static func isDirectSoundFamily(_ macro: Int32) -> Bool {
        switch macro {
        case BankVoiceMacro.directSound, BankVoiceMacro.directSoundNoResample,
             BankVoiceMacro.directSoundAlt:
            return true
        default:
            return false
        }
    }

    /// The programmable-wave macros: CGB envelopes whose wave bytes the
    /// picker audition publishes instead of PCM.
    public static func isWaveMacro(_ macro: Int32) -> Bool {
        switch macro {
        case BankVoiceMacro.programmableWave, BankVoiceMacro.programmableWaveAlt:
            return true
        default:
            return false
        }
    }

    /// voicetypeicons::iconKey: the icon-cache key a glyph plus its
    /// alt-chip flag maps to; -1 while the row publishes no type.
    public static func iconKey(glyph: VoiceListGlyph?, altChip: Bool) -> Int {
        guard let glyph else { return -1 }
        return Int(glyph.rawValue) * 2 + (altChip ? 1 : 0)
    }

    /// vgMacroIsCgb: CGB ADSR ranges (A/D/R 0-7, S 0-15).
    public static func macroIsCgb(_ macro: Int32) -> Bool {
        switch macro {
        case BankVoiceMacro.directSound, BankVoiceMacro.directSoundNoResample,
             BankVoiceMacro.directSoundAlt, BankVoiceMacro.keysplit,
             BankVoiceMacro.keysplitAll:
            return false
        default:
            return true
        }
    }

    /// vgAdsrFamily: the envelope family a macro's ADSR values belong to;
    /// -1 for keysplit/drumkit voices, which carry no envelope.
    public static func adsrFamily(forMacro macro: Int32) -> Int32 {
        switch macro {
        case BankVoiceMacro.directSound, BankVoiceMacro.directSoundNoResample,
             BankVoiceMacro.directSoundAlt:
            return BankVoiceMacro.directSound
        case BankVoiceMacro.square1, BankVoiceMacro.square1Alt:
            return BankVoiceMacro.square1
        case BankVoiceMacro.square2, BankVoiceMacro.square2Alt:
            return BankVoiceMacro.square2
        case BankVoiceMacro.programmableWave, BankVoiceMacro.programmableWaveAlt:
            return BankVoiceMacro.programmableWave
        case BankVoiceMacro.noise, BankVoiceMacro.noiseAlt:
            return BankVoiceMacro.noise
        default:
            return -1
        }
    }

    /// vgDefaultAdsr: project-typical envelope for the symbol, then the
    /// family, then the full-sustain fallback with a short release tail.
    public static func defaultAdsr(_ defaults: VoiceListAdsrDefaults, macro: Int32,
                                   symbol: String) -> VoiceListAdsr {
        if !symbol.isEmpty, let bySymbol = defaults.bySymbol[symbol] {
            return bySymbol
        }
        let family = adsrFamily(forMacro: macro)
        if let byFamily = defaults.byFamily[family] {
            return byFamily
        }
        return macroIsCgb(macro)
            ? VoiceListAdsr(attack: 0, decay: 0, sustain: 15, release: 3)
            : VoiceListAdsr(attack: 255, decay: 0, sustain: 255, release: 165)
    }

    /// vgVoiceStructuralChange: macro or symbol moved, so a scalar ToneData
    /// poke is not enough and the bank must reload from rendered source.
    public static func structuralChange(before: BankVoice, after: BankVoice) -> Bool {
        before.macro != after.macro || before.symbol != after.symbol ||
            before.keysplitTable != after.keysplitTable
    }

    /// m4aVoiceTypeName + the browser's synth/keysplit/alt-chip layering
    /// (typeDisplayName): synth voices keep "Synth (Golden Sun)", keysplits
    /// keep "Keysplit", alt CGB variants gain " (Alt)".
    public static func typeDisplayName(typeByte: UInt8, synth: Bool) -> String {
        if synth { return "Synth (Golden Sun)" }
        if typeByte == voiceKeysplit { return "Keysplit" }
        let name = voiceTypeName(typeByte)
        return isAltChip(typeByte) ? "\(name) (Alt)" : name
    }

    /// m4aVoiceTypeName: drumkit, fixed-pitch and reverse samples, then the
    /// CGB mask; keysplit deliberately falls through to "Sample".
    public static func voiceTypeName(_ type: UInt8) -> String {
        if type == voiceKeysplitAll { return "Drumkit" }
        if type == voiceDirectsoundNoResample { return "Sample (fixed pitch)" }
        if type == voiceDirectsoundAlt { return "Sample (reverse)" }
        switch type & voiceTypeCgbMask {
        case voiceSquare1: return "Square 1"
        case voiceSquare2: return "Square 2"
        case voiceProgrammableWave: return "Wave"
        case voiceNoise: return "Noise"
        default: return "Sample"
        }
    }

    /// voicetypeicons::isAltChip: alt CGB variants (0x09-0x0C) render their
    /// family glyph on a grey chip.
    public static func isAltChip(_ type: UInt8) -> Bool {
        (type & voiceTypeFix) != 0 && (type & voiceTypeCgbMask) != 0
    }

    /// voicetypeicons::forTypeByte: the glyph a type byte maps to; synth and
    /// cry/unknown types read as a sample.
    public static func glyph(forTypeByte type: UInt8, synth: Bool) -> VoiceListGlyph {
        if synth { return .sample }
        switch type {
        case voiceKeysplit: return .keysplit
        case voiceKeysplitAll: return .drumkit
        case voiceDirectsoundAlt: return .sampleReverse
        default:
            switch type & voiceTypeCgbMask {
            case voiceSquare1: return .square1
            case voiceSquare2: return .square2
            case voiceProgrammableWave: return .wave
            case voiceNoise: return .noise
            default: return .sample
            }
        }
    }

    /// The tree's ADSR text: the values the engine sees (CGB envelopes are
    /// masked on load); keysplit/drumkit voices carry none.
    public static func adsrText(_ voice: BankVoice) -> String {
        if voice.macro == BankVoiceMacro.keysplit || voice.macro == BankVoiceMacro.keysplitAll {
            return ""
        }
        if macroIsCgb(voice.macro) {
            return "\(voice.attack & 7) \(voice.decay & 7) \(voice.sustain & 15) \(voice.release & 7)"
        }
        return "\(voice.attack & 0xFF) \(voice.decay & 0xFF) \(voice.sustain & 0xFF) \(voice.release & 0xFF)"
    }

    /// voiceColumnText: "NNN  <name>" — sample symbols shed the
    /// DirectSoundWave prefix so the instrument reads first; symbol-less
    /// voices fall back to the type name.
    public static func voiceColumnText(slot: Int, symbol: String, typeName: String) -> String {
        var shown = symbol
        if shown.hasPrefix("DirectSoundWave") {
            shown = String(shown.dropFirst("DirectSoundWave".count))
            if shown.hasPrefix("Data_") {
                shown = String(shown.dropFirst("Data_".count))
            }
        }
        if shown.isEmpty { shown = typeName }
        return String(format: "%03d  %@", slot, shown)
    }

    /// SongRegistry::voicegroupDisplayName: the leading underscore folds
    /// into the fixed "voicegroup_" prefix the UI shows.
    public static func voicegroupDisplayName(_ arg: String) -> String {
        arg.hasPrefix("_") ? String(arg.dropFirst()) : arg
    }

    /// SongRegistry::voicegroupArgFromDisplay: a name typed under the
    /// "voicegroup_" prefix back to a -G arg. A leading underscore means a
    /// raw arg was pasted; a verbatim match against knownArgs keeps legacy
    /// underscore-less args addressable; everything else assumes the
    /// underscore.
    public static func voicegroupArg(fromDisplay text: String, knownArgs: [String]) -> String {
        if text.isEmpty || text.hasPrefix("_") { return text }
        if !knownArgs.contains("_" + text), knownArgs.contains(text) { return text }
        return "_" + text
    }
}

