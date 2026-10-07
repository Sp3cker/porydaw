import Foundation

/// A hard failure to open, edit, or save a bank; expected conflicts are edit results instead.
public enum VoicegroupStoreError: Error, LocalizedError {
    case operationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .operationFailed(let message): message
        }
    }
}

/// The source and its current bank are canonical; published slot values are snapshots.
private struct BankRecord {
    let id: VoicegroupId
    let source: VoicegroupSource
    var current: Bank
    var sourceFileTime: Date
    var published: LoadedBankView
}

private struct BankMemo {
    let id: VoicegroupId
    var filePath: String
    var sourceFileTime: Date
}

// Single-use tokens survive bank rebuilds; the source delta's byte match guards undo.
private struct TokenRegistry {
    struct Entry {
        let id: VoicegroupId
        let materialization: BlankSlotMaterialization
    }

    private(set) var entries: [UInt64: Entry] = [:]
    private var next: UInt64 = 1

    mutating func mint(id: VoicegroupId, materialization: BlankSlotMaterialization) -> UInt64 {
        let token = next
        precondition(token != 0 && entries[token] == nil, "Voicegroup token space exhausted")
        next = next &+ 1
        entries[token] = Entry(id: id, materialization: materialization)
        return token
    }

    mutating func consume(_ token: UInt64) -> Entry? {
        entries.removeValue(forKey: token)
    }
}

/// Worker-confined bank ownership. Call every method from the store's serial executor.
public final class VoicegroupStore {
    private let projectRoot: String
    private var layout: ProjectLayout
    private var soundMap: SoundDataMap
    private var progMap: ProgWaveMap
    private var keysplits: KeysplitTables
    private let cache = WaveCache()
    private var locator: VoicegroupLocator
    private let textCache = VoicegroupTextCache()
    /// Pending definitions are mutated only by the owning project's serial executor.
    public var pendingSynths: [String: VgSynthDesc] = [:]
    private var records: [VoicegroupId: BankRecord] = [:]
    private var memos: [String: BankMemo] = [:]
    private var tokens = TokenRegistry()

    /// Opens the project's layout and parses its asset maps before loading banks.
    /// - Throws: `VoicegroupStoreError` when the root or asset maps cannot be read.
    public init(projectRoot: String) throws {
        let root = URL(filePath: projectRoot).standardizedFileURL.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw VoicegroupStoreError.operationFailed("Could not initialize the project voicegroup loader.")
        }
        let layout = ProjectLayout(projectRoot: root)
        self.projectRoot = root
        self.layout = layout
        locator = VoicegroupLocator(layout: layout)
        do {
            soundMap = try SoundDataMap.parse(files: layout.soundDataFiles)
            progMap = try ProgWaveMap.parse(files: layout.programmableWaveFiles)
            keysplits = try KeysplitTables.parse(files: layout.keysplitTableFiles)
        } catch {
            throw VoicegroupStoreError.operationFailed("Could not parse the project sample maps: \(error)")
        }
    }

    /// Refreshes maps and rebuilds loaded banks from their current, possibly dirty sources.
    /// - Throws: `VoicegroupStoreError` when the refreshed asset maps cannot be parsed.
    public func rebind() throws -> [LoadedBankView] {
        cache.removeAll()
        let refreshed = ProjectLayout(projectRoot: projectRoot)
        do {
            let sound = try SoundDataMap.parse(files: refreshed.soundDataFiles)
            let prog = try ProgWaveMap.parse(files: refreshed.programmableWaveFiles)
            let tables = try KeysplitTables.parse(files: refreshed.keysplitTableFiles)
            soundMap = sound
            progMap = prog
            keysplits = tables
        } catch {
            throw VoicegroupStoreError.operationFailed("Could not refresh the project sample maps: \(error)")
        }
        layout = refreshed
        locator = VoicegroupLocator(layout: refreshed)
        textCache.removeAll()
        var views: [LoadedBankView] = []
        views.reserveCapacity(records.count)
        for (id, var record) in records {
            guard let bank = try? buildBank(source: record.source) else { continue }
            record.current = bank
            record.published = Self.publish(id: id, source: record.source, bank: bank)
            records[id] = record
            views.append(record.published)
        }
        return views
    }

    /// Resolves a song's voicegroup argument, reusing a canonical bank whose section is unchanged
    /// and rebasing its unsaved edits onto sibling changes in the same source file.
    /// - Parameter voicegroupArg: The song's `-G` argument; empty selects `_dummy`.
    /// - Returns: An immutable bank publication for the resolved source identity.
    /// - Throws: `VoicegroupStoreError` if the source or native bank cannot load, or if disk
    ///   changed a section that has unsaved edits.
    public func loadBank(voicegroupArg: String) throws -> LoadedBankView {
        let arg = voicegroupArg.isEmpty ? "_dummy" : voicegroupArg
        if let memo = memos[arg], let record = records[memo.id],
            record.source.filePath == memo.filePath,
            record.sourceFileTime == memo.sourceFileTime,
            modificationTime(memo.filePath) == memo.sourceFileTime
        {
            return record.published
        }

        guard let location = locator.locate(voicegroupArg: arg) else {
            throw VoicegroupStoreError.operationFailed("No voicegroup file declares voicegroup\(arg).")
        }
        let bytes = try VoicegroupText.read(location.filePath)
        let text = try VoicegroupText.parse(bytes: bytes, sectionLabel: location.sectionLabel)
        let bank = try BankBuilder(inputs: bankBuildInputs()).build(text, at: location)
        let source = VoicegroupSource()
        var error: String?
        guard source.open(location: location, bytes: bytes, projectRoot: projectRoot, voicegroupArg: arg, error: &error)
        else {
            throw VoicegroupStoreError.operationFailed(error ?? "Could not open the voicegroup source.")
        }
        let path = URL(filePath: source.filePath).standardizedFileURL.path
        let prefix = projectRoot.hasSuffix("/") ? projectRoot : projectRoot + "/"
        guard path.hasPrefix(prefix),
            let id = VoicegroupId(
                sourceRelativePath: String(path.dropFirst(prefix.count)),
                sectionLabel: source.sectionLabel)
        else {
            throw VoicegroupStoreError.operationFailed("Could not identify the voicegroup source.")
        }
        guard let time = modificationTime(path) else {
            throw VoicegroupStoreError.operationFailed("Cannot read \(path)")
        }
        if var record = records[id] {
            if record.sourceFileTime == time {
                memos[arg] = BankMemo(id: id, filePath: path, sourceFileTime: time)
                return record.published
            }
            let retained: Bool
            do {
                retained = try record.source.rebasePreservingEdits(from: source)
            } catch {
                throw VoicegroupStoreError.operationFailed(error.localizedDescription)
            }
            if retained {
                record.sourceFileTime = time
                if record.published.dirty != record.source.dirty {
                    record.published = Self.publish(id: id, source: record.source, bank: record.current)
                }
                records[id] = record
                memos[arg] = BankMemo(id: id, filePath: path, sourceFileTime: time)
                return record.published
            }
        }
        let view = Self.publish(id: id, source: source, bank: bank)
        records[id] = BankRecord(
            id: id, source: source, current: bank,
            sourceFileTime: time, published: view)
        memos[arg] = BankMemo(id: id, filePath: path, sourceFileTime: time)
        return view
    }

    /// Applies an expected-value slot edit or an exact-source materialization revert.
    /// - Parameter input: Identity and requested operation.
    /// - Returns: A new publication on success or a confirmed not-applied conflict.
    /// - Throws: `VoicegroupStoreError` on a hard source or loader failure.
    public func applyVoicegroupEdit(input: VoicegroupEditInput) throws -> VoicegroupEditResult {
        guard try refreshIfStale(id: input.id), var record = records[input.id] else {
            return .conflict(.init(voicegroup: input.id))
        }
        let source = record.source
        let before = source.sourceBytes()
        var materialization: BlankSlotMaterialization?
        switch input.operation {
        case .set(let edit):
            guard (0..<128).contains(edit.slot) else { return .conflict(.init(voicegroup: input.id)) }
            if let expected = edit.expected {
                guard source.voiceAt(slot: edit.slot) == expected,
                    source.setVoice(slot: edit.slot, voice: edit.value)
                else {
                    return .conflict(.init(voicegroup: input.id))
                }
            } else {
                guard source.voiceAt(slot: edit.slot) == nil,
                    let added = source.materializeBlankSlot(slot: edit.slot, voice: edit.value)
                else {
                    return .conflict(.init(voicegroup: input.id))
                }
                materialization = added
            }
        case .revert(let revert):
            guard source.revertBlankSlotMaterialization(revert.materialization) else {
                return .conflict(.init(voicegroup: input.id))
            }
        }
        let bank: Bank
        do {
            bank = try buildBank(source: source)
        } catch {
            let restored = source.restoreSourceBytes(before)
            precondition(restored, "Previously parsed voicegroup bytes must restore")
            throw VoicegroupStoreError.operationFailed("Edited voicegroup failed to load.")
        }
        record.current = bank
        record.published = Self.publish(id: record.id, source: source, bank: bank)
        records[input.id] = record
        let token = materialization.map { tokens.mint(id: input.id, materialization: $0) }
        return .applied(
            .init(
                view: record.published, materialization: materialization,
                materializationToken: token))
    }

    /// Consumes a materialization token, then attempts its narrow-delta undo.
    /// - Parameters:
    ///   - id: Identity of the bank whose slot was inserted.
    ///   - materializationToken: Single-use token from a successful insertion.
    /// - Returns: A new publication or a confirmed conflict for spent and stale tokens.
    /// - Throws: `VoicegroupStoreError` for a hard source or loader failure.
    public func revertBlankSlot(id: VoicegroupId, materializationToken: UInt64) throws -> VoicegroupEditResult {
        guard let entry = tokens.consume(materializationToken), entry.id == id else {
            return .conflict(.init(voicegroup: id))
        }
        return try applyVoicegroupEdit(
            input: .init(id: id, operation: .revert(.init(materialization: entry.materialization))))
    }

    /// Writes the source and republishes the bank loaded from its saved bytes.
    /// - Parameter id: Identity of a loaded bank.
    /// - Returns: The clean publication, or nil if the source write fails.
    /// - Throws: `VoicegroupStoreError` for an unloaded bank or a failed reload.
    public func saveVoicegroup(id: VoicegroupId) throws -> LoadedBankView? {
        // A failed stale reload must not hide the error from the actual write attempt.
        guard (try? refreshIfStale(id: id)) != false, var record = records[id] else {
            throw VoicegroupStoreError.operationFailed("Voicegroup is not loaded: \(id.sourceRelativePath)")
        }
        let saved: Bool
        do {
            saved = try record.source.save()
        } catch let conflict as VoicegroupSourceConflict {
            throw VoicegroupStoreError.operationFailed("Cannot write \(record.source.filePath): \(conflict.message)")
        } catch {
            throw VoicegroupStoreError.operationFailed("Cannot write \(record.source.filePath)")
        }
        // Nil is reserved for the supersede race (another edit landed between the
        // save snapshot and didSave); write failures throw above instead.
        guard saved else { return nil }
        let bank = try buildBank(source: record.source)
        guard let time = modificationTime(record.source.filePath) else {
            throw VoicegroupStoreError.operationFailed("Cannot read \(record.source.filePath)")
        }
        record.sourceFileTime = time
        record.current = bank
        record.published = Self.publish(id: id, source: record.source, bank: bank)
        records[id] = record
        for (arg, memo) in memos where memo.id == id {
            memos[arg] = BankMemo(id: id, filePath: record.source.filePath, sourceFileTime: time)
        }
        return record.published
    }

    /// Builds a detached bank directly from the loaded source's current descriptors.
    /// - Returns: A self-contained preview bank, or nil when building fails.
    public func preview(id: VoicegroupId) -> Bank? {
        guard let source = records[id]?.source else { return nil }
        return try? buildBank(source: source)
    }

    /// Returns the record's current detached publication without loading.
    /// - Parameter id: Identity of a loaded bank.
    /// - Returns: The published view, or nil when the bank is not loaded.
    public func currentPublication(id: VoicegroupId) -> LoadedBankView? {
        records[id]?.published
    }

    /// Shares the store's maps, decode cache and text cache with the picker.
    /// All use stays on the owning project's serial executor; banks retain decoded assets.
    public func bankBuildInputs() throws -> BankBuildInputs {
        var overlay = soundMap
        for definition in VoicegroupSource.synthInstruments(projectRoot).defs {
            guard mintedSynthDesc(symbol: definition.symbol) != nil else { continue }
            Self.overlaySynth(definition.descriptor, symbol: definition.symbol, into: &overlay)
        }
        for (symbol, descriptor) in pendingSynths {
            Self.overlaySynth(descriptor, symbol: symbol, into: &overlay)
        }
        for record in records.values {
            let location = VoicegroupLocation(
                filePath: record.source.filePath, sectionLabel: record.source.sectionLabel)
            textCache.set(record.source.sourceBytes(), at: location)
            for slot in 0..<128 {
                guard let symbol = record.source.voiceAt(slot: slot)?.symbol,
                    let descriptor = mintedSynthDesc(symbol: symbol)
                else { continue }
                Self.overlaySynth(descriptor, symbol: symbol, into: &overlay)
            }
        }
        return BankBuildInputs(
            layout: layout, soundMap: overlay, progMap: progMap, keysplits: keysplits,
            cache: cache, locator: locator,
            textProvider: { location, contiguousFill, noSubRecurse in
                try self.textCache.text(at: location, contiguousFill: contiguousFill, noSubRecurse: noSubRecurse)
            })
    }

    private func buildBank(source: VoicegroupSource) throws -> Bank {
        do {
            let text = try source.descriptors()
            var inputs = try bankBuildInputs()
            for index in 0..<128 {
                guard let symbol = text.voices[index]?.symbol else { continue }
                let name = String(decoding: symbol, as: UTF8.self)
                guard let descriptor = mintedSynthDesc(symbol: name) else { continue }
                Self.overlaySynth(descriptor, symbol: name, into: &inputs.soundMap)
            }
            let location = VoicegroupLocation(filePath: source.filePath, sectionLabel: source.sectionLabel)
            textCache.set(source.sourceBytes(), at: location)
            return try BankBuilder(inputs: inputs).build(text, at: location)
        } catch let error as VoicegroupStoreError {
            throw error
        } catch {
            throw VoicegroupStoreError.operationFailed("Could not build \(source.filePath): \(error)")
        }
    }

    private static func overlaySynth(_ descriptor: VgSynthDesc, symbol: String, into map: inout SoundDataMap) {
        let key = Array(symbol.utf8)[...]
        guard map[key] == nil else { return }
        map.entries[SymbolKey(key)] = .synth([
            0x80, UInt8(truncatingIfNeeded: descriptor.waveform),
            UInt8(truncatingIfNeeded: descriptor.baseDuty), UInt8(truncatingIfNeeded: descriptor.dutyStep),
            UInt8(truncatingIfNeeded: descriptor.modDepth), UInt8(truncatingIfNeeded: descriptor.phase),
        ])
    }

    private func refreshIfStale(id: VoicegroupId) throws -> Bool {
        guard let record = records[id] else {
            throw VoicegroupStoreError.operationFailed("Voicegroup is not loaded: \(id.sourceRelativePath)")
        }
        let path = record.source.filePath
        let time = modificationTime(path)
        let memo = memos[record.source.voicegroupArg]
        guard time != record.sourceFileTime || memo?.id != id || memo?.filePath != path || memo?.sourceFileTime != time
        else { return true }
        let reloaded = try loadBank(voicegroupArg: record.source.voicegroupArg)
        return reloaded.id == id
    }

    private func modificationTime(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    private static func publish(id: VoicegroupId, source: VoicegroupSource, bank: Bank) -> LoadedBankView {
        var slots: [VoicegroupSlotView] = []
        slots.reserveCapacity(128)
        for slot in 0..<128 {
            slots.append(.init(kind: source.kindAt(slot: slot), voice: source.voiceAt(slot: slot)))
        }
        return LoadedBankView(
            id: id, bank: bank, loadName: source.loadName,
            dirty: source.dirty, slotViews: slots)
    }
}
