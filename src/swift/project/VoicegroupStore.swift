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

// The source and its current native bank are canonical; published slot values are snapshots.
private struct BankRecord {
    let id: VoicegroupId
    let source: VoicegroupSource
    var current: BankHandle
    var sourceFileTime: Date
    var published: LoadedBankView
}

private struct BankMemo {
    let id: VoicegroupId
    var filePath: String
    var sourceFileTime: Date
}

// Tokens are single-use, scoped to the bank that produced the source delta.
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

    mutating func expire(id: VoicegroupId) {
        entries = entries.filter { $0.value.id != id }
    }

}

/// Worker-confined bank ownership. Call every method from the store's serial executor;
/// the loader's own context worker performs native calls outside the cooperative pool.
public final class VoicegroupStore {
    private let projectRoot: String
    private let context: ProjectContext
    private var records: [VoicegroupId: BankRecord] = [:]
    private var memos: [String: BankMemo] = [:]
    private var tokens = TokenRegistry()

    /// Opens a loader for a project before any bank is requested.
    /// - Parameter projectRoot: Root containing the project's sound files.
    /// - Throws: `VoicegroupStoreError` when the loader cannot open the project.
    public init(projectRoot: String) throws {
        guard let context = ProjectContext.open(projectRoot: projectRoot) else {
            throw VoicegroupStoreError.operationFailed("Could not initialize the project voicegroup loader.")
        }
        self.projectRoot = URL(filePath: projectRoot).standardizedFileURL.path
        self.context = context
    }
    /// Shares the store-owned loader instead of opening a second native project.
    /// - Parameters:
    ///   - projectRoot: Root containing the project's sound files.
    ///   - context: The store's already-opened loader context.
    init(projectRoot: String, context: ProjectContext) {
        self.projectRoot = URL(filePath: projectRoot).standardizedFileURL.path
        self.context = context
    }

    /// Resolves a song's voicegroup argument, reusing an unchanged canonical bank.
    /// - Parameter voicegroupArg: The song's `-G` argument; empty selects `_dummy`.
    /// - Returns: An immutable bank publication for the resolved source identity.
    /// - Throws: `VoicegroupStoreError` if the source or native bank cannot load.
    public func loadBank(voicegroupArg: String) throws -> LoadedBankView {
        let arg = voicegroupArg.isEmpty ? "_dummy" : voicegroupArg
        if let memo = memos[arg], let record = records[memo.id],
           record.source.filePath == memo.filePath,
           record.sourceFileTime == memo.sourceFileTime,
           modificationTime(memo.filePath) == memo.sourceFileTime {
            return record.published
        }

        let source = VoicegroupSource()
        var error: String?
        guard source.open(projectRoot: projectRoot, voicegroupArg: arg, error: &error) else {
            throw VoicegroupStoreError.operationFailed(error ?? "Could not open the voicegroup source.")
        }
        let path = URL(filePath: source.filePath).standardizedFileURL.path
        let prefix = projectRoot.hasSuffix("/") ? projectRoot : projectRoot + "/"
        guard path.hasPrefix(prefix),
              let id = VoicegroupId(sourceRelativePath: String(path.dropFirst(prefix.count)),
                                    sectionLabel: source.sectionLabel) else {
            throw VoicegroupStoreError.operationFailed("Could not identify the voicegroup source.")
        }
        guard let time = modificationTime(path) else {
            throw VoicegroupStoreError.operationFailed("Cannot read \(path)")
        }
        if let record = records[id], record.sourceFileTime == time {
            memos[arg] = BankMemo(id: id, filePath: path, sourceFileTime: time)
            return record.published
        }
        guard let bank = context.load(target: .init(filePath: path, sectionLabel: source.sectionLabel)) else {
            throw VoicegroupStoreError.operationFailed("Could not load voicegroup source \(path).")
        }
        bank.graftMintedSynths(source: source)
        let view = Self.publish(id: id, source: source, bank: bank)
        tokens.expire(id: id)
        records[id] = BankRecord(id: id, source: source, current: bank,
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
                      source.setVoice(slot: edit.slot, voice: edit.value) else {
                    return .conflict(.init(voicegroup: input.id))
                }
            } else {
                guard source.voiceAt(slot: edit.slot) == nil,
                      let added = source.materializeBlankSlot(slot: edit.slot, voice: edit.value) else {
                    return .conflict(.init(voicegroup: input.id))
                }
                materialization = added
            }
        case .revert(let revert):
            guard source.revertBlankSlotMaterialization(revert.materialization) else {
                return .conflict(.init(voicegroup: input.id))
            }
        }

        guard let bank = source.loadPreviewedSource(using: context) else {
            let restored = source.restoreSourceBytes(before)
            precondition(restored, "Previously parsed voicegroup bytes must restore")
            throw VoicegroupStoreError.operationFailed("Edited voicegroup failed to load.")
        }
        record.current = bank
        record.published = Self.publish(id: record.id, source: source, bank: bank)
        records[input.id] = record
        let token = materialization.map { tokens.mint(id: input.id, materialization: $0) }
        return .applied(.init(view: record.published, materialization: materialization,
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
        return try applyVoicegroupEdit(input: .init(id: id, operation: .revert(.init(materialization: entry.materialization))))
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
        } catch {
            throw VoicegroupStoreError.operationFailed("Cannot write \(record.source.filePath)")
        }
        // Nil is reserved for the supersede race (another edit landed between the
        // save snapshot and didSave); write failures throw above instead.
        guard saved else { return nil }
        guard let bank = context.load(target: .init(filePath: record.source.filePath,
                                                    sectionLabel: record.source.sectionLabel)) else {
            throw VoicegroupStoreError.operationFailed("Saved voicegroup failed to reload.")
        }
        bank.graftMintedSynths(source: record.source)
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

    /// Auditions the current source via a staged `loadName.inc` shadow file.
    /// - Parameter id: Identity of a loaded bank.
    /// - Returns: A self-contained preview bank, or nil when loading fails.
    public func preview(id: VoicegroupId) -> BankHandle? {
        records[id]?.source.loadPreviewedSource(using: context)
    }

    /// Returns the record's current detached publication without loading.
    /// - Parameter id: Identity of a loaded bank.
    /// - Returns: The published view, or nil when the bank is not loaded.
    func currentPublication(id: VoicegroupId) -> LoadedBankView? {
        records[id]?.published
    }

    private func refreshIfStale(id: VoicegroupId) throws -> Bool {
        guard let record = records[id] else {
            throw VoicegroupStoreError.operationFailed("Voicegroup is not loaded: \(id.sourceRelativePath)")
        }
        let path = record.source.filePath
        let time = modificationTime(path)
        let memo = memos[record.source.voicegroupArg]
        guard time != record.sourceFileTime || memo?.id != id ||
              memo?.filePath != path || memo?.sourceFileTime != time else { return true }
        let reloaded = try loadBank(voicegroupArg: record.source.voicegroupArg)
        return reloaded.id == id
    }

    private func modificationTime(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    private static func publish(id: VoicegroupId, source: VoicegroupSource, bank: BankHandle) -> LoadedBankView {
        var slots: [VoicegroupSlotView] = []
        slots.reserveCapacity(128)
        for slot in 0..<128 {
            slots.append(.init(kind: source.kindAt(slot: slot), voice: source.voiceAt(slot: slot)))
        }
        return LoadedBankView(id: id, bank: bank, loadName: source.loadName,
                              dirty: source.dirty, slotViews: slots)
    }
}
