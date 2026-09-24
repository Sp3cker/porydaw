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

/// One published bank slot, mirroring VoicegroupSlotView.
public struct BankSlotView: Equatable, Sendable {
    /// BankSlotKind ordinal.
    public var kind: Int32
    /// The parsed voice when kind is editable.
    public var voice: BankVoice?
    /// Native split facts copied once at publication; -1 is an invalid child.
    public var subvoiceMacros: [Int32]?

    public init(kind: Int32 = BankSlotKind.none, voice: BankVoice? = nil,
                subvoiceMacros: [Int32]? = nil) {
        self.kind = kind
        self.voice = voice
        self.subvoiceMacros = subvoiceMacros
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

    fileprivate init(handle: ProjectBankLease) {
        self.handle = handle
        sourcePath = handle.id.sourceRelativePath
        sectionLabel = handle.sectionLabel
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

/// An opened song: Swift-owned MIDI bytes and metadata plus the owned bank
/// lease. Swift alone parses/encodes the MIDI bytes.
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

// MARK: - Project service

/// Async Swift front over the project-store actor. The actor owns bank
/// transitions; document history never blocks on it.
public actor ProjectService {
    private var store: ProjectStore?
    private var snapshot: ProjectSnapshot?
    private var closed = false

    public init() {}

    private func requireStore() throws -> ProjectStore {
        guard !closed else { throw ProjectServiceError.serviceClosed }
        guard let store else {
            throw ProjectServiceError.operationFailed("Project is not open.")
        }
        return store
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
        } catch {
            throw projectFailure(error)
        }
    }

    /// Returns playable labels from the project snapshot.
    public func songLabels() async throws -> [String] {
        let store = try requireStore()
        do {
            return try await store.songs().filter { $0.registered && $0.hasMid }.map(\.label)
        } catch {
            throw projectFailure(error)
        }
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
            guard song.registered, song.hasMid, let midiPath = song.midPath else {
                throw ProjectServiceError.operationFailed("No playable song named \(label).")
            }
            let bytes = try await store.run { try ProjectFileStore.read(midiPath) }
            let bank = try await store.loadBank(voicegroupArg: song.cfg.voicegroupArgument)
            let lease = NativeBankLease(handle: bank)
            return LoadedSong(
                label: song.label, midiPath: midiPath, constant: song.constant,
                player: song.player, trackBudget: snapshot?.trackBudgetFor(song: song) ?? 16,
                hasMid: song.hasMid, hasCfg: song.hasCfg, registered: song.registered,
                config: song.cfg, source: SongSource(label: song.label, midiPath: midiPath,
                                                    hasConfig: song.hasCfg),
                midiBytes: Array(bytes), bank: lease, bankSlots: copySlots(bank),
                bankDirty: bank.dirty, bankLoadName: bank.loadName)
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
                guard let saved = try await store.saveVoicegroup(lease: bank.handle) else {
                    throw ProjectServiceError.operationFailed(
                        "Could not save voicegroup \(bank.sourcePath) [\(bank.sectionLabel)].")
                }
                refreshed = appliedBank(saved, token: nil)
            }
            try await store.run {
                try ProjectFileStore.writeAtomic(snapshot.destination.midiPath,
                                                 data: Data(snapshot.bytes))
            }
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

    /// Applies a set-slot edit against the lease's bank. A nil expected value
    /// requires the slot to still be blank (materialization); a set expected
    /// value requires an exact match. Mismatches throw bankConflict.
    public func bankApply(lease: NativeBankLease, slot: Int,
                          value: BankVoice, expected: BankVoice?) async throws -> AppliedBankEdit {
        let store = try requireStore()
        do {
            let converted = try projectVoice(value)
            let old = try expected.map(projectVoice)
            let result = try await store.applyVoicegroupEdit(
                lease: lease.handle,
                operation: .set(SetVoicegroupSlot(slot: slot, value: converted, expected: old)))
            return try bankEditResult(result)
        } catch {
            throw projectFailure(error)
        }
    }

    /// Reverts a blank-slot materialization via its single-shot token. Spent
    /// or unknown tokens throw bankConflict; the source bytes stay untouched.
    public func bankRevert(lease: NativeBankLease, token: UInt64) async throws -> AppliedBankEdit {
        let store = try requireStore()
        do {
            return try bankEditResult(
                await store.revertBlankSlot(lease: lease.handle, materializationToken: token))
        } catch {
            throw projectFailure(error)
        }
    }

    /// Idempotent. Owned leases outlive the service.
    public func close() async {
        store = nil
        snapshot = nil
        closed = true
    }
}

// MARK: - Confirmed bank history action

/// Inbox sharing one session's latest confirmed bank view across merged action
/// generations. History crosses entries opaquely, so the action publishes the
/// post-apply view here and the session drains it after undo/redo.
@MainActor
final class BankResultInbox {
    private(set) var pending: AppliedBankEdit?

    func deliver(_ result: AppliedBankEdit) {
        pending = result
    }

    func drain() -> AppliedBankEdit? {
        defer { pending = nil }
        return pending
    }
}

/// The actual BankHistoryAction replay/merge behavior: blank-slot
/// materialization with single-shot revert tokens, scalar set replay in both
/// directions, and scalar merge sealing (same slot, same changed-field set;
/// blank materialization never merges). Save points seal via markSaved.
@MainActor
final class ServiceBankAction: BankHistoryAction {
    private let service: ProjectService
    private let slot: Int
    /// The pre-edit voice; nil when the slot was blank.
    private let before: BankVoice?
    private let after: BankVoice
    private var token: UInt64?
    private let materializedBlank: Bool
    private let inbox: BankResultInbox
    private(set) var current: AppliedBankEdit

    init(service: ProjectService, slot: Int, before: BankVoice?, after: BankVoice,
         token: UInt64?, materializedBlank: Bool, current: AppliedBankEdit,
         inbox: BankResultInbox) {
        self.service = service
        self.slot = slot
        self.before = before
        self.after = after
        self.token = token
        self.materializedBlank = materializedBlank
        self.current = current
        self.inbox = inbox
    }

    func apply(direction: BankHistoryDirection) async throws {
        do {
            let result: AppliedBankEdit
            switch direction {
            case .undo:
                if materializedBlank, let live = token {
                    result = try await service.bankRevert(lease: current.lease, token: live)
                    token = nil
                } else if let restore = before {
                    result = try await service.bankApply(lease: current.lease, slot: slot,
                                                         value: restore, expected: after)
                } else {
                    throw ProjectServiceError.operationFailed("Bank undo has no pre-edit voice.")
                }
            case .redo:
                if materializedBlank, token == nil {
                    result = try await service.bankApply(lease: current.lease, slot: slot,
                                                         value: after, expected: nil)
                    token = result.materializationToken
                } else if let reapply = before {
                    result = try await service.bankApply(lease: current.lease, slot: slot,
                                                         value: after, expected: reapply)
                } else {
                    throw ProjectServiceError.operationFailed("Bank redo has no pre-edit voice.")
                }
            }
            current = result
            inbox.deliver(result)
        } catch let error as ProjectServiceError {
            guard error == .bankConflict else { throw error }
            throw BankHistoryReplayError.staleEntry
        }
    }

    var isRedundant: Bool {
        !materializedBlank && before == after
    }

    func merged(with newer: any BankHistoryAction) -> (any BankHistoryAction)? {
        guard let other = newer as? ServiceBankAction,
              other.service === service,
              other.slot == slot,
              other.current.lease.sourcePath == current.lease.sourcePath,
              !materializedBlank, !other.materializedBlank,
              token == nil, other.token == nil,
              let oldest = before, let middle = other.before,
              middle == after,
              bankChangedFieldMask(oldest, after) == bankChangedFieldMask(middle, other.after)
        else { return nil }
        return ServiceBankAction(service: service, slot: slot, before: oldest,
                                 after: other.after, token: nil, materializedBlank: false,
                                 current: other.current, inbox: inbox)
    }

    func rebaseCurrent(with newer: any BankHistoryAction) {
        guard let other = newer as? ServiceBankAction,
              other.service === service,
              other.current.lease.sourcePath == current.lease.sourcePath else { return }
        current = other.current
    }
}

/// Scalar merge boundary: which of the twelve voice fields an edit changes.
/// Internal to the Swift merge policy; the mask never crosses the store boundary.
private func bankChangedFieldMask(_ before: BankVoice, _ after: BankVoice) -> UInt32 {
    var mask: UInt32 = 0
    if before.macro != after.macro { mask |= 1 << 0 }
    if before.key != after.key { mask |= 1 << 1 }
    if before.pan != after.pan { mask |= 1 << 2 }
    if before.symbol != after.symbol { mask |= 1 << 3 }
    if before.keysplitTable != after.keysplitTable { mask |= 1 << 4 }
    if before.sweep != after.sweep { mask |= 1 << 5 }
    if before.duty != after.duty { mask |= 1 << 6 }
    if before.period != after.period { mask |= 1 << 7 }
    if before.attack != after.attack { mask |= 1 << 8 }
    if before.decay != after.decay { mask |= 1 << 9 }
    if before.sustain != after.sustain { mask |= 1 << 10 }
    if before.release != after.release { mask |= 1 << 11 }
    return mask
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

/// Copy published Swift slots and native split facts while the lease pins the bank.
private func copySlots(_ lease: ProjectBankLease) -> [BankSlotView] {
    lease.withNativeBank { box in
        let nativeLease = pd_bank_lease_native(box)
        let bank = nativeLease.pointee.__getUnsafe()
        return lease.slotViews.enumerated().map { index, slot in
            BankSlotView(kind: slot.kind.rawValue, voice: slot.voice.map(copyVoice),
                         subvoiceMacros: bank.flatMap { storage in
                             guard index < 128 else { return nil }
                             return withUnsafePointer(to: storage.pointee.voices) {
                                 $0.withMemoryRebound(to: ToneData.self, capacity: 128) {
                                     copySubvoiceMacros($0[index])
                                 }
                             }
                         })
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
