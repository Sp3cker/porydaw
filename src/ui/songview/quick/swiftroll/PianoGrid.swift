import Foundation
import QtBridge
import SwiftGridKeyFeed
import SwiftGridRollBand
@MainActor
final class GridNote {
    // Local scene identity is the 1-based document row; `token` is the
    // document-scoped NoteId delivered by the sgd_ feed.
    let noteId: Int
    let token: UInt64
    var tick: Int
    var duration: Int
    var pitch: Int
    let track: Int
    let velocity: Int
    let ghost: Bool

    init(
        noteId: Int, tick: Int, duration: Int, pitch: Int,
        track: Int, velocity: Int, ghost: Bool, token: UInt64 = 0
    ) {
        self.noteId = noteId
        self.token = token
        self.tick = tick
        self.duration = duration
        self.pitch = pitch
        self.track = track
        self.velocity = velocity
        self.ghost = ghost
    }
}

// Input-jurisdiction vocabulary for the grid surface. Mirrors
// songview::TimelineInputCancelReason declaration order (FocusLost,
// PointerUngrabbed, Hidden, WindowDeactivated); QML entries pass the raw
// value, Swift rehydrates with GridCancelReason(rawValue:) and treats
// unknown codes as no-ops.
public enum GridCancelReason: Int {
    case focusLost = 0
    case pointerUngrabbed = 1
    case hidden = 2
    case windowDeactivated = 3
}

// Qt::MouseButton / Qt::KeyboardModifier raw values carried by sgb_ facts.
// The C enum cases are not importable (rawValue only), so the band path
// compares against these mirrors — the same convention SgcCommands.swift
// uses for the C SgcIntent/SgcResult enums.
private enum QtFact {
    static let leftButton: Int32 = 0x0000_0001
    static let rightButton: Int32 = 0x0000_0002
    static let shiftModifier: Int32 = 0x0200_0000
    static let controlModifier: Int32 = 0x0400_0000
}

@MainActor
@QtBridgeable
public final class PianoGrid: QmlInstantiableStatus {

    @QtIgnored
    private(set) var notes: [GridNote] = []
    @QtTracked public var scene: GridScene = GridScene()
    @QtTracked public var palette: GridPalette = GridPalette()

    public var readOnly: Bool = false {
        willSet {
            if newValue {
                gesture = nil
                activeNoteId = -1
            }
        }
    }
    public var documentToken: String = "" {
        willSet {
            if let documentFeed {
                precondition(newValue == String(documentFeed.documentId), "Document binding is immutable")
            }
        }
    }
    public var documentTrack: Int = -1 {
        willSet {
            if newValue != documentTrack, let document = documentFeed?.document {
                loadDocument(document, trackIndex: newValue)
            }
        }
    }
    public var renderedNoteCount: Int = 0
    public var appliedRevisionText: String = ""
    @QtIgnored private var documentFeed: DocumentFeed?
    // Writable-seam bindings (spec §1–3): the intent pipe minted with the
    // document binding, the sgs_ session receiver, and the sgb_ band-surface
    // binding. commandPipe != nil is the single "editing" gate for intent
    // submission.
    @QtIgnored private var commandPipe: SgcCommandPipe?
    // True once bindDocument completed and commandPipe exists. The overlay
    // gates bindEditing on this so changed-handlers firing before the
    // document bind cannot trap.
    public var documentBound: Bool = false
    @QtIgnored private var sessionFeed: SessionFeed?
    @QtIgnored private var bandTargetId: UInt64 = 0
    // Gutter audition state for band-driven input (production m_kbdKey): the
    // sounding key, -1 when idle. Selection on gutter press is a session
    // intent; the audition itself is host-side and out of seam scope.
    @QtIgnored private var bandGutterKey: Int = -1
    @QtIgnored private var appliedDocumentRevision: UInt64?
    @QtIgnored private var documentEndTick: Int = 0

    // Published geometry snapshot for QML and the smoke harness. `metrics`
    // below is the single authority; these are write-once-per-configure
    // outputs assigned only in publishGeometry() and never read by Swift
    // interaction or projection logic.
    public var baseFontPx: Double = 13
    public var devicePixelRatio: Double = 1
    public var beatWidth: Double = 35
    public var rowHeight: Double = 13
    public var gridWidth: Double = 0
    public var gridHeight: Double = 0
    public var leadPadWidth: Double = 48
    public var keyboardWidth: Double = 56
    public var rulerHeight: Double = 0
    public var initialScrollY: Double = 0

    public var highestPitch: Int = 127
    public var lowestPitch: Int = 0
    public var ticksPerBeat: Int = GridMetrics.ticksPerBeat
    public var snapTicks: Int = 6
    public var visibleGridTicks: Int = 12
    public var beatCount: Int = 16
    public var editCursorTick: Int = 0

    public var activeNoteId: Int = -1

    public var cursorKind: Int = 0
    public var statusText: String = ""
    public var noteSummary: String = "[]"

    private var measurementFonts: [GridFontKind: GridFontSpec] = [:]

    @QtIgnored
    private var typography: GridTypography?

    // Sole geometry authority for all Swift-side computation.
    var metrics = GridMetrics(baseFontPx: 13, dpr: 1, width: 0, height: 0)

    private var gesture: GridGesture?
    private var selection: Set<Int> = []
    var lastVelocity: Int = 100
    var hoverKey: Int = -1
    @QtIgnored
    var viewportScrollY: Double = 0
    @QtIgnored private var viewportScrollX: Double = 0
    private var noteSummaryDirty = true
    private var selectionAtRightPress: Set<Int> = []
    // Host-named cancel delivery. -1 = none this session. Written only by
    // inputCancelled. Raw values match GridCancelReason /
    // TimelineInputCancelReason.
    public var lastCancelReason: Int = -1

    var drawPreview: (tick: Int, duration: Int, pitch: Int)? {
        guard case .draw(let state) = gesture else { return nil }
        return (state.tick, state.duration, state.key)
    }

    private var selectionBand: (x: Double, y: Double, w: Double, h: Double)? {
        guard case .band(let state) = gesture else { return nil }
        let x0 = min(state.pressX, state.curX)
        let x1 = max(state.pressX, state.curX)
        let y0 = min(state.pressY, state.curY)
        let y1 = max(state.pressY, state.curY)
        return (x0, y0, x1 - x0, y1 - y0)
    }

    public init() {}

    public func componentComplete() {
        bindDocument(documentToken: documentToken)
    }

    public func bindDocument(documentToken: String) {
        precondition(documentFeed == nil, "Document binding is immutable")
        guard let token = UInt64(documentToken), token != 0,
            String(token) == documentToken
        else {
            preconditionFailure("A canonical nonzero document token is required")
        }
        let feed = DocumentFeed(documentId: token)
        self.documentToken = documentToken
        bindDocumentFeed(feed, trackIndex: documentTrack)
        precondition(feed.connect(), "The document endpoint is absent or already bound")
    }

    @QtIgnored
    func bindDocumentFeed(_ feed: DocumentFeed, trackIndex: Int) {
        precondition(documentFeed == nil && feed.document == nil, "Bind before initial delivery")
        documentToken = String(feed.documentId)
        documentFeed = feed
        commandPipe = SgcCommandPipe(documentId: feed.documentId)
        documentBound = true
        documentTrack = trackIndex
        feed.onDocument = { [weak self] document in
            guard let self else { return }
            self.loadDocument(document, trackIndex: self.documentTrack)
        }
    }

    @QtIgnored
    func setDocumentTrack(_ trackIndex: Int) {
        documentTrack = trackIndex
    }

    // Binds the writable seams for this document-bound grid: the sgs_
    // session receiver (authoritative selection state), the sgk_ key
    // recipient (host-arbitrated command ids), and the sgb_ band surface
    // (pointer facts from SwiftRollBand). All ids are canonical decimal
    // tokens like documentToken; the band target must already be registered
    // by its SwiftRollBand. Idempotent per grid: a second bind is a
    // programming error, like bindDocument.
    public func bindEditing(bandTarget: String, sessionToken: String) {
        // Order-safe: QML changed-handlers may call before bindDocument.
        guard commandPipe != nil else { return }
        precondition(sessionFeed == nil && bandTargetId == 0, "Editing binding is immutable")
        guard let target = UInt64(bandTarget), target != 0,
            String(target) == bandTarget,
            let sessionId = UInt64(sessionToken), sessionId != 0,
            String(sessionId) == sessionToken
        else {
            preconditionFailure("Canonical nonzero band/session tokens are required")
        }
        let feed = SessionFeed(sessionId: sessionId)
        feed.onSession = { [weak self] session in
            guard let self else { return }
            self.applySession(session)
        }
        precondition(feed.connect(), "The session endpoint is absent or already bound")
        sessionFeed = feed
        precondition(
            sgk_set_delivery(
                target,
                { facts, context in
                    guard let facts, let context else { return 0 }
                    return MainActor.assumeIsolated {
                        let grid: PianoGrid = Unmanaged.fromOpaque(context).takeUnretainedValue()
                        return grid.bandKeyAnswer(
                            command: facts.pointee.command, origin: facts.pointee.origin,
                            autoRepeat: facts.pointee.autoRepeat != 0,
                            commandAvailable: facts.pointee.commandAvailable != 0) ? 1 : 0
                    }
                }, Unmanaged.passUnretained(self).toOpaque()),
            "The key endpoint is absent or already bound")
        var surface = SgbSurface(
            pointer: { kind, event, context in
                guard let event, let context else { return 0 }
                let facts = event.pointee
                return MainActor.assumeIsolated {
                    let grid: PianoGrid = Unmanaged.fromOpaque(context).takeUnretainedValue()
                    return grid.bandPointer(
                        kind: kind, tick: facts.tick, key: facts.key, button: facts.button,
                        buttons: facts.buttons, modifiers: facts.modifiers,
                        surface: facts.surface) ? 1 : 0
                }
            },
            wheel: { _, _ in
                // Viewing scroll stays with the overlay WheelHandler; the band
                // path declines every wheel so the host owns it.
                0
            },
            leave: { context in
                guard let context else { return }
                MainActor.assumeIsolated {
                    let grid: PianoGrid = Unmanaged.fromOpaque(context).takeUnretainedValue()
                    grid.bandLeave()
                }
            },
            cancel: { reason, context in
                guard let context else { return }
                MainActor.assumeIsolated {
                    let grid: PianoGrid = Unmanaged.fromOpaque(context).takeUnretainedValue()
                    grid.bandCancel(reason: reason)
                }
            },
            gestureActive: { context in
                guard let context else { return 0 }
                return MainActor.assumeIsolated {
                    let grid: PianoGrid = Unmanaged.fromOpaque(context).takeUnretainedValue()
                    return grid.bandGestureActive() ? 1 : 0
                }
            },
            context: Unmanaged.passUnretained(self).toOpaque())
        precondition(sgb_set_surface(target, &surface), "The band endpoint is absent or already bound")
        bandTargetId = target
    }

    // sgk_ answer (spec §4): the shared band eligibility over this grid's live
    // gesture state and the latest sgs_ snapshot, so the production verdicts
    // are the same ones the harness surface returns for the same facts. Only
    // consume swallows the key; execute and decline defer to the single host
    // tier.
    private func bandKeyAnswer(
        command: Int32, origin: Int32, autoRepeat: Bool, commandAvailable: Bool
    ) -> Bool {
        guard
            let verdict = SgkBandEligibility.verdict(
                command: command, origin: origin, autoRepeat: autoRepeat,
                commandAvailable: commandAvailable, gestureActive: bandGestureActive(),
                session: sessionFeed?.session)
        else { return false }
        return verdict == .consume
    }

    // Authoritative session push (spec §3): the note-selection token list
    // replaces the local selection wholesale; primary track follows the
    // host's own channel (documentTrack) and is not re-derived here.
    private func applySession(_ session: SgsSession) {
        let tokens = Set(session.selectedNoteIds)
        var next: Set<Int> = []
        for note in notes where !note.ghost && tokens.contains(note.token) {
            next.insert(note.noteId)
        }
        if next != selection {
            selection = next
            noteSummaryDirty = true
            scene.rebuildNotes(sceneInput())
            publishOutputs()
        }
    }

    // Local ids whose notes still carry a live document token — used to
    // re-derive selection after an sgd_ rebuild and to translate local
    // selection into intent token lists.
    private func selectionTokens() -> Set<Int> {
        var live: Set<Int> = []
        for note in notes where !note.ghost && note.token != 0 {
            live.insert(note.noteId)
        }
        return selection.intersection(live)
    }

    private func tokenList(_ ids: Set<Int>) -> [UInt64] {
        var tokens: [UInt64] = []
        for note in notes where ids.contains(note.noteId) && note.token != 0 {
            tokens.append(note.token)
        }
        return tokens
    }

    // The single selection mutation point: the local set updates for
    // rendering, and an editing-bound grid submits the complete desired set
    // as one session intent (spec §2). Empty sets submit SGC_SELECTION_CLEAR.
    private func applySelection(_ next: Set<Int>) {
        guard next != selection else { return }
        selection = next
        noteSummaryDirty = true
        if let commandPipe {
            let tokens = tokenList(next)
            if tokens.isEmpty {
                commandPipe.submit(.selectionClear)
            } else {
                commandPipe.submit(.selectionSetNotes(noteIds: tokens))
            }
        }
    }

    private func selectedTokens() -> [UInt64] { tokenList(selection) }

    // Band-fact → content-point conversion. The sgb_ seam delivers
    // band-local ticks and keys (never pixels); the gesture engine runs in
    // content pixels, so each fact maps through the same metrics the
    // renderer uses. Row-center y is sufficient: hit zones only test row
    // containment and edge-grip x.
    private func bandPoint(tick: Double, key: Int32) -> (x: Double, y: Double) {
        let y = key >= 0 && key <= 127
            ? (Double(127 - key) + 0.5) * metrics.rowHeight
            : -1
        return (metrics.contentX(tick), y)
    }

    // sgb_ pointer entry. Facts arrive already arbitrated by the surface
    // contract: left/right plot presses, gutter left presses, moves, and
    // releases are absorbed; anything else declines back to the host.
    func bandPointer(
        kind: Int32, tick: Double, key: Int32, button: Int32, buttons: Int32,
        modifiers: Int32, surface: Int32
    ) -> Bool {
        guard !readOnly, commandPipe != nil else { return false }
        switch kind {
        case Int32(SGB_POINTER_PRESS):
            return bandPress(
                tick: tick, key: key, button: button, modifiers: modifiers,
                surface: surface)
        case Int32(SGB_POINTER_DOUBLE_CLICK):
            return bandDoubleClick(
                tick: tick, key: key, button: button, modifiers: modifiers,
                surface: surface)
        case Int32(SGB_POINTER_MOVE):
            if surface == Int32(SGB_SURFACE_GUTTER) {
                if bandGutterKey >= 0 {
                    bandGutterKey = Int(key)
                }
                return true
            }
            guard gesture != nil else { return false }
            let point = bandPoint(tick: tick, key: key)
            if gesture?.isRight == true {
                updateRightPointer(x: point.x, y: point.y, modifiers: modifiers)
            } else {
                updatePointer(x: point.x, y: point.y)
            }
            return true
        case Int32(SGB_POINTER_RELEASE):
            if surface == Int32(SGB_SURFACE_GUTTER) {
                bandGutterKey = -1
                return true
            }
            guard gesture != nil else { return false }
            let point = bandPoint(tick: tick, key: key)
            if gesture?.isRight == true {
                endRightPointer(x: point.x, y: point.y, modifiers: modifiers)
            } else {
                updatePointer(x: point.x, y: point.y)
                endPointer()
            }
            return true
        default:
            return false
        }
    }

    private func bandPress(tick: Double, key: Int32, button: Int32, modifiers: Int32,
                           surface: Int32) -> Bool {
        if surface == Int32(SGB_SURFACE_GUTTER) {
            // Gutter left press (production beginKbdAudition): select the
            // primary-track notes on the row and hold the audition key.
            // The audition itself is host-side; only the selection intent
            // crosses the seam.
            guard button == QtFact.leftButton else { return false }
            bandGutterKey = Int(key)
            var ids: Set<Int> = []
            for note in notes where !note.ghost && note.pitch == Int(key) {
                ids.insert(note.noteId)
            }
            applySelection(ids)
            return true
        }
        if button == QtFact.rightButton {
            // Shift-right-drag is the host time-selection gesture; no sgc_
            // verb covers it, so the press declines back to the host.
            if modifiers & QtFact.shiftModifier != 0 { return false }
            beginRightPointer(
                x: metrics.contentX(tick), y: bandPoint(tick: tick, key: key).y,
                threshold: metrics.drawThreshold)
            return gesture != nil
        }
        guard button == QtFact.leftButton else { return false }
        let point = bandPoint(tick: tick, key: key)
        beginPointer(x: point.x, y: point.y, modifiers: modifiers)
        return gesture != nil
    }

    private func bandDoubleClick(tick: Double, key: Int32, button: Int32,
                                 modifiers: Int32, surface: Int32) -> Bool {
        // Production pointerDoubleClick: non-left or gutter double-clicks
        // behave as a plain press; on a note it deletes, on empty space it
        // arms a draw that commits on release.
        if surface == Int32(SGB_SURFACE_GUTTER) || button != QtFact.leftButton {
            return bandPress(
                tick: tick, key: key, button: button, modifiers: modifiers,
                surface: surface)
        }
        let point = bandPoint(tick: tick, key: key)
        doublePointer(x: point.x, y: point.y)
        return true
    }

    func bandLeave() {
        bandGutterKey = -1
        clearKeyboardHover()
    }

    func bandCancel(reason: Int32) {
        bandGutterKey = -1
        if gesture?.isRight == true {
            cancelRightPointer(reason: Int(reason))
        } else {
            cancelPointer(reason: Int(reason))
        }
    }

    func bandGestureActive() -> Bool {
        gesture != nil || bandGutterKey >= 0
    }

    @QtIgnored
    func loadDocument(_ document: SgdDocument, trackIndex: Int) {
        guard let feed = documentFeed, document.documentId == feed.documentId,
            document.revision == feed.appliedRevision
        else { return }
        let snapshotChanged = appliedDocumentRevision != document.revision
        if snapshotChanged {
            let signatures = document.signatures.withUnsafeBufferPointer { buffer in
                [TimeSigPoint](capacity: buffer.count) { output in
                    let borrowed = Span(_unsafeElements: buffer)
                    for index in borrowed.indices {
                        let signature = borrowed[index]
                        output.append(TimeSigPoint(
                            tick: signature.startTick, numerator: signature.numerator,
                            denomPow2: signature.denomPow2))
                    }
                }
            }
            metrics.timeAxis = TimeAxis(map: TimeMap(
                ticksPerBeat: UInt32(max(0, document.ticksPerBeat)), timeSigs: signatures))
            appliedDocumentRevision = document.revision
            documentEndTick = Int(signatures.last?.tick ?? 0)
            appliedRevisionText = String(document.revision)
        }
        // One retained receiver owns the snapshot. This is the only projection:
        // no filter/map intermediates and no narrowing of UInt32 tick values.
        notes.removeAll(keepingCapacity: true)
        let validTrack = trackIndex >= 0 && trackIndex < Int(document.trackCount)
        if snapshotChanged || validTrack {
            document.notes.withUnsafeBufferPointer { buffer in
                let borrowed = Span(_unsafeElements: buffer)
                for index in borrowed.indices {
                    let note = borrowed[index]
                    if snapshotChanged {
                        documentEndTick = max(documentEndTick, Int(note.onTick) + Int(note.durationTicks))
                    }
                    if !validTrack || Int(note.trackIndex) != trackIndex { continue }
                    notes.append(GridNote(
                        noteId: index + 1, tick: Int(note.onTick),
                        duration: Int(note.durationTicks), pitch: Int(note.key),
                        track: Int(note.trackIndex), velocity: Int(note.velocity), ghost: false,
                        token: note.noteId))
                }
            }
        }
        gesture = nil
        activeNoteId = -1
        // Editing keeps the sgs_-pushed selection across document pushes:
        // local ids are re-derived from the retained tokens below (stale
        // tokens drop silently, spec §3). The unbound read-only path keeps
        // the historical clear.
        if sessionFeed == nil {
            selection.removeAll()
        } else {
            selection = selectionTokens()
        }
        selectionAtRightPress.removeAll()
        noteSummaryDirty = true
        publishGeometry()
        recomputeGeometry()
        rebuildScene()
        publishOutputs()
    }

    @QtSignal public func contextMenuRequested(x: Double, y: Double)

    public func deleteSelection() {
        guard !readOnly, let pipe = commandPipe else { return }
        // One batch intent = one undo entry (spec §2); the host's
        // reconciliation clears the selection through sgs_.
        let tokens = selectedTokens()
        if !tokens.isEmpty {
            pipe.deleteNotes(tokens)
        }
        selection.removeAll()
        noteSummaryDirty = true
        refreshNotes()
        publishOutputs()
    }

    public func configureViewport(
        baseFontPx: Double, devicePixelRatio: Double,
        width: Double, height: Double
    ) {
        metrics = GridMetrics(
            baseFontPx: baseFontPx, dpr: devicePixelRatio,
            width: width, height: height, timeAxis: metrics.timeAxis)
        initialScrollY = defaultVerticalScroll()
        publishGeometry()
        recomputeGeometry()
        rebuildScene()
        publishOutputs()
    }

    private func publishGeometry() {
        let m = metrics
        baseFontPx = m.baseFontPx
        devicePixelRatio = m.dpr
        beatWidth = m.beatWidth
        rowHeight = m.rowHeight
        keyboardWidth = m.keyboardWidth
        leadPadWidth = m.leadPadWidth
        gridHeight = m.gridHeight
        ticksPerBeat = m.documentTicksPerBeat
        snapTicks = m.snapTicks
        visibleGridTicks = m.visibleGridTicks
    }

    public func reloadVisuals() {
        rebuildScene()
        publishOutputs()
    }

    private func sceneInput() -> GridSceneInput {
        GridSceneInput(
            metrics: metrics,
            palette: palette,
            gridWidth: gridWidth,
            rulerHeight: rulerHeight,
            typography: typography,
            fontSpec: { self.fontSpec($0) },
            notes: notes,
            displayedNote: { self.displayedNote($0) },
            isSelected: { self.isSelected($0) },
            drawPreview: drawPreview,
            lastVelocity: lastVelocity,
            hoverKey: hoverKey,
            viewportScrollX: viewportScrollX,
            viewportScrollY: viewportScrollY,
            selectionBand: selectionBand)
    }

    private func rebuildScene() {
        let input = sceneInput()
        scene.rebuildStatic(input)
        scene.rebuildNotes(input)
    }

    private func refreshNotes() {
        let previousWidth = gridWidth
        let measured = recomputeGeometry()
        let input = sceneInput()
        if measured || gridWidth != previousWidth {
            scene.rebuildStatic(input)
        }
        scene.rebuildNotes(input)
    }

    private func defaultVerticalScroll() -> Double {
        var lo = 127
        var hi = 0
        for i in 0..<notes.count {
            lo = min(lo, notes[i].pitch)
            hi = max(hi, notes[i].pitch)
        }
        let midKey = lo <= hi ? (lo + hi) / 2 : 60
        let centerRow = 127 - midKey
        return max(
            0.0,
            Double(centerRow) * metrics.rowHeight - max(
                metrics.initialViewportHeight, metrics.viewportHeight) / 2.0)
    }

    private func recomputeGridWidth() {
        var end = documentFeed == nil ? GridMetrics.songLengthTicks : documentEndTick
        if documentFeed == nil {
            for note in notes {
                end = max(end, note.tick + note.duration)
            }
        }
        if let preview = drawPreview {
            end = max(end, preview.tick + preview.duration)
        }
        let contentWidth = metrics.leadPadWidth + Double(end) * metrics.pxPerTick
            + metrics.viewportWidth
        // A shorter/empty snapshot must not force the host Flickable to pan.
        gridWidth = readOnly
            ? max(contentWidth, viewportScrollX + metrics.viewportWidth) : contentWidth
    }

    @discardableResult
    private func recomputeGeometry() -> Bool {
        recomputeGridWidth()
        return updateTypography()
    }

    private var typographyKey: (fontPx: Double, dpr: Double)?

    @discardableResult
    private func updateTypography() -> Bool {
        let key = (fontPx: metrics.baseFontPx, dpr: metrics.dpr)
        if let current = typographyKey,
            current.fontPx == key.fontPx && current.dpr == key.dpr
        {
            return false
        }
        measurementFonts = GridTypography.fonts(metrics: metrics)
        let measured = GridTypography(
            fonts: measurementFonts, rowHeight: metrics.rowHeight)
        typography = measured
        typographyKey = key
        rulerHeight = measured.boldHeight + 1 + measured.rulerHeight + 1
        return true
    }

    @QtIgnored
    func fontSpec(_ kind: GridFontKind) -> [String: QVariantSettable] {
        if let t = typography {
            return t.fontMap(kind)
        }
        return measurementFonts[kind]!.map
    }

    public func beginPointer(x: Double, y: Double) {
        beginPointer(x: x, y: y, modifiers: 0)
    }

    // Shared left-press entry: QML delivers pixel points with no modifiers;
    // the band path delivers the same points converted from tick/key facts
    // plus the press modifiers (production applyNotePressSelection).
    func beginPointer(x: Double, y: Double, modifiers: Int32) {
        guard !readOnly else { return }
        guard gesture == nil else { return }
        let pressTick = metrics.tickAtContentX(x)
        let pressKey = metrics.yToPitch(y)
        guard pressKey >= 0 else { return }
        let hit = hitNote(x: x, y: y)
        // Left-grip decline (spec §5 deviation, S-3): a leading resize shifts
        // every selected note's start by +d and its duration by −d, which the
        // frozen §2 vocabulary carries only as per-note noteMove+noteResize
        // pairs or as two batch intents — 2N or 2 undo entries against one
        // gesture = one entry. The editing lane declines the press instead of
        // opening a gesture it cannot land atomically.
        if hit?.zone == .leftEdge, commandPipe != nil { return }
        var next: GridGesture = .pendingDraw(
            GridGesture.PendingDraw(
                pressX: x, pressY: y,
                pressTick: pressTick, pressKey: pressKey))
        if let hit {
            let note = notes[hit.index]
            let onEdge = hit.zone == .leftEdge || hit.zone == .rightEdge
            if modifiers & QtFact.controlModifier != 0 {
                if onEdge {
                    // Ctrl on an edge only adds; the grip never toggles off.
                    if !isSelected(note.noteId) {
                        applySelection(selection.union([note.noteId]))
                    }
                } else {
                    var toggled = selection
                    if toggled.contains(note.noteId) {
                        toggled.remove(note.noteId)
                    } else {
                        toggled.insert(note.noteId)
                    }
                    applySelection(toggled)
                }
            } else if !isSelected(note.noteId) {
                applySelection([note.noteId])
            }
            lastVelocity = note.velocity
            switch hit.zone {
            case .rightEdge:
                next = .resize(
                    pressTick: pressTick,
                    gripTick: note.tick + note.duration,
                    oppositeTick: note.tick, leading: false)
            case .leftEdge:
                // A bound grid already declined the left grip; unbound input
                // cannot commit it.
                next = .resize(
                    pressTick: pressTick,
                    gripTick: note.tick,
                    oppositeTick: note.tick + note.duration,
                    leading: true)
            default:
                next = .move(pressTick: pressTick, pressKey: pressKey)
            }
            activeNoteId = note.noteId
        } else {
            applySelection([])
        }
        gesture = next
        scene.rebuildNotes(sceneInput())
        publishOutputs()
    }

    public func updatePointer(x: Double, y: Double) {
        guard !readOnly else { return }
        guard let g = gesture, !g.isRight else { return }
        gesture = g.updated(x: x, y: y, metrics: metrics)
        refreshNotes()
        publishOutputs()
    }

    public func endPointer() {
        guard !readOnly, commandPipe != nil else { return }
        guard let g = gesture, !g.isRight else { return }
        commitGesture(g)
        gesture = nil
        activeNoteId = -1
        refreshNotes()
        publishOutputs()
    }

    // Document-mode gesture commit (spec §5): the live drag was a Swift-side
    // preview; the document mutates exactly once here, as intents through
    // sgc_. Selection tokens are snapshotted before any submit — each
    // document intent triggers a synchronous sgd_ rebuild that re-derives
    // the local selection from live tokens.
    private func commitGesture(_ g: GridGesture) {
        guard let pipe = commandPipe else { return }
        switch g {
        case .pendingDraw(let state):
            // The edit cursor is host-side state with no sgc_ verb; the
            // local mirror still tracks the click.
            editCursorTick = metrics.snapTick(state.pressTick)
        case .draw(let state):
            let outcome = pipe.addDrawnNote(
                track: Int32(documentTrack), key: Int32(state.key),
                onTick: UInt32(max(0, state.tick)),
                durationTicks: UInt32(max(1, state.duration)),
                velocity: Int32(lastVelocity))
            // Production selects the drawn note on commit (commitDrawDrag).
            if outcome.result == .executed && outcome.noteId != 0 {
                pipe.selectNotes([outcome.noteId])
            }
        case .move(let state):
            guard state.dTick != 0 || state.dKey != 0 else { return }
            let tokens = selectedTokens()
            pipe.moveNotes(
                noteIds: tokens, deltaTicks: Int64(state.dTick),
                deltaKeys: Int32(state.dKey))
        case .resize(let state):
            guard state.delta != 0 else { return }
            // Trailing resize: one batch intent = one undo entry (S-3); the
            // uniform duration delta mirrors production resizeNotes. The left
            // grip never reaches a commit — the editing lane declines its
            // press (spec §5 deviation).
            let tokens = selectedTokens()
            pipe.resizeNotes(noteIds: tokens, dDuration: Int64(state.delta))
        case .pendingMenu, .band:
            break
        }
    }
    public func inputCancelled(reason: Int) {
        lastCancelReason = reason
        cancelPointer(reason: reason)
    }

    public func cancelPointer(reason: Int) {
        guard !readOnly else { return }
        guard let g = gesture else { return }
        guard let cancelReason = GridCancelReason(rawValue: reason) else { return }
        // Focus loss keeps both gesture families alive with zero state
        // change: a later updatePointer/endPointer still commits.
        if cancelReason == .focusLost { return }
        gesture = nil
        activeNoteId = -1
        if g.isRight {
            // Restore the press-time selection through the bound session seam.
            applySelection(selectionAtRightPress)
        }
        if cancelReason == .hidden || cancelReason == .windowDeactivated {
            cancelHoverAndPreview()
        }
        scene.rebuildNotes(sceneInput())
        publishOutputs()
    }

    // Hidden and window-deactivated teardown beyond the pointer-ungrab
    // baseline. Window-deactivated is identical for the grid surface by
    // design; only the entry differs (per-surface visible vs window-level
    // once, popup surfaces excluded by the host).
    private func cancelHoverAndPreview() {
        hoverKey = -1
        cursorKind = 0
        scene.rebuildHover(sceneInput())
    }

    public func beginRightPointer(x: Double, y: Double, threshold: Double) {
        guard !readOnly else { return }
        if let g = gesture, !g.isRight {
            gesture = nil
            activeNoteId = -1
        }
        guard gesture == nil else { return }
        selectionAtRightPress = selection
        var hitId = -1
        if let hit = hitNote(x: x, y: y) {
            let note = notes[hit.index]
            hitId = note.noteId
            if !isSelected(note.noteId) {
                applySelection([note.noteId])
            }
        }
        gesture = .pendingMenu(
            GridGesture.PendingMenu(
                pressX: x, pressY: y,
                threshold: threshold,
                hitNoteId: hitId))
        scene.rebuildNotes(sceneInput())
        publishOutputs()
    }

    public func updateRightPointer(x: Double, y: Double) {
        updateRightPointer(x: x, y: y, modifiers: 0)
    }

    func updateRightPointer(x: Double, y: Double, modifiers: Int32) {
        guard !readOnly else { return }
        guard let g = gesture, g.isRight else { return }
        gesture = g.updated(x: x, y: y, metrics: metrics)
        scene.rebuildNotes(sceneInput())
        publishOutputs()
    }

    public func endRightPointer(x: Double, y: Double) {
        endRightPointer(x: x, y: y, modifiers: 0)
    }

    func endRightPointer(x: Double, y: Double, modifiers: Int32) {
        guard !readOnly else { return }
        guard let g = gesture, g.isRight else { return }
        switch g {
        case .pendingMenu(let state):
            if state.hitNoteId >= 0 {
                contextMenuRequested(x: x, y: y)
            } else {
                applySelection([])
            }
        case .band(let state):
            // Production selectBand: the covered set unions the press-time
            // selection only while Ctrl is held at release.
            var desired = bandCoverage(
                pressX: state.pressX, pressY: state.pressY,
                curX: state.curX, curY: state.curY)
            if modifiers & QtFact.controlModifier != 0 {
                desired.formUnion(selectionAtRightPress)
            }
            applySelection(desired)
        default:
            break
        }
        gesture = nil
        scene.rebuildNotes(sceneInput())
        publishOutputs()
    }

    public func cancelRightPointer(reason: Int) {
        guard !readOnly else { return }
        guard let g = gesture, g.isRight else { return }
        guard let cancelReason = GridCancelReason(rawValue: reason) else { return }
        if cancelReason == .focusLost { return }
        gesture = nil
        applySelection(selectionAtRightPress)
        if cancelReason == .hidden || cancelReason == .windowDeactivated {
            cancelHoverAndPreview()
        }
        scene.rebuildNotes(sceneInput())
        publishOutputs()
    }

    // Notes whose rendered rect intersects the marquee — the production
    // release-time coverage rule.
    private func bandCoverage(
        pressX: Double, pressY: Double, curX: Double, curY: Double
    ) -> Set<Int> {
        let x0 = min(pressX, curX)
        let x1 = max(pressX, curX)
        let y0 = min(pressY, curY)
        let y1 = max(pressY, curY)
        var covered: Set<Int> = []
        for note in notes where !note.ghost {
            let r = metrics.noteRect(
                x0: metrics.displayX(Double(note.tick)),
                x1: metrics.displayX(Double(note.tick + note.duration)),
                pitch: note.pitch)
            let overlaps =
                r.x < x1 && r.x + r.w > x0
                && r.y < y1 && r.y + r.h > y0
            if overlaps { covered.insert(note.noteId) }
        }
        return covered
    }

    public func doublePointer(x: Double, y: Double) {
        guard !readOnly, let commandPipe else { return }
        guard gesture == nil else { return }
        // Production pointerDoubleClick: delete on a note, arm a draw on
        // empty space (committed by the release that follows).
        if let hit = hitNote(x: x, y: y) {
            let note = notes[hit.index]
            if note.token != 0 {
                commandPipe.submit(.noteDelete(noteIds: [note.token]))
            }
            applySelection([])
            scene.rebuildNotes(sceneInput())
            publishOutputs()
            return
        }
        beginPointer(x: x, y: y, modifiers: 0)
        if case .pendingDraw(let state) = gesture {
            let anchor = metrics.snapTickDown(state.pressTick)
            gesture = .draw(
                GridGesture.Draw(
                    anchorTick: anchor, tick: anchor,
                    duration: metrics.snapTicks, key: state.pressKey))
            scene.rebuildNotes(sceneInput())
            publishOutputs()
        }
    }

    public func hoverPointer(x: Double, y: Double) {
        guard gesture == nil else { return }
        clearKeyboardHover()
        guard let hit = hitNote(x: x, y: y) else {
            cursorKind = 0
            return
        }
        switch hit.zone {
        case .rightEdge: cursorKind = 3
        case .leftEdge: cursorKind = 2
        default: cursorKind = 1
        }
    }

    public func setViewportScroll(y: Double) {
        guard viewportScrollY != y else { return }
        viewportScrollY = y
        scene.rebuildHover(sceneInput())
    }

    public func setViewportScrollX(x: Double) {
        guard viewportScrollX != x else { return }
        viewportScrollX = x
        scene.rebuildStatic(sceneInput())
    }

    public func hoverKeyboard(y: Double) {
        let key = metrics.yToPitch(y)
        guard key != hoverKey else { return }
        hoverKey = key
        scene.rebuildHover(sceneInput())
    }

    public func clearKeyboardHover() {
        guard hoverKey >= 0 else { return }
        hoverKey = -1
        scene.rebuildHover(sceneInput())
    }


    @QtIgnored
    func isSelected(_ noteId: Int) -> Bool { selection.contains(noteId) }

    @QtIgnored
    func displayedNote(_ note: GridNote) -> (tick: Int, end: Int, pitch: Int) {
        var tick = note.tick
        var end = note.tick + note.duration
        var pitch = note.pitch
        guard let g = gesture, !note.ghost, isSelected(note.noteId) else {
            return (tick, end, pitch)
        }
        switch g {
        case .resize(let state) where state.leading:
            tick = min(max(0, tick + state.delta), end - 1)
        case .move(let state):
            tick = max(0, tick + state.dTick)
            end = max(tick + 1, end + state.dTick)
            pitch = min(127, max(0, pitch + state.dKey))
        case .resize(let state):
            end = max(tick + 1, end + state.delta)
        default:
            break
        }
        return (tick, end, pitch)
    }

    private enum HitZone {
        case none, body, leftEdge, rightEdge
    }

    private func hitZone(
        x: Double, y: Double,
        note: GridNote
    ) -> (zone: HitZone, inside: Bool) {
        let reach = metrics.edgeGripReach
        let r = metrics.noteRect(
            x0: metrics.displayX(Double(note.tick)),
            x1: metrics.displayX(Double(note.tick + note.duration)),
            pitch: note.pitch)
        guard y >= r.y, y < r.y + r.h else { return (.none, false) }
        let right = r.x + r.w
        let inside = x >= r.x && x < right
        guard inside || (x >= r.x - reach && x < right + reach) else {
            return (.none, false)
        }
        let inner = metrics.edgeGripInnerReach(rectWidth: r.w)
        if x >= right - inner && x <= right + reach { return (.rightEdge, inside) }
        if x >= r.x - reach && x <= r.x + inner { return (.leftEdge, inside) }
        return (.body, inside)
    }

    private func hitNote(x: Double, y: Double) -> (index: Int, zone: HitZone)? {
        var hit: (index: Int, zone: HitZone)?
        var hitInside = false
        var grip: (index: Int, zone: HitZone)?
        for i in 0..<notes.count {
            let note = notes[i]
            if note.ghost { continue }
            let (zone, inside) = hitZone(x: x, y: y, note: note)
            if zone == .none { continue }
            hit = (i, zone)
            hitInside = inside
            if inside && (zone == .leftEdge || zone == .rightEdge) {
                grip = (i, zone)
            }
        }
        if let grip, !hitInside { return grip }
        return hit
    }

    private func publishOutputs() {
        renderedNoteCount = notes.count
        // The JSON diagnostics are not document publication.
        if !readOnly && noteSummaryDirty {
            noteSummaryDirty = false
            var parts: [String] = []
            parts.reserveCapacity(notes.count)
            for note in notes {
                parts.append(
                    "{\"id\":\(note.noteId),\"tick\":\(note.tick),"
                        + "\"duration\":\(note.duration),\"pitch\":\(note.pitch),"
                        + "\"track\":\(note.track),\"velocity\":\(note.velocity),"
                        + "\"selected\":\(isSelected(note.noteId)),\"ghost\":\(note.ghost)}")
            }
            noteSummary = "[" + parts.joined(separator: ",") + "]"
        }

        if let g = gesture {
            switch g {
            case .pendingDraw(let state):
                statusText = "Pending draw at tick \(metrics.snapTick(state.pressTick))"
            case .draw(let state):
                statusText =
                    "Drawing — tick \(state.tick), duration \(state.duration), "
                    + "pitch \(state.key)"
            case .move(let state):
                statusText =
                    "Moving \(selection.count) note(s) — dTick \(state.dTick), "
                    + "dKey \(state.dKey)"
            case .resize:
                statusText = "Resizing \(selection.count) note(s)"
            case .pendingMenu:
                statusText = "\(notes.count) notes, \(selection.count) selected"
            case .band:
                statusText = "Selecting \(selection.count) note(s)"
            }
        } else {
            statusText = "\(notes.count) notes, \(selection.count) selected"
        }
    }
}
