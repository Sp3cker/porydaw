// Pointer x/y -> hit-test -> gesture state machine -> preview -> status.
// Hands off to refreshNotes()/sceneInput() for scene projection and publication.
import Foundation
import PorydawAppCommands
import PorydawAppPresentation
import PorydawCore
import PorydawDocument
import QtBridge

// Pointer interaction state machine for the piano grid. Each kind carries
// only the state that kind actually uses; transitions happen in updated(x:y:).
enum GridGesture {
    case pendingDraw(PendingDraw)
    case draw(Draw)
    case velocity(Velocity)
    case move(Move)
    case resize(Resize)
    case pendingMenu(PendingMenu)
    case band(Band)
    case pan(Pan)

    var isRight: Bool {
        switch self {
        case .pendingMenu, .band: return true
        default: return false
        }
    }

    struct PendingDraw {
        var pressX: Double
        var pressY: Double
        var pressTick: Double
        var pressKey: Int
    }

    struct Draw {
        var anchorTick: Int
        var tick: Int
        var duration: Int
        var key: Int
    }

    struct Move {
        var pressTick: Double
        var pressKey: Int
        var dTick: Int = 0
        var dKey: Int = 0
    }
    struct Velocity {
        var noteId: NoteID
        var pressY: Double
        var original: Int
        var delta: Int = 0
        var preview: Int? = nil
    }

    struct Resize {
        var pressTick: Double
        var gripTick: Int
        var oppositeTick: Int
        var leading: Bool
        var delta: Int = 0
    }

    struct PendingMenu {
        var pressX: Double
        var pressY: Double
        var threshold: Double
        var hitNoteId: NoteID
    }

    struct Band {
        var pressX: Double
        var pressY: Double
        var curX: Double
        var curY: Double
    }

    struct Pan {
        var pressX: Double
        var pressY: Double
        var deltaX: Double = 0
        var deltaY: Double = 0
    }

    static func move(pressTick: Double, pressKey: Int) -> GridGesture {
        .move(Move(pressTick: pressTick, pressKey: pressKey))
    }

    static func resize(
        pressTick: Double, gripTick: Int, oppositeTick: Int,
        leading: Bool
    ) -> GridGesture {
        .resize(
            Resize(
                pressTick: pressTick, gripTick: gripTick,
                oppositeTick: oppositeTick, leading: leading))
    }

    func updated(
        x: Double, y: Double, metrics: GridMetrics, grid: RollGrid,
        camera: EditorCamera, scale: ScaleProjection
    ) -> GridGesture {
        func pitch(_ y: Double) -> Int {
            camera.projection.pitch(
                atY: y, keyHeight: camera.snapshot.keyHeight,
                scrollY: camera.snapshot.scrollY, dpr: metrics.dpr) ?? -1
        }
        switch self {
        case .pendingDraw(var state):
            let key = pitch(y)
            if key >= 0 && (!scale.fold || scale.contains(key)) { state.pressKey = key }
            guard abs(x - state.pressX) >= metrics.drawThreshold else {
                return .pendingDraw(state)
            }
            let anchor = grid.snapTickDown(state.pressTick, camera: camera)
            let draw = Draw(
                anchorTick: Int(anchor), tick: Int(anchor),
                duration: Int(grid.snapTicksAt(anchor, camera: camera)), key: state.pressKey)
            return GridGesture.draw(draw).updated(
                x: x, y: y, metrics: metrics, grid: grid, camera: camera, scale: scale)
        case .draw(var state):
            let tick = camera.tickAtContentX(x)
            let gridTicks = Int(grid.snapTicksAt(Tick(max(0, state.anchorTick)), camera: camera))
            if tick >= Double(state.anchorTick) {
                state.tick = state.anchorTick
                state.duration =
                    max(
                        state.anchorTick + gridTicks,
                        Int(grid.snapTickUp(tick, camera: camera))) - state.anchorTick
            } else {
                state.tick = Int(grid.snapTickDown(tick, camera: camera))
                state.duration = state.anchorTick + gridTicks - state.tick
            }
            let key = pitch(y)
            if key >= 0 && (!scale.fold || scale.contains(key)) { state.key = key }
            return .draw(state)
        case .move(var state):
            let tick = camera.tickAtContentX(x)
            let gridTicks = Int(
                grid.snapTicksAt(
                    TimeDefaults.tick(from: max(0, state.pressTick)),
                    camera: camera))
            state.dTick = Int(((tick - state.pressTick) / Double(gridTicks)).rounded()) * gridTicks
            if scale.fold {
                let projection = camera.projection
                let currentRow = projection.row(
                    atY: y, keyHeight: camera.snapshot.keyHeight,
                    scrollY: camera.snapshot.scrollY, dpr: metrics.dpr)
                let grabRow = projection.row(forPitch: state.pressKey)
                if currentRow != PitchProjection.hiddenRow,
                    grabRow != PitchProjection.hiddenRow
                {
                    var degrees = 0
                    if currentRow < grabRow {
                        for row in currentRow..<grabRow {
                            if let pitch = projection.visiblePitch(at: row), scale.contains(pitch) {
                                degrees += 1
                            }
                        }
                    } else if currentRow > grabRow {
                        for row in (grabRow + 1)...currentRow {
                            if let pitch = projection.visiblePitch(at: row), scale.contains(pitch) {
                                degrees -= 1
                            }
                        }
                    }
                    state.dKey = degrees
                }
            } else {
                let key = pitch(y)
                if key >= 0 { state.dKey = key - state.pressKey }
            }
            return .move(state)
        case .velocity(var state):
            state.delta = Int((state.pressY - y).rounded())
            state.preview = min(127, max(1, state.original + state.delta))
            return .velocity(state)
        case .resize(var state):
            let tick = camera.tickAtContentX(x)
            let desired = Double(state.gripTick) + (tick - state.pressTick)
            let snapped =
                state.leading
                ? min(
                    Int(grid.snapTick(desired, camera: camera)),
                    Int(grid.snapTickDown(Double(state.oppositeTick) - 1.0, camera: camera)))
                : max(
                    Int(grid.snapTick(desired, camera: camera)),
                    Int(grid.snapTickUp(Double(state.oppositeTick) + 1.0, camera: camera)))
            state.delta =
                abs(desired - Double(state.gripTick)) < abs(desired - Double(snapped))
                ? 0 : snapped - state.gripTick
            return .resize(state)
        case .pendingMenu(let state):
            guard
                manhattanExceeds(
                    press: (state.pressX, state.pressY), x: x, y: y, threshold: state.threshold)
            else {
                return .pendingMenu(state)
            }
            return .band(
                Band(
                    pressX: state.pressX, pressY: state.pressY, curX: x, curY: y))
        case .band(var state):
            state.curX = x
            state.curY = y
            return .band(state)
        case .pan(var state):
            state.deltaX = x - state.pressX
            state.deltaY = y - state.pressY
            state.pressX = x
            state.pressY = y
            return .pan(state)
        }
    }
}

@MainActor
extension PianoGrid {

    @QtIgnored
    func pitch(atY y: Double) -> Int {
        let snapshot = viewport.camera.snapshot
        return viewport.camera.projection.pitch(
            atY: y, keyHeight: snapshot.keyHeight,
            scrollY: snapshot.scrollY, dpr: metrics.dpr) ?? -1
    }

    @QtIgnored
    func displayedNote(_ note: GridNote) -> (tick: Int, end: Int, pitch: Int) {
        var tick = note.tick
        var end = note.tick + note.duration
        var pitch = note.pitch
        guard let gesture, !note.ghost, session.selectedNotes.contains(note.noteId) else {
            return (tick, end, pitch)
        }
        switch gesture {
        case .resize(let state) where state.leading:
            tick = min(max(0, tick + state.delta), end - 1)
        case .move(let state):
            tick = max(0, tick + state.dTick)
            end = max(tick + 1, end + state.dTick)
            if viewport.scale.fold && state.dKey != 0 {
                let destination = viewport.scale.scale.pitch(
                    pitch, steps: state.dKey, root: viewport.scale.root)
                if destination >= 0 { pitch = destination }
            } else {
                pitch = min(127, max(0, pitch + state.dKey))
            }
        case .resize(let state):
            end = max(tick + 1, end + state.delta)
        default:
            break
        }
        return (tick, end, pitch)
    }

    enum HitZone { case none, body, leftEdge, rightEdge }

    @QtIgnored
    private func hitZone(x: Double, y: Double, note: GridNote) -> (HitZone, Bool) {
        let reach = metrics.edgeGripReach
        let rect = metrics.noteRect(
            camera: viewport.camera,
            x0: viewport.camera.viewX(tick: Double(note.tick), dpr: metrics.dpr),
            x1: viewport.camera.viewX(
                tick: Double(note.tick + note.duration), dpr: metrics.dpr),
            pitch: note.pitch)
        guard y >= rect.y, y < rect.y + rect.h else { return (.none, false) }
        let right = rect.x + rect.w
        let inside = x >= rect.x && x < right
        guard inside || (x >= rect.x - reach && x < right + reach) else {
            return (.none, false)
        }
        let inner = metrics.edgeGripInnerReach(rectWidth: rect.w)
        if x >= right - inner && x <= right + reach { return (.rightEdge, inside) }
        if x >= rect.x - reach && x <= rect.x + inner { return (.leftEdge, inside) }
        return (.body, inside)
    }

    @QtIgnored
    func hitNote(x: Double, y: Double) -> (index: Int, zone: HitZone)? {
        var hit: (index: Int, zone: HitZone)?
        var hitInside = false
        var grip: (index: Int, zone: HitZone)?
        for index in notes.indices {
            if notes[index].ghost { continue }
            let (zone, inside) = hitZone(x: x, y: y, note: notes[index])
            if zone == .none { continue }
            hit = (index, zone)
            hitInside = inside
            if inside && (zone == .leftEdge || zone == .rightEdge) {
                grip = (index, zone)
            }
        }
        if let grip, !hitInside { return grip }
        return hit
    }

    @QtIgnored
    func currentStatusText() -> String {
        if let gesture {
            switch gesture {
            case .pendingDraw(let state):
                return "Pending draw at tick \(viewport.grid.snapTick(state.pressTick, camera: viewport.camera))"
            case .draw(let state):
                return "Drawing — tick \(state.tick), duration \(state.duration), pitch \(state.key)"
            case .velocity:
                return "Changing velocity"
            case .move(let state):
                return "Moving \(session.selectedNotes.count) note(s) — dTick \(state.dTick), dKey \(state.dKey)"
            case .resize:
                return "Resizing \(session.selectedNotes.count) note(s)"
            case .pendingMenu:
                return "\(notes.count) notes, \(session.selectedNotes.count) selected"
            case .band:
                return "Selecting \(session.selectedNotes.count) note(s)"
            case .pan:
                return "Panning"
            }
        }
        if case .band = rightGesture {
            return "Selecting \(session.selectedNotes.count) note(s)"
        }
        return "\(notes.count) notes, \(session.selectedNotes.count) selected"
    }

    @QtIgnored
    func applyPressSelection(_ id: NoteID, modifiers: Int) {
        if modifiers & QtFact.controlModifier != 0 {
            if !session.selectedNotes.contains(id) {
                addSelectedNoteFromLeftPointer(id)
            }
        } else if modifiers & QtFact.shiftModifier != 0 {
            addSelectedNoteFromLeftPointer(id)
        } else if !session.selectedNotes.contains(id) {
            session.setSelectedNotes([id])
        }
    }

    @QtIgnored
    func addSelectedNoteFromLeftPointer(_ id: NoteID) {
        session.addSelectedNote(id)
        if case .band = rightGesture, !rightBandDemoted,
            !selectionAtRightPress.contains(id)
        {
            selectionAtRightPress.append(id)
        }
    }

    @QtIgnored
    func removeSelectedNoteFromLeftPointer(_ id: NoteID) {
        session.removeSelectedNote(id)
        if case .band = rightGesture, !rightBandDemoted {
            selectionAtRightPress.removeAll { $0 == id }
        }
    }

    @QtIgnored
    func commitGesture() {
        guard let gesture else { return }
        let ids = session.selectedNoteOrder
        switch gesture {
        case .pendingDraw:
            break
        case .draw(let state):
            addNote(tick: state.tick, duration: state.duration, pitch: state.key)
        case .velocity(let state):
            if state.delta != 0 {
                var changes: [NoteVelocity] = []
                for id in session.selectedNoteOrder {
                    guard let current = session.document.note(id) else { continue }
                    changes.append(
                        NoteVelocity(
                            noteID: id, velocity: Int(current.velocity) + state.delta))
                }
                if changes.isEmpty {
                    changes.append(
                        NoteVelocity(
                            noteID: state.noteId, velocity: state.original + state.delta))
                }
                if session.document.setVelocities(
                    changes, expectedRevision: session.document.revision) != nil
                {
                    lastVelocity = min(127, max(1, state.original + state.delta))
                }
            }
        case .move(let state):
            if viewport.scale.fold && state.dKey != 0 {
                let selected = ids.compactMap { session.document.note($0) }
                if let pitches = viewport.scale.destinations(for: selected, steps: state.dKey) {
                    _ = session.document.moveNotes(
                        selected.map(\.id), toPitches: pitches, byTicks: Int64(state.dTick))
                }
            } else {
                session.document.moveNotes(ids, byTicks: Int64(state.dTick), byKeys: state.dKey)
            }
        case .resize(let state):
            session.document.resizeNotes(
                ids, edge: state.leading ? .leading : .trailing,
                byTicks: Int64(state.delta))
        case .pendingMenu, .band, .pan:
            break
        }
    }

    @QtIgnored
    private func addNote(tick: Int, duration: Int, pitch: Int) {
        guard session.selectedTrack != nil, tick >= 0, duration > 0,
            (0...127).contains(pitch),
            Int64(tick) + Int64(duration) <= Int64(TimeDefaults.maxTick)
        else { return }
        guard
            let ids = try? session.document.addNotes([
                NewNote(
                    track: trackIndex, tick: Tick(tick), pitch: UInt8(pitch),
                    duration: Tick(duration), velocity: UInt8(min(127, max(1, lastVelocity))))
            ]), let id = ids.first
        else { return }
        session.setSelectedNotes([id])
        activeNoteId = id.rawValue
    }

    @QtIgnored
    func bandCoveredNotes() -> [GridNote] {
        guard let band = selectionBand else { return [] }
        return notes.filter { note in
            guard !note.ghost else { return false }
            let displayed = displayedNote(note)
            let rect = metrics.noteRect(
                camera: viewport.camera,
                x0: viewport.camera.viewX(tick: Double(displayed.tick), dpr: metrics.dpr),
                x1: viewport.camera.viewX(tick: Double(displayed.end), dpr: metrics.dpr),
                pitch: displayed.pitch)
            return rect.x < band.x + band.w && rect.x + rect.w > band.x
                && rect.y < band.y + band.h && rect.y + rect.h > band.y
        }
    }

    @QtIgnored
    func applyBandSelection() {
        guard selectionBand != nil else { return }
        let previous =
            rightPointerModifiers & QtFact.controlModifier != 0
            ? selectionAtRightPress : []
        session.setSelectedNotes(previous + bandCoveredNotes().map(\.noteId))
    }

    @QtIgnored
    func auditionBandEntrants() {
        guard selectionBand != nil else { return }
        var covered: [NoteID: (track: Int, pitch: Int)] = [:]
        for note in bandCoveredNotes() {
            guard let source = session.document.note(note.noteId), source.duration > 0 else {
                continue
            }
            covered[note.noteId] = (note.track, note.pitch)
            if bandAuditioned[note.noteId] == nil {
                onAudition?(note.track, note.pitch, note.velocity)
            }
        }
        for (id, entry) in bandAuditioned where covered[id] == nil {
            onAudition?(entry.track, entry.pitch, 0)
        }
        bandAuditioned = covered
    }

    @QtIgnored
    func releaseBandAudition() {
        for (_, entry) in bandAuditioned {
            onAudition?(entry.track, entry.pitch, 0)
        }
        bandAuditioned.removeAll()
    }

    func beginPointerImpl(x: Double, y: Double, modifiers: Int) {
        guard gesture == nil else { return }
        suppressedLeftRelease = false
        pointerModifiers = modifiers
        stopAudition()
        pendingVelocityReanchor = nil
        let pressTick = viewport.camera.tickAtContentX(x)
        let pressKey = pitch(atY: y)
        guard pressKey >= 0 else { return }
        if let hit = hitNote(x: x, y: y) {
            let note = notes[hit.index]
            let control = modifiers & QtFact.controlModifier != 0
            pendingControlToggle =
                control && session.selectedNotes.contains(note.noteId)
                ? note.noteId : nil
            activeNoteId = note.noteId.rawValue
            lastVelocity = note.velocity
            keyboardAuditionKey = note.pitch
            keyboardAuditionTrack = trackIndex
            onAudition?(trackIndex, note.pitch, note.velocity)
            if control && hit.zone != .leftEdge && hit.zone != .rightEdge {
                gesture = .velocity(
                    GridGesture.Velocity(
                        noteId: note.noteId, pressY: y, original: note.velocity))
                pendingVelocityReanchor =
                    session.selectedNotes.contains(note.noteId) ? nil : note.noteId
                cursorKind = GridCursorKind.velocity.rawValue
                if hoverKey != note.pitch {
                    hoverKey = note.pitch
                    scene.rebuildHover(sceneInput())
                }
            } else {
                applyPressSelection(note.noteId, modifiers: modifiers)
                switch hit.zone {
                case .leftEdge:
                    gesture = .resize(
                        pressTick: pressTick, gripTick: note.tick,
                        oppositeTick: note.tick + note.duration, leading: true)
                case .rightEdge:
                    gesture = .resize(
                        pressTick: pressTick, gripTick: note.tick + note.duration,
                        oppositeTick: note.tick, leading: false)
                default:
                    gesture = .move(pressTick: pressTick, pressKey: pressKey)
                }
            }
            if case .band(let band) = rightGesture, !control {
                rightBandDemoted = true
                rightGesture = .pendingMenu(
                    GridGesture.PendingMenu(
                        pressX: band.pressX, pressY: band.pressY,
                        threshold: .infinity, hitNoteId: NoteID()))
                releaseBandAudition()
            }
        } else {
            guard !viewport.scale.fold || viewport.scale.contains(pressKey)
            else { return }
            session.clearSelectedNotes()
            gesture = .pendingDraw(
                GridGesture.PendingDraw(
                    pressX: x, pressY: y, pressTick: pressTick, pressKey: pressKey))
            keyboardAuditionKey = pressKey
            keyboardAuditionTrack = trackIndex
            onAudition?(trackIndex, pressKey, min(127, max(1, lastVelocity)))
        }
        refreshNotes()
    }

    func beginPanImpl(x: Double, y: Double) {
        guard !interactionActive else { return }
        gesture = .pan(GridGesture.Pan(pressX: x, pressY: y))
        if cursorKind != GridCursorKind.closedHand.rawValue {
            cursorKind = GridCursorKind.closedHand.rawValue
        }
        publishOutputs()
    }

    func updatePanImpl(x: Double, y: Double) {
        guard let gesture, case .pan = gesture else { return }
        let updated = gesture.updated(
            x: x, y: y, metrics: metrics, grid: viewport.grid,
            camera: viewport.camera, scale: viewport.scale)
        guard case .pan(let state) = updated else { return }
        if state.deltaX != 0 || state.deltaY != 0 {
            viewport.mutateCamera { camera in
                _ = camera.scrollByPx(-state.deltaX)
                _ = camera.scrollRollBy(-state.deltaY)
            }
        }
        self.gesture = updated
    }

    func endPanImpl() {
        guard case .pan = gesture else { return }
        gesture = nil
        if cursorKind != GridCursorKind.arrow.rawValue {
            cursorKind = GridCursorKind.arrow.rawValue
        }
        publishOutputs()
    }

    func updatePointerImpl(x: Double, y: Double, modifiers: Int = 0) {
        pointerModifiers = modifiers
        guard let gesture, !gesture.isRight else { return }
        if case .velocity(let state) = gesture, state.preview == nil,
            abs(y - state.pressY) < dragDistance
        {
            return
        }
        self.gesture = gesture.updated(
            x: x, y: y, metrics: metrics, grid: viewport.grid,
            camera: viewport.camera, scale: viewport.scale)
        let audition: (track: Int, pitch: Int, velocity: Int)?
        switch self.gesture {
        case .pendingDraw(let state):
            audition = (trackIndex, state.pressKey, min(127, max(1, lastVelocity)))
        case .draw(let state):
            audition = (trackIndex, state.key, min(127, max(1, lastVelocity)))
        case .move:
            if let note = session.document.note(NoteID(activeNoteId)) {
                let source = GridNote(
                    noteId: note.id, tick: Int(note.tick), duration: Int(note.duration),
                    pitch: Int(note.pitch), track: note.track,
                    velocity: Int(note.velocity), ghost: false)
                audition = (note.track, displayedNote(source).pitch, Int(note.velocity))
            } else {
                audition = nil
            }
        default:
            audition = nil
        }
        if let audition,
            audition.pitch != keyboardAuditionKey || audition.track != keyboardAuditionTrack
        {
            stopAudition()
            keyboardAuditionKey = audition.pitch
            keyboardAuditionTrack = audition.track
            onAudition?(audition.track, audition.pitch, audition.velocity)
        }
        if case .velocity(let state) = self.gesture {
            if let reanchor = pendingVelocityReanchor {
                pendingVelocityReanchor = nil
                session.setSelectedNotes([reanchor])
            } else if !session.selectedNotes.contains(state.noteId) {
                session.setSelectedNotes([state.noteId])
            }
            pendingControlToggle = nil
        }
        refreshNotes()
    }

    func endPointerImpl(x: Double, y: Double) {
        defer { suppressedLeftRelease = false }
        guard let gesture, !gesture.isRight else { return }
        if case .pendingDraw(let state) = gesture {
            if abs(x - state.pressX) >= drawThreshold {
                self.gesture = gesture.updated(
                    x: x, y: y, metrics: metrics, grid: viewport.grid,
                    camera: viewport.camera, scale: viewport.scale)
                if !suppressedLeftRelease { commitGesture() }
                stopAudition()
            } else {
                if case .band = rightGesture {
                    stopAudition()
                } else {
                    if let selection = session.timeSelection, selection.isActive,
                        session.timeSelectionCoversTrack(trackIndex),
                        selection.contains(Tick(max(0, Int(viewport.camera.tickAtContentX(x)))))
                    {
                        session.clearTimeSelection()
                    }
                    let tick = viewport.grid.snapTick(state.pressTick, camera: viewport.camera)
                    session.editCursor = Tick(tick)
                    editCursorTick = Int(tick)
                    onCommitCursor?(Tick(tick))
                    stopAudition()
                }
            }
        } else if case .velocity(let state) = gesture, state.preview == nil {
            // A stationary modifier press is a deferred selection click.
        } else {
            self.gesture = gesture.updated(
                x: x, y: y, metrics: metrics, grid: viewport.grid,
                camera: viewport.camera, scale: viewport.scale)
            if !suppressedLeftRelease { commitGesture() }
        }
        if let pendingControlToggle, !suppressedLeftRelease {
            switch self.gesture {
            case .move(let state) where state.dTick == 0 && state.dKey == 0:
                removeSelectedNoteFromLeftPointer(pendingControlToggle)
            case .resize(let state) where state.delta == 0:
                removeSelectedNoteFromLeftPointer(pendingControlToggle)
            case .velocity(let state) where state.preview == nil:
                removeSelectedNoteFromLeftPointer(pendingControlToggle)
            default:
                break
            }
        } else if case .velocity(let state) = self.gesture, state.preview == nil,
            !suppressedLeftRelease
        {
            addSelectedNoteFromLeftPointer(state.noteId)
        }
        pendingControlToggle = nil
        pendingVelocityReanchor = nil
        pointerModifiers = 0
        self.gesture = nil
        stopAudition()
        activeNoteId = 0
        refreshFromSession()
    }

    func beginRightPointerImpl(x: Double, y: Double, modifiers: Int) {
        guard rightGesture == nil else { return }
        if case .pan = gesture { return }
        rightPointerModifiers = modifiers
        selectionAtRightPress = session.selectedNoteOrder
        rightBandDemoted = false
        releaseBandAudition()
        let hit = hitNote(x: x, y: y)
        let blockedByLeft: Bool
        switch gesture {
        case nil, .pendingDraw: blockedByLeft = false
        case .velocity(let state): blockedByLeft = state.preview != nil
        default: blockedByLeft = true
        }
        rightGesture = .pendingMenu(
            GridGesture.PendingMenu(
                pressX: x, pressY: y, threshold: blockedByLeft ? .infinity : dragDistance,
                hitNoteId: hit.map { notes[$0.index].noteId } ?? NoteID()))
        publishOutputs()
    }

    func updateRightPointerImpl(x: Double, y: Double, modifiers: Int) {
        guard let rightGesture else { return }
        rightPointerModifiers = modifiers
        if !rightBandDemoted {
            let leftAllowsBand: Bool
            switch gesture {
            case nil, .pendingDraw: leftAllowsBand = true
            case .velocity(let state): leftAllowsBand = state.preview == nil
            default: leftAllowsBand = false
            }
            if leftAllowsBand {
                self.rightGesture = rightGesture.updated(
                    x: x, y: y, metrics: metrics, grid: viewport.grid,
                    camera: viewport.camera, scale: viewport.scale)
            }
        }
        if case .band = self.rightGesture { auditionBandEntrants() }
        refreshNotes()
    }

    func endRightPointerImpl(x: Double, y: Double, modifiers: Int) {
        guard let rightGesture else { return }
        rightPointerModifiers = modifiers
        if case .pendingDraw = gesture {
            // PendingDraw remains parked until its own release.
        } else if gesture != nil {
            pointerModifiers = 0
            gesture = nil
            suppressedLeftRelease = true
            pendingVelocityReanchor = nil
        }
        let updated =
            rightBandDemoted
            ? rightGesture
            : rightGesture.updated(
                x: x, y: y, metrics: metrics, grid: viewport.grid,
                camera: viewport.camera, scale: viewport.scale)
        self.rightGesture = updated
        if case .band = updated, !rightBandDemoted {
            applyBandSelection()
        } else if case .pendingMenu(let state) = updated {
            if state.hitNoteId.isAssigned {
                if !session.selectedNotes.contains(state.hitNoteId) {
                    session.setSelectedNotes([state.hitNoteId])
                    refreshNotes()
                }
                contextMenuRequested(x: x, y: y)
            } else {
                session.clearSelectedNotes()
                session.clearTimeSelection()
            }
        }
        self.rightGesture = nil
        if gesture == nil { activeNoteId = 0 }
        releaseBandAudition()
        pendingControlToggle = nil
        pendingVelocityReanchor = nil
        publishOutputs()
        refreshNotes()
    }

    func doublePointerImpl(x: Double, y: Double) {
        stopAudition()
        if let hit = hitNote(x: x, y: y) {
            gesture = nil
            let id = notes[hit.index].noteId
            let ids = session.selectedNotes.contains(id) ? session.selectedNoteOrder : [id]
            session.document.deleteNotes(ids)
            session.clearSelectedNotes()
            refreshFromSession()
            return
        }
        let key = pitch(atY: y)
        guard key >= 0, !viewport.scale.fold || viewport.scale.contains(key)
        else { return }
        session.clearSelectedNotes()
        let tick = viewport.grid.snapTickDown(
            viewport.camera.tickAtContentX(x),
            camera: viewport.camera)
        gesture = .draw(
            GridGesture.Draw(
                anchorTick: Int(tick), tick: Int(tick),
                duration: Int(viewport.grid.snapTicksAt(tick, camera: viewport.camera)), key: key))
        refreshNotes()
    }

    func beginKeyboardPointerImpl(y: Double) {
        let key = pitch(atY: y)
        guard (0...127).contains(key) else { return }
        session.setSelectedNotes(notes.filter { !$0.ghost && $0.pitch == key }.map(\.noteId))
        refreshNotes()
        updateKeyboardPointer(y: y)
    }

    func updateKeyboardPointerImpl(y: Double) {
        let key = pitch(atY: y)
        guard key >= 0, key <= 127, key != keyboardAuditionKey else { return }
        stopAudition()
        let track = trackIndex
        keyboardAuditionKey = key
        keyboardAuditionTrack = track
        onAudition?(track, key, 100)
        hoverKey = key
        scene.rebuildHover(sceneInput())
    }

    func endKeyboardPointerImpl() {
        stopAudition()
    }

    func inputCancelledImpl(reason: Int) {
        guard let reason = GridCancelReason(rawValue: reason) else { return }
        lastCancelReason = reason.rawValue
        cancelInput()
    }

    func finishKeyboardTransposeAuditionImpl() -> Bool {
        guard keyboardTransposeAuditionActive, keyboardAuditionKey != nil,
            keyboardAuditionTrack != nil
        else { return false }
        stopAudition()
        return true
    }
}
