import Foundation
import PorydawVoicegroup
import PorydawVoicegroupNative

#if canImport(CryptoKit)
    import CryptoKit
#endif

struct BankDigest: Equatable, Codable {
    struct Slot: Equatable, Codable {
        var type, key, length, panSweep, attack, decay, sustain, release: UInt8
        var waveKey: String
        var progKey: String
        var wavePointerBits: UInt8
        var tableKey: String
        var subBank: BankDigest?
        var name: String
    }

    var slots: [Slot]

    static func of(_ bank: UnsafePointer<LoadedVoiceGroup>) -> BankDigest {
        guard let voicesOffset = MemoryLayout<LoadedVoiceGroup>.offset(of: \.voices),
            let namesOffset = MemoryLayout<LoadedVoiceGroup>.offset(of: \.voiceNames)
        else {
            preconditionFailure("LoadedVoiceGroup inline tables must have stored offsets")
        }
        let raw = UnsafeRawPointer(bank)
        let voices = raw.advanced(by: voicesOffset).assumingMemoryBound(to: ToneData.self)
        let names = raw.advanced(by: namesOffset).assumingMemoryBound(to: CChar.self)
        return of(voices: voices, names: names) { subgroup in
            guard
                let names = voicegroup_subgroup_names(
                    bank, subgroup.assumingMemoryBound(to: ToneData.self))
            else { return nil }
            return UnsafeRawPointer(names).assumingMemoryBound(to: CChar.self)
        }
    }

    static func of(_ bank: Bank) -> BankDigest {
        withExtendedLifetime(bank) {
            of(voices: bank.voices, names: bank.names) { subgroup in
                guard let subBank = bank.subBanks.first(where: { UnsafeRawPointer($0.voices) == subgroup }) else {
                    return nil
                }
                return UnsafePointer(subBank.names)
            }
        }
    }

    static func of(
        voices: UnsafePointer<ToneData>, names: UnsafePointer<CChar>,
        subBankNames: (UnsafeRawPointer) -> UnsafePointer<CChar>?
    ) -> BankDigest {
        digest(voices: voices, names: names, subBankNames: subBankNames)
    }

    private static func digest(
        voices: UnsafePointer<ToneData>, names: UnsafePointer<CChar>?,
        subBankNames: (UnsafeRawPointer) -> UnsafePointer<CChar>?
    ) -> BankDigest {
        var slots: [Slot] = []
        slots.reserveCapacity(Int(VOICEGROUP_SIZE))
        for index in 0..<Int(VOICEGROUP_SIZE) {
            let tone = voices[index]
            var waveKey = "nil"
            var progKey = "nil"
            var wavePointerBits: UInt8 = 0
            var tableKey = "nil"
            var subBank: BankDigest?
            if tone.type == UInt8(VOICE_KEYSPLIT) || tone.type == UInt8(VOICE_KEYSPLIT_ALL) {
                if let subgroup = tone.subGroup {
                    let raw = UnsafeRawPointer(subgroup)
                    subBank = digest(
                        voices: raw.assumingMemoryBound(to: ToneData.self),
                        names: subBankNames(raw), subBankNames: subBankNames)
                }
                if let table = tone.keySplitTable {
                    tableKey = hex(UnsafeBufferPointer(start: table, count: Int(VOICEGROUP_SIZE)))
                }
            } else {
                switch tone.type & UInt8(VOICE_TYPE_CGB_MASK) {
                case UInt8(VOICE_DIRECTSOUND):
                    if let wave = tone.wav { waveKey = waveDigest(wave) }
                case UInt8(VOICE_PROGRAMMABLE_WAVE):
                    if let pointer = tone.wavePointer {
                        progKey = hex(UnsafeRawBufferPointer(start: pointer, count: 16))
                    }
                case UInt8(VOICE_SQUARE_1), UInt8(VOICE_SQUARE_2), UInt8(VOICE_NOISE):
                    wavePointerBits = UInt8(UInt(bitPattern: tone.wavePointer) & 3)
                default:
                    break
                }
            }
            let name: String
            if let names {
                name = String(cString: names.advanced(by: index * Int(VG_VOICE_NAME_LEN)))
            } else {
                name = ""
            }
            slots.append(
                Slot(
                    type: tone.type, key: tone.key, length: tone.length, panSweep: tone.panSweep,
                    attack: tone.attack, decay: tone.decay, sustain: tone.sustain, release: tone.release,
                    waveKey: waveKey, progKey: progKey, wavePointerBits: wavePointerBits,
                    tableKey: tableKey, subBank: subBank, name: name))
        }
        return BankDigest(slots: slots)
    }

    private static func waveDigest(_ pointer: UnsafePointer<WaveData>) -> String {
        let wave = pointer.pointee
        var hash = WaveHasher()
        hash.append(wave.type)
        hash.append(wave.status)
        hash.append(wave.freq)
        hash.append(wave.loopStart)
        hash.append(wave.size)
        if wave.size > 0 {
            precondition(wave.data != nil, "A nonempty decoded wave must have PCM storage")
            hash.update(UnsafeRawBufferPointer(start: wave.data, count: Int(wave.size)))
        }
        return hash.finish()
    }

    private static func hex<Bytes: Collection>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            let high = byte >> 4
            let low = byte & 15
            result.append(high < 10 ? high + 48 : high + 87)
            result.append(low < 10 ? low + 48 : low + 87)
        }
        return String(decoding: result, as: UTF8.self)
    }

    private struct WaveHasher {
        #if canImport(CryptoKit)
            private var hash = SHA256()
        #else
            private var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        #endif

        mutating func append<Value: FixedWidthInteger>(_ value: Value) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { update($0) }
        }

        mutating func update(_ bytes: UnsafeRawBufferPointer) {
            #if canImport(CryptoKit)
                hash.update(bufferPointer: bytes)
            #else
                for byte in bytes {
                    hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
                }
            #endif
        }

        mutating func finish() -> String {
            #if canImport(CryptoKit)
                return BankDigest.hex(Array(hash.finalize()))
            #else
                var bigEndian = hash.bigEndian
                return withUnsafeBytes(of: &bigEndian) { BankDigest.hex($0) }
            #endif
        }
    }
}
