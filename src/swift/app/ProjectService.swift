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

/// One published bank slot, mirroring VoicegroupSlotView.
public struct BankSlotView: Equatable, Sendable {
    /// BankSlotKind ordinal.
    public var kind: Int32
    /// The parsed voice when kind is editable.
    public var voice: BankVoice?

    public init(kind: Int32 = BankSlotKind.none, voice: BankVoice? = nil) {
        self.kind = kind
        self.voice = voice
    }
}

// MARK: - Owned bank lease

/// Swift ownership wrapper over one opaque native bank handle. ARC shares the
/// wrapper; deinit releases the handle on whatever thread drops the last
/// reference (the release is thread-safe). Applied edits mint a fresh lease;
/// the superseded wrapper keeps its own bank alive, so old views stay valid.
public final class NativeBankLease: @unchecked Sendable {
    fileprivate let handle: OpaquePointer
    /// Voicegroup identity, copied from the published view for save requests.
    public let sourcePath: String
    public let sectionLabel: String

    fileprivate init(handle: OpaquePointer, sourcePath: String, sectionLabel: String) {
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

// MARK: - Project service

/// Async Swift front over the serial native worker. The actor serializes bank
/// transitions; document history never blocks on it.
public actor ProjectService {
    private var handle: OpaquePointer?
    private var closed = false

    public init() {
        handle = pd_service_create()
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
                // A blank redo materializes again and mints a fresh token.
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
    }

    func merged(with newer: any BankHistoryAction) -> (any BankHistoryAction)? {
        guard let other = newer as? ServiceBankAction,
              other.service === service,
              other.slot == slot,
              !materializedBlank, !other.materializedBlank,
              token == nil, other.token == nil,
              let oldest = before, let middle = other.before,
              bankChangedFieldMask(oldest, after) == bankChangedFieldMask(middle, other.after)
        else { return nil }
        return ServiceBankAction(service: service, slot: slot, before: oldest,
                                 after: other.after, token: nil, materializedBlank: false,
                                 current: other.current, inbox: inbox)
    }
}

/// Scalar merge boundary: which of the twelve voice fields an edit changes.
/// Internal to the Swift merge policy; the mask never crosses the C boundary.
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

// MARK: - Borrowed-then-copied completion glue

/// Handoff for one outstanding operation. The C completion runs on the worker
/// thread, copies every borrowed payload synchronously, then resumes.
private final class ContinuationBox<T>: @unchecked Sendable {
    let continuation: CheckedContinuation<T, Error>

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }
}

private func copyCString(_ pointer: UnsafePointer<CChar>?) -> String {
    guard let pointer else { return "" }
    return String(cString: pointer)
}

private func copyBytes(_ pointer: UnsafePointer<UInt8>?, _ count: Int) -> [UInt8] {
    guard let pointer, count > 0 else { return [] }
    return Array(UnsafeBufferPointer(start: pointer, count: count))
}

private func copyCfg(_ cfg: PdSongCfg) -> (rawFlags: [String], voicegroupArgument: String,
                                           masterVolume: Int, reverb: Int?, priority: Int) {
    var rawFlags: [String] = []
    rawFlags.reserveCapacity(cfg.rawFlagCount)
    if let base = cfg.rawFlags {
        for index in 0..<cfg.rawFlagCount {
            rawFlags.append(copyCString(base[index]))
        }
    }
    return (rawFlags, copyCString(cfg.voicegroupArg), Int(cfg.masterVolume),
            cfg.hasReverb ? Int(cfg.reverb) : nil, Int(cfg.priority))
}

private func copyVoice(_ voice: PdVoiceValue) -> BankVoice {
    BankVoice(macro: voice.macro, key: voice.key, pan: voice.pan,
              symbol: copyCString(voice.symbol), keysplitTable: copyCString(voice.keysplitTable),
              sweep: voice.sweep, duty: voice.duty, period: voice.period,
              attack: voice.attack, decay: voice.decay, sustain: voice.sustain,
              release: voice.release)
}

private func copySlots(_ view: UnsafePointer<PdBankView>?) -> (slots: [BankSlotView],
                                                               loadName: String,
                                                               sourcePath: String,
                                                               sectionLabel: String,
                                                               dirty: Bool) {
    guard let view, let base = view.pointee.slotViews else { return ([], "", "", "", false) }
    var slots: [BankSlotView] = []
    slots.reserveCapacity(view.pointee.slotCount)
    for index in 0..<view.pointee.slotCount {
        let slot = base[index]
        slots.append(BankSlotView(kind: slot.kind,
                                  voice: slot.hasVoice ? copyVoice(slot.voice) : nil))
    }
    return (slots, copyCString(view.pointee.loadName), copyCString(view.pointee.sourcePath),
            copyCString(view.pointee.sectionLabel), view.pointee.dirty)
}

private let openCompletion: PdOpenCompletion = { context, ok, error in
    let holder =
        Unmanaged<ContinuationBox<Void>>.fromOpaque(context!).takeRetainedValue()
    if ok {
        holder.continuation.resume()
    } else {
        holder.continuation.resume(throwing: ProjectServiceError.operationFailed(copyCString(error)))
    }
}

private let songCompletion: PdSongCompletion = {
    context, ok, midiBytes, midiByteCount, meta, bank, lease, error in
    let holder =
        Unmanaged<ContinuationBox<LoadedSong>>.fromOpaque(context!).takeRetainedValue()
    guard ok, let meta, let midiBytes else {
        holder.continuation.resume(
            throwing: ProjectServiceError.operationFailed(copyCString(error)))
        return
    }
    guard let lease else {
        holder.continuation.resume(
            throwing: ProjectServiceError.operationFailed("Song opened without a bank lease."))
        return
    }
    let cfg = copyCfg(meta.pointee.cfg)
    let bankCopy = copySlots(bank)
    let song = LoadedSong(
        label: copyCString(meta.pointee.label), midiPath: copyCString(meta.pointee.midiPath),
        constant: copyCString(meta.pointee.constant), player: copyCString(meta.pointee.player),
        trackBudget: Int(meta.pointee.trackBudget), hasMid: meta.pointee.hasMid,
        hasCfg: meta.pointee.hasCfg, registered: meta.pointee.registered,
        config: SongConfig(rawFlags: cfg.rawFlags, voicegroupArgument: cfg.voicegroupArgument,
                           masterVolume: cfg.masterVolume, reverb: cfg.reverb,
                           priority: cfg.priority, exactGate: meta.pointee.cfg.exactGate,
                           extendedClocks: meta.pointee.cfg.extendedClocks,
                           noCompression: meta.pointee.cfg.noCompression),
        source: SongSource(label: copyCString(meta.pointee.label),
                           midiPath: copyCString(meta.pointee.midiPath),
                           hasConfig: meta.pointee.hasCfg),
        midiBytes: copyBytes(midiBytes, midiByteCount),
        bank: NativeBankLease(handle: lease, sourcePath: bankCopy.sourcePath,
                              sectionLabel: bankCopy.sectionLabel),
        bankSlots: bankCopy.slots, bankDirty: bankCopy.dirty,
        bankLoadName: bankCopy.loadName)
    holder.continuation.resume(returning: song)
}

private let saveCompletion: PdSaveCompletion = {
    context, ok, flagsWritten, bank, lease, error in
    let holder =
        Unmanaged<ContinuationBox<SaveReceipt>>.fromOpaque(context!).takeRetainedValue()
    guard ok else {
        holder.continuation.resume(
            throwing: ProjectServiceError.operationFailed(copyCString(error)))
        return
    }
    var receipt = SaveReceipt(flagsWritten: flagsWritten, bank: nil)
    if let bank, let lease {
        let bankCopy = copySlots(bank)
        receipt.bank = AppliedBankEdit(
            lease: NativeBankLease(handle: lease, sourcePath: bankCopy.sourcePath,
                                   sectionLabel: bankCopy.sectionLabel),
            slots: bankCopy.slots, dirty: bankCopy.dirty, loadName: bankCopy.loadName,
            materializationToken: nil)
    }
    holder.continuation.resume(returning: receipt)
}

private let bankEditCompletion: PdBankEditCompletion = {
    context, outcome, bank, lease, token, error in
    let holder =
        Unmanaged<ContinuationBox<AppliedBankEdit>>.fromOpaque(context!).takeRetainedValue()
    let code = Int(outcome)
    if code == Int(PD_BANK_EDIT_CONFLICT) {
        holder.continuation.resume(throwing: ProjectServiceError.bankConflict)
    } else if code == Int(PD_BANK_EDIT_APPLIED) {
        guard let bank, let lease else {
            holder.continuation.resume(
                throwing: ProjectServiceError.operationFailed(
                    "Bank edit applied without a refreshed view."))
            return
        }
        let bankCopy = copySlots(bank)
        holder.continuation.resume(returning: AppliedBankEdit(
            lease: NativeBankLease(handle: lease, sourcePath: bankCopy.sourcePath,
                                   sectionLabel: bankCopy.sectionLabel),
            slots: bankCopy.slots, dirty: bankCopy.dirty, loadName: bankCopy.loadName,
            materializationToken: token == 0 ? nil : token))
    } else {
        holder.continuation.resume(
            throwing: ProjectServiceError.operationFailed(copyCString(error)))
    }
}

private func withPdVoice(_ voice: BankVoice, _ body: (PdVoiceValue) -> Void) {
    voice.symbol.withCString { symbolPtr in
        voice.keysplitTable.withCString { keysplitPtr in
            body(PdVoiceValue(macro: voice.macro, key: voice.key, pan: voice.pan,
                              symbol: symbolPtr, keysplitTable: keysplitPtr,
                              sweep: voice.sweep, duty: voice.duty, period: voice.period,
                              attack: voice.attack, decay: voice.decay, sustain: voice.sustain,
                              release: voice.release))
        }
    }
}
