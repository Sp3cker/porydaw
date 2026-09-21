import Foundation
import PorydawCore

// MARK: - Public session types


/// What the session publishes after reconciling a document change.
public struct SessionChange: Sendable {
    public var revision: UInt64
    public var trackRemap: TrackRemap?

    public init(revision: UInt64, trackRemap: TrackRemap? = nil) {
        self.revision = revision
        self.trackRemap = trackRemap
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
    /// Current projection, always rebuilt via the state factory.
    public private(set) var timeline: PlaybackTimeline
    public private(set) var bankLease: NativeBankLease
    public private(set) var bankSlots: [BankSlotView]
    public private(set) var bankDirty: Bool
    public private(set) var bankLoadName: String
    public private(set) var isClosed = false

    /// Session-only state. Direct sets push no history and never dirty.
    public var selectedNotes: Set<NoteID> = []
    public var selectedTrack: Int?
    public var editCursor: Tick = 0
    public private(set) var camera: EditorCamera
    public var mutedTracks: Set<Int> = []
    public var soloedTracks: Set<Int> = []

    /// Presenter callback, invoked after selection reconciliation, timeline
    /// rebuild, and playback publication.
    public var onChange: ((SessionChange) -> Void)?
    /// Immutable playback publication for Task 7 to bind.
    public var onPlayback: ((PlaybackTimeline) -> Void)?
    /// Presentation-only camera publication. ApplicationSession is the sole subscriber.
    public var onCameraChange: ((EditorCamera.Snapshot) -> Void)?

    private let service: ProjectService
    private let inbox = BankResultInbox()
    private let sampleRate: Double
    private var previousBankVoices: [BankVoice?]
    /// A queued bank write owns the session's bank/history lifecycle, but not
    /// ordinary document mutation admission.
    private var bankPersistenceInFlight = false

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
        if let refreshed = receipt.bank {
            adoptBank(refreshed, remembersPrevious: false)
        }
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
        return result
    }

    @discardableResult
    public func undo() async throws -> Bool {
        try requireOpen()
        guard !bankPersistenceInFlight else { return false }
        let undone = try await document.history.undo()
        if undone, let result = inbox.drain() {
            adoptBank(result)
        }
        return undone
    }

    @discardableResult
    public func redo() async throws -> Bool {
        try requireOpen()
        guard !bankPersistenceInFlight else { return false }
        let redone = try await document.history.redo()
        if redone, let result = inbox.drain() {
            adoptBank(result)
        }
        return redone
    }

    /// Breaks presenter callbacks first, then releases the service worker
    /// after its outstanding work finishes. Owned leases outlive the session.
    /// Returns `false` while a bank transition or persistence write owns it.
    @discardableResult
    public func close() async -> Bool {
        guard !bankPersistenceInFlight, !document.history.bankTransitionInFlight else { return false }
        onChange = nil
        onPlayback = nil
        onCameraChange = nil
        document.onChange = nil
        await service.close()
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

    /// Coordinates selection reconciliation before presentation/playback: dead
    /// note references are pruned and the track scope follows the remap, then
    /// the timeline is rebuilt via the state factory, playback is published,
    /// and the presenter is notified.
    private func handleDocumentChange(_ change: DocumentChange) {
        selectedNotes = selectedNotes.filter { $0.isAssigned && document.note($0) != nil }
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
        onChange?(SessionChange(revision: change.revision, trackRemap: change.trackRemap))
    }
}
