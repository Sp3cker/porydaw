import Foundation
import PorydawCore
import PorydawProject
import PorydawBankLease

// MARK: - Public errors

/// Typed failures for the project store boundary.
public enum ProjectServiceError: Error, Equatable, Sendable {
    /// The service is closed; no further operations are accepted.
    case serviceClosed
    /// A hard project-store failure with the underlying message.
    case operationFailed(String)
    /// A requested label is not a playable song in this project.
    case songNotPlayable(label: String)
    /// A playable song's MIDI source cannot be read.
    case songMidiUnavailable(label: String, path: String)
    /// The requested song's voicegroup argument cannot resolve a bank.
    case songBankUnavailable(label: String, voicegroupArgument: String, reason: String)
    /// The requested song's MIDI destination cannot be written.
    case songSaveUnavailable(label: String, path: String)
    /// The bank changed underneath the edit (stale expected value, occupied
    /// blank slot, out-of-range slot, spent materialization token). The
    /// document is unchanged; the caller decides the conflict policy.
    case bankConflict
}

// MARK: - Public bank vocabulary

/// VgMacro ordinals.
public enum BankVoiceMacro {
    public static let directSound: Int32 = 0
    public static let directSoundNoResample: Int32 = 1
    public static let directSoundAlt: Int32 = 2
    public static let square1: Int32 = 3
    public static let square1Alt: Int32 = 4
    public static let square2: Int32 = 5
    public static let square2Alt: Int32 = 6
    public static let programmableWave: Int32 = 7
    public static let programmableWaveAlt: Int32 = 8
    public static let noise: Int32 = 9
    public static let noiseAlt: Int32 = 10
    public static let keysplit: Int32 = 11
    public static let keysplitAll: Int32 = 12
}

/// VgLineKind ordinals.
public enum BankSlotKind {
    public static let none: Int32 = 0
    public static let other: Int32 = 1
    public static let header: Int32 = 2
    public static let editable: Int32 = 3
    public static let readOnlyVoice: Int32 = 4
    public static let broken: Int32 = 5
}

/// One editable voice's parsed macro arguments.
public struct BankVoice: Equatable, Sendable {
    public var macro: Int32
    public var key: Int32
    public var pan: Int32
    public var symbol: String
    public var keysplitTable: String
    public var sweep: Int32
    public var duty: Int32
    public var period: Int32
    public var attack: Int32
    public var decay: Int32
    public var sustain: Int32
    public var release: Int32

    public init(macro: Int32 = BankVoiceMacro.directSound, key: Int32 = 60, pan: Int32 = 0,
                symbol: String = "", keysplitTable: String = "", sweep: Int32 = 0,
                duty: Int32 = 2, period: Int32 = 0, attack: Int32 = 0, decay: Int32 = 0,
                sustain: Int32 = 0, release: Int32 = 0) {
        self.macro = macro
        self.key = key
        self.pan = pan
        self.symbol = symbol
        self.keysplitTable = keysplitTable
        self.sweep = sweep
        self.duty = duty
        self.period = period
        self.attack = attack
        self.decay = decay
        self.sustain = sustain
        self.release = release
    }
}

/// The scalar envelope of a loaded tone; keysplit/drumkit tones carry none.
public struct BankToneAdsr: Equatable, Sendable {
    public var attack: Int32
    public var decay: Int32
    public var sustain: Int32
    public var release: Int32

    public init(attack: Int32, decay: Int32, sustain: Int32, release: Int32) {
        self.attack = attack
        self.decay = decay
        self.sustain = sustain
        self.release = release
    }
}

/// The immutable loaded bank's tone for a slot the source model does not
/// cover with a parsed voice (read-only cry lines, broken lines, headers).
public struct BankTone: Equatable, Sendable {
    /// Trimmed voiceNames[slot]; empty when the tone carries no name.
    public var name: String
    /// The raw ToneData.type byte (VOICE_* constants).
    public var type: Int32
    /// toneIsSynth: a fix/alt-free type byte with a zero-size wav descriptor.
    public var isSynth: Bool
    /// The scalar envelope; nil for keysplit/drumkit tones.
    public var adsr: BankToneAdsr?

    public init(name: String, type: Int32, isSynth: Bool, adsr: BankToneAdsr?) {
        self.name = name
        self.type = type
        self.isSynth = isSynth
        self.adsr = adsr
    }
}

/// One published bank slot.
public struct BankSlotView: Equatable, Sendable {
    /// BankSlotKind ordinal.
    public var kind: Int32
    /// The parsed voice when kind is editable.
    public var voice: BankVoice?
    /// The loaded bank's tone when the slot has no parsed voice and is not
    /// blank; nil for editable and blank slots.
    public var tone: BankTone?
    /// Loader-confirmed synth descriptor, including in-memory minted symbols
    /// absent from the current on-disk catalog.
    public var isSynth: Bool
    /// Native split facts copied once at publication; -1 is an invalid child.
    public var subvoiceMacros: [Int32]?
    /// Detached display names indexed by MIDI key for a loaded drumkit.
    public var drumPadNames: [String]?

    public init(kind: Int32 = BankSlotKind.none, voice: BankVoice? = nil,
                tone: BankTone? = nil, subvoiceMacros: [Int32]? = nil,
                drumPadNames: [String]? = nil, isSynth: Bool = false) {
        self.kind = kind
        self.voice = voice
        self.tone = tone
        self.subvoiceMacros = subvoiceMacros
        self.drumPadNames = drumPadNames
        self.isSynth = isSynth
    }

    public func subvoiceMacro(forKey key: Int) -> Int32? {
        guard (0..<128).contains(key), let subvoiceMacros,
              subvoiceMacros.indices.contains(key), subvoiceMacros[key] >= 0 else { return nil }
        return subvoiceMacros[key]
    }
}

// MARK: - Owned bank lease

/// Retains one actor-owned bank lease. Applied edits mint a fresh lease;
/// the superseded wrapper keeps its own bank alive, so old views stay valid.
public final class NativeBankLease: Sendable {
    let handle: ProjectBankLease
    /// Voicegroup identity, copied from the published view for save requests.
    public let sourcePath: String
    public let sectionLabel: String
    internal let publicationOwner: UUID
    /// Monotonically increasing revision of this published project bank view.
    public let publicationRevision: UInt64

    fileprivate init(handle: ProjectBankLease) {
        self.handle = handle
        sourcePath = handle.id.sourceRelativePath
        sectionLabel = handle.sectionLabel
        publicationOwner = handle.publicationOwner
        publicationRevision = handle.publicationRevision
    }

    /// Identity of the underlying native bank, for reuse/validity checks.
    public var bankToken: UInt { handle.bankToken }

    /// Borrows the native voice array while this lease keeps its bank alive.
    /// The pointer must not be retained beyond the lease's lifetime.
    /// - Parameter body: A synchronous operation on the borrowed voices.
    /// - Returns: The operation's result.
    /// - Throws: Any error thrown by `body`.
    public func withVoices<T>(_ body: (UnsafeMutablePointer<ToneData>?) throws -> T) rethrows -> T {
        let voices = handle.withNativeBank { box -> UnsafeMutablePointer<ToneData>? in
            let nativeLease = pd_bank_lease_native(box)
            guard let storage = nativeLease.pointee.__getUnsafe(),
                  let offset = MemoryLayout<LoadedVoiceGroup>.offset(of: \.voices) else {
                return nil
            }
            return UnsafeMutableRawPointer(mutating: storage).advanced(by: offset)
                .assumingMemoryBound(to: ToneData.self)
        }
        return try withExtendedLifetime(handle) { try body(voices) }
    }
}

// MARK: - Operation results

/// One playable song's listing metadata.
/// `id` is the SongInfo identity: the numeric song ID when
/// registered, the project snapshot index for unregistered strays — stable
/// within one listing and the identity every song-list callback carries.
public struct SongListing: Equatable, Sendable {
    public var id: Int
    public var label: String
    public var constant: String
    public var player: String
    public var midiPath: String
    public var trackBudget: Int
    public var hasMid: Bool
    public var hasCfg: Bool
    /// false: the .mid exists but song_table.inc has no entry — an
    /// unregistered stray the Register Song flow can still complete.
    public var registered: Bool
    /// Registration files still missing the entry (e.g. "songs.h"); empty
    /// when the registration is complete.
    public var registrationGaps: [String]

    public init(id: Int, label: String, constant: String, player: String,
                midiPath: String, trackBudget: Int, hasMid: Bool, hasCfg: Bool,
                registered: Bool, registrationGaps: [String]) {
        self.id = id
        self.label = label
        self.constant = constant
        self.player = player
        self.midiPath = midiPath
        self.trackBudget = trackBudget
        self.hasMid = hasMid
        self.hasCfg = hasCfg
        self.registered = registered
        self.registrationGaps = registrationGaps
    }

    /// SongInfo::isPlayable: the .mid exists. Every listed song is playable.
    public var isPlayable: Bool { hasMid }
    /// Register Song enablement: unregistered strays and partial
    /// registrations alike.
    public var registrationIncomplete: Bool { !registered || !registrationGaps.isEmpty }
}

/// An opened song: Swift-owned MIDI bytes plus borrowed-then-copied metadata
/// and the owned bank lease. Swift alone parses/encodes the MIDI bytes.
public struct LoadedSong: Sendable {
    public var label: String
    public var midiPath: String
    public var constant: String
    public var player: String
    public var trackBudget: Int
    public var hasMid: Bool
    public var hasCfg: Bool
    public var registered: Bool
    public var config: SongConfig
    public var source: SongSource
    public var midiBytes: [UInt8]
    public var bank: NativeBankLease
    public var bankSlots: [BankSlotView]
    public var bankDirty: Bool
    public var bankLoadName: String
}

/// A confirmed bank transition: the replacement lease plus its copied view.
public struct AppliedBankEdit: Sendable {
    public var lease: NativeBankLease
    public var slots: [BankSlotView]
    public var dirty: Bool
    public var loadName: String
    /// Live blank-materialization token, nil unless this edit materialized a
    /// blank slot. Single-shot: consumed by the matching revert.
    public var materializationToken: UInt64?
}

/// An ordered save receipt. The bank stage, when run, refreshes the lease.
public struct SaveReceipt: Sendable {
    public var flagsWritten: Bool
    public var bank: AppliedBankEdit?
}

/// The registration plan behind the native Register Song confirmation
/// (RegistrationPlanResult): the resolved identity plus the registration
/// files still missing the entry, named exactly as the list badge names
/// them. The shell confirms, then hands the plan to registerSong.
public struct SongRegistrationPlan: Equatable, Sendable {
    public var label: String
    public var constant: String
    public var player: String
    /// The proposed song-table index.
    public var songId: Int
    /// Registration files still missing the entry ("song_table.inc",
    /// "songs.h", ...); empty when the registration is already complete.
    public var missingFiles: [String]

    public init(label: String, constant: String, player: String, songId: Int,
                missingFiles: [String]) {
        self.label = label
        self.constant = constant
        self.player = player
        self.songId = songId
        self.missingFiles = missingFiles
    }
}

public struct SongDeletionPlan: Equatable, Sendable {
    /// The song's table index; -1 = no table entry, 0 = the engine's
    /// fallback song, which cannot be deleted.
    public var tableIndex: Int
    public var tableCount: Int
    /// true: the song_table.inc row is removed outright; false: it becomes
    /// a reusable free slot and no other song's ID changes.
    public var lastEntry: Bool
    /// Registration files carrying a line the delete removes.
    public var inSongsH: Bool
    public var inLdScript: Bool
    public var inCharmap: Bool
    public var inDebugMenu: Bool
    public var deletableVoicegroupName: String?
    /// The display form of deletableVoicegroupName.
    public var deletableVoicegroupDisplay: String?

    public init(tableIndex: Int, tableCount: Int, lastEntry: Bool, inSongsH: Bool,
                inLdScript: Bool, inCharmap: Bool, inDebugMenu: Bool,
                deletableVoicegroupName: String?, deletableVoicegroupDisplay: String?) {
        self.tableIndex = tableIndex
        self.tableCount = tableCount
        self.lastEntry = lastEntry
        self.inSongsH = inSongsH
        self.inLdScript = inLdScript
        self.inCharmap = inCharmap
        self.inDebugMenu = inDebugMenu
        self.deletableVoicegroupName = deletableVoicegroupName
        self.deletableVoicegroupDisplay = deletableVoicegroupDisplay
    }
}

// MARK: - Project service

/// Async Swift front over the project-store actor. The actor owns bank
/// transitions; document history never blocks on it.
public actor ProjectService {
    nonisolated let bankViews = ProjectBankViews()
    internal var store: ProjectStore?
    internal var snapshot: ProjectSnapshot?
    internal var projectRoot = ""
    internal var closed = false

    public init() {}

    internal func requireStore() throws -> ProjectStore {
        guard !closed else { throw ProjectServiceError.serviceClosed }
        guard let store else {
            throw ProjectServiceError.operationFailed("Project is not open.")
        }
        return store
    }
    internal func publish(_ value: AppliedBankEdit, from source: ProjectStore) async {
        guard !closed, store === source else { return }
        await bankViews.publish(value)
    }

    /// Idempotent. Owned leases outlive the service.
    public func close() async {
        store = nil
        snapshot = nil
        closed = true
        await bankViews.reset()
    }
}

// MARK: - Store value conversion

internal func projectFailure(_ error: any Error) -> ProjectServiceError {
    if let error = error as? ProjectServiceError { return error }
    if let error = error as? any LocalizedError, let message = error.errorDescription {
        return .operationFailed(message)
    }
    return .operationFailed(error.localizedDescription)
}

internal func projectVoice(_ voice: BankVoice) throws -> PorydawProject.VgVoice {
    guard let macro = PorydawProject.VgMacro(rawValue: voice.macro) else {
        throw ProjectServiceError.operationFailed("Voice macro ordinal is out of range.")
    }
    return PorydawProject.VgVoice(macro: macro, key: Int(voice.key), pan: Int(voice.pan),
                   symbol: voice.symbol, keysplitTable: voice.keysplitTable,
                   sweep: Int(voice.sweep), duty: Int(voice.duty), period: Int(voice.period),
                   attack: Int(voice.attack), decay: Int(voice.decay),
                   sustain: Int(voice.sustain), release: Int(voice.release))
}

private func copyVoice(_ voice: PorydawProject.VgVoice) -> BankVoice {
    let macro = voice.macro.rawValue
    let key = Int32(voice.key)
    let pan = Int32(voice.pan)
    let sweep = Int32(voice.sweep)
    let duty = Int32(voice.duty)
    let period = Int32(voice.period)
    let attack = Int32(voice.attack)
    let decay = Int32(voice.decay)
    let sustain = Int32(voice.sustain)
    let release = Int32(voice.release)
    return BankVoice(macro: macro, key: key, pan: pan, symbol: voice.symbol,
                     keysplitTable: voice.keysplitTable, sweep: sweep, duty: duty,
                     period: period, attack: attack, decay: decay,
                     sustain: sustain, release: release)
}

private func copySlots(_ lease: ProjectBankLease) -> [BankSlotView] {
    lease.withNativeBank { box in
        let nativeLease = pd_bank_lease_native(box)
        let bank = nativeLease.pointee.__getUnsafe()
        return lease.slotViews.enumerated().map { index, slot in
            let voice = slot.voice.map(copyVoice)
            let loaded: ToneData? = bank.flatMap { storage in
                guard slot.kind != .none, index < 128,
                      let voicesOffset = MemoryLayout<LoadedVoiceGroup>.offset(of: \.voices)
                else { return nil }
                return UnsafeRawPointer(storage).advanced(by: voicesOffset)
                    .assumingMemoryBound(to: ToneData.self)[index]
            }
            let synth = loaded.map {
                $0.type & 0xE7 == 0 && $0.wav?.pointee.size == 0 && $0.wav?.pointee.data != nil
            } ?? false
            let tone: BankTone? = bank.flatMap { storage in
                guard voice == nil, let loaded,
                      let namesOffset = MemoryLayout<LoadedVoiceGroup>.offset(of: \.voiceNames)
                else { return nil }
                let names = UnsafeRawPointer(storage).advanced(by: namesOffset)
                    .assumingMemoryBound(to: CChar.self)
                let start = names.advanced(by: index * Int(VG_VOICE_NAME_LEN))
                let length = (0..<Int(VG_VOICE_NAME_LEN)).first(where: {
                    start[$0] == 0
                }) ?? Int(VG_VOICE_NAME_LEN)
                let bytes = UnsafeRawPointer(start).assumingMemoryBound(to: UInt8.self)
                let name = String(decoding: UnsafeBufferPointer(start: bytes, count: length),
                                  as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                let adsr = loaded.type == UInt8(VOICE_KEYSPLIT)
                    || loaded.type == UInt8(VOICE_KEYSPLIT_ALL) ? nil
                    : BankToneAdsr(attack: Int32(loaded.attack), decay: Int32(loaded.decay),
                                   sustain: Int32(loaded.sustain), release: Int32(loaded.release))
                return BankTone(name: name, type: Int32(loaded.type), isSynth: synth, adsr: adsr)
            }
            let subvoices = loaded.flatMap(copySubvoiceMacros)
            let drumPadNames: [String]? = loaded.flatMap { tone in
                guard tone.type == UInt8(VOICE_KEYSPLIT_ALL),
                      let subgroup = tone.subGroup?.assumingMemoryBound(to: ToneData.self),
                      let bank else { return nil }
                return (0..<128).map { key in
                    guard let name = voicegroup_subgroup_slot_name(bank, subgroup, Int32(key))
                    else { return "" }
                    let bounded = UnsafeBufferPointer(
                        start: UnsafeRawPointer(name).assumingMemoryBound(to: UInt8.self),
                        count: Int(VG_VOICE_NAME_LEN))
                    let length = bounded.firstIndex(of: 0) ?? bounded.count
                    return String(decoding: bounded.prefix(length), as: UTF8.self)
                }
            }
            return BankSlotView(kind: slot.kind.rawValue, voice: voice, tone: tone,
                                subvoiceMacros: subvoices, drumPadNames: drumPadNames,
                                isSynth: synth)
        }
    }
}

/// Resolve split facts while the borrowed native bank is pinned.
/// Published slots retain only the copied ordinals, never native pointers.
private func copySubvoiceMacros(_ tone: ToneData) -> [Int32]? {
    let split = tone.type & UInt8(VOICE_KEYSPLIT | VOICE_KEYSPLIT_ALL)
    guard split != 0 else { return nil }
    guard let group = tone.subGroup?.assumingMemoryBound(to: ToneData.self),
          tone.type & UInt8(VOICE_KEYSPLIT) == 0 || tone.keySplitTable != nil else {
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
        case UInt8(VOICE_SQUARE_1): return BankVoiceMacro.square1
        case UInt8(VOICE_SQUARE_2): return BankVoiceMacro.square2
        case UInt8(VOICE_PROGRAMMABLE_WAVE): return BankVoiceMacro.programmableWave
        case UInt8(VOICE_NOISE): return BankVoiceMacro.noise
        default:
            return type == UInt8(VOICE_DIRECTSOUND) || type == UInt8(VOICE_DIRECTSOUND_NO_RESAMPLE)
                || type == UInt8(VOICE_DIRECTSOUND_ALT) ? BankVoiceMacro.directSound : -1
        }
    }
}

internal func appliedBank(_ lease: ProjectBankLease, token: UInt64?) -> AppliedBankEdit {
    AppliedBankEdit(lease: NativeBankLease(handle: lease), slots: copySlots(lease),
                    dirty: lease.dirty, loadName: lease.loadName,
                    materializationToken: token == 0 ? nil : token)
}

internal func bankEditResult(_ result: ProjectBankEditOutcome) throws -> AppliedBankEdit {
    switch result {
    case let .applied(lease, _, token): appliedBank(lease, token: token)
    case .conflict: throw ProjectServiceError.bankConflict
    }
}
