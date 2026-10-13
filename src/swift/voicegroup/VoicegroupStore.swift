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
    var source: VoicegroupSource
    var current: Bank
    var sourceFileTime: Date
    var published: LoadedBankView
    var kitKeys = KitStaging.Keys()
}

private struct BankMemo {
    let id: VoicegroupId
    var filePath: String
    var sourceFileTime: Date
}

private struct KitStaging {
    struct Keys {
        var subgroups: Set<VoicegroupLocation> = []
        var tables: Set<String> = []
        var isEmpty: Bool { subgroups.isEmpty && tables.isEmpty }
    }

    var subgroups: [VoicegroupLocation: VoicegroupSource] = [:]
    var tables: [String: KeysplitTable] = [:]
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
    private var kitStaging = KitStaging()

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
            record.published = Self.publish(
                id: id, source: record.source, bank: bank, staged: !record.kitKeys.isEmpty)
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
                if record.published.dirty != (record.source.dirty || !record.kitKeys.isEmpty) {
                    record.published = Self.publish(
                        id: id, source: record.source, bank: record.current, staged: !record.kitKeys.isEmpty)
                }
                records[id] = record
                memos[arg] = BankMemo(id: id, filePath: path, sourceFileTime: time)
                return record.published
            }
        }
        let staging = stagingWithoutKeys(of: id)
        textCache.removeAll()
        let bank = try buildBank(source: source, staging: staging)
        kitStaging = staging
        textCache.removeAll()
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
        record.published = Self.publish(
            id: record.id, source: source, bank: bank, staged: !record.kitKeys.isEmpty)
        records[input.id] = record
        let token = materialization.map { tokens.mint(id: input.id, materialization: $0) }
        return .applied(
            .init(
                view: record.published, materialization: materialization,
                materializationToken: token))
    }

    /// Stages a kit edit and republishes only the requested voicegroup's bank.
    /// - Throws: `VoicegroupStoreError` naming the source on conflict or build failure.
    public func applyKitEdit(input: KitEditInput, expected: KitParentExpectation) throws -> VoicegroupEditResult {
        guard try refreshIfStale(id: input.id), var record = records[input.id] else {
            throw VoicegroupStoreError.operationFailed("Voicegroup is not loaded: \(input.id.sourceRelativePath)")
        }
        let source = record.source
        guard (0..<128).contains(input.slot) else {
            throw VoicegroupStoreError.operationFailed("Cannot edit slot \(input.slot) in \(source.filePath).")
        }
        if case .parent(let voice) = expected,
            voice == nil ? source.kindAt(slot: input.slot) != .none : source.voiceAt(slot: input.slot) != voice
        {
            throw VoicegroupStoreError.operationFailed(
                "Cannot edit slot \(input.slot) in \(source.filePath): parent changed.")
        }
        let parentOnly = input.subgroupSymbol.isEmpty && input.children.isEmpty && input.table == nil
        let parent = try detachedSource(source)
        var staging = kitStaging
        var keys = record.kitKeys
        if !parentOnly {
            guard let targetParent = input.parent,
                targetParent.macro == .keysplitAll || targetParent.macro == .keysplit,
                targetParent.symbol == input.subgroupSymbol, input.children.count <= 128
            else {
                throw VoicegroupStoreError.operationFailed("Invalid kit edit in \(source.filePath).")
            }
            guard let location = locator.locateSubgroup(symbol: Array(input.subgroupSymbol.utf8)[...]) else {
                throw VoicegroupStoreError.operationFailed(
                    "no sub-voicegroup \(input.subgroupSymbol) found in the project (\(source.filePath))")
            }
            let subgroup: VoicegroupSource
            if let staged = staging.subgroups[location] {
                subgroup = try detachedSource(staged)
            } else {
                subgroup = VoicegroupSource()
                var error: String?
                guard subgroup.open(location: location, error: &error) else {
                    throw VoicegroupStoreError.operationFailed(
                        "Cannot open \(location.filePath): \(error ?? "invalid source")")
                }
            }
            if let table = input.table {
                guard targetParent.macro == .keysplit, targetParent.keysplitTable == table.name,
                    table.table.count == 128, (0..<128).contains(table.startingNote),
                    (0...128).contains(table.maxNote),
                    table.table.allSatisfy({ (value: UInt8) in value < 128 })
                else {
                    throw VoicegroupStoreError.operationFailed("Invalid keysplit table in \(parent.filePath).")
                }
                staging.tables[table.name] = table
                keys.tables.insert(table.name)
            }
            for (slot, child) in input.children.enumerated() {
                guard subgroup.setVoice(slot: slot, voice: child ?? kitBlankChildVoice) else {
                    throw VoicegroupStoreError.operationFailed("Cannot edit slot \(slot) in \(subgroup.filePath).")
                }
            }
            staging.subgroups[location] = subgroup
            keys.subgroups.insert(location)
        }
        var materialization: BlankSlotMaterialization?
        if let targetParent = input.parent {
            if parent.kindAt(slot: input.slot) == .none {
                guard let inserted = parent.materializeBlankSlot(slot: input.slot, voice: targetParent) else {
                    throw VoicegroupStoreError.operationFailed(
                        "Cannot materialize slot \(input.slot) in \(parent.filePath).")
                }
                materialization = inserted
            } else if !parent.setVoice(slot: input.slot, voice: targetParent) {
                throw VoicegroupStoreError.operationFailed("Cannot edit slot \(input.slot) in \(parent.filePath).")
            }
        } else {
            guard parentOnly, let inserted = input.materialization,
                inserted.firstAddedSlot <= input.slot,
                input.slot < inserted.firstAddedSlot + inserted.addedLines.count,
                parent.revertBlankSlotMaterialization(inserted, authoritative: expected == .authoritative)
            else {
                throw VoicegroupStoreError.operationFailed(
                    "Cannot restore undefined slot \(input.slot) in \(parent.filePath).")
            }
        }
        let bank: Bank
        do {
            bank = try buildBank(source: parent, staging: staging)
        } catch {
            textCache.removeAll()
            throw error
        }
        record.source = parent
        record.kitKeys = keys
        record.current = bank
        record.published = Self.publish(id: input.id, source: parent, bank: bank, staged: !keys.isEmpty)
        kitStaging = staging
        records[input.id] = record
        return .applied(.init(view: record.published, materialization: materialization, materializationToken: nil))
    }

    /// Reads raw parent and child voices through the current kit staging overlays.
    /// - Returns: A parent-only value for a non-kit or undefined slot.
    /// - Throws: `VoicegroupStoreError` for an unloaded bank or invalid source.
    public func kitSnapshot(id: VoicegroupId, slot: Int) throws -> KitSnapshot? {
        guard try refreshIfStale(id: id), let source = records[id]?.source else {
            throw VoicegroupStoreError.operationFailed("Voicegroup is not loaded: \(id.sourceRelativePath)")
        }
        guard (0..<128).contains(slot) else {
            throw VoicegroupStoreError.operationFailed("Cannot read slot \(slot) in \(source.filePath).")
        }
        let parent = source.voiceAt(slot: slot)
        guard let parent, parent.macro == .keysplitAll || parent.macro == .keysplit else {
            return KitSnapshot(
                voicegroup: source.voicegroupArg, parent: parent, subgroupSymbol: "", children: [], table: nil)
        }
        let inputs = try bankBuildInputs()
        guard let location = inputs.locator.locateSubgroup(symbol: Array(parent.symbol.utf8)[...]) else {
            throw VoicegroupStoreError.operationFailed(
                "no sub-voicegroup \(parent.symbol) found in the project (\(source.filePath))")
        }
        let subgroup: VoicegroupSource
        if let staged = kitStaging.subgroups[location] {
            subgroup = staged
        } else if let loaded = records.values.first(where: {
            $0.source.filePath == location.filePath && $0.source.sectionLabel == location.sectionLabel
        }) {
            subgroup = loaded.source
        } else {
            subgroup = VoicegroupSource()
            var error: String?
            guard subgroup.open(location: location, error: &error) else {
                throw VoicegroupStoreError.operationFailed(
                    "Cannot open \(location.filePath): \(error ?? "invalid source")")
            }
        }
        let children = (0..<128).map { (childSlot: Int) -> VgVoice? in subgroup.voiceAt(slot: childSlot) }
        let table = parent.macro == .keysplit ? inputs.keysplits.table(named: parent.keysplitTable) : nil
        return KitSnapshot(
            voicegroup: source.voicegroupArg, parent: parent,
            subgroupSymbol: parent.symbol, children: children, table: table)
    }

    /// Copies a project sample from the bank resolver without exposing cached pointers.
    public func sampleAsset(symbol: String) throws -> KitSampleAsset? {
        let builder = BankBuilder(inputs: try bankBuildInputs())
        guard let wave = try builder.resolveSample(symbol: Array(symbol.utf8)[...]) else { return nil }
        let header = Span(_unsafeStart: wave, count: 1)[0]
        let pcm: [Int8]
        if let data = header.data {
            let samples = Span(_unsafeStart: data, count: Int(header.size))
            pcm = (0..<samples.count).map { (index: Int) -> Int8 in samples[index] }
        } else {
            precondition(header.size == 0, "A decoded sample must have PCM storage")
            pcm = []
        }
        return KitSampleAsset(
            pcm: pcm,
            frequency: header.freq, looped: header.status & 0x4000 != 0, loopStart: Int(header.loopStart))
    }

    /// Copies one programmable wave and releases the resolver's fresh allocation.
    public func progWaveWords(symbol: String) throws -> [UInt32]? {
        let builder = BankBuilder(inputs: try bankBuildInputs())
        guard let wave = try builder.resolveProgWave(symbol: Array(symbol.utf8)[...]) else { return nil }
        defer { free(wave) }
        let words = Span(_unsafeStart: wave, count: 4)
        return (0..<4).map { (index: Int) -> UInt32 in words[index] }
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
        if record.kitKeys.isEmpty {
            let saved: Bool
            do {
                saved = try record.source.save()
            } catch let conflict as VoicegroupSourceConflict {
                throw VoicegroupStoreError.operationFailed(
                    "Cannot write \(record.source.filePath): \(conflict.message)")
            } catch {
                throw VoicegroupStoreError.operationFailed("Cannot write \(record.source.filePath)")
            }
            // Nil is reserved for an edit superseding the save snapshot.
            guard saved else { return nil }
            record.current = try buildBank(source: record.source)
            guard let time = modificationTime(record.source.filePath) else {
                throw VoicegroupStoreError.operationFailed("Cannot read \(record.source.filePath)")
            }
            record.sourceFileTime = time
        } else {
            try saveKit(record: &record)
        }
        record.published = Self.publish(
            id: id, source: record.source, bank: record.current, staged: !record.kitKeys.isEmpty)
        records[id] = record
        for (arg, memo) in memos where memo.id == id {
            memos[arg] = BankMemo(
                id: id, filePath: record.source.filePath, sourceFileTime: record.sourceFileTime)
        }
        return record.published
    }

    private func detachedSource(_ source: VoicegroupSource) throws -> VoicegroupSource {
        let copy = VoicegroupSource()
        var error: String?
        guard
            copy.open(
                location: VoicegroupLocation(filePath: source.filePath, sectionLabel: source.sectionLabel),
                bytes: source.pristineSource, projectRoot: source.projectRoot,
                voicegroupArg: source.voicegroupArg, error: &error),
            copy.restoreSourceBytes(source.sourceBytes())
        else {
            throw VoicegroupStoreError.operationFailed("Cannot open \(source.filePath): \(error ?? "invalid source")")
        }
        return copy
    }

    private func stagingWithoutKeys(of id: VoicegroupId) -> KitStaging {
        var staging = kitStaging
        let retained = records.filter { $0.key != id }.values
        staging.subgroups = staging.subgroups.filter { location, _ in
            retained.contains { $0.kitKeys.subgroups.contains(location) }
        }
        staging.tables = staging.tables.filter { name, _ in
            retained.contains { $0.kitKeys.tables.contains(name) }
        }
        return staging
    }

    private func saveKit(record: inout BankRecord) throws {
        let parent = try detachedSource(record.source)
        let keys = record.kitKeys
        var subgroups: [VoicegroupSource] = []
        var tableWrites: [(table: KeysplitTable, path: String)] = []
        var originals: [String: Data] = [:]
        var written: Set<String> = []
        let priorTables = keysplits
        var savedStaging = kitStaging
        for location in keys.subgroups { savedStaging.subgroups.removeValue(forKey: location) }
        for name in keys.tables { savedStaging.tables.removeValue(forKey: name) }
        let bank: Bank
        let time: Date
        do {
            originals[parent.filePath] = try ProjectFileStore.read(parent.filePath)
            for location in keys.subgroups.sorted(by: {
                ($0.filePath, $0.sectionLabel) < ($1.filePath, $1.sectionLabel)
            }) {
                guard let staged = kitStaging.subgroups[location] else {
                    preconditionFailure("Tracked kit subgroup has no staged source")
                }
                subgroups.append(try detachedSource(staged))
                originals[location.filePath] = try ProjectFileStore.read(location.filePath)
            }
            let files = layout.ensuringDeepScan().keysplitTableFiles
            for name in keys.tables.sorted() {
                guard let table = kitStaging.tables[name] else {
                    preconditionFailure("Tracked kit table has no staged value")
                }
                var path = files.first ?? projectRoot + "/sound/keysplit_tables.inc"
                for candidate in files {
                    if try KeysplitTables.parse(files: [candidate]).table(named: name) != nil {
                        path = candidate
                        break
                    }
                }
                originals[path] = try ProjectFileStore.read(path)
                tableWrites.append((table, path))
            }
            let parentSaved = try parent.save()
            written.insert(parent.filePath)
            guard parentSaved else {
                throw VoicegroupStoreError.operationFailed("Cannot save \(parent.filePath): edit superseded.")
            }
            for subgroup in subgroups {
                let subgroupSaved = try subgroup.save()
                written.insert(subgroup.filePath)
                guard subgroupSaved else {
                    throw VoicegroupStoreError.operationFailed("Cannot save \(subgroup.filePath): edit superseded.")
                }
            }
            for write in tableWrites {
                try KeysplitTableWriter.replace(table: write.table, inFile: write.path)
                written.insert(write.path)
            }
            if subgroups.contains(where: { $0.filePath == parent.filePath }) {
                guard try parent.rebasePreservingEdits(from: parent.diskSnapshot()) else {
                    throw VoicegroupStoreError.operationFailed("Cannot refresh \(parent.filePath): source changed.")
                }
            }
            keysplits = try KeysplitTables.parse(files: layout.ensuringDeepScan().keysplitTableFiles)
            textCache.removeAll()
            bank = try buildBank(source: parent, staging: savedStaging)
            guard let savedTime = modificationTime(parent.filePath) else {
                throw VoicegroupStoreError.operationFailed("Cannot read \(parent.filePath)")
            }
            time = savedTime
        } catch {
            keysplits = priorTables
            textCache.removeAll()
            for path in written {
                guard let bytes = originals[path] else { preconditionFailure("Written kit source has no snapshot") }
                do {
                    try ProjectFileStore.writeAtomic(path, data: bytes)
                } catch {
                    throw VoicegroupStoreError.operationFailed("Cannot restore \(path): \(error)")
                }
            }
            throw VoicegroupStoreError.operationFailed("Cannot save \(parent.filePath): \(error)")
        }
        record.source = parent
        record.current = bank
        record.sourceFileTime = time
        record.kitKeys = KitStaging.Keys()
        for (id, var other) in records where id != record.id {
            guard
                !other.kitKeys.subgroups.isDisjoint(with: keys.subgroups)
                    || !other.kitKeys.tables.isDisjoint(with: keys.tables)
            else { continue }
            other.kitKeys.subgroups.subtract(keys.subgroups)
            other.kitKeys.tables.subtract(keys.tables)
            other.published = Self.publish(
                id: id, source: other.source, bank: other.current, staged: !other.kitKeys.isEmpty)
            records[id] = other
        }
        kitStaging = savedStaging
        textCache.removeAll()
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
        try bankBuildInputs(staging: kitStaging)
    }

    private func bankBuildInputs(
        staging: KitStaging, source: VoicegroupSource? = nil
    ) throws -> BankBuildInputs {
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
        if let source {
            let location = VoicegroupLocation(filePath: source.filePath, sectionLabel: source.sectionLabel)
            textCache.set(source.sourceBytes(), at: location)
        }
        for (location, source) in staging.subgroups {
            textCache.set(source.sourceBytes(), at: location)
        }
        var tables = keysplits
        if !staging.tables.isEmpty {
            let definitions = keysplits.tables.filter { staging.tables[$0.name] == nil } + Array(staging.tables.values)
            tables = KeysplitTables(tables: definitions)
        }
        return BankBuildInputs(
            layout: layout, soundMap: overlay, progMap: progMap, keysplits: tables,
            cache: cache, locator: locator,
            textProvider: { location, contiguousFill, noSubRecurse in
                try self.textCache.text(at: location, contiguousFill: contiguousFill, noSubRecurse: noSubRecurse)
            })
    }

    private func buildBank(source: VoicegroupSource, staging: KitStaging? = nil) throws -> Bank {
        do {
            let text = try source.descriptors()
            let staging = staging ?? kitStaging
            var inputs = try bankBuildInputs(staging: staging, source: source)
            for index in 0..<128 {
                guard let symbol = text.voices[index]?.symbol else { continue }
                let name = String(decoding: symbol, as: UTF8.self)
                guard let descriptor = mintedSynthDesc(symbol: name) else { continue }
                Self.overlaySynth(descriptor, symbol: name, into: &inputs.soundMap)
            }
            let location = VoicegroupLocation(filePath: source.filePath, sectionLabel: source.sectionLabel)
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

    private static func publish(
        id: VoicegroupId, source: VoicegroupSource, bank: Bank, staged: Bool = false
    ) -> LoadedBankView {
        var slots: [VoicegroupSlotView] = []
        slots.reserveCapacity(128)
        for slot in 0..<128 {
            slots.append(.init(kind: source.kindAt(slot: slot), voice: source.voiceAt(slot: slot)))
        }
        return LoadedBankView(
            id: id, bank: bank, loadName: source.loadName,
            dirty: source.dirty || staged, slotViews: slots)
    }
}
