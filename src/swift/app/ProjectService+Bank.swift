import Foundation
import PorydawCore
import PorydawProject
import PorydawBankLease

extension ProjectService {

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

    /// Reads the editor's symbol catalogs; refuses a missing project sound directory.
    public func voicegroupCatalog() async throws -> VoicegroupCatalog {
        let store = try requireStore()
        let root = projectRoot
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory),
            isDirectory.boolValue,
            FileManager.default.fileExists(atPath: root + "/sound", isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw ProjectServiceError.operationFailed("Project sound directory is unavailable.")
        }
        let catalog = await store.voicegroupCatalog()
        let groups = catalog.groups
        let direct = catalog.direct
        var adsrBySymbol: [String: VoiceListAdsr] = [:]
        adsrBySymbol.reserveCapacity(groups.typicalAdsr.bySymbol.count)
        for (symbol, adsr) in groups.typicalAdsr.bySymbol {
            adsrBySymbol[symbol] = VoiceListAdsr(attack: Int32(adsr.attack),
                decay: Int32(adsr.decay), sustain: Int32(adsr.sustain),
                release: Int32(adsr.release))
        }
        var adsrByFamily: [Int32: VoiceListAdsr] = [:]
        adsrByFamily.reserveCapacity(groups.typicalAdsr.byFamily.count)
        for (key, adsr) in groups.typicalAdsr.byFamily {
            adsrByFamily[Int32(key)] = VoiceListAdsr(attack: Int32(adsr.attack),
                decay: Int32(adsr.decay), sustain: Int32(adsr.sustain),
                release: Int32(adsr.release))
        }
        let defaults = VoiceListAdsrDefaults(bySymbol: adsrBySymbol, byFamily: adsrByFamily)
        var keysplits: [String: String] = [:]
        keysplits.reserveCapacity(groups.keysplits.count)
        for split in groups.keysplits { keysplits[split.symbol] = split.table }
        let synths: [String] = direct.synths.defs.map(\.symbol)
        var synthDefinitions: [String: VgSynthDesc] = [:]
        synthDefinitions.reserveCapacity(direct.synths.defs.count)
        for def in direct.synths.defs { synthDefinitions[def.symbol] = def.descriptor }
        return VoicegroupCatalog(
            groupArgs: groups.groupArgs,
            samples: direct.directSound, waves: VoicegroupSource.progWaveSymbols(root),
            drumkits: groups.drumkits,
            keysplits: keysplits,
            synths: synths,
            synthDefinitions: synthDefinitions,
            canMintSynths: direct.synths.creatable(), defaults: defaults)
    }
    /// Writes a per-file voicegroup, appends its hub include, then rescans
    /// the project so the catalog publishes the new arg. Refusals throw.
    /// `copyFromFile` is project-relative ("" for the dummy template).
    public func createVoicegroup(name: String, copyFromFile: String,
                                 copySectionLabel: String) async throws {
        let store = try requireStore()
        guard Self.isValidVoicegroupName(name: name) else {
            throw ProjectServiceError.operationFailed("Invalid voicegroup name: \(name).")
        }
        do {
            let args = try await store.voicegroupArgs()
            guard !args.contains("_" + name) else {
                throw ProjectServiceError.operationFailed("A voicegroup named \(name) already exists.")
            }
            let copyPath = copyFromFile.isEmpty ? "" : projectRoot + "/" + copyFromFile
            try VoicegroupSource.createVoicegroup(projectRoot: projectRoot, name: name,
                                                  copyFromFile: copyPath,
                                                  copySectionLabel: copySectionLabel)
            try VoicegroupSource.appendIncludeLine(projectRoot: projectRoot, name: name)
            try await open(root: projectRoot)
        } catch {
            throw projectFailure(error)
        }
    }

    public nonisolated static func isValidVoicegroupName(name: String) -> Bool {
        name.range(of: #"^[A-Za-z][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
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
                throw ProjectServiceError.songNotPlayable(label: label)
            }
            guard song.hasMid, let midiPath = song.midPath else {
                throw ProjectServiceError.songNotPlayable(label: label)
            }
            let bytes: Data
            do {
                bytes = try await store.readFile(midiPath)
            } catch ProjectFileStoreError.cannotRead(let path) {
                throw ProjectServiceError.songMidiUnavailable(label: label, path: path)
            }
            let bank: ProjectBankLease
            do {
                bank = try await store.loadBank(voicegroupArg: song.cfg.voicegroupArgument)
            } catch VoicegroupStoreError.operationFailed(let reason) {
                throw ProjectServiceError.songBankUnavailable(
                    label: label, voicegroupArgument: song.cfg.voicegroupArgument,
                    reason: reason)
            }
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
            let failure = projectFailure(error)
            guard case let .operationFailed(message) = failure else { throw failure }
            throw ProjectServiceError.operationFailed("Open song \(label): \(message)")
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
            do {
                try await store.writeFile(snapshot.destination.midiPath, data: Data(snapshot.bytes))
            } catch ProjectFileStoreError.cannotWrite(let path) {
                throw ProjectServiceError.songSaveUnavailable(
                    label: snapshot.destination.label, path: path)
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
            let failure = projectFailure(error)
            guard case let .operationFailed(message) = failure else { throw failure }
            throw ProjectServiceError.operationFailed(
                "Save song \(snapshot.destination.label): \(message)")
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
                          value: BankVoice, expected: BankVoice?,
                          publishResult: Bool = true) async throws -> AppliedBankEdit {
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
            if publishResult { await publish(applied, from: store) }
            return applied
        } catch {
            throw projectFailure(error)
        }
    }

    /// Reverts a blank-slot materialization via its single-shot token. Spent
    /// or unknown tokens throw bankConflict; the source bytes stay untouched.
    public func bankRevert(lease: NativeBankLease, token: UInt64,
                           publishResult: Bool = true) async throws -> AppliedBankEdit {
        let store = try requireStore()
        guard lease.publicationOwner == store.publicationOwner else {
            throw ProjectServiceError.serviceClosed
        }
        do {
            let applied = try bankEditResult(
                await store.revertBlankSlot(lease: lease.handle, materializationToken: token))
            if publishResult { await publish(applied, from: store) }
            return applied
        } catch {
            throw projectFailure(error)
        }
    }
}
