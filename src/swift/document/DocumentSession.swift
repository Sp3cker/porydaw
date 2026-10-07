import Foundation
import PorydawVoicegroup
import PorydawCore
import PorydawProject

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
    public static let scale = SessionChangeDomains(rawValue: 1 << 7)
}

/// What the session publishes after reconciling a completed state change.
public struct SessionChange: Sendable {
    public var revision: UInt64
    public var trackRemap: TrackRemap?
    public var domains: SessionChangeDomains

    public init(
        revision: UInt64, trackRemap: TrackRemap? = nil,
        domains: SessionChangeDomains = [.document, .dirty, .history]
    ) {
        self.revision = revision
        self.trackRemap = trackRemap
        self.domains = domains
    }
}

public struct TrackTimeSelection: Equatable, Sendable {
    public let startTick: Tick
    public let endTick: Tick
    public let trackScope: Set<Int>
    public var active: Bool { endTick > startTick }

    public init(startTick: Tick = 0, endTick: Tick = 0, trackScope: Set<Int> = []) {
        self.startTick = startTick
        self.endTick = endTick
        self.trackScope = trackScope
    }
}

public struct SelectionTransition: Equatable, Sendable {
    public let previousTrackTime: TrackTimeSelection
    public let trackTime: TrackTimeSelection
}

/// Presentation repair the owning viewport performs inside the current
/// state-change batch, before any change publication fans out.
public enum ViewportRepair: Sendable {
    /// Drawer lane state follows an engine-track remap.
    case trackRemap(TrackRemap)
    /// Folded scale rows may be stale: the primary track or its notes changed.
    case scaleFold
    /// The camera time domain and the grid axis/clock follow the rebuilt timeline.
    case timeDomain
}

/// The song's MIDI file changed on disk since this session last loaded or
/// saved it. The caller prompts before overwriting; nothing was written.
public struct SaveConflictError: Error, Sendable {
    public let label: String
    public init(label: String) { self.label = label }
}

// MARK: - Document session

/// One document plus its confirmed bank history,
/// session-only selection/track-scope/mute-solo, the current bank
/// lease, and the published playback projection.
///
/// Initial open and edit/history projections share one retained timeline builder.
/// Document history stays immediate; bank transitions serialize on the service actor.
/// Selection and other session state never dirty the document and never enter
/// history.
@MainActor
public final class DocumentSession {
    public private(set) var document: SongDocument
    public private(set) lazy var projectionCache = DocumentProjectionCache(session: self)
    /// Current immutable projection from the session's retained builder.
    public internal(set) var timeline: PlaybackTimeline
    internal var timelineBuilder: PlaybackTimelineBuilder
    public var bankLease: ProjectBankLease { sharedBank.value.lease }
    public var bankSlots: [BankSlotView] { sharedBank.value.slots }
    public var bankDirty: Bool { sharedBank.value.dirty }
    public var bankLoadName: String { sharedBank.value.loadName }
    public private(set) var isClosed = false
    /// On-disk MIDI identity at the last load or save. Nil predates tracking
    /// (direct init); the first save then adopts the disk without prompting.
    public private(set) var lastKnownMidiBytes: [UInt8]?

    /// Selection order is authoritative; membership is its cached lookup index.
    /// Both are session-only and never dirty the document or enter history.
    public internal(set) var selectedNoteOrder: [NoteID] = []
    public internal(set) var selectedNotes: Set<NoteID> = []
    public internal(set) var selectedTracks: Set<Int> = []
    public internal(set) var timeSelection: AutomationTimeSelection?
    public enum TrackScopeAction: Sendable { case plain, toggle, range }
    internal var changingPrimaryInternally = false
    public var selectedTrack: Int? {
        didSet {
            guard selectedTrack != oldValue else { return }
            withStateChanges {
                selectedTracks = selectedTrack.map { [$0] } ?? []
                if !changingPrimaryInternally {
                    clearSelectedNotes()
                    clearTimeSelection()
                }
                onViewportRepair?(.scaleFold)
                publishChange([.selection])
            }
        }
    }
    public var editCursor: Tick = 0 {
        didSet {
            if editCursor != oldValue { publishChange([.cursor]) }
        }
    }
    public var gridClockTicks: Tick {
        TimelineSnapPolicy.clockTicks(
            division: document.ticksPerBeat,
            extendedClocks: document.state.config.extendedClocks)
    }
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
    /// Presentation repair hook, installed by the document's viewport. The
    /// session calls it at fixed points inside a state-change batch, so every
    /// change consumer reads an already-repaired viewport.
    public var onViewportRepair: ((ViewportRepair) -> Void)?

    public var onPlayback: ((PlaybackTimeline) -> Void)?
    internal var selectionTransitionObservers: [UUID: (SelectionTransition) -> Void] = [:]

    public func addSelectionTransitionObserver(_ observer: @escaping (SelectionTransition) -> Void) -> UUID {
        let token = UUID()
        selectionTransitionObservers[token] = observer
        return token
    }

    public func removeSelectionTransitionObserver(_ token: UUID) {
        selectionTransitionObservers.removeValue(forKey: token)
    }

    /// Borrowed from ApplicationSession, which owns the project service.
    internal unowned let service: ProjectService
    internal let inbox = BankResultInbox()
    internal var sharedBank: SharedBankState
    internal var pendingBankNotification = false
    /// A queued bank write owns the session's bank/history lifecycle, but not
    /// ordinary document mutation admission.
    public internal(set) var bankPersistenceInFlight = false
    /// Nested synchronous state changes accumulate one final publication.
    internal var stateChangeDepth = 0
    internal var pendingDomains: SessionChangeDomains = []
    internal var pendingTrackRemap: TrackRemap?
    internal var publishedTrackTime = TrackTimeSelection()

    public init(
        document: SongDocument, service: ProjectService,
        lease: ProjectBankLease, slots: [BankSlotView], dirty: Bool,
        loadName: String, sampleRate: Double = 48_000
    ) {
        self.document = document
        self.service = service
        sharedBank = service.bankViews.state(
            for: AppliedBankEdit(
                lease: lease, slots: slots, dirty: dirty, loadName: loadName,
                materializationToken: nil))
        var builder = PlaybackTimelineBuilder()
        timeline = builder.build(state: document.state, sampleRate: sampleRate)
        timelineBuilder = builder
        document.onChange = { [weak self] change in
            self?.handleDocumentChange(change)
        }
        sharedBank.attach(self)
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

    /// Publishes a viewport scale change through the session's change fan-out;
    /// the scale itself lives on the document's viewport.
    public func noteScaleChanged() {
        publishChange([.scale])
    }

    /// Composes a session from an already-opened song and its decoded MIDI,
    /// for the startup prefetch. The throwing open below funnels through this;
    /// decode failure still throws before anything is adopted.
    public static func open(
        loaded: LoadedSong, file: MidiFile, service: ProjectService,
        sampleRate: Double
    ) -> DocumentSession {
        let document = SongDocument(
            file: file, config: loaded.config,
            source: loaded.source, trackBudget: loaded.trackBudget)
        let session = DocumentSession(
            document: document, service: service, lease: loaded.bank,
            slots: loaded.bankSlots, dirty: loaded.bank.dirty,
            loadName: loaded.bank.loadName, sampleRate: sampleRate)
        session.lastKnownMidiBytes = loaded.midiBytes
        return session
    }

    /// Opens a song through the service, adopts it as the document (tempo
    /// metas stripped, authoritative tempo held by state), and composes the
    /// session. MIDI decode failure throws; nothing half-adopted is kept.
    public static func open(
        service: ProjectService, label: String,
        sampleRate: Double = 48_000
    ) async throws -> DocumentSession {
        let loaded = try await service.openSong(label: label)
        let midiBytes = loaded.midiBytes
        let file = try await Task { @concurrent in try MidiFile.decode(midiBytes) }.value
        return open(loaded: loaded, file: file, service: service, sampleRate: sampleRate)
    }

    /// Writes the song MIDI unless it changed on disk since the last load or
    /// save, in which case nothing is written and SaveConflictError throws so
    /// the caller can prompt. Bank-only voicegroup saves bypass this session.
    public func save(forceOverwrite: Bool = false) async throws {
        try requireOpen()
        guard !bankPersistenceInFlight, !document.history.bankTransitionInFlight else {
            throw ProjectServiceError.operationFailed("A bank transition is already in progress.")
        }
        guard document.isDirty || bankDirty else { return }
        let bank = bankDirty ? bankLease : nil
        if bank != nil { bankPersistenceInFlight = true }
        defer {
            if bank != nil {
                bankPersistenceInFlight = false
                flushPendingBankNotification()
            }
        }
        let snapshot = try document.captureSave()
        if !forceOverwrite { try checkMidiConflict(against: snapshot) }
        let receipt = try await service.save(snapshot, bank: bank)
        document.didSave(snapshot)
        lastKnownMidiBytes = snapshot.bytes
        var domains: SessionChangeDomains = [.dirty, .history]
        if let refreshed = receipt.bank {
            adoptBank(refreshed)
            domains.insert(.bank)
        }
        if domains.contains(.bank) { pendingBankNotification = false }
        publishChange(domains)
    }

    /// Compares the MIDI file against the last load or save. Readable bytes
    /// that differ prompt, unless the write would land identical bytes
    /// anyway. A path that exists but cannot be read is a save failure, not
    /// a conflict: it falls through so the bank stage still runs and the
    /// write stage reports the real error. Outright deletion is the one
    /// unreadable case that prompts — the write would succeed by recreating
    /// the file, so the external change would otherwise pass silently.
    private func checkMidiConflict(against snapshot: SaveSnapshot) throws {
        guard let known = lastKnownMidiBytes else { return }
        guard
            let current = try? Data(
                contentsOf: URL(
                    fileURLWithPath: document.source.midiPath))
        else {
            if !FileManager.default.fileExists(atPath: document.source.midiPath) {
                throw SaveConflictError(label: document.source.label)
            }
            return
        }
        if !current.elementsEqual(known) && !current.elementsEqual(snapshot.bytes) {
            throw SaveConflictError(label: document.source.label)
        }
    }

    /// Confirmed user bank edit: applies through the service, then records the
    /// replayable action. Conflicts throw and record nothing.
    @discardableResult
    public func applyBankEdit(
        slot: Int, value: BankVoice,
        expected: BankVoice?
    ) async throws -> AppliedBankEdit {
        try requireOpen()
        guard !bankPersistenceInFlight else {
            throw ProjectServiceError.operationFailed("A bank transition is already in progress.")
        }
        if !bankDirty { document.history.sealBankMerge() }
        guard let transition = document.history.beginBankTransition() else {
            throw ProjectServiceError.operationFailed("A bank transition is already in progress.")
        }
        publishChange([.history])
        var ownsTransition = true
        defer {
            if ownsTransition {
                document.history.endBankTransition(transition)
                publishChange([.history])
            }
            flushPendingBankNotification()
        }
        let result = try await service.bankApply(
            lease: bankLease, slot: slot,
            value: value, expected: expected,
            publishResult: false)
        let materializationToken = expected == nil ? result.materializationToken : nil
        withStateChanges {
            document.history.finishBankTransition(
                transition,
                recording: ServiceBankAction(
                    service: service, slot: slot, before: expected, after: value,
                    token: materializationToken,
                    materializedBlank: materializationToken != nil,
                    current: result, inbox: inbox))
            ownsTransition = false
            adoptBank(result)
            pendingBankNotification = false
            publishChange([.bank, .dirty, .history])
        }
        return result
    }

    /// Reserves a synth symbol in the project without changing this document.
    /// - Parameter descriptor: The desired waveform and pulse parameters.
    /// - Returns: The reusable assembler symbol.
    /// - Throws: A project failure when the required synth macros are absent.
    public func mintSynth(_ descriptor: VgSynthDesc) async throws -> String {
        try requireOpen()
        return try await service.mintSynth(descriptor)
    }

    /// Records the requested -G edit even when its bank cannot load; the
    /// previous bank remains bound until a replacement succeeds.
    public func selectVoicegroup(_ arg: String) async throws {
        try requireOpen()
        guard !arg.isEmpty, arg != document.state.config.voicegroupArgument,
            !bankPersistenceInFlight, !document.history.bankTransitionInFlight
        else { return }
        bankPersistenceInFlight = true
        defer {
            bankPersistenceInFlight = false
            flushPendingBankNotification()
        }
        withStateChanges {
            var config = document.state.config
            config.voicegroupArgument = arg
            document.setConfig(config)
            publishChange([.dirty, .history])
        }
        let bank = try await service.loadBank(voicegroupArg: arg)
        try requireOpen()
        withStateChanges {
            adoptBank(bank)
            pendingBankNotification = false
            publishChange([.bank, .dirty, .history])
        }
    }

    @discardableResult
    public func undo() async throws -> Bool {
        try await stepHistory(.undo)
    }

    @discardableResult
    public func redo() async throws -> Bool {
        try await stepHistory(.redo)
    }

    /// Crosses a -G history edit even if its replacement bank fails to load.
    /// The last valid lease remains bound while the requested cfg stays undoable.
    private func stepHistory(_ direction: BankHistoryDirection) async throws -> Bool {
        try requireOpen()
        guard !bankPersistenceInFlight else { return false }
        var preparedBank: AppliedBankEdit?
        var loadFailure: Error?
        if let arg = document.history.voicegroupArgumentAfter(direction) {
            guard let token = document.history.beginBankTransition() else { return false }
            bankPersistenceInFlight = true
            do {
                preparedBank = try await service.loadBank(voicegroupArg: arg)
                try requireOpen()
            } catch {
                loadFailure = error
            }
            document.history.endBankTransition(token)
        }
        bankPersistenceInFlight = true
        defer {
            bankPersistenceInFlight = false
            flushPendingBankNotification()
        }
        let previousArg = document.state.config.voicegroupArgument
        let changed: Bool
        switch direction {
        case .undo: changed = try await document.history.undo()
        case .redo: changed = try await document.history.redo()
        }
        withStateChanges {
            var domains: SessionChangeDomains = [.dirty, .history]
            if changed, let preparedBank,
                document.state.config.voicegroupArgument != previousArg
            {
                adoptBank(preparedBank)
                domains.insert(.bank)
            }
            if changed, let result = inbox.drain() {
                adoptBank(result)
                domains.insert(.bank)
            }
            if domains.contains(.bank) { pendingBankNotification = false }
            publishChange(domains)
        }
        if let loadFailure { throw loadFailure }
        return changed
    }

    /// Breaks document and presenter callbacks without stopping the project worker.
    /// ApplicationSession keeps the borrowed service alive across song replacement.
    /// Returns `false` while a bank transition or persistence write owns it.
    @discardableResult
    public func close() async -> Bool {
        guard !bankPersistenceInFlight, !document.history.bankTransitionInFlight else { return false }
        onChange = nil
        onViewportRepair = nil
        selectionTransitionObservers.removeAll()
        onPlayback = nil
        document.onChange = nil
        isClosed = true
        sharedBank.detach(self)
        return true
    }

}
