import Foundation
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

    public init(revision: UInt64, trackRemap: TrackRemap? = nil,
                domains: SessionChangeDomains = [.document, .dirty, .history]) {
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

// MARK: - Document session

/// One document plus its confirmed bank history,
/// session-only selection/track-scope/camera/mute-solo, the current bank
/// lease, and the published playback projection.
///
/// Every timeline projection goes through the canonical state factory, for the
/// initial open and for every edit/history rebuild alike. Document history
/// operations stay immediate; bank transitions serialize on the service actor.
/// Selection and other session state never dirty the document and never enter
/// history.
@MainActor
public final class DocumentSession {
    public private(set) var document: SongDocument
    internal private(set) lazy var projectionCache = DocumentProjectionCache(session: self)
    /// Current projection, always rebuilt via the state factory.
    public private(set) var timeline: PlaybackTimeline
    public var bankLease: NativeBankLease { sharedBank.value.lease }
    public var bankSlots: [BankSlotView] { sharedBank.value.slots }
    public var bankDirty: Bool { sharedBank.value.dirty }
    public var bankLoadName: String { sharedBank.value.loadName }
    public private(set) var isClosed = false

    /// Selection order is authoritative; membership is its cached lookup index.
    /// Both are session-only and never dirty the document or enter history.
    public private(set) var selectedNoteOrder: [NoteID] = []
    public private(set) var selectedNotes: Set<NoteID> = []
    public private(set) var selectedTracks: Set<Int> = []
    public private(set) var timeSelection: AutomationTimeSelection?
    public enum TrackScopeAction { case plain, toggle, range }
    private var changingPrimaryInternally = false
    public var selectedTrack: Int? {
        didSet {
            guard selectedTrack != oldValue else { return }
            withStateChanges {
                selectedTracks = selectedTrack.map { [$0] } ?? []
                if !changingPrimaryInternally {
                    clearSelectedNotes()
                    clearTimeSelection()
                }
                if scaleProjection.fold { refreshScaleProjection() }
                publishChange([.selection])
            }
        }
    }
    public private(set) var scaleProjection = ScaleProjection()
    public var editCursor: Tick = 0 {
        didSet {
            if editCursor != oldValue { publishChange([.cursor]) }
        }
    }
    public private(set) var camera: EditorCamera
    var grid: RollGrid
    var gridClockTicks: Tick {
        TimelineSnapPolicy.clockTicks(division: document.ticksPerBeat,
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
    public var onPlayback: ((PlaybackTimeline) -> Void)?
    private var selectionTransitionObservers: [UUID: (SelectionTransition) -> Void] = [:]
    /// Presentation-only camera publication. The document workspace is the sole subscriber.
    public var onCameraChange: ((EditorCamera.Snapshot) -> Void)?
    /// Camera publication with the field-level delta used by the workspace
    /// to choose projection-only drawer updates.
    public var onCameraChangeDetailed: ((EditorCamera.Snapshot, EditorCamera.Change) -> Void)?

    public func addSelectionTransitionObserver(_ observer: @escaping (SelectionTransition) -> Void) -> UUID {
        let token = UUID()
        selectionTransitionObservers[token] = observer
        return token
    }

    public func removeSelectionTransitionObserver(_ token: UUID) {
        selectionTransitionObservers.removeValue(forKey: token)
    }

    /// Borrowed from ApplicationSession, which owns the project service.
    private unowned let service: ProjectService
    private let inbox = BankResultInbox()
    private let sampleRate: Double
    private var sharedBank: SharedBankState
    private var pendingBankNotification = false
    /// A queued bank write owns the session's bank/history lifecycle, but not
    /// ordinary document mutation admission.
    private var bankPersistenceInFlight = false
    /// Nested synchronous state changes accumulate one final publication.
    private var stateChangeDepth = 0
    private var pendingDomains: SessionChangeDomains = []
    private var pendingTrackRemap: TrackRemap?
    private var publishedTrackTime = TrackTimeSelection()

    public init(document: SongDocument, service: ProjectService,
                lease: NativeBankLease, slots: [BankSlotView], dirty: Bool,
                loadName: String, sampleRate: Double = 48_000) {
        self.document = document
        self.service = service
        sharedBank = service.bankViews.state(for: AppliedBankEdit(
            lease: lease, slots: slots, dirty: dirty, loadName: loadName,
            materializationToken: nil))
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
        grid = RollGrid(axis: TimeAxis(map: TimeMap(
            ticksPerBeat: UInt32(max(1, document.ticksPerBeat)),
            lengthTicks: timeline.lengthTicks,
            timeSigs: document.timeSignatures.map {
                TimeSigPoint(tick: $0.tick, numerator: $0.numerator,
                             denomPow2: $0.denominatorPower)
            })), clockTicks: TimelineSnapPolicy.clockTicks(
                division: document.ticksPerBeat,
                extendedClocks: document.state.config.extendedClocks))
        document.onChange = { [weak self] change in
            self?.handleDocumentChange(change)
        }
        sharedBank.attach(self)
    }

    public func setSelectedNotes(_ ids: [NoteID]) {
        var membership = Set<NoteID>()
        let order = ids.filter { $0.isAssigned && membership.insert($0).inserted }
        guard order != selectedNoteOrder || (!order.isEmpty && timeSelection?.isActive == true) else { return }
        withStateChanges {
            if !order.isEmpty { clearTimeSelection() }
            guard order != selectedNoteOrder else { return }
            selectedNoteOrder = order
            selectedNotes = membership
            publishChange([.selection])
        }
    }

    public func applyTimeSelection(_ selection: AutomationTimeSelection?) {
        var sanitized = selection?.isActive == true ? selection : nil
        var nextScope: Set<Int>?
        if var active = sanitized {
            switch active.scope {
            case .lanes:
                active.lanes = Set(active.lanes.filter {
                    guard let track = $0.track else { return false }
                    return (0..<16).contains(track)
                })
                sanitized = active.lanes.isEmpty && !active.tempo ? nil : active
            case let .tracks(scope):
                let stored = Set(scope.filter { (0..<16).contains($0) })
                    .union(selectedTrack.map { [$0] } ?? [])
                nextScope = Set(stored.filter { (0..<document.engineTracks.usedTrackCount).contains($0) })
                active.scope = .tracks(stored)
                sanitized = active
            }
        }
        guard timeSelection != sanitized || nextScope.map({ selectedTracks != $0 }) == true else { return }
        withStateChanges {
            if let nextScope, selectedTracks != nextScope {
                selectedTracks = nextScope
                publishChange([.selection])
            }
            timeSelection = sanitized
            if sanitized != nil { clearSelectedNotes() }
            publishChange([.selection])
        }
    }

    public func clearTimeSelection() { applyTimeSelection(nil) }

    public func timeSelectionCoversTrack(_ track: Int) -> Bool {
        guard (0..<document.engineTracks.usedTrackCount).contains(track),
              let selection = timeSelection, selection.isActive,
              case let .tracks(scope) = selection.scope else { return false }
        return scope.contains(track)
    }

    public func timeSelectionCoversTempo() -> Bool {
        let usedTracks = Set(0..<document.engineTracks.usedTrackCount)
        guard let selection = timeSelection, selection.isActive else { return false }
        if case let .tracks(scope) = selection.scope {
            return !usedTracks.isEmpty && scope.intersection(usedTracks) == usedTracks
        }
        return selection.tempo
    }

    private var trackTimeSelection: TrackTimeSelection {
        guard let selection = timeSelection, selection.isActive,
              case .tracks = selection.scope else { return TrackTimeSelection() }
        return TrackTimeSelection(startTick: selection.range.startTick,
                                  endTick: selection.range.endTick, trackScope: selectedTracks)
    }

    public func selectPrimaryTrack(_ track: Int) {
        guard (0..<document.engineTracks.usedTrackCount).contains(track),
              selectedTrack != track else { return }
        adjustTrackScope(track: track, action: .plain)
    }

    public func adjustTrackScope(track: Int, action: TrackScopeAction) {
        guard (0..<document.engineTracks.usedTrackCount).contains(track) else { return }
        var primary = selectedTrack ?? track
        var scope = selectedTracks
        var clearNotes = false
        var clearTime = false
        switch action {
        case .plain:
            clearTime = primary != track
            primary = track
            scope = [track]
            clearNotes = true
        case .toggle:
            if scope.contains(track) { scope.remove(track) }
            else { scope.insert(track) }
            guard !scope.isEmpty else { return }
            if !scope.contains(primary) {
                primary = scope.min()!
                clearNotes = true
            }
        case .range:
            scope = Set(min(primary, track)...max(primary, track))
        }
        withStateChanges {
            changingPrimaryInternally = true
            selectedTrack = primary
            changingPrimaryInternally = false
            if selectedTracks != scope {
                selectedTracks = scope
                publishChange([.selection])
            }
            if var selection = timeSelection, case .tracks = selection.scope,
               selection.scope != .tracks(scope) {
                selection.scope = .tracks(scope)
                timeSelection = selection
                publishChange([.selection])
            }
            if clearNotes { clearSelectedNotes() }
            if clearTime { clearTimeSelection() }
        }
    }

    public func addSelectedNote(_ id: NoteID) {
        guard id.isAssigned, !selectedNotes.contains(id) else { return }
        withStateChanges {
            clearTimeSelection()
            selectedNoteOrder.append(id)
            selectedNotes.insert(id)
            publishChange([.selection])
        }
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
        let newSnapshot = camera.snapshot
        let projectionChanged = camera.projection != oldProjection
        guard newSnapshot != oldSnapshot || projectionChanged else {
            return false
        }
        let change = EditorCamera.Change.between(
            oldSnapshot, newSnapshot, projectionChanged: projectionChanged)
        onCameraChange?(newSnapshot)
        onCameraChangeDetailed?(newSnapshot, change)
        return true
    }

    /// Changes one tab's display state without changing MIDI or song history.
    public func setScale(root: Int) {
        var next = scaleProjection
        next.setRoot(root)
        applyScale(next)
    }

    public func setScale(type: ScaleID) {
        var next = scaleProjection
        next.setScale(type)
        applyScale(next)
    }

    public func setScale(highlight: Bool) {
        var next = scaleProjection
        next.highlight = highlight
        applyScale(next)
    }

    public func setScale(fold: Bool) {
        var next = scaleProjection
        next.fold = fold
        applyScale(next)
    }

    private func applyScale(_ next: ScaleProjection) {
        guard next != scaleProjection else { return }
        let foldChanged = next.fold != scaleProjection.fold
        scaleProjection = next
        if foldChanged { refreshScaleProjection() }
        publishChange([.scale])
    }

    private func refreshScaleProjection() {
        let notes = selectedTrack.map { document.notes(in: $0) } ?? []
        let rows = scaleProjection.projection(notes: notes)
        guard rows != camera.projection else { return }
        let before = camera.snapshot
        let centeredPitch = camera.projection.pitch(
            atY: before.rollHeight / 2, keyHeight: before.keyHeight,
            scrollY: before.scrollY, dpr: 1)
        mutateCamera {
            $0.updateProjection(rows)
            if let centeredPitch, let nearest = rows.nearestVisiblePitch(to: centeredPitch) {
                _ = $0.setVScroll(
                    Double(rows.row(forPitch: nearest)) * before.keyHeight
                        - before.rollHeight / 2)
            }
        }
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

    public func save() async throws {
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
        let receipt = try await service.save(snapshot, bank: bank)
        document.didSave(snapshot)
        var domains: SessionChangeDomains = [.dirty, .history]
        if let refreshed = receipt.bank {
            adoptBank(refreshed)
            domains.insert(.bank)
        }
        if domains.contains(.bank) { pendingBankNotification = false }
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
        if !bankDirty { document.history.sealBankMerge() }
        guard let transition = document.history.beginBankTransition() else {
            throw ProjectServiceError.operationFailed("A bank transition is already in progress.")
        }
        var ownsTransition = true
        defer {
            if ownsTransition { document.history.endBankTransition(transition) }
            flushPendingBankNotification()
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
        pendingBankNotification = false
        publishChange([.bank, .dirty, .history])
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

    /// Retargets the song's -G argument only after its replacement bank loads.
    /// A failed load leaves the document, lease and history untouched.
    public func selectVoicegroup(_ arg: String) async throws {
        try requireOpen()
        guard !arg.isEmpty, arg != document.state.config.voicegroupArgument,
              !bankPersistenceInFlight, !document.history.bankTransitionInFlight else { return }
        bankPersistenceInFlight = true
        defer {
            bankPersistenceInFlight = false
            flushPendingBankNotification()
        }
        let previous = document.state.config.voicegroupArgument
        let bank = try await service.loadBank(voicegroupArg: arg)
        try requireOpen()
        guard document.state.config.voicegroupArgument == previous else {
            throw ProjectServiceError.operationFailed("Voicegroup changed during load.")
        }
        withStateChanges {
            var config = document.state.config
            config.voicegroupArgument = arg
            document.setConfig(config)
            guard document.state.config.voicegroupArgument == arg else { return }
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

    /// Rebind before crossing an undoable -G edit. An unavailable target
    /// cannot leave the history cursor on a config whose bank never loaded.
    private func stepHistory(_ direction: BankHistoryDirection) async throws -> Bool {
        try requireOpen()
        guard !bankPersistenceInFlight else { return false }
        var preparedBank: AppliedBankEdit?
        if let arg = document.history.voicegroupArgumentAfter(direction) {
            guard let token = document.history.beginBankTransition() else { return false }
            bankPersistenceInFlight = true
            do {
                preparedBank = try await service.loadBank(voicegroupArg: arg)
                try requireOpen()
            } catch {
                document.history.endBankTransition(token)
                bankPersistenceInFlight = false
                flushPendingBankNotification()
                throw error
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
               document.state.config.voicegroupArgument != previousArg {
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
        return changed
    }

    /// Breaks document and presenter callbacks without stopping the project worker.
    /// ApplicationSession keeps the borrowed service alive across song replacement.
    /// Returns `false` while a bank transition or persistence write owns it.
    @discardableResult
    public func close() async -> Bool {
        guard !bankPersistenceInFlight, !document.history.bankTransitionInFlight else { return false }
        onChange = nil
        selectionTransitionObservers.removeAll()
        onPlayback = nil
        onCameraChange = nil
        onCameraChangeDetailed = nil
        document.onChange = nil
        isClosed = true
        sharedBank.detach(self)
        return true
    }

    // MARK: - Internals

    private func requireOpen() throws {
        if isClosed {
            throw ProjectServiceError.serviceClosed
        }
    }

    private func adoptBank(_ result: AppliedBankEdit) {
        let next = service.bankViews.state(for: result)
        if next !== sharedBank {
            sharedBank.detach(self)
            sharedBank = next
            next.attach(self)
        }
        service.bankViews.publish(result)
    }

    internal func sharedBankDidChange(_ state: SharedBankState) {
        guard !isClosed, state === sharedBank else { return }
        if bankPersistenceInFlight || document.history.bankTransitionInFlight {
            pendingBankNotification = true
        } else {
            publishChange([.bank, .dirty])
        }
    }

    private func flushPendingBankNotification() {
        guard pendingBankNotification, !isClosed else { return }
        pendingBankNotification = false
        publishChange([.bank, .dirty])
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
        if domains.contains(.selection) { emitSelectionTransition() }
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
        if domains.contains(.selection) { emitSelectionTransition() }
        onChange?(SessionChange(revision: document.revision,
                                trackRemap: trackRemap,
                                domains: domains))
    }

    private func emitSelectionTransition() {
        let previous = publishedTrackTime
        let next = trackTimeSelection
        publishedTrackTime = next
        let transition = SelectionTransition(previousTrackTime: previous, trackTime: next)
        for observer in Array(selectionTransitionObservers.values) {
            observer(transition)
        }
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
            let priorScope = selectedTracks
            let priorPrimary = selectedTrack
            let priorNotes = selectedNoteOrder
            let priorTimeSelection = timeSelection
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
            if let remap = change.trackRemap {
                let mappedPrimary = priorPrimary.flatMap { track -> Int? in
                    guard remap.engineTrackMap.indices.contains(track) else { return nil }
                    return remap.engineTrackMap[track]
                }
                let primaryDeleted = priorPrimary != nil && mappedPrimary == nil
                let nextPrimary = mappedPrimary ?? priorPrimary.map {
                    min($0, max(0, document.engineTracks.usedTrackCount - 1))
                }
                changingPrimaryInternally = true
                selectedTrack = nextPrimary
                changingPrimaryInternally = false
                selectedTracks = Set(priorScope.compactMap { track in
                    remap.engineTrackMap.indices.contains(track)
                        ? remap.engineTrackMap[track] : nil
                })
                if let selectedTrack { selectedTracks.insert(selectedTrack) }
                if var selection = timeSelection {
                    switch selection.scope {
                    case let .tracks(stored):
                        if primaryDeleted {
                            timeSelection = nil
                        } else {
                            var mapped = Set(stored.compactMap { track -> Int? in
                                if remap.engineTrackMap.indices.contains(track) {
                                    return remap.engineTrackMap[track]
                                }
                                return (0..<16).contains(track) ? track : nil
                            })
                            if let selectedTrack { mapped.insert(selectedTrack) }
                            selection.scope = .tracks(mapped)
                            timeSelection = selection
                            selectedTracks = Set(mapped.filter {
                                (0..<document.engineTracks.usedTrackCount).contains($0)
                            })
                        }
                    case .lanes:
                        selection.lanes = Set(selection.lanes.compactMap { parameter -> AutomationParameter? in
                            guard let track = parameter.track,
                                  remap.engineTrackMap.indices.contains(track),
                                  let destination = remap.engineTrackMap[track] else { return nil }
                            if case let .controlChange(_, controller) = parameter {
                                return .controlChange(track: destination, controller: controller)
                            }
                            return .pitchBend(track: destination)
                        })
                        timeSelection = selection.lanes.isEmpty && !selection.tempo ? nil : selection
                    }
                }
            }
            if scaleProjection.fold { refreshScaleProjection() }
            timeline = PlaybackTimeline.build(state: document.state, sampleRate: sampleRate)
            camera.updateTimeDomain(
                ticksPerBeat: UInt32(max(1, document.ticksPerBeat)),
                lengthTicks: UInt64(timeline.lengthTicks))
            grid.axis = projectionCache.timeAxis
            grid.setTicksPerClock(gridClockTicks)
            onPlayback?(timeline)
            var domains: SessionChangeDomains = [.document, .dirty, .history]
            if selectedNoteOrder != priorNotes || selectedTrack != priorPrimary
                || selectedTracks != priorScope || timeSelection != priorTimeSelection {
                domains.insert(.selection)
            }
            publishChange(domains, trackRemap: change.trackRemap)
        }
    }
}
