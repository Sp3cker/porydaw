import Foundation
import PorydawCore
import PorydawProjectService

// MARK: - Public errors

/// Typed failures for the native project service boundary.
public enum ProjectServiceError: Error, Equatable, Sendable {
    /// The service is closed; no further operations are accepted.
    case serviceClosed
    /// A hard native failure with the worker's message.
    case operationFailed(String)
    /// The bank changed underneath the edit (stale expected value, occupied
    /// blank slot, out-of-range slot, spent materialization token). The
    /// document is unchanged; the caller decides the conflict policy.
    case bankConflict
}

// MARK: - Public bank vocabulary

/// VgMacro ordinals, mirroring the declaration order in
/// src/project/voicegroupsource.h. The adapter carries ordinals, not names.
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

/// VgLineKind ordinals, mirroring the declaration order in
/// src/project/voicegroupsource.h.
public enum BankSlotKind {
    public static let none: Int32 = 0
    public static let other: Int32 = 1
    public static let header: Int32 = 2
    public static let editable: Int32 = 3
    public static let readOnlyVoice: Int32 = 4
    public static let broken: Int32 = 5
}

/// One editable voice's parsed macro arguments, mirroring VgVoice.
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
/// cover with a parsed voice (read-only cry lines, broken lines, headers) —
/// the same fallback VoicegroupBrowser::updateRow inks from
/// bank->voices[slot].
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

/// One published bank slot, mirroring VoicegroupSlotView.
public struct BankSlotView: Equatable, Sendable {
    /// BankSlotKind ordinal.
    public var kind: Int32
    /// The parsed voice when kind is editable.
    public var voice: BankVoice?
    /// The loaded bank's tone when the slot has no parsed voice and is not
    /// blank; nil for editable and blank slots.
    public var tone: BankTone?
    /// Native split facts copied once at publication; -1 is an invalid child.
    public var subvoiceMacros: [Int32]?

    public init(kind: Int32 = BankSlotKind.none, voice: BankVoice? = nil,
                tone: BankTone? = nil, subvoiceMacros: [Int32]? = nil) {
        self.kind = kind
        self.voice = voice
        self.tone = tone
        self.subvoiceMacros = subvoiceMacros
    }

    public func subvoiceMacro(forKey key: Int) -> Int32? {
        guard (0..<128).contains(key), let subvoiceMacros,
              subvoiceMacros.indices.contains(key), subvoiceMacros[key] >= 0 else { return nil }
        return subvoiceMacros[key]
    }
}

// MARK: - Owned bank lease

/// Swift ownership wrapper over one opaque native bank handle. ARC shares the
/// wrapper; deinit releases the handle on whatever thread drops the last
/// reference (the release is thread-safe). Applied edits mint a fresh lease;
/// the superseded wrapper keeps its own bank alive, so old views stay valid.
public final class NativeBankLease: @unchecked Sendable {
    let handle: OpaquePointer
    /// Voicegroup identity, copied from the published view for save requests.
    public let sourcePath: String
    public let sectionLabel: String

    init(handle: OpaquePointer, sourcePath: String, sectionLabel: String) {
        self.handle = handle
        self.sourcePath = sourcePath
        self.sectionLabel = sectionLabel
    }

    deinit {
        pd_bank_lease_release(handle)
    }

    /// Identity of the underlying native bank, for reuse/validity checks.
    public var bankToken: UInt {
        UInt(pd_bank_lease_bank_token(handle))
    }
}

// MARK: - Operation results

/// One playable song's listing metadata, mirroring SongInfo as SongListPanel
/// consumes it. `id` is the SongInfo identity: the numeric song ID when
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

/// The removal plan behind the native Delete Song confirmation
/// (DeletionPlanResult): what unregisterSong would edit plus the voicegroup
/// that may be deleted with the song.
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
    /// The voicegroup file deletable with the song (used only by it), as a
    /// raw name; nil when none applies. Pass it back to deleteSong to
    /// delete it too — the worker re-verifies it is still unused.
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

/// Async Swift front over the serial native worker. The actor serializes bank
/// transitions; document history never blocks on it.
public actor ProjectService {
    nonisolated(unsafe) private var handle: OpaquePointer?
    private var closed = false

    public init() {
        handle = pd_service_create()
    }

    deinit {
        if let handle {
            pd_service_destroy(handle)
        }
    }

    private func requireHandle() throws -> OpaquePointer {
        guard let handle, !closed else { throw ProjectServiceError.serviceClosed }
        return handle
    }

    /// Opens the project root on the worker.
    public func open(root: String) async throws {
        let handle = try requireHandle()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            root.withCString { rootPtr in
                let context = Unmanaged.passRetained(ContinuationBox(continuation)).toOpaque()
                pd_service_open(handle, rootPtr, context, openCompletion)
            }
        }
    }
    /// Returns every playable song's listing — registered, partially
    /// registered and unregistered strays alike — in project snapshot order.
    /// This is the feed SongListPresenter consumes.
    public func songs() async throws -> [SongListing] {
        let handle = try requireHandle()
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[SongListing], Error>) in
            let context = Unmanaged.passRetained(ContinuationBox(continuation)).toOpaque()
            pd_service_list_songs(handle, context, songListCompletion)
        }
    }
    /// Returns the playable labels copied from the native project snapshot.
    /// Playable means the .mid exists, so unregistered strays are included.
    public func songLabels() async throws -> [String] {
        try await songs().map(\.label)
    }

    /// The read-only half of the native Register Song flow: resolves the
    /// song's identity and computes the registration plan for the shell's
    /// confirmation. Unknown labels throw.
    public func songRegistrationPlan(label: String) async throws -> SongRegistrationPlan {
        let handle = try requireHandle()
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<SongRegistrationPlan, Error>) in
            label.withCString { labelPtr in
                let context = Unmanaged.passRetained(ContinuationBox(continuation)).toOpaque()
                pd_service_song_registration_plan(handle, labelPtr, context,
                                                  registrationPlanCompletion)
            }
        }
    }

    /// The confirmed half of the Register Song flow: writes the song into
    /// every registration file with the plan's constant/player, then
    /// refreshes the project snapshot. Returns the assigned song ID.
    public func registerSong(_ plan: SongRegistrationPlan) async throws -> Int {
        let handle = try requireHandle()
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Int, Error>) in
            plan.label.withCString { labelPtr in
                plan.constant.withCString { constantPtr in
                    plan.player.withCString { playerPtr in
                        let context =
                            Unmanaged.passRetained(ContinuationBox(continuation)).toOpaque()
                        pd_service_song_register(handle, labelPtr, constantPtr, playerPtr,
                                                 context, mutationCompletion)
                    }
                }
            }
        }
    }

    /// The read-only half of the native Delete Song flow: what unregistering
    /// the song would edit and the voicegroup deletable with it, for the
    /// shell's confirmation. Unknown labels throw.
    public func songDeletionPlan(label: String) async throws -> SongDeletionPlan {
        let handle = try requireHandle()
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<SongDeletionPlan, Error>) in
            label.withCString { labelPtr in
                let context = Unmanaged.passRetained(ContinuationBox(continuation)).toOpaque()
                pd_service_song_deletion_plan(handle, labelPtr, context, deletionPlanCompletion)
            }
        }
    }

    /// The confirmed half of the Delete Song flow: moves the .mid to
    /// .porydaw/trash, removes the .s and midi.cfg flags, unregisters the
    /// song, optionally deletes the plan's voicegroup, then refreshes the
    /// project snapshot. Song ID 0 (the engine fallback) throws.
    public func deleteSong(label: String, voicegroupName: String? = nil) async throws {
        let handle = try requireHandle()
        _ = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Int, Error>) in
            label.withCString { labelPtr in
                (voicegroupName ?? "").withCString { voicegroupPtr in
                    let context = Unmanaged.passRetained(ContinuationBox(continuation)).toOpaque()
                    pd_service_song_delete(handle, labelPtr, voicegroupPtr, context,
                                           mutationCompletion)
                }
            }
        }
    }

    /// The project's -G voicegroup arguments (the catalog's groupArgs),
    /// sorted — the voice-list selector's choice feed.
    public func voicegroupArgs() async throws -> [String] {
        let handle = try requireHandle()
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[String], Error>) in
            let context = Unmanaged.passRetained(ContinuationBox(continuation)).toOpaque()
            pd_service_voicegroup_args(handle, context, stringListCompletion)
        }
    }
    /// Opens a playable song: raw MIDI bytes plus copied metadata and the
    /// owned bank lease. Unknown labels and unreadable stages throw.
    public func openSong(label: String) async throws -> LoadedSong {
        let handle = try requireHandle()
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<LoadedSong, Error>) in
            label.withCString { labelPtr in
                let context = Unmanaged.passRetained(ContinuationBox(continuation)).toOpaque()
                pd_service_open_song(handle, labelPtr, context, songCompletion)
            }
        }
    }

    /// Ordered save: optional bank stage, then MIDI bytes, then flags. A
    /// failed stage throws and later stages never run; nothing here marks the
    /// document clean — the caller confirms via SongDocument.didSave.
    public func save(_ snapshot: SaveSnapshot, bank: NativeBankLease?) async throws -> SaveReceipt {
        let handle = try requireHandle()
        let config = snapshot.config
        let flagCopies = config.rawFlags.map { strdup($0) }
        defer { flagCopies.forEach { free($0) } }
        let labelCopy = strdup(snapshot.destination.label)
        defer { free(labelCopy) }
        let midCopy = strdup(snapshot.destination.midiPath)
        defer { free(midCopy) }
        let voicegroupCopy = strdup(config.voicegroupArgument)
        defer { free(voicegroupCopy) }
        let bankSourceCopy = bank.flatMap { strdup($0.sourcePath) }
        defer { if let bankSourceCopy { free(bankSourceCopy) } }
        let bankSectionCopy = bank.flatMap { strdup($0.sectionLabel) }
        defer { if let bankSectionCopy { free(bankSectionCopy) } }
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<SaveReceipt, Error>) in
            snapshot.bytes.withUnsafeBufferPointer { midiBuffer in
                flagCopies.withUnsafeBufferPointer { flagBuffer in
                    var flagPointers = flagBuffer.map { UnsafePointer($0) }
                    flagPointers.withUnsafeBufferPointer { flagPointerBuffer in
                        var request = PdSaveRequest(
                            label: labelCopy,
                            midPath: midCopy,
                            midiBytes: midiBuffer.baseAddress.map {
                                UnsafeRawPointer($0).assumingMemoryBound(to: UInt8.self)
                            },
                            midiByteCount: snapshot.bytes.count,
                            cfg: PdSongCfg(
                                rawFlags: flagPointerBuffer.baseAddress,
                                rawFlagCount: config.rawFlags.count,
                                voicegroupArg: voicegroupCopy,
                                masterVolume: Int32(config.masterVolume),
                                reverb: Int32(config.reverb ?? -1),
                                hasReverb: config.reverb != nil,
                                priority: Int32(config.priority),
                                exactGate: config.exactGate,
                                extendedClocks: config.extendedClocks,
                                noCompression: config.noCompression),
                            flagsNeeded: snapshot.flagsNeeded,
                            saveBank: bank != nil,
                            bankSourcePath: bankSourceCopy.map { UnsafePointer($0) },
                            bankSectionLabel: bankSectionCopy.map { UnsafePointer($0) })
                        let context =
                            Unmanaged.passRetained(ContinuationBox(continuation)).toOpaque()
                        pd_service_save(handle, &request, context, saveCompletion)
                    }
                }
            }
        }
    }

    /// Applies a set-slot edit against the lease's bank. A nil expected value
    /// requires the slot to still be blank (materialization); a set expected
    /// value requires an exact match. Mismatches throw bankConflict.
    public func bankApply(lease: NativeBankLease, slot: Int,
                          value: BankVoice, expected: BankVoice?) async throws -> AppliedBankEdit {
        let handle = try requireHandle()
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<AppliedBankEdit, Error>) in
            withPdVoice(value) { valueCopy in
                if let expected {
                    withPdVoice(expected) { expectedCopy in
                        var edit = PdVoiceEdit(slot: Int32(slot), value: valueCopy,
                                               hasExpected: true, expected: expectedCopy)
                        let context =
                            Unmanaged.passRetained(ContinuationBox(continuation)).toOpaque()
                        pd_service_bank_apply(handle, lease.handle, &edit, context,
                                              bankEditCompletion)
                    }
                } else {
                    var edit = PdVoiceEdit(
                        slot: Int32(slot), value: valueCopy, hasExpected: false,
                        expected: PdVoiceValue(macro: 0, key: 0, pan: 0, symbol: nil,
                                               keysplitTable: nil, sweep: 0, duty: 0, period: 0,
                                               attack: 0, decay: 0, sustain: 0, release: 0))
                    let context =
                        Unmanaged.passRetained(ContinuationBox(continuation)).toOpaque()
                    pd_service_bank_apply(handle, lease.handle, &edit, context,
                                          bankEditCompletion)
                }
            }
        }
    }

    /// Reverts a blank-slot materialization via its single-shot token. Spent
    /// or unknown tokens throw bankConflict; the source bytes stay untouched.
    public func bankRevert(lease: NativeBankLease, token: UInt64) async throws -> AppliedBankEdit {
        let handle = try requireHandle()
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<AppliedBankEdit, Error>) in
            let context = Unmanaged.passRetained(ContinuationBox(continuation)).toOpaque()
            pd_service_bank_revert(handle, lease.handle, token, context, bankEditCompletion)
        }
    }

    /// Idempotent. Drains outstanding work on the worker before releasing it;
    /// owned leases outlive the service.
    public func close() async {
        guard let handle else { return }
        self.handle = nil
        closed = true
        // The raw C handle is a value; sever the actor-region link so the
        // detached teardown closure is not inferred to race with self.
        nonisolated(unsafe) let serviceHandle = handle
        await Task.detached { pd_service_destroy(serviceHandle) }.value
    }
}
