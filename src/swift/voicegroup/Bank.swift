import Foundation
import PorydawVoicegroupNative

/// Owns one decoder allocation; its header and payload are immutable after build.
public final class WaveRef: @unchecked Sendable {
    public let raw: UnsafeMutablePointer<WaveData>
    public let path: String

    init(raw: UnsafeMutablePointer<WaveData>, path: String) {
        self.raw = raw
        self.path = path
    }

    deinit { free(raw) }
}

/// Owns one packed-wave allocation; its bytes are immutable after build.
public final class ProgWaveRef: @unchecked Sendable {
    public let raw: UnsafeMutablePointer<UInt32>
    public let path: String

    init(raw: UnsafeMutablePointer<UInt32>, path: String) {
        self.raw = raw
        self.path = path
    }

    deinit { free(raw) }
}

/// Owns the tone and display-name buffers for one keysplit target.
public final class SubBank {
    public let voices: UnsafeMutablePointer<ToneData>
    public let names: UnsafeMutablePointer<CChar>

    init() {
        guard let voiceStorage = calloc(128, MemoryLayout<ToneData>.stride),
            let nameStorage = calloc(128, Int(VG_VOICE_NAME_LEN))
        else { preconditionFailure("Unable to allocate sub-bank storage") }
        voices = voiceStorage.bindMemory(to: ToneData.self, capacity: 128)
        names = nameStorage.bindMemory(to: CChar.self, capacity: 128 * Int(VG_VOICE_NAME_LEN))
    }

    deinit {
        free(voices)
        free(names)
    }

    /// Decodes a slot's bounded, NUL-terminated display name without trimming.
    public func name(at slot: Int) -> String {
        withExtendedLifetime(self) { bankVoiceName(names, at: slot) }
    }
}

/// Builder-only mutation finishes before publication; tones and all borrowed
/// allocations are immutable while the bank is shared with readers or the engine.
public final class Bank: @unchecked Sendable {
    public let voices: UnsafeMutablePointer<ToneData>
    public let names: UnsafeMutablePointer<CChar>
    public private(set) var subBanks: [SubBank] = []
    public private(set) var tables: [UnsafeMutablePointer<UInt8>] = []
    public private(set) var waves: [WaveRef] = []
    public private(set) var progWaves: [ProgWaveRef] = []

    public init() {
        guard let voiceStorage = calloc(128, MemoryLayout<ToneData>.stride),
            let nameStorage = calloc(128, Int(VG_VOICE_NAME_LEN))
        else { preconditionFailure("Unable to allocate bank storage") }
        voices = voiceStorage.bindMemory(to: ToneData.self, capacity: 128)
        names = nameStorage.bindMemory(to: CChar.self, capacity: 128 * Int(VG_VOICE_NAME_LEN))
    }

    deinit {
        for table in tables { free(table) }
        subBanks.removeAll()
        free(names)
        free(voices)
    }

    /// Decodes a slot's bounded, NUL-terminated display name without trimming.
    public func name(at slot: Int) -> String {
        withExtendedLifetime(self) { bankVoiceName(names, at: slot) }
    }

    /// Finds the registered sub-bank by the identity of the tone's subgroup pointer.
    public func subBank(for tone: ToneData) -> SubBank? {
        guard let subgroup = tone.subGroup else { return nil }
        return subBanks.first { UnsafeMutableRawPointer($0.voices) == subgroup }
    }

    func register(wave: WaveRef) {
        guard !waves.contains(where: { $0 === wave }) else { return }
        waves.append(wave)
    }

    func register(prog: ProgWaveRef) {
        guard !progWaves.contains(where: { $0 === prog }) else { return }
        progWaves.append(prog)
    }

    func registerTable(_ bytes: UnsafePointer<UInt8>) -> UnsafeMutablePointer<UInt8> {
        guard let storage = malloc(128) else { preconditionFailure("Unable to allocate keysplit table") }
        let table = storage.bindMemory(to: UInt8.self, capacity: 128)
        memcpy(table, bytes, 128)
        tables.append(table)
        return table
    }

    func register(subBank: SubBank) {
        subBanks.append(subBank)
    }
}

private func bankVoiceName(_ names: UnsafePointer<CChar>, at slot: Int) -> String {
    precondition(slot >= 0 && slot < 128, "Bank slot must be in 0..<128")
    let start = names.advanced(by: slot * Int(VG_VOICE_NAME_LEN))
    var length = 0
    while length < Int(VG_VOICE_NAME_LEN) && start[length] != 0 { length += 1 }
    let bytes = UnsafeRawPointer(start).assumingMemoryBound(to: UInt8.self)
    return String(decoding: UnsafeBufferPointer(start: bytes, count: length), as: UTF8.self)
}
