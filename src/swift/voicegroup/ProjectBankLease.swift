import Foundation
import PorydawVoicegroupNative

/// Pins a bank through ARC and carries an immutable snapshot of its source publication.
/// Consumers read value accessors; `engineVoices` is the single raw engine handoff.
public final class ProjectBankLease: @unchecked Sendable {
    let bank: Bank
    public let id: VoicegroupId
    public let loadName: String
    public let sectionLabel: String
    public let dirty: Bool
    public let slotViews: [VoicegroupSlotView]
    public let publicationOwner: UUID
    public let publicationRevision: UInt64

    public init(bank: Bank, view: LoadedBankView, publicationOwner: UUID, publicationRevision: UInt64) {
        self.bank = bank
        id = view.id
        loadName = view.loadName
        sectionLabel = view.id.sectionLabel
        dirty = view.dirty
        slotViews = view.slotViews
        self.publicationOwner = publicationOwner
        self.publicationRevision = publicationRevision
    }

    /// Whether both leases pin the same loaded bank.
    public func sharesBank(with other: ProjectBankLease) -> Bool {
        bank === other.bank
    }

    /// A value copy of the loaded tone in `slot`.
    public subscript(slot: Int) -> ToneData {
        withVoice(at: slot) { $0.pointee }
    }

    /// The loader's name for `slot`, decoded up to its NUL terminator, untrimmed.
    public func voiceName(at slot: Int) -> String {
        Self.requireSlot(slot)
        return bank.name(at: slot)
    }

    /// Resolves the split facts of the tone in `slot` into `VgMacro` ordinals per MIDI key.
    /// Nil for a non-split tone; -1 marks an invalid child.
    public func subvoiceMacros(at slot: Int) -> [Int32]? {
        withVoice(at: slot) { voice in
            let tone = voice.pointee
            let split = tone.type & UInt8(VOICE_KEYSPLIT | VOICE_KEYSPLIT_ALL)
            guard split != 0 else { return nil }
            guard let group = tone.subGroup?.assumingMemoryBound(to: ToneData.self),
                tone.type & UInt8(VOICE_KEYSPLIT) == 0 || tone.keySplitTable != nil
            else {
                return Array(repeating: -1, count: 128)
            }
            return (0..<128).map { key in
                let index: Int
                if tone.type & UInt8(VOICE_KEYSPLIT_ALL) != 0 {
                    index = key
                } else if let table = tone.keySplitTable {
                    index = Int(table[key])
                } else {
                    return -1
                }
                guard index < Int(VOICEGROUP_SIZE) else { return -1 }
                let type = group[index].type
                guard type & UInt8(VOICE_KEYSPLIT | VOICE_KEYSPLIT_ALL) == 0 else { return -1 }
                switch type & UInt8(VOICE_TYPE_CGB_MASK) {
                case UInt8(VOICE_SQUARE_1): return VgMacro.square1.rawValue
                case UInt8(VOICE_SQUARE_2): return VgMacro.square2.rawValue
                case UInt8(VOICE_PROGRAMMABLE_WAVE): return VgMacro.progWave.rawValue
                case UInt8(VOICE_NOISE): return VgMacro.noise.rawValue
                default:
                    return type == UInt8(VOICE_DIRECTSOUND) || type == UInt8(VOICE_DIRECTSOUND_NO_RESAMPLE)
                        || type == UInt8(VOICE_DIRECTSOUND_ALT) ? VgMacro.directSound.rawValue : -1
                }
            }
        }
    }

    /// Display names indexed by MIDI key for a drumkit (keysplit-all) tone in `slot`;
    /// nil for any other tone. Unnamed pads are empty.
    public func drumPadNames(at slot: Int) -> [String]? {
        withVoice(at: slot) { voice in
            let tone = voice.pointee
            guard tone.type == UInt8(VOICE_KEYSPLIT_ALL), let subgroup = bank.subBank(for: tone) else { return nil }
            return (0..<128).map { subgroup.name(at: $0) }
        }
    }

    /// The bank's voice array, for handing to the C audio engine, which stores it.
    /// Valid only while the caller retains this lease. Never use it in document-layer code;
    /// read tones through the value accessors instead.
    @unsafe public var engineVoices: UnsafeMutablePointer<ToneData> { bank.voices }

    private func withVoice<T>(at slot: Int, _ body: (UnsafeMutablePointer<ToneData>) -> T) -> T {
        Self.requireSlot(slot)
        return withExtendedLifetime(bank) { body(bank.voices + slot) }
    }

    private static func requireSlot(_ slot: Int) {
        precondition((0..<Int(VOICEGROUP_SIZE)).contains(slot), "Voicegroup slot \(slot) is out of range.")
    }
}

extension ToneData {
    /// Loader-confirmed synth descriptor: a DirectSound tone whose wave is an
    /// in-memory minted synth (zero size, non-null data).
    public var isMintedSynthDescriptor: Bool {
        type & 0xE7 == 0 && wav?.pointee.size == 0 && wav?.pointee.data != nil
    }
}
