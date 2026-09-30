import Foundation

// BENCH-ONLY STUB. Not part of Porydaw and never executed by measured code.
//
// `BankHandle` is really defined in ProjectContext.swift, which imports the
// native loader module (Qt-linked C++; unbuildable with stock swiftc). The
// startup stages this benchmark executes never reference `BankHandle` or
// `LoadedBankView`: build.sh aborts the build if any compiled project source
// Production marks the real handle @unchecked Sendable for the same reason:
// it wraps a thread-safe native reference count (ProjectContext.swift:57).
public final class BankHandle: @unchecked Sendable {}

// BENCH-ONLY COPIES of the loader's packed VOICE_* tags, values transcribed
// verbatim from external/poryaaaa voicegroup_types.h. Only consumed by
// vgMacroVoiceType, which no measured stage calls.
public let VOICE_DIRECTSOUND: Int32 = 0x00
public let VOICE_SQUARE_1: Int32 = 0x01
public let VOICE_SQUARE_2: Int32 = 0x02
public let VOICE_PROGRAMMABLE_WAVE: Int32 = 0x03
public let VOICE_NOISE: Int32 = 0x04
public let VOICE_DIRECTSOUND_NO_RESAMPLE: Int32 = 0x08
public let VOICE_SQUARE_1_ALT: Int32 = 0x09
public let VOICE_SQUARE_2_ALT: Int32 = 0x0A
public let VOICE_PROGRAMMABLE_WAVE_ALT: Int32 = 0x0B
public let VOICE_NOISE_ALT: Int32 = 0x0C
public let VOICE_DIRECTSOUND_ALT: Int32 = 0x10
public let VOICE_KEYSPLIT: Int32 = 0x40
public let VOICE_KEYSPLIT_ALL: Int32 = 0x80

// BENCH-ONLY SHAPE-ALIKE of the loader's ToneData (field names and scalar
// types match voicegroup_types.h; layout is Swift's, not the C union
// layout). Only consumed by applyScalarsToToneData, which no measured
// stage calls.
public struct ToneData {
    public var type: UInt8 = 0
    public var key: UInt8 = 0
    public var length: UInt8 = 0
    public var panSweep: UInt8 = 0
    public var wavePointer: UnsafeMutablePointer<UInt32>?
    public var attack: UInt8 = 0
    public var decay: UInt8 = 0
    public var sustain: UInt8 = 0
    public var release: UInt8 = 0
}
