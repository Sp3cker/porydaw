import Foundation
import PorydawVoicegroupNative

private let bankStorageCapacity =
    128 + (128 * Int(VG_VOICE_NAME_LEN) + MemoryLayout<ToneData>.stride - 1) / MemoryLayout<ToneData>.stride

/// Owns the tone and display-name storage for one keysplit target.
public final class SubBank: ManagedBuffer<
    (voices: UnsafeMutablePointer<ToneData>, names: UnsafeMutablePointer<CChar>), ToneData
>
{
    public var voices: UnsafeMutablePointer<ToneData> { header.voices }
    public var names: UnsafeMutablePointer<CChar> { header.names }

    static func make() -> SubBank {
        create(minimumCapacity: bankStorageCapacity) { storage in
            // Tail storage is stable for the class lifetime; escaped voices serve the engine handoff exemption.
            storage.withUnsafeMutablePointerToElements { voices in
                initializeBankSlab(voices)
                let names = UnsafeMutableRawPointer(voices.advanced(by: 128))
                    .bindMemory(to: CChar.self, capacity: 128 * Int(VG_VOICE_NAME_LEN))
                return (voices, names)
            }
        } as! SubBank
    }

    /// Decodes a slot's bounded, NUL-terminated display name without trimming.
    public func name(at slot: Int) -> String {
        withExtendedLifetime(self) { bankVoiceName(names, at: slot) }
    }
}

/// Builder-only mutation finishes before publication; tones and all borrowed
/// allocations are immutable while the bank is shared with readers or the engine.
public final class Bank: ManagedBuffer<Bank.Storage, ToneData> {
    public struct Storage {
        let voices: UnsafeMutablePointer<ToneData>
        let names: UnsafeMutablePointer<CChar>
        var subBanks: [SubBank] = []
        var tables: [UnsafeMutablePointer<UInt8>] = []
        var waves: [UnsafeMutablePointer<WaveData>] = []
        var progWaves: [UnsafeMutablePointer<UInt32>] = []
        let cache: WaveCache
    }

    public var voices: UnsafeMutablePointer<ToneData> { header.voices }
    public var names: UnsafeMutablePointer<CChar> { header.names }
    public var subBanks: [SubBank] { header.subBanks }
    public var tables: [UnsafeMutablePointer<UInt8>] { header.tables }
    public var waves: [UnsafeMutablePointer<WaveData>] { header.waves }
    public var progWaves: [UnsafeMutablePointer<UInt32>] { header.progWaves }

    static func prepareOwnershipMetadata() {
        _ = Bank.self
        _ = SubBank.self
        _ = [SubBank]()
        _ = [UnsafeMutablePointer<UInt8>]()
        _ = [UnsafeMutablePointer<WaveData>]()
        _ = [UnsafeMutablePointer<UInt32>]()
    }

    public static func make(cache: WaveCache = WaveCache()) -> Bank {
        create(minimumCapacity: bankStorageCapacity) { storage in
            // Tail storage is stable for the class lifetime; escaped voices serve the engine handoff exemption.
            storage.withUnsafeMutablePointerToElements { voices in
                initializeBankSlab(voices)
                let names = UnsafeMutableRawPointer(voices.advanced(by: 128))
                    .bindMemory(to: CChar.self, capacity: 128 * Int(VG_VOICE_NAME_LEN))
                return Storage(voices: voices, names: names, cache: cache)
            }
        } as! Bank
    }

    deinit {
        for wave in header.waves { header.cache.release(wave) }
        // C-owned decoder/table allocations cross the engine boundary; ManagedBuffer frees its own slab.
        for wave in header.progWaves { free(wave) }
        for table in header.tables { free(table) }
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

    public func register(wave: UnsafeMutablePointer<WaveData>) {
        do {
            let registered = header.waves
            for index in 0..<registered.count {
                if registered[index] == wave { return }
            }
        }
        header.cache.retain(wave)
        header.waves.append(wave)
    }

    public func register(prog: UnsafeMutablePointer<UInt32>) {
        do {
            let registered = header.progWaves
            for index in 0..<registered.count {
                if registered[index] == prog { return }
            }
        }
        header.progWaves.append(prog)
    }

    func registerTable(_ source: borrowing Span<UInt8>) -> UnsafeMutablePointer<UInt8> {
        precondition(source.count == 128)
        guard let storage = malloc(128) else { preconditionFailure("Unable to allocate keysplit table") }
        let table = storage.bindMemory(to: UInt8.self, capacity: 128)
        var destination = MutableSpan(_unsafeStart: table, count: 128)
        var index = 0
        while index < 128 { destination[index] = source[index]; index += 1 }
        header.tables.append(table)
        return table
    }

    func register(subBank: SubBank) {
        header.subBanks.append(subBank)
    }
}

private func bankVoiceName(_ names: UnsafePointer<CChar>, at slot: Int) -> String {
    precondition(slot >= 0 && slot < 128, "Bank slot must be in 0..<128")
    let bytes = Span(
        _unsafeStart: UnsafeRawPointer(names).assumingMemoryBound(to: UInt8.self), count: 128 * Int(VG_VOICE_NAME_LEN))
    let offset = slot * Int(VG_VOICE_NAME_LEN)
    var length = 0
    while length < Int(VG_VOICE_NAME_LEN) && bytes[offset + length] != 0 { length += 1 }
    return AsmLine.text(bytes.extracting(offset..<(offset + length)))
}

private func initializeBankSlab(_ voices: UnsafeMutablePointer<ToneData>) {
    let count = 128 * (MemoryLayout<ToneData>.stride + Int(VG_VOICE_NAME_LEN))
    let storage = UnsafeMutableRawPointer(voices).assumingMemoryBound(to: UInt8.self)
    var bytes = MutableSpan(_unsafeStart: storage, count: count)
    bytes.update(repeating: 0)
}

