import Foundation
import PorydawCore

// MARK: - Public session types


/// The session state affected by a completed operation.
public struct SessionChangeDomains: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let document = SessionChangeDomains(rawValue: 1 << 0)
    public static let selection = SessionChangeDomains(rawValue: 1 << 1)
    public static let dirty = SessionChangeDomains(rawValue: 1 << 2)
    public static let history = SessionChangeDomains(rawValue: 1 << 3)
    public static let bank = SessionChangeDomains(rawValue: 1 << 4)
    public static let cursor = SessionChangeDomains(rawValue: 1 << 5)
    public static let mixState = SessionChangeDomains(rawValue: 1 << 6)
}

/// What the session publishes after reconciling a completed state change.
public struct SessionChange: Sendable {
    public var revision: UInt64
    public var trackRemap: TrackRemap?
    public var domains: SessionChangeDomains

    public init(revision: UInt64, trackRemap: TrackRemap? = nil,
                domains: SessionChangeDomains = [.document, .dirty, .history]) {
        self.revision = revision
        self.trackRemap = trackRemap
        self.domains = domains
    }
}

// MARK: - Document session

/// Task 8's ownership interface: one document plus its confirmed bank history,
/// session-only selection/track-scope/camera/mute-solo, the current bank
/// lease, and the published playback projection.
///
/// Every timeline projection goes through the canonical state factory, for the
/// initial open and for every edit/history rebuild alike. Document history
/// operations stay immediate; bank transitions serialize on the service actor.
/// Selection and other session state never dirty the document and never enter
/// history. Playback is published as an immutable value for Task 7 to bind;
/// the old AudioEngine timeline API is not referenced here.
@MainActor
public final class DocumentSession {
    public private(set) var document: SongDocument
    internal private(set) lazy var projectionCache = DocumentProjectionCache(session: self)
    /// Current projection, always rebuilt via the state factory.
    public private(set) var timeline: PlaybackTimeline
    public private(set) var bankLease: NativeBankLease
    public private(set) var bankSlots: [BankSlotView]
    public private(set) var bankDirty: Bool
    public private(set) var bankLoadName: String
    public private(set) var isClosed = false

    /// Selection order is authoritative; membership is its cached lookup index.
    /// Both are session-only and never dirty the document or enter history.
    public private(set) var selectedNoteOrder: [NoteID] = []
    public private(set) var selectedNotes: Set<NoteID> = []
    public var selectedTrack: Int? {
        didSet {
            if selectedTrack != oldValue { publishChange([.selection]) }
        }
    }
    public var editCursor: Tick = 0 {
        didSet {
            if editCursor != oldValue { publishChange([.cursor]) }
        }
    }
    public private(set) var camera: EditorCamera
    public var mutedTracks: Set<Int> = [] {
        didSet {
            if mutedTracks != oldValue { publishChange([.mixState]) }
        }
    }
    public var soloedTracks: Set<Int> = [] {
        didSet {
            if soloedTracks != oldValue { publishChange([.mixState]) }
        }
    }

    /// Session-state callback. Document changes invoke it after selection
    /// reconciliation, timeline rebuild, and playback publication.
    public var onChange: ((SessionChange) -> Void)?
    /// Immutable playback publication for Task 7 to bind.
    public var onPlayback: ((PlaybackTimeline) -> Void)?
    /// Presentation-only camera publication. The document workspace is the sole subscriber.
    public var onCameraChange: ((EditorCamera.Snapshot) -> Void)?

    /// Borrowed from ApplicationSession, which owns the project service.
    private unowned let service: ProjectService
    private let inbox = BankResultInbox()
    private let sampleRate: Double
    private var previousBankVoices: [BankVoice?]
    /// A queued bank write owns the session's bank/history lifecycle, but not
    /// ordinary document mutation admission.
    private var bankPersistenceInFlight = false
    /// Nested synchronous state changes accumulate one final publication.
    private var stateChangeDepth = 0
    private var pendingDomains: SessionChangeDomains = []
    private var pendingTrackRemap: TrackRemap?

    public init(document: SongDocument, service: ProjectService,
                lease: NativeBankLease, slots: [BankSlotView], dirty: Bool,
                loadName: String, sampleRate: Double = 48_000) {
        self.document = document
        self.service = service
        self.bankLease = lease
        self.bankSlots = slots
        self.bankDirty = dirty
        self.bankLoadName = loadName
        self.previousBankVoices = slots.map(\.voice)
        self.sampleRate = sampleRate
        let timeline = PlaybackTimeline.build(state: document.state, sampleRate: sampleRate)
        self.timeline = timeline
        let limits = GridCameraPolicy.limits(baseFontPx: GridCameraPolicy.seedBaseFontPx)
        self.camera = EditorCamera(
            ticksPerBeat: UInt32(max(1, document.ticksPerBeat)),
            lengthTicks: UInt64(timeline.lengthTicks),
            viewportWidth: 0,
            rollHeight: 0,
            limits: limits)
        document.onChange = { [weak self] change in
            self?.handleDocumentChange(change)
        }
    }

    public func setSelectedNotes(_ ids: [NoteID]) {
        var membership = Set<NoteID>()
        let order = ids.filter { $0.isAssigned && membership.insert($0).inserted }
        guard order != selectedNoteOrder else { return }
        selectedNoteOrder = order
        selectedNotes = membership
        publishChange([.selection])
    }

    public func addSelectedNote(_ id: NoteID) {
        guard id.isAssigned, !selectedNotes.contains(id) else { return }
        selectedNoteOrder.append(id)
        selectedNotes.insert(id)
        publishChange([.selection])
    }

    public func removeSelectedNote(_ id: NoteID) {
        guard selectedNotes.contains(id) else { return }
        selectedNoteOrder.removeAll { $0 == id }
        selectedNotes.remove(id)
        publishChange([.selection])
    }

    public func removeSelectedNotes(_ ids: Set<NoteID>) {
        guard !selectedNotes.isDisjoint(with: ids) else { return }
        selectedNoteOrder.removeAll { ids.contains($0) }
        selectedNotes.subtract(ids)
        publishChange([.selection])
    }

    public func clearSelectedNotes() {
        guard !selectedNoteOrder.isEmpty else { return }
        selectedNoteOrder.removeAll()
        selectedNotes.removeAll()
        publishChange([.selection])
    }

    /// Coalesces synchronous session mutations into one publication. Nested
    /// calls join the outer batch; mutations are not rolled back when `body`
    /// throws, so the completed state is published before the error propagates.
    @discardableResult
    public func withStateChanges<Result>(_ body: () throws -> Result) rethrows -> Result {
        stateChangeDepth += 1
        defer {
            stateChangeDepth -= 1
            if stateChangeDepth == 0 { flushStateChanges() }
        }
        return try body()
    }

    /// Applies one presentation-only camera mutation and publishes exactly once
    /// when either the numeric snapshot or pitch projection changes.
    @discardableResult
    public func mutateCamera(_ body: (inout EditorCamera) -> Void) -> Bool {
        let oldSnapshot = camera.snapshot
        let oldProjection = camera.projection
        body(&camera)
        guard camera.snapshot != oldSnapshot || camera.projection != oldProjection else {
            return false
        }
        onCameraChange?(camera.snapshot)
        return true
    }

    /// Opens a song through the service, adopts it as the document (tempo
    /// metas stripped, authoritative tempo held by state), and composes the
    /// session. MIDI decode failure throws; nothing half-adopted is kept.
    public static func open(service: ProjectService, label: String,
                            sampleRate: Double = 48_000) async throws -> DocumentSession {
        let loaded = try await service.openSong(label: label)
        let file = try MidiFile.decode(loaded.midiBytes)
        let document = SongDocument(file: file, config: loaded.config,
                                    source: loaded.source, trackBudget: loaded.trackBudget)
        return DocumentSession(document: document, service: service, lease: loaded.bank,
                               slots: loaded.bankSlots, dirty: loaded.bankDirty,
                               loadName: loaded.bankLoadName, sampleRate: sampleRate)
    }

    /// Ordered save (bank stage when the bank is dirty, then MIDI, then
    /// flags). A clean session performs no work and emits no receipt. Failures
    /// throw and never mark clean.
    public func save() async throws {
        try requireOpen()
        guard !bankPersistenceInFlight, !document.history.bankTransitionInFlight else {
            throw ProjectServiceError.operationFailed("A bank transition is already in progress.")
        }
        guard document.isDirty || bankDirty else { return }
        let bank = bankDirty ? bankLease : nil
        if bank != nil { bankPersistenceInFlight = true }
        defer {
            if bank != nil { bankPersistenceInFlight = false }
        }
        let snapshot = try document.captureSave()
        let receipt = try await service.save(snapshot, bank: bank)
        document.didSave(snapshot)
        var domains: SessionChangeDomains = [.dirty, .history]
        if let refreshed = receipt.bank {
            adoptBank(refreshed, remembersPrevious: false)
            domains.insert(.bank)
        }
        publishChange(domains)
    }

    /// Confirmed user bank edit: applies through the service, then records the
    /// replayable action. Conflicts throw and record nothing.
    @discardableResult
    public func applyBankEdit(slot: Int, value: BankVoice,
                              expected: BankVoice?) async throws -> AppliedBankEdit {
        try requireOpen()
        guard !bankPersistenceInFlight else {
            throw ProjectServiceError.operationFailed("A bank transition is already in progress.")
        }
        if bankSlots.indices.contains(slot),
           bankSlots[slot].voice != expected,
           previousBankVoices.indices.contains(slot),
           previousBankVoices[slot] == expected {
            throw ProjectServiceError.operationFailed(
                "A bank transition is already in progress.")
        }
        guard let transition = document.history.beginBankTransition() else {
            throw ProjectServiceError.operationFailed("A bank transition is already in progress.")
        }
        var ownsTransition = true
        defer {
            if ownsTransition { document.history.endBankTransition(transition) }
        }
        let result = try await service.bankApply(lease: bankLease, slot: slot,
                                                 value: value, expected: expected)
        adoptBank(result)
        let materializationToken = expected == nil ? result.materializationToken : nil
        document.history.finishBankTransition(transition, recording: ServiceBankAction(
            service: service, slot: slot, before: expected, after: value,
            token: materializationToken,
            materializedBlank: materializationToken != nil,
            current: result, inbox: inbox))
        ownsTransition = false
        publishChange([.bank, .dirty, .history])
        return result
    }

    @discardableResult
    public func undo() async throws -> Bool {
        try requireOpen()
        guard !bankPersistenceInFlight else { return false }
        let undone = try await document.history.undo()
        var domains: SessionChangeDomains = [.dirty, .history]
        if undone, let result = inbox.drain() {
            adoptBank(result)
            domains.insert(.bank)
        }
        publishChange(domains)
        return undone
    }

    @discardableResult
    public func redo() async throws -> Bool {
        try requireOpen()
        guard !bankPersistenceInFlight else { return false }
        let redone = try await document.history.redo()
        var domains: SessionChangeDomains = [.dirty, .history]
        if redone, let result = inbox.drain() {
            adoptBank(result)
            domains.insert(.bank)
        }
        publishChange(domains)
        return redone
    }

    /// Breaks document and presenter callbacks without stopping the project worker.
    /// ApplicationSession keeps the borrowed service alive across song replacement.
    /// Returns `false` while a bank transition or persistence write owns it.
    @discardableResult
    public func close() async -> Bool {
        guard !bankPersistenceInFlight, !document.history.bankTransitionInFlight else { return false }
        onChange = nil
        onPlayback = nil
        onCameraChange = nil
        document.onChange = nil
        isClosed = true
        return true
    }

    // MARK: - Internals

    private func requireOpen() throws {
        if isClosed {
            throw ProjectServiceError.serviceClosed
        }
    }

    private func adoptBank(_ result: AppliedBankEdit, remembersPrevious: Bool = true) {
        if remembersPrevious {
            previousBankVoices = bankSlots.map(\.voice)
        }
        bankLease = result.lease
        bankSlots = result.slots
        bankDirty = result.dirty
        bankLoadName = result.loadName
    }

    private func publishChange(_ domains: SessionChangeDomains,
                               trackRemap: TrackRemap? = nil) {
        guard !domains.isEmpty else { return }
        if stateChangeDepth > 0 {
            pendingDomains.formUnion(domains)
            if let trackRemap {
                pendingTrackRemap = pendingTrackRemap.map {
                    composeTrackRemaps($0, followedBy: trackRemap)
                } ?? trackRemap
            }
            return
        }
        onChange?(SessionChange(revision: document.revision,
                                trackRemap: trackRemap,
                                domains: domains))
    }

    private func flushStateChanges() {
        guard !pendingDomains.isEmpty else { return }
        let domains = pendingDomains
        let trackRemap = pendingTrackRemap
        pendingDomains = []
        pendingTrackRemap = nil
        onChange?(SessionChange(revision: document.revision,
                                trackRemap: trackRemap,
                                domains: domains))
    }

    /// A batch may contain successive structural document mutations. Compose
    /// their old-to-new mappings instead of publishing an ambiguous last remap.
    private func composeTrackRemaps(_ first: TrackRemap,
                                    followedBy second: TrackRemap) -> TrackRemap {
        let chunks = first.chunkMap.map { intermediate -> Int? in
            guard let intermediate, second.chunkMap.indices.contains(intermediate) else {
                return nil
            }
            return second.chunkMap[intermediate]
        }
        let tracks = first.engineTrackMap.map { intermediate -> Int? in
            guard let intermediate,
                  second.engineTrackMap.indices.contains(intermediate) else {
                return nil
            }
            return second.engineTrackMap[intermediate]
        }
        return TrackRemap(chunkMap: chunks, engineTrackMap: tracks,
                          newChunkCount: second.newChunkCount,
                          newEngineTrackCount: second.newEngineTrackCount)
    }

    /// Coordinates selection reconciliation before presentation/playback: dead
    /// note references are pruned and the track scope follows the remap, then
    /// the timeline is rebuilt via the state factory, playback is published,
    /// and the presenter is notified.
    private func handleDocumentChange(_ change: DocumentChange) {
        withStateChanges {
            let survivingSelection = selectedNoteOrder.filter { document.note($0) != nil }
            if survivingSelection.count != selectedNoteOrder.count {
                selectedNoteOrder = survivingSelection
                selectedNotes = Set(survivingSelection)
                publishChange([.selection])
            }
            if let remap = change.trackRemap {
                // Session playback masks follow engine-track identity through edits
                // and the inverse remaps history publishes on undo.
                mutedTracks = Set(mutedTracks.compactMap { track in
                    remap.engineTrackMap.indices.contains(track)
                        ? remap.engineTrackMap[track] : nil
                })
                soloedTracks = Set(soloedTracks.compactMap { track in
                    remap.engineTrackMap.indices.contains(track)
                        ? remap.engineTrackMap[track] : nil
                })
            }
            if let remap = change.trackRemap, let track = selectedTrack {
                if track < remap.engineTrackMap.count, let mapped = remap.engineTrackMap[track] {
                    selectedTrack = mapped
                } else {
                    selectedTrack = nil
                }
            }
            if let track = selectedTrack,
               !(0..<document.engineTracks.usedTrackCount).contains(track) {
                selectedTrack = nil
            }
            timeline = PlaybackTimeline.build(state: document.state, sampleRate: sampleRate)
            camera.updateTimeDomain(
                ticksPerBeat: UInt32(max(1, document.ticksPerBeat)),
                lengthTicks: UInt64(timeline.lengthTicks))
            onPlayback?(timeline)
            publishChange([.document, .selection, .dirty, .history],
                          trackRemap: change.trackRemap)
        }
    }
}
