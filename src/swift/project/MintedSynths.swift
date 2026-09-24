import Foundation
import PorydawProjectNative

/// Native waveform storage pinned by the bank handle until its loader allocation is freed.
// Grafted only by the serialized store before publication; the native buffers stay pinned thereafter.
final class MintedSynthStorage: @unchecked Sendable {
    let waves: UnsafeMutablePointer<WaveData>
    let bytes: UnsafeMutablePointer<UInt8>

    init() {
        waves = .allocate(capacity: 128)
        waves.initialize(repeating: WaveData(), count: 128)
        bytes = .allocate(capacity: 128 * 17)
        bytes.initialize(repeating: 0, count: 128 * 17)
    }

    deinit {
        waves.deinitialize(count: 128)
        waves.deallocate()
        bytes.deinitialize(count: 128 * 17)
        bytes.deallocate()
    }

    func graft(slot: Int, descriptor: VgSynthDesc) -> UnsafeMutablePointer<WaveData> {
        let wave = waves.advanced(by: slot)
        let samples = bytes.advanced(by: slot * 17)
        wave.pointee.status = 0x4000
        wave.pointee.freq = 0x01058920
        wave.pointee.data = UnsafeMutableRawPointer(samples).assumingMemoryBound(to: Int8.self)
        samples[0] = 0x80
        samples[1] = UInt8(truncatingIfNeeded: descriptor.waveform)
        samples[2] = UInt8(truncatingIfNeeded: descriptor.baseDuty)
        samples[3] = UInt8(truncatingIfNeeded: descriptor.dutyStep)
        samples[4] = UInt8(truncatingIfNeeded: descriptor.modDepth)
        samples[5] = UInt8(truncatingIfNeeded: descriptor.phase)
        return wave
    }
}

/// Decodes the canonical Golden Sun synth symbol and optional decimal collision suffix.
/// - Parameter symbol: The voice's exact assembler symbol.
/// - Returns: Its pulse, saw, or triangle descriptor, or nil for a non-minted symbol.
public func mintedSynthDesc(symbol: String) -> VgSynthDesc? {
    let stem = "DirectSoundSynth_GoldenSun_"
    guard symbol.hasPrefix(stem) else { return nil }
    let suffix = symbol.dropFirst(stem.count)
    if suffix == "Saw" || (suffix.hasPrefix("Saw") &&
        mintedCollisionSuffix(suffix.dropFirst(3))) {
        return VgSynthDesc(waveform: 1)
    }
    if suffix == "Triangle" || (suffix.hasPrefix("Triangle") &&
        mintedCollisionSuffix(suffix.dropFirst(8))) {
        return VgSynthDesc(waveform: 2)
    }
    let hex = suffix.prefix(8)
    guard hex.utf8.count == 8,
          hex.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) }),
          mintedCollisionSuffix(suffix.dropFirst(8)),
          let packed = UInt32(hex, radix: 16) else { return nil }
    return VgSynthDesc(waveform: 0, baseDuty: Int((packed >> 24) & 0xff),
                       dutyStep: Int((packed >> 16) & 0xff),
                       modDepth: Int((packed >> 8) & 0xff), phase: Int(packed & 0xff))
}

private func mintedCollisionSuffix(_ suffix: Substring) -> Bool {
    if suffix.isEmpty { return true }
    guard suffix.first == "_" else { return false }
    let digits = suffix.dropFirst()
    return !digits.isEmpty && digits.utf8.allSatisfy { (48...57).contains($0) }
}

extension BankHandle {
    /// Fills only unresolved direct-sound voices carrying canonical minted synth symbols.
    /// - Parameter source: The editable voicegroup that produced this loader bank.
    func graftMintedSynths(source: VoicegroupSource) {
        withUnsafeMutablePointer(to: &raw.pointee.voices) { tuple in
            tuple.withMemoryRebound(to: ToneData.self, capacity: 128) { tones in
                for slot in 0..<128 {
                    guard let voice = source.voiceAt(slot: slot), tones[slot].wav == nil else { continue }
                    switch voice.macro {
                    case .directSound, .directSoundNoResample, .directSoundAlt: break
                    default: continue
                    }
                    guard let descriptor = mintedSynthDesc(symbol: voice.symbol) else { continue }
                    let storage = mintedStorage ?? MintedSynthStorage()
                    mintedStorage = storage
                    tones[slot].wav = storage.graft(slot: slot, descriptor: descriptor)
                }
            }
        }
    }
}
