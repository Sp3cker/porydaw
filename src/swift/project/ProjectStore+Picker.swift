import Foundation
import PorydawVoicegroup
import PorydawVoicegroupNative

/// A detached audio preview; no pointer into a bank escapes the project worker.
public enum PickerSound: Sendable {
    case sample(
        bytes: [Int8], frequency: UInt32, loopStart: UInt32,
        looped: Bool, toneKey: UInt8, envelope: (UInt8, UInt8, UInt8, UInt8)?)
    case wave(bytes: [UInt8], envelope: (UInt8, UInt8, UInt8, UInt8)?)
}

/// Committed direct-sound metadata shown in the sample picker.
public struct PickerSampleInfo: Sendable, Equatable {
    public let looped: Bool
    public let rateHz: Int
    public let seconds: Double

    public init(looped: Bool, rateHz: Int, seconds: Double) {
        self.looped = looped
        self.rateHz = rateHz
        self.seconds = seconds
    }
}

struct PickerSampleCache {
    let bank: Bank
    let direct: [String: UnsafeMutablePointer<WaveData>]
    let waves: [String: UnsafeMutablePointer<UInt32>]
    let keysplits: [String: (bank: Bank, table: KeysplitTable)]
}

extension ProjectStore {
    /// Reads direct-sound metadata from the project's cached decoded samples.
    /// - Returns: Metadata for loaded symbols with nonempty sample data.
    public func pickerSampleInfo() -> [String: PickerSampleInfo] {
        guard let cache = loadPickerSamples() else { return [:] }
        return withExtendedLifetime(cache.bank) {
        var info: [String: PickerSampleInfo] = [:]
        info.reserveCapacity(cache.direct.count)
            for (symbol, reference) in cache.direct {
                let wave = reference
                guard wave.pointee.data != nil, wave.pointee.size > 0
            else { continue }
            let rateHz = Int(wave.pointee.freq / 1024)
            guard rateHz > 0 else { continue }
            info[symbol] = PickerSampleInfo(
                looped: wave.pointee.status & 0x4000 != 0,
                rateHz: rateHz, seconds: Double(wave.pointee.size) / Double(rateHz))
        }
        return info
        }
    }

    /// Resolves the picker's symbol through the same Swift builder as loaded banks.
    /// - Parameters:
    ///   - symbol: The complete assembler symbol.
    ///   - kind: `sample`, `wave`, or `keysplit`.
    /// - Returns: Playable detached bytes, or nil for an unresolved or unsupported instrument.
    public func pickerSound(symbol: String, kind: String) -> PickerSound? {
        guard let cache = loadPickerSamples() else { return nil }
        switch kind {
        case "sample":
            guard let wave = cache.direct[symbol] else { return nil }
            return Self.sampleSound(wave, bank: cache.bank)
        case "wave":
            guard let wave = cache.waves[symbol] else { return nil }
            return withExtendedLifetime(cache.bank) { Self.waveSound(wave) }
        case "keysplit":
            guard let split = cache.keysplits[symbol] else { return nil }
            return withExtendedLifetime(split.bank) {
                let subIndex = Int(split.table.table[60])
            guard subIndex < 128 else { return nil }
                let tone = Span(_unsafeStart: split.bank.voices, count: 128)[subIndex]
            guard tone.type & 0xC0 == 0 else { return nil }
            let envelope: (UInt8, UInt8, UInt8, UInt8) =
                (tone.attack, tone.decay, tone.sustain, tone.release)
            if tone.type & 7 == 0, let wave = tone.wav {
                    return Self.sampleSound(wave, bank: split.bank, toneKey: tone.key, envelope: envelope)
            }
            if tone.type & 7 == 3, let wave = tone.wavePointer {
                return Self.waveSound(wave, envelope: envelope)
            }
            return nil
            }
        default:
            return nil
        }
    }

    private func loadPickerSamples() -> PickerSampleCache? {
        guard let store = voicegroupStore else { return nil }
        if let pickerSamples { return pickerSamples }
        do {
            let inputs = try store.bankBuildInputs()
            let builder = BankBuilder(inputs: inputs)
            let bank = Bank.make(cache: inputs.cache)
            var direct: [String: UnsafeMutablePointer<WaveData>] = [:]
            var waves: [String: UnsafeMutablePointer<UInt32>] = [:]
            var keysplits: [String: (bank: Bank, table: KeysplitTable)] = [:]
            for symbol in VoicegroupSource.directSoundSymbols(projectRoot) {
                if let wave = try builder.resolveSample(symbol: Array(symbol.utf8)[...]) {
                    bank.register(wave: wave)
                    direct[symbol] = wave
                }
            }
            for symbol in VoicegroupSource.progWaveSymbols(projectRoot) {
                if let wave = try builder.resolveProgWave(symbol: Array(symbol.utf8)[...]) {
                    bank.register(prog: wave)
                    waves[symbol] = wave
                }
            }
            var tables = inputs.keysplits
            var scannedTables = false
            for instrument in VoicegroupSource.keysplitInstruments(projectRoot) {
                guard let location = inputs.locator.locateSubgroup(symbol: Array(instrument.symbol.utf8)[...]) else {
                    continue
                }
                let text = try inputs.textProvider(location, true, false)
                let bank = try builder.build(text, at: location)
                if tables.table(named: instrument.table) == nil, !scannedTables {
                    tables = try KeysplitTables.parse(files: inputs.layout.ensuringDeepScan().keysplitTableFiles)
                    scannedTables = true
                }
                guard let table = tables.table(named: instrument.table) else { continue }
                keysplits[instrument.symbol] = (bank, table)
            }
            let cache = PickerSampleCache(bank: bank, direct: direct, waves: waves, keysplits: keysplits)
            pickerSamples = cache
            return cache
        } catch {
            return nil
        }
    }

    private static func sampleSound(
        _ wave: UnsafeMutablePointer<WaveData>, bank: Bank, toneKey: UInt8 = 60,
        envelope: (UInt8, UInt8, UInt8, UInt8)? = nil
    ) -> PickerSound? {
        withExtendedLifetime(bank) {
            let header = Span(_unsafeStart: wave, count: 1)[0]
            guard let data = header.data, header.size > 0, let size = Int(exactly: header.size) else { return nil }
            // Bulk snapshot A/B evidence: docs/BUILDING.md, "Voicegroup loading: parity and performance gate".
            let bytes = Array(UnsafeBufferPointer(start: data, count: size))
            return .sample(
                bytes: bytes, frequency: header.freq, loopStart: header.loopStart,
                looped: header.status & 0x4000 != 0, toneKey: toneKey, envelope: envelope)
        }
    }

    private static func waveSound(
        _ wave: UnsafeMutablePointer<UInt32>,
        envelope: (UInt8, UInt8, UInt8, UInt8)? = nil
    ) -> PickerSound {
        let words = Span(_unsafeStart: wave, count: 4)
        let source = Span<UInt8>(viewing: words.bytes)
        let bytes = [UInt8](capacity: 16) { output in
            var index = 0
            while index < 16 { output.append(source[index]); index += 1 }
        }
        return .wave(bytes: bytes, envelope: envelope)
    }
}
