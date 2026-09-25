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
    /// The bank changed underneath the edit (stale expected value, occupied
    /// blank slot, out-of-range slot, spent materialization token). The
    /// document is unchanged; the caller decides the conflict policy.
    case bankConflict
}

// MARK: - Public bank vocabulary

/// VgMacro ordinals, mirroring VgMacro's declaration in VoiceValues.swift.
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

/// VgLineKind ordinals, mirroring VoiceValues.swift.
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
    /// Loader-confirmed synth descriptor, including in-memory minted symbols
    /// absent from the current on-disk catalog.
    public var isSynth: Bool
    /// Native split facts copied once at publication; -1 is an invalid child.
    public var subvoiceMacros: [Int32]?

    public init(kind: Int32 = BankSlotKind.none, voice: BankVoice? = nil,
                tone: BankTone? = nil, subvoiceMacros: [Int32]? = nil,
                isSynth: Bool = false) {
        self.kind = kind
        self.voice = voice
        self.tone = tone
        self.subvoiceMacros = subvoiceMacros
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
    internal let publicationRevision: UInt64

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
    private var store: ProjectStore?
    private var snapshot: ProjectSnapshot?
    private var projectRoot = ""
    private var closed = false

    public init() {}

    private func requireStore() throws -> ProjectStore {
        guard !closed else { throw ProjectServiceError.serviceClosed }
        guard let store else {
            throw ProjectServiceError.operationFailed("Project is not open.")
        }
        return store
    }
    private func publish(_ value: AppliedBankEdit, from source: ProjectStore) async {
        guard !closed, store === source else { return }
        await bankViews.publish(value)
    }

    /// Opens the project root in the project-store actor.
    public func open(root: String) async throws {
        guard !closed else { throw ProjectServiceError.serviceClosed }
        let candidate = ProjectStore(projectRoot: URL(filePath: root, directoryHint: .isDirectory))
        do {
            let opened = try await candidate.open()
            guard !closed else { throw ProjectServiceError.serviceClosed }
            store = candidate
            snapshot = opened
            projectRoot = root
            await bankViews.reset(owner: candidate.publicationOwner)
        } catch {
            throw projectFailure(error)
        }
    }

    public func songs() async throws -> [SongListing] {
        let store = try requireStore()
        do {
            let values = try await store.songs()
            let statuses = try await store.registrationStatuses()
            var result: [SongListing] = []
            result.reserveCapacity(values.count)
            for song in values where song.hasMid {
                let gaps = statuses[song.label]?.missingFiles ?? []
                result.append(SongListing(id: song.id, label: song.label, constant: song.constant,
                                          player: song.player, midiPath: song.midPath ?? "",
                                          trackBudget: snapshot?.trackBudgetFor(song: song) ?? 16,
                                          hasMid: song.hasMid, hasCfg: song.hasCfg,
                                          registered: song.registered, registrationGaps: gaps))
            }
            return result
        } catch { throw projectFailure(error) }
    }

    public func songLabels() async throws -> [String] {
        try await songs().map(\.label)
    }

    public func songRegistrationPlan(label: String) async throws -> SongRegistrationPlan {
        let store = try requireStore()
        do {
            let song: ProjectSong
            do { song = try await store.songMeta(label: label) }
            catch ProjectStoreReadError.songNotFound {
                throw ProjectServiceError.operationFailed("No song named \(label) in this project.")
            }
            let constant = song.constant.isEmpty ? song.label.uppercased() : song.constant
            let player = song.player.isEmpty ? "MUSIC_PLAYER_BGM" : song.player
            let plan = try await store.registrationPlan(label: label, constant: constant,
                                                        player: player)
            let status = try await store.registrationStatus(label: label, constant: constant)
            return SongRegistrationPlan(label: label, constant: constant, player: player,
                                        songId: plan.songId, missingFiles: status.missingFiles)
        } catch { throw projectFailure(error) }
    }

    public func registerSong(_ plan: SongRegistrationPlan) async throws -> Int {
        let store = try requireStore()
        do {
            let id = try await store.registerSong(label: plan.label, constant: plan.constant,
                                                  player: plan.player)
            snapshot = try await store.snapshot()
            return id
        } catch { throw projectFailure(error) }
    }

    public func songDeletionPlan(label: String) async throws -> SongDeletionPlan {
        let store = try requireStore()
        do {
            guard !label.isEmpty else {
                throw ProjectServiceError.operationFailed("Invalid song label.")
            }
            let song: ProjectSong
            do { song = try await store.songMeta(label: label) }
            catch ProjectStoreReadError.songNotFound {
                throw ProjectServiceError.operationFailed("No song named \(label) in this project.")
            }
            let constant = song.constant.isEmpty ? song.label.uppercased() : song.constant
            let plan = try await store.removalPlan(label: label, constant: constant)
            let voicegroup = try await store.deletableVoicegroup(label: label)
            return SongDeletionPlan(tableIndex: plan.tableIndex, tableCount: plan.tableCount,
                                    lastEntry: plan.lastEntry, inSongsH: plan.inSongsH,
                                    inLdScript: plan.inLdScript, inCharmap: plan.inCharmap,
                                    inDebugMenu: plan.inDebugMenu,
                                    deletableVoicegroupName: voicegroup,
                                    deletableVoicegroupDisplay: voicegroup.map {
                                        $0.hasPrefix("_") ? String($0.dropFirst()) : $0
                                    })
        } catch { throw projectFailure(error) }
    }

    public func deleteSong(label: String, voicegroupName: String? = nil) async throws {
        let store = try requireStore()
        do {
            try await store.deleteSong(label: label, voicegroupName: voicegroupName)
            snapshot = try await store.snapshot()
        } catch { throw projectFailure(error) }
    }

    public func voicegroupArgs() async throws -> [String] {
        let store = try requireStore()
        do { return try await store.voicegroupArgs() }
        catch { throw projectFailure(error) }
    }

    /// Loads another voicegroup without reopening the song. The returned lease
    /// owns its bank independently of the currently presented lease.
    public func loadBank(voicegroupArg: String) async throws -> AppliedBankEdit {
        let store = try requireStore()
        do {
            let bank = try await store.loadBank(voicegroupArg: voicegroupArg)
            let loaded = appliedBank(bank, token: nil)
            await publish(loaded, from: store)
            return loaded
        } catch {
            throw projectFailure(error)
        }
    }

    /// Reads the editor's symbol catalogs from the root supplying the bank.
    public func voicegroupCatalog() async throws -> VoicegroupCatalog {
        let store = try requireStore()
        let root = projectRoot
        let catalog = await store.voicegroupCatalog()
        let groups = catalog.groups
        let direct = catalog.direct
        let defaults = VoiceListAdsrDefaults(
            bySymbol: groups.typicalAdsr.bySymbol.mapValues {
                VoiceListAdsr(attack: Int32($0.attack), decay: Int32($0.decay),
                              sustain: Int32($0.sustain), release: Int32($0.release))
            },
            byFamily: Dictionary(uniqueKeysWithValues:
                groups.typicalAdsr.byFamily.map { key, adsr in
                    (Int32(key), VoiceListAdsr(
                        attack: Int32(adsr.attack), decay: Int32(adsr.decay),
                        sustain: Int32(adsr.sustain), release: Int32(adsr.release)))
                }))
        return VoicegroupCatalog(
            groupArgs: groups.groupArgs,
            samples: direct.directSound, waves: VoicegroupSource.progWaveSymbols(root),
            drumkits: groups.drumkits,
            keysplits: Dictionary(groups.keysplits.map { ($0.symbol, $0.table) },
                                  uniquingKeysWith: { _, latest in latest }),
            synths: direct.synths.defs.map(\.symbol),
            synthDefinitions: Dictionary(direct.synths.defs.map { ($0.symbol, $0.descriptor) },
                                         uniquingKeysWith: { first, _ in first }),
            canMintSynths: direct.synths.creatable(), defaults: defaults)
    }

    /// Resolves a picker audition through the project's own loader.
    /// - Parameters:
    ///   - symbol: The full sample, wave, or keysplit symbol.
    ///   - kind: The picker row's instrument family.
    /// - Returns: Detached playable bytes, or nil when the symbol cannot load.
    public func pickerSound(symbol: String, kind: VoiceListAuditionKind) async -> PickerSound? {
        guard let store else { return nil }
        let family: String
        switch kind {
        case .sample: family = "sample"
        case .wave: family = "wave"
        case .keysplit: family = "keysplit"
        }
        return await store.pickerSound(symbol: symbol, kind: family)
    }

    /// Mints a memory-only synth definition for a pending voicegroup edit.
    /// - Parameter descriptor: Waveform and pulse parameters to resolve.
    /// - Returns: An existing or newly reserved assembler symbol.
    /// - Throws: A project failure if the required macros are unavailable.
    public func mintSynth(_ descriptor: VgSynthDesc) async throws -> String {
        let store = try requireStore()
        do { return try await store.mintSynth(descriptor) }
        catch { throw projectFailure(error) }
    }

    /// Opens a playable song: raw MIDI bytes, metadata and the owned bank lease.
    /// Unknown labels and unreadable stages throw.
    public func openSong(label: String) async throws -> LoadedSong {
        let store = try requireStore()
        do {
            let song: ProjectSong
            do {
                song = try await store.songMeta(label: label)
            } catch ProjectStoreReadError.songNotFound {
                throw ProjectServiceError.operationFailed(
                    label.isEmpty ? "Invalid song label." : "No playable song named \(label).")
            }
            guard song.hasMid, let midiPath = song.midPath else {
                throw ProjectServiceError.operationFailed("No playable song named \(label).")
            }
            let bytes = try await store.readFile(midiPath)
            let bank = try await store.loadBank(voicegroupArg: song.cfg.voicegroupArgument)
            let published = appliedBank(bank, token: nil)
            await publish(published, from: store)
            return LoadedSong(
                label: song.label, midiPath: midiPath, constant: song.constant,
                player: song.player, trackBudget: snapshot?.trackBudgetFor(song: song) ?? 16,
                hasMid: song.hasMid, hasCfg: song.hasCfg, registered: song.registered,
                config: song.cfg, source: SongSource(label: song.label, midiPath: midiPath,
                                                    hasConfig: song.hasCfg),
                midiBytes: Array(bytes), bank: published.lease, bankSlots: published.slots,
                bankDirty: published.dirty, bankLoadName: published.loadName)
        } catch {
            throw projectFailure(error)
        }
    }

    /// Ordered save: optional bank stage, then MIDI bytes, then flags. A
    /// failed stage throws and later stages never run; nothing here marks the
    /// document clean — the caller confirms via SongDocument.didSave.
    public func save(_ snapshot: SaveSnapshot, bank: NativeBankLease?) async throws -> SaveReceipt {
        let store = try requireStore()
        do {
            var refreshed: AppliedBankEdit?
            if let bank {
                refreshed = try await saveBankStage(bank, in: store)
            }
            try await store.writeFile(snapshot.destination.midiPath, data: Data(snapshot.bytes))
            var flagsWritten = false
            if snapshot.flagsNeeded {
                let midiDir = URL(filePath: snapshot.destination.midiPath)
                    .deletingLastPathComponent()
                try await store.saveSongFlags(midiDir: midiDir, label: snapshot.destination.label,
                                              config: snapshot.config)
                flagsWritten = true
            }
            return SaveReceipt(flagsWritten: flagsWritten, bank: refreshed)
        } catch {
            throw projectFailure(error)
        }
    }

    public func saveBank(lease: NativeBankLease) async throws -> AppliedBankEdit {
        let store = try requireStore()
        do {
            return try await saveBankStage(lease, in: store)
        } catch {
            throw projectFailure(error)
        }
    }

    private func saveBankStage(_ bank: NativeBankLease,
                               in store: ProjectStore) async throws -> AppliedBankEdit {
        guard bank.publicationOwner == store.publicationOwner else {
            throw ProjectServiceError.serviceClosed
        }
        guard let saved = try await store.saveVoicegroup(lease: bank.handle) else {
            throw ProjectServiceError.operationFailed(
                "Could not save voicegroup \(bank.sourcePath) [\(bank.sectionLabel)].")
        }
        let savedView = appliedBank(saved, token: nil)
        await publish(savedView, from: store)
        return savedView
    }

    /// Applies a set-slot edit against the lease's bank. A nil expected value
    /// requires the slot to still be blank (materialization); a set expected
    /// value requires an exact match. Mismatches throw bankConflict.
    public func bankApply(lease: NativeBankLease, slot: Int,
                          value: BankVoice, expected: BankVoice?) async throws -> AppliedBankEdit {
        let store = try requireStore()
        guard lease.publicationOwner == store.publicationOwner else {
            throw ProjectServiceError.serviceClosed
        }
        do {
            let converted = try projectVoice(value)
            let old = try expected.map(projectVoice)
            let result = try await store.applyVoicegroupEdit(
                lease: lease.handle,
                operation: .set(SetVoicegroupSlot(slot: slot, value: converted, expected: old)))
            let applied = try bankEditResult(result)
            await publish(applied, from: store)
            return applied
        } catch {
            throw projectFailure(error)
        }
    }

    /// Reverts a blank-slot materialization via its single-shot token. Spent
    /// or unknown tokens throw bankConflict; the source bytes stay untouched.
    public func bankRevert(lease: NativeBankLease, token: UInt64) async throws -> AppliedBankEdit {
        let store = try requireStore()
        guard lease.publicationOwner == store.publicationOwner else {
            throw ProjectServiceError.serviceClosed
        }
        do {
            let applied = try bankEditResult(
                await store.revertBlankSlot(lease: lease.handle, materializationToken: token))
            await publish(applied, from: store)
            return applied
        } catch {
            throw projectFailure(error)
        }
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

private func projectFailure(_ error: any Error) -> ProjectServiceError {
    if let error = error as? ProjectServiceError { return error }
    if let error = error as? any LocalizedError, let message = error.errorDescription {
        return .operationFailed(message)
    }
    return .operationFailed(error.localizedDescription)
}

private func projectVoice(_ voice: BankVoice) throws -> PorydawProject.VgVoice {
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
    BankVoice(macro: voice.macro.rawValue, key: Int32(voice.key), pan: Int32(voice.pan),
              symbol: voice.symbol, keysplitTable: voice.keysplitTable,
              sweep: Int32(voice.sweep), duty: Int32(voice.duty), period: Int32(voice.period),
              attack: Int32(voice.attack), decay: Int32(voice.decay),
              sustain: Int32(voice.sustain), release: Int32(voice.release))
}

private func copySlots(_ lease: ProjectBankLease) -> [BankSlotView] {
    lease.withNativeBank { box in
        let nativeLease = pd_bank_lease_native(box)
        let bank = nativeLease.pointee.__getUnsafe()
        return lease.slotViews.enumerated().map { index, slot in
            let voice = slot.voice.map(copyVoice)
            let loaded: ToneData? = bank.flatMap { storage in
                guard slot.kind != .none, index < 128 else { return nil }
                return withUnsafePointer(to: storage.pointee.voices) {
                    $0.withMemoryRebound(to: ToneData.self, capacity: 128) { $0[index] }
                }
            }
            let synth = loaded.map {
                $0.type & 0xE7 == 0 && $0.wav?.pointee.size == 0 && $0.wav?.pointee.data != nil
            } ?? false
            let tone: BankTone? = bank.flatMap { storage in
                guard voice == nil, let loaded else { return nil }
                let name = withUnsafePointer(to: storage.pointee.voiceNames) {
                    $0.withMemoryRebound(to: CChar.self,
                                         capacity: 128 * Int(VG_VOICE_NAME_LEN)) { names in
                        let start = names.advanced(by: index * Int(VG_VOICE_NAME_LEN))
                        let length = (0..<Int(VG_VOICE_NAME_LEN)).first(where: {
                            start[$0] == 0
                        }) ?? Int(VG_VOICE_NAME_LEN)
                        let bytes = UnsafeRawPointer(start).assumingMemoryBound(to: UInt8.self)
                        return String(decoding: UnsafeBufferPointer(start: bytes, count: length),
                                      as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                let adsr = loaded.type == UInt8(VOICE_KEYSPLIT)
                    || loaded.type == UInt8(VOICE_KEYSPLIT_ALL) ? nil
                    : BankToneAdsr(attack: Int32(loaded.attack), decay: Int32(loaded.decay),
                                   sustain: Int32(loaded.sustain), release: Int32(loaded.release))
                return BankTone(name: name, type: Int32(loaded.type), isSynth: synth, adsr: adsr)
            }
            let subvoices = loaded.flatMap(copySubvoiceMacros)
            return BankSlotView(kind: slot.kind.rawValue, voice: voice, tone: tone,
                                subvoiceMacros: subvoices, isSynth: synth)
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

private func appliedBank(_ lease: ProjectBankLease, token: UInt64?) -> AppliedBankEdit {
    AppliedBankEdit(lease: NativeBankLease(handle: lease), slots: copySlots(lease),
                    dirty: lease.dirty, loadName: lease.loadName,
                    materializationToken: token == 0 ? nil : token)
}

private func bankEditResult(_ result: ProjectBankEditOutcome) throws -> AppliedBankEdit {
    switch result {
    case let .applied(lease, token): appliedBank(lease, token: token)
    case .conflict: throw ProjectServiceError.bankConflict
    }
}
