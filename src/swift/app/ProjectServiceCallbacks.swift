import Foundation
import PorydawCore
import PorydawProjectService

// MARK: - Borrowed-then-copied completion glue

/// Handoff for one outstanding operation. The C completion runs on the worker
/// thread, copies every borrowed payload synchronously, then resumes.
final class ContinuationBox<T>: @unchecked Sendable {
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

private func copyTone(_ slot: PdBankSlotView) -> BankTone? {
    guard slot.hasTone else { return nil }
    return BankTone(name: copyCString(slot.toneName), type: slot.toneType,
                    isSynth: slot.toneSynth,
                    adsr: slot.hasToneAdsr
                        ? BankToneAdsr(attack: slot.toneAttack, decay: slot.toneDecay,
                                       sustain: slot.toneSustain, release: slot.toneRelease)
                        : nil)
}

/// Resolve native split facts while the completion's owning lease is alive.
/// The sole owned array is retained by the published slot, never native pointers.
private func copySubvoiceMacros(_ tone: ToneData) -> [Int32]? {
    let split = tone.type & UInt8(VOICE_KEYSPLIT | VOICE_KEYSPLIT_ALL)
    guard split != 0 else { return nil }
    guard let group = tone.subGroup?.assumingMemoryBound(to: ToneData.self),
          tone.type & UInt8(VOICE_KEYSPLIT) == 0 || tone.keySplitTable != nil else {
        return Array(repeating: -1, count: 128)
    }
    return (0..<128).map { key in
        let index = tone.type & UInt8(VOICE_KEYSPLIT_ALL) != 0
            ? key : Int(tone.keySplitTable![key])
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

private func copySlots(_ view: UnsafePointer<PdBankView>?, lease: OpaquePointer)
    -> (slots: [BankSlotView],
                                                               loadName: String,
                                                               sourcePath: String,
                                                               sectionLabel: String,
                                                               dirty: Bool) {
    guard let view, let base = view.pointee.slotViews else { return ([], "", "", "", false) }
    let nativeLease = pd_bank_lease_native(lease)
    defer { withExtendedLifetime(nativeLease) {} }
    let bank = nativeLease.pointee.__getUnsafe()
    var slots: [BankSlotView] = []
    slots.reserveCapacity(view.pointee.slotCount)
    for index in 0..<view.pointee.slotCount {
        let slot = base[index]
        slots.append(BankSlotView(kind: slot.kind,
                                  voice: slot.hasVoice ? copyVoice(slot.voice) : nil,
                                  tone: copyTone(slot),
                                  subvoiceMacros: bank.flatMap { bank in
                                      guard index < 128 else { return nil }
                                      return withUnsafePointer(to: bank.pointee.voices) {
                                          $0.withMemoryRebound(to: ToneData.self, capacity: 128) {
                                              copySubvoiceMacros($0[index])
                                          }
                                      }
                                  }))
    }
    return (slots, copyCString(view.pointee.loadName), copyCString(view.pointee.sourcePath),
            copyCString(view.pointee.sectionLabel), view.pointee.dirty)
}

let openCompletion: PdOpenCompletion = { context, ok, error in
    let holder =
        Unmanaged<ContinuationBox<Void>>.fromOpaque(context!).takeRetainedValue()
    if ok {
        holder.continuation.resume()
    } else {
        holder.continuation.resume(throwing: ProjectServiceError.operationFailed(copyCString(error)))
    }
}

let songListCompletion: PdSongListCompletion = {
    context, ok, entries, entryCount, error in
    let holder =
        Unmanaged<ContinuationBox<[SongListing]>>.fromOpaque(context!).takeRetainedValue()
    guard ok else {
        holder.continuation.resume(
            throwing: ProjectServiceError.operationFailed(copyCString(error)))
        return
    }
    var result: [SongListing] = []
    result.reserveCapacity(entryCount)
    if let entries {
        for index in 0..<entryCount {
            let entry = entries[index]
            var gaps: [String] = []
            gaps.reserveCapacity(entry.registrationGapCount)
            if let gapBase = entry.registrationGaps {
                for gapIndex in 0..<entry.registrationGapCount {
                    gaps.append(copyCString(gapBase[gapIndex]))
                }
            }
            result.append(SongListing(
                id: Int(entry.id), label: copyCString(entry.label),
                constant: copyCString(entry.constant), player: copyCString(entry.player),
                midiPath: copyCString(entry.midiPath), trackBudget: Int(entry.trackBudget),
                hasMid: entry.hasMid, hasCfg: entry.hasCfg, registered: entry.registered,
                registrationGaps: gaps))
        }
    }
    holder.continuation.resume(returning: result)
}

let registrationPlanCompletion: PdSongRegistrationPlanCompletion = {
    context, ok, plan, error in
    let holder =
        Unmanaged<ContinuationBox<SongRegistrationPlan>>.fromOpaque(context!).takeRetainedValue()
    guard ok, let plan else {
        holder.continuation.resume(
            throwing: ProjectServiceError.operationFailed(copyCString(error)))
        return
    }
    var missing: [String] = []
    missing.reserveCapacity(plan.pointee.missingFileCount)
    if let base = plan.pointee.missingFiles {
        for index in 0..<plan.pointee.missingFileCount {
            missing.append(copyCString(base[index]))
        }
    }
    holder.continuation.resume(returning: SongRegistrationPlan(
        label: copyCString(plan.pointee.label), constant: copyCString(plan.pointee.constant),
        player: copyCString(plan.pointee.player), songId: Int(plan.pointee.songId),
        missingFiles: missing))
}

let deletionPlanCompletion: PdSongDeletionPlanCompletion = {
    context, ok, plan, error in
    let holder =
        Unmanaged<ContinuationBox<SongDeletionPlan>>.fromOpaque(context!).takeRetainedValue()
    guard ok, let plan else {
        holder.continuation.resume(
            throwing: ProjectServiceError.operationFailed(copyCString(error)))
        return
    }
    let voicegroup = copyCString(plan.pointee.deletableVoicegroup)
    let display = copyCString(plan.pointee.deletableVoicegroupDisplay)
    holder.continuation.resume(returning: SongDeletionPlan(
        tableIndex: Int(plan.pointee.tableIndex), tableCount: Int(plan.pointee.tableCount),
        lastEntry: plan.pointee.lastEntry, inSongsH: plan.pointee.inSongsH,
        inLdScript: plan.pointee.inLdScript, inCharmap: plan.pointee.inCharmap,
        inDebugMenu: plan.pointee.inDebugMenu,
        deletableVoicegroupName: voicegroup.isEmpty ? nil : voicegroup,
        deletableVoicegroupDisplay: display.isEmpty ? nil : display))
}

let mutationCompletion: PdSongMutationCompletion = {
    context, ok, songId, error in
    let holder =
        Unmanaged<ContinuationBox<Int>>.fromOpaque(context!).takeRetainedValue()
    guard ok else {
        holder.continuation.resume(
            throwing: ProjectServiceError.operationFailed(copyCString(error)))
        return
    }
    holder.continuation.resume(returning: Int(songId))
}

let stringListCompletion: PdStringListCompletion = {
    context, ok, strings, stringCount, error in
    let holder =
        Unmanaged<ContinuationBox<[String]>>.fromOpaque(context!).takeRetainedValue()
    guard ok else {
        holder.continuation.resume(
            throwing: ProjectServiceError.operationFailed(copyCString(error)))
        return
    }
    var result: [String] = []
    result.reserveCapacity(stringCount)
    if let strings {
        for index in 0..<stringCount {
            result.append(copyCString(strings[index]))
        }
    }
    holder.continuation.resume(returning: result)
}

let songCompletion: PdSongCompletion = {
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
    let bankCopy = copySlots(bank, lease: lease)
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

let saveCompletion: PdSaveCompletion = {
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
        let bankCopy = copySlots(bank, lease: lease)
        receipt.bank = AppliedBankEdit(
            lease: NativeBankLease(handle: lease, sourcePath: bankCopy.sourcePath,
                                   sectionLabel: bankCopy.sectionLabel),
            slots: bankCopy.slots, dirty: bankCopy.dirty, loadName: bankCopy.loadName,
            materializationToken: nil)
    }
    holder.continuation.resume(returning: receipt)
}

let bankEditCompletion: PdBankEditCompletion = {
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
        let bankCopy = copySlots(bank, lease: lease)
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

func withPdVoice(_ voice: BankVoice, _ body: (PdVoiceValue) -> Void) {
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

