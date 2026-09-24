import Foundation
import PorydawProjectNative

/// A detached audio preview; no pointer into the project loader escapes its worker.
public enum PickerSound: Sendable {
    case sample(bytes: [Int8], frequency: UInt32, loopStart: UInt32,
                looped: Bool, toneKey: UInt8, envelope: (UInt8, UInt8, UInt8, UInt8)?)
    case wave(bytes: [UInt8], envelope: (UInt8, UInt8, UInt8, UInt8)?)
}

struct PickerSampleCache {
    let set: SampleSetHandle
    let direct: [String]
    let waves: [String]
    let keysplits: [(symbol: String, table: String)]
}

extension ProjectStore {
    /// Resolves the picker's symbol through the same project loader as the bank.
    /// - Parameters:
    ///   - symbol: The complete assembler symbol.
    ///   - kind: `sample`, `wave`, or `keysplit`.
    /// - Returns: Playable detached bytes, or nil for an unresolved or unsupported instrument.
    public func pickerSound(symbol: String, kind: String) -> PickerSound? {
        guard let projectContext else { return nil }
        let cache: PickerSampleCache
        if let pickerSamples {
            cache = pickerSamples
        } else {
            let direct = VoicegroupSource.directSoundSymbols(projectRoot)
            let waves = VoicegroupSource.progWaveSymbols(projectRoot)
            let keysplits = VoicegroupSource.keysplitInstruments(projectRoot)
            guard let set = projectContext.loadSamples(
                direct: direct, wave: waves, keysplit: keysplits.map(\.symbol),
                tables: keysplits.map(\.table)) else { return nil }
            cache = PickerSampleCache(set: set, direct: direct, waves: waves,
                                      keysplits: keysplits)
            pickerSamples = cache
        }
        let set = cache.set
        switch kind {
        case "sample":
            guard let index = cache.direct.firstIndex(of: symbol),
                  index < Int(set.raw.pointee.count),
                  let wave = set.raw.pointee.waves[index] else { return nil }
            return Self.sampleSound(wave)
        case "wave":
            guard let index = cache.waves.firstIndex(of: symbol),
                  index < Int(set.raw.pointee.progWaveCount),
                  let wave = set.raw.pointee.progWaves[index] else { return nil }
            return Self.waveSound(wave)
        case "keysplit":
            guard let index = cache.keysplits.firstIndex(where: { $0.symbol == symbol }),
                  index < Int(set.raw.pointee.keysplitCount) else { return nil }
            let split = set.raw.pointee.keysplits[index]
            guard let table = split.table, let group = split.subGroup else { return nil }
            let subIndex = Int(table[60])
            guard subIndex < 128 else { return nil }
            let tone = group[subIndex]
            guard tone.type & 0xC0 == 0 else { return nil }
            let envelope: (UInt8, UInt8, UInt8, UInt8) =
                (tone.attack, tone.decay, tone.sustain, tone.release)
            if tone.type & 7 == 0, let wave = tone.wav {
                return Self.sampleSound(wave, toneKey: tone.key, envelope: envelope)
            }
            if tone.type & 7 == 3, let wave = tone.wavePointer {
                return Self.waveSound(wave, envelope: envelope)
            }
            return nil
        default:
            return nil
        }
    }

    private static func sampleSound(
        _ wave: UnsafeMutablePointer<WaveData>, toneKey: UInt8 = 60,
        envelope: (UInt8, UInt8, UInt8, UInt8)? = nil
    ) -> PickerSound? {
        guard let data = wave.pointee.data, wave.pointee.size > 0,
              let size = Int(exactly: wave.pointee.size) else { return nil }
        return .sample(bytes: Array(UnsafeBufferPointer(start: data, count: size)),
                       frequency: wave.pointee.freq, loopStart: wave.pointee.loopStart,
                       looped: wave.pointee.status & 0x4000 != 0,
                       toneKey: toneKey, envelope: envelope)
    }

    private static func waveSound(
        _ wave: UnsafeMutablePointer<UInt32>,
        envelope: (UInt8, UInt8, UInt8, UInt8)? = nil
    ) -> PickerSound {
        let bytes = wave.withMemoryRebound(to: UInt8.self, capacity: 16) {
            Array(UnsafeBufferPointer(start: $0, count: 16))
        }
        return .wave(bytes: bytes, envelope: envelope)
    }
}
