import PorydawCore

// MARK: - Reducer state

/// The document-owned values sampled at the page boundary. The reducer never
/// reaches back into a session while deciding a transition.
struct VelocityDocumentFacts: Sendable {
    var revision: UInt64
    var selectedTrack: Int
    var notes: [Note]
    var orderedSelection: [NoteID]
    var source: VelocityContextSource
    var editCursor: Tick

    private var noteIndices: [NoteID: Int]
    private(set) var selectedIDSet: Set<NoteID>
    private var selectedNotesCache: [Note]

    init(revision: UInt64 = 0, selectedTrack: Int = -1, notes: [Note] = [],
         orderedSelection: [NoteID] = [], source: VelocityContextSource = .unresolved,
         editCursor: Tick = 0) {
        self.revision = revision
        self.selectedTrack = selectedTrack
        self.notes = notes
        self.orderedSelection = orderedSelection
        self.source = source
        self.editCursor = editCursor
        var indices: [NoteID: Int] = [:]
        indices.reserveCapacity(notes.count)
        for index in notes.indices { indices[notes[index].id] = index }
        noteIndices = indices
        selectedIDSet = Set(orderedSelection)
        selectedNotesCache = orderedSelection.compactMap { id in
            indices[id].map { notes[$0] }
        }
    }

    func note(_ id: NoteID) -> Note? {
        noteIndices[id].map { notes[$0] }
    }

    func selectedNotes() -> [Note] {
        selectedNotesCache
    }

    mutating func setOrderedSelection(_ ids: [NoteID]) {
        orderedSelection = ids
        selectedIDSet = Set(ids)
        selectedNotesCache.removeAll(keepingCapacity: true)
        selectedNotesCache.reserveCapacity(ids.count)
        for id in ids {
            if let index = noteIndices[id] { selectedNotesCache.append(notes[index]) }
        }
    }
}

struct VelocityBodyFacts: Sendable {
    var plotWidth: Double = 0
    var plotHeight: Double = 0
    var rulerWidth: Double = 0
    var devicePixelRatio: Double = 1
    var baseFontPx: Double = VelocityPagePolicy.seedBaseFontPx
    var dragDistance: Double = 10
    var geometry = VelocityNodeGeometry()
}

/// The common revision-bound capture used by relative and ramp edits, and by
/// the participant set of a paint sweep.
public struct VelocityEditGesture: Sendable {
    public var revision: UInt64
    public var track: Int
    public private(set) var notes: [VelocityFrozenNote]
    private var noteIndices: [NoteID: Int]
    var noteX: [NoteID: Double]

    public var axis: VelocityAxisModel
    public var detentUnlock: Bool
    public var activationDistance: Double
    public var relativeActivated = false
    public var pressX: Double
    public var pressY: Double
    public var previousX: Double
    public var previousY: Double
    public var preview: [NoteID: UInt8] = [:]
    var selectionBeforePress: [NoteID]
    var pressedNote: NoteID?
    var controlPress: Bool

    public init(revision: UInt64, track: Int, notes: [VelocityFrozenNote],
                axis: VelocityAxisModel, detentUnlock: Bool,
                activationDistance: Double, pressX: Double, pressY: Double,
                selectionBeforePress: [NoteID] = [], pressedNote: NoteID? = nil,
                controlPress: Bool = false, noteX: [NoteID: Double] = [:]) {
        self.revision = revision
        self.track = track
        self.notes = notes
        var indices: [NoteID: Int] = [:]
        indices.reserveCapacity(notes.count)
        for index in notes.indices { indices[notes[index].noteID] = index }
        noteIndices = indices
        self.noteX = noteX
        self.axis = axis
        self.detentUnlock = detentUnlock
        self.activationDistance = activationDistance
        self.pressX = pressX
        self.pressY = pressY
        previousX = pressX
        previousY = pressY
        self.selectionBeforePress = selectionBeforePress
        self.pressedNote = pressedNote
        self.controlPress = controlPress
    }

    public func frozenNote(_ id: NoteID) -> VelocityFrozenNote? {
        noteIndices[id].map { notes[$0] }
    }

    mutating func reserveParticipantCapacity(_ count: Int) {
        notes.reserveCapacity(count)
        noteIndices.reserveCapacity(count)
        noteX.reserveCapacity(count)
        preview.reserveCapacity(count)
    }

    public mutating func append(_ note: VelocityFrozenNote) {
        guard noteIndices[note.noteID] == nil else { return }
        noteIndices[note.noteID] = notes.count
        notes.append(note)
    }
}

struct VelocityPaintCandidate: Sendable {
    var note: VelocityFrozenNote
    var x: Double
}

public struct VelocityPaintGesture: Sendable {
    public var edit: VelocityEditGesture
    var candidates: [VelocityPaintCandidate]
}

public struct VelocityBandGesture: Sendable {
    public var revision: UInt64
    public var track: Int
    public var pressX: Double
    public var pressY: Double
    public var x: Double
    public var y: Double
    public var selectionBeforePress: [NoteID]
    public var pressedNote: NoteID?
    public var extendSelection: Bool
    public var preview: [NoteID] = []
}

public struct VelocityPanGesture: Sendable {
    public var revision: UInt64
    public var track: Int
    public var previousX: Double
    public var previousY: Double
    public var selectionBeforePress: [NoteID]
}

public enum VelocityGesture: Sendable {
    case relative(VelocityEditGesture)
    case paint(VelocityPaintGesture)
    case ramp(VelocityEditGesture)
    case pendingBand(VelocityBandGesture)
    case band(VelocityBandGesture)
    case pan(VelocityPanGesture)

    var edit: VelocityEditGesture? {
        switch self {
        case let .relative(value), let .ramp(value): value
        case let .paint(value): value.edit
        case .pendingBand, .band, .pan: nil
        }
    }

    var notes: [VelocityFrozenNote] { edit?.notes ?? [] }
    func frozenNote(_ id: NoteID) -> VelocityFrozenNote? { edit?.frozenNote(id) }
    var preview: [NoteID: UInt8] { edit?.preview ?? [:] }
    var detentUnlock: Bool { edit?.detentUnlock ?? false }
    var relativeActivated: Bool {
        if case let .relative(value) = self { return value.relativeActivated }
        return false
    }

    var selectionBeforePress: [NoteID] {
        switch self {
        case let .relative(value), let .ramp(value): value.selectionBeforePress
        case let .paint(value): value.edit.selectionBeforePress
        case let .pendingBand(value), let .band(value): value.selectionBeforePress
        case let .pan(value): value.selectionBeforePress
        }
    }

    var captureIdentity: (revision: UInt64, track: Int) {
        switch self {
        case let .relative(value), let .ramp(value): (value.revision, value.track)
        case let .paint(value): (value.edit.revision, value.edit.track)
        case let .pendingBand(value), let .band(value): (value.revision, value.track)
        case let .pan(value): (value.revision, value.track)
        }
    }
}

public enum VelocityMode: Sendable {
    case idle
    case gesture(VelocityGesture)
    case prompt(VelocityPromptState)

    mutating func takeGesture() -> VelocityGesture? {
        guard case let .gesture(gesture) = self else { return nil }
        self = .idle
        return gesture
    }
}

struct VelocityState: Sendable {
    var document = VelocityDocumentFacts()
    var camera: EditorCamera?
    var body = VelocityBodyFacts()
    var detentsEnabled = true
    var hovered: NoteID?
    var contextTick: Tick = 0
    var playing = false
    var presentedContext = VelocityVoiceContext(status: .unresolvedVoice)
    var lastPlayheadPublication: (tick: Tick, playing: Bool)?
    var playheadPresentationCount: UInt64 = 0
    var mode: VelocityMode = .idle

    var selectedNotes: [Note] { document.selectedNotes() }

    mutating func refreshPresentedContext() {
        let effectiveTick = playing ? contextTick : document.editCursor
        presentedContext = VelocityContextPolicy.presentation(
            selectedNotes: selectedNotes, effectiveTick: effectiveTick,
            resolve: document.source.resolver())
    }
}

// MARK: - Events, effects and transition result

enum VelocityEvent: Sendable {
    case pointer(surface: VelocityInputSurface?, input: DrawerPointerInput)
    case escape
    case cancel
    case body(width: Double, height: Double, rulerWidth: Double,
              devicePixelRatio: Double, baseFontPx: Double, dragDistance: Double)
    case document(VelocityDocumentFacts)
    case camera(EditorCamera?)
    case editCursor(Tick)
    case playhead(tick: Double, playing: Bool)
    case setDetents(Bool)
    case toggleDetents
    case openPrompt
    case promptDraft(String)
    case acceptPrompt
    case cancelPrompt
    case detach
}

enum VelocityEffect: Sendable {
    case setOrderedSelection([NoteID])
    case setVelocities([NoteVelocity], expectedRevision: UInt64)
    case panCamera(delta: Double)
    case notifyAcceptedVelocity(UInt8)
}

struct VelocityTransition: Sendable {
    var consumed = false
    var accepted = false
    var effects: [VelocityEffect] = []
    var publication: VelocityPublicationScope = []
}

// MARK: - Pure reducer

enum VelocityReducer {
    static func reduce(_ state: inout VelocityState, event: consuming VelocityEvent,
                       scene: borrowing VelocityScene) -> VelocityTransition {
        switch event {
        case let .pointer(surface, input):
            return reducePointer(&state, surface: surface, input: input, scene: scene)
        case .escape:
            guard case .idle = state.mode else {
                return cancelInteraction(&state, restoreSelection: true, consumed: true)
            }
            return VelocityTransition()
        case .cancel:
            return cancelInteraction(&state, restoreSelection: true, consumed: true)
        case let .body(width, height, rulerWidth, dpr, baseFontPx, dragDistance):
            let nextWidth = max(0, width.isFinite ? width : 0)
            let nextHeight = max(0, height.isFinite ? height : 0)
            let nextRuler = max(0, rulerWidth.isFinite ? rulerWidth : 0)
            let nextDpr = dpr.isFinite && dpr > 0 ? dpr : 1
            let nextFont = baseFontPx.isFinite && baseFontPx > 0
                ? baseFontPx : VelocityPagePolicy.seedBaseFontPx
            let nextDrag = dragDistance.isFinite && dragDistance > 0
                ? dragDistance : state.body.dragDistance
            let changed = nextWidth != state.body.plotWidth
                || nextHeight != state.body.plotHeight
                || nextRuler != state.body.rulerWidth
                || nextDpr != state.body.devicePixelRatio
                || nextFont != state.body.baseFontPx
                || nextDrag != state.body.dragDistance
            guard changed else { return VelocityTransition(consumed: true) }
            state.body = VelocityBodyFacts(
                plotWidth: nextWidth, plotHeight: nextHeight, rulerWidth: nextRuler,
                devicePixelRatio: nextDpr, baseFontPx: nextFont, dragDistance: nextDrag,
                geometry: VelocityNodeGeometry(baseFontPx: nextFont, devicePixelRatio: nextDpr))
            return VelocityTransition(consumed: true, publication: .content)
        case let .document(facts):
            var transition = VelocityTransition(consumed: true, publication: .content)
            if case let .gesture(gesture) = state.mode {
                let identity = gesture.captureIdentity
                if identity.revision != facts.revision || identity.track != facts.selectedTrack {
                    state.mode = .idle
                    transition.publication.formUnion([.interaction, .transient])
                }
            } else if case let .prompt(prompt) = state.mode,
                      prompt.revision != facts.revision || prompt.track != facts.selectedTrack {
                state.mode = .idle
                transition.publication.formUnion([.prompt, .interaction])
            }
            state.document = facts
            state.refreshPresentedContext()
            return transition
        case let .camera(camera):
            state.camera = camera
            return VelocityTransition(consumed: true, publication: .camera)
        case let .editCursor(tick):
            guard state.document.editCursor != tick else { return VelocityTransition(consumed: true) }
            let previous = VelocityContextKey(context: state.presentedContext, playing: state.playing)
            state.document.editCursor = tick
            if !state.playing { state.refreshPresentedContext() }
            let next = VelocityContextKey(context: state.presentedContext, playing: state.playing)
            return VelocityTransition(consumed: true,
                                      publication: previous == next ? [] : .content)
        case let .playhead(tick, playing):
            let resolvedTick = velocityContextTick(tick)
            if let last = state.lastPlayheadPublication,
               last.tick == resolvedTick, last.playing == playing {
                return VelocityTransition(consumed: true)
            }
            let previous = VelocityContextKey(context: state.presentedContext, playing: state.playing)
            let playingChanged = state.playing != playing
            state.lastPlayheadPublication = (resolvedTick, playing)
            state.playheadPresentationCount &+= 1
            state.contextTick = resolvedTick
            state.playing = playing
            state.refreshPresentedContext()
            let next = VelocityContextKey(context: state.presentedContext, playing: playing)
            return VelocityTransition(consumed: true,
                                      publication: previous != next || playingChanged
                                          ? .content : .readout)
        case let .setDetents(enabled):
            guard state.detentsEnabled != enabled else { return VelocityTransition(consumed: true) }
            var transition = cancelGesture(&state, restoreSelection: true)
            state.detentsEnabled = enabled
            transition.consumed = true
            transition.publication.formUnion(.axisAndHandles)
            return transition
        case .toggleDetents:
            return reduce(&state, event: .setDetents(!state.detentsEnabled), scene: scene)
        case .openPrompt:
            var transition = cancelGesture(&state, restoreSelection: true)
            let notes = state.selectedNotes
            guard state.document.selectedTrack >= 0, state.presentedContext.editable,
                  let first = notes.first else {
                transition.consumed = false
                return transition
            }
            let ids = notes.map(\.id)
            let before = notes.map(\.velocity)
            let initial = Int(first.velocity)
            state.mode = .prompt(VelocityPromptState(
                revision: state.document.revision, track: state.document.selectedTrack,
                noteIDs: ids, beforeValues: before, initialValue: initial,
                draft: String(initial)))
            transition.consumed = true
            transition.publication.formUnion([.prompt, .interaction, .handles, .readout])
            return transition
        case let .promptDraft(text):
            guard case var .prompt(prompt) = state.mode else { return VelocityTransition() }
            prompt.draft = String(text.prefix(4))
            prompt.error = VelocityPromptPolicy.error(draft: prompt.draft)
            state.mode = .prompt(prompt)
            return VelocityTransition(consumed: true, publication: .prompt)
        case .acceptPrompt:
            return acceptPrompt(&state)
        case .cancelPrompt:
            guard case .prompt = state.mode else { return VelocityTransition() }
            state.mode = .idle
            return VelocityTransition(consumed: true,
                                      publication: [.prompt, .interaction, .handles, .readout])
        case .detach:
            state = VelocityState()
            return VelocityTransition(consumed: true, publication: .clear)
        }
    }

    private static func reducePointer(_ state: inout VelocityState,
                                      surface: VelocityInputSurface?,
                                      input: borrowing DrawerPointerInput,
                                      scene: borrowing VelocityScene) -> VelocityTransition {
        switch input.phase {
        case .press:
            return pointerPress(&state, surface: surface, input: input, scene: scene)
        case .move:
            return pointerMove(&state, input: input, scene: scene)
        case .release:
            return pointerRelease(&state, input: input)
        case .leave:
            let changed = state.hovered != nil
            state.hovered = nil
            guard changed, case .idle = state.mode else { return VelocityTransition(consumed: true) }
            return VelocityTransition(consumed: true, publication: .axisAndHandles)
        }
    }

    private static func pointerPress(_ state: inout VelocityState,
                                     surface: VelocityInputSurface?,
                                     input: borrowing DrawerPointerInput,
                                     scene: borrowing VelocityScene) -> VelocityTransition {
        guard state.document.selectedTrack >= 0, let surface else { return VelocityTransition() }
        switch input.changedButton {
        case .primary, .secondary, .middle:
            break
        case .none, .other:
            return VelocityTransition()
        }
        var transition = cancelInteraction(&state, restoreSelection: true, consumed: false)
        let selectionAtPress = state.document.orderedSelection

        switch surface {
        case .ruler:
            guard input.changedButton == .primary,
                  scene.axis.inRuler(x: input.x, rulerWidth: state.body.rulerWidth)
            else { return transition }
            transition.consumed = true
            guard state.presentedContext.editable else { return transition }
            let unlock = detentsUnlocked(state, modifiers: input.modifiers, allowShift: false)
            let velocity = unlock
                ? Int(clampVelocity(scene.axis.yToVelocity(input.y)))
                : scene.axis.rulerVelocityAt(y: input.y,
                                             labelHeight: scene.axis.geometry.labelHeight)
            guard velocity >= VelocityPromptPolicy.minimum else { return transition }
            let frozen = freeze(state.selectedNotes, source: state.document.source)
            var edit = makeEdit(state, notes: frozen, axis: scene.axis,
                                detentUnlock: unlock, input: input,
                                selectionBeforePress: selectionAtPress)
            edit.preview.reserveCapacity(edit.notes.count)
            for note in edit.notes { edit.preview[note.noteID] = UInt8(velocity) }
            let updates = VelocityGesturePolicy.updates(edit)
            if !updates.isEmpty {
                transition.effects.append(.setVelocities(updates,
                                                         expectedRevision: edit.revision))
            }
            return transition

        case .plot:
            switch input.changedButton {
            case .middle:
                state.mode = .gesture(.pan(VelocityPanGesture(
                    revision: state.document.revision, track: state.document.selectedTrack,
                    previousX: input.x, previousY: input.y,
                    selectionBeforePress: selectionAtPress)))
                transition.consumed = true
                transition.publication.formUnion(.interaction)
                return transition
            case .secondary:
                let hit = hitTest(input, scene: scene, includeStems: true)
                if let hit, !input.modifiers.control, !selectionAtPress.contains(hit) {
                    setSelection(&state, [hit], transition: &transition)
                }
                state.mode = .gesture(.pendingBand(VelocityBandGesture(
                    revision: state.document.revision, track: state.document.selectedTrack,
                    pressX: input.x, pressY: input.y, x: input.x, y: input.y,
                    selectionBeforePress: selectionAtPress, pressedNote: hit,
                    extendSelection: input.modifiers.control)))
                transition.consumed = true
                transition.publication.formUnion([.interaction, .handles, .readout])
                return transition
            case .primary:
                return primaryPlotPress(&state, input: input, scene: scene,
                                        selectionAtPress: selectionAtPress,
                                        transition: transition)
            case .none, .other:
                return transition
            }
        }
    }

    private static func primaryPlotPress(_ state: inout VelocityState,
                                         input: borrowing DrawerPointerInput,
                                         scene: borrowing VelocityScene,
                                         selectionAtPress: [NoteID],
                                         transition initial: consuming VelocityTransition)
        -> VelocityTransition {
        var transition = initial
        let unlock = detentsUnlocked(state, modifiers: input.modifiers, allowShift: true)
        if input.modifiers.shift {
            transition.consumed = true
            guard state.presentedContext.editable else { return transition }
            let notes = state.selectedNotes
            var noteX: [NoteID: Double] = [:]
            noteX.reserveCapacity(notes.count)
            for handle in scene.handles where state.document.orderedSelection.contains(handle.noteID) {
                noteX[handle.noteID] = handle.x
            }
            var edit = makeEdit(state, notes: freeze(notes, source: state.document.source),
                                axis: scene.axis, detentUnlock: unlock, input: input,
                                selectionBeforePress: selectionAtPress, noteX: noteX)
            VelocityGesturePolicy.applyRamp(&edit, x: input.x, y: input.y,
                                             hitRadius: state.body.geometry.hitRadius) {
                noteX[$0.noteID] ?? input.x
            }
            state.mode = .gesture(.ramp(edit))
            transition.publication.formUnion([.interaction, .handles, .transient, .readout])
            return transition
        }

        let hit = hitTest(input, scene: scene, includeStems: true)
        if hit == nil {
            transition.consumed = true
            guard state.presentedContext.editable else { return transition }
            var candidates: [VelocityPaintCandidate] = []
            candidates.reserveCapacity(selectionAtPress.count)
            for id in selectionAtPress {
                guard let note = state.document.note(id),
                      let handle = scene.handles.first(where: { $0.noteID == id }) else { continue }
                candidates.append(VelocityPaintCandidate(
                    note: freeze(note, source: state.document.source), x: handle.x))
            }
            var paint = VelocityPaintGesture(
                edit: makeEdit(state, notes: [], axis: scene.axis,
                               detentUnlock: unlock, input: input,
                               selectionBeforePress: selectionAtPress),
                candidates: candidates)
            paint.edit.reserveParticipantCapacity(candidates.count)
            VelocityGesturePolicy.applyPaint(
                &paint, from: (input.x, input.y), to: (input.x, input.y),
                hitRadius: state.body.geometry.hitRadius)
            state.mode = .gesture(.paint(paint))
            transition.publication.formUnion([.interaction, .handles, .readout])
            return transition
        }

        if input.modifiers.control {
            var selection = selectionAtPress
            if let hit, !selection.contains(hit) { selection.append(hit) }
            setSelection(&state, selection, transition: &transition)
        } else if let hit, !selectionAtPress.contains(hit) {
            setSelection(&state, [hit], transition: &transition)
        }
        transition.consumed = true
        guard state.presentedContext.editable else { return transition }

        // Selection is state immediately, so both context and active values are
        // re-derived before this revision-bound edit is frozen.
        state.refreshPresentedContext()
        let axis = axisForCurrentSelection(state, geometry: scene.axis.geometry)
        let edit = makeEdit(
            state, notes: freeze(state.selectedNotes, source: state.document.source),
            axis: axis, detentUnlock: unlock, input: input,
            selectionBeforePress: selectionAtPress, pressedNote: hit,
            controlPress: input.modifiers.control)
        state.mode = .gesture(.relative(edit))
        transition.publication.formUnion([.interaction, .handles, .readout])
        return transition
    }

    private static func pointerMove(_ state: inout VelocityState,
                                    input: borrowing DrawerPointerInput,
                                    scene: borrowing VelocityScene) -> VelocityTransition {
        guard state.document.selectedTrack >= 0 else { return VelocityTransition() }
        guard let gesture = state.mode.takeGesture() else {
            let hit = hitTest(input, scene: scene, includeStems: false)
            guard hit != state.hovered else { return VelocityTransition(consumed: true) }
            state.hovered = hit
            state.refreshPresentedContext()
            return VelocityTransition(consumed: true, publication: .axisAndHandles)
        }

        switch gesture {
        case var .relative(edit):
            edit.previousX = input.x
            edit.previousY = input.y
            VelocityGesturePolicy.applyRelative(&edit, y: input.y)
            state.mode = .gesture(.relative(edit))
            return VelocityTransition(consumed: true, publication: .handlesAndReadout)
        case var .paint(paint):
            let previous = (paint.edit.previousX, paint.edit.previousY)
            VelocityGesturePolicy.applyPaint(
                &paint, from: previous, to: (input.x, input.y),
                hitRadius: state.body.geometry.hitRadius)
            paint.edit.previousX = input.x
            paint.edit.previousY = input.y
            state.mode = .gesture(.paint(paint))
            return VelocityTransition(consumed: true, publication: .handlesAndReadout)
        case var .ramp(edit):
            let noteX = edit.noteX
            VelocityGesturePolicy.applyRamp(&edit, x: input.x, y: input.y,
                                             hitRadius: state.body.geometry.hitRadius) {
                noteX[$0.noteID] ?? input.x
            }
            edit.previousX = input.x
            edit.previousY = input.y
            state.mode = .gesture(.ramp(edit))
            return VelocityTransition(consumed: true,
                                      publication: [.handles, .transient, .readout])
        case var .pendingBand(band):
            guard abs(input.x - band.pressX) + abs(input.y - band.pressY)
                    >= state.body.dragDistance else {
                state.mode = .gesture(.pendingBand(band))
                return VelocityTransition(consumed: true)
            }
            updateBand(&band, x: input.x, y: input.y, scene: scene)
            state.mode = .gesture(.band(band))
            return VelocityTransition(consumed: true,
                                      publication: [.handles, .transient, .readout])
        case var .band(band):
            updateBand(&band, x: input.x, y: input.y, scene: scene)
            state.mode = .gesture(.band(band))
            return VelocityTransition(consumed: true,
                                      publication: [.handles, .transient, .readout])
        case var .pan(pan):
            let delta = input.x - pan.previousX
            pan.previousX = input.x
            pan.previousY = input.y
            state.mode = .gesture(.pan(pan))
            var transition = VelocityTransition(consumed: true)
            if delta != 0 { transition.effects.append(.panCamera(delta: delta)) }
            return transition
        }
    }

    private static func pointerRelease(_ state: inout VelocityState,
                                       input: borrowing DrawerPointerInput) -> VelocityTransition {
        guard state.document.selectedTrack >= 0,
              case let .gesture(gesture) = state.mode else { return VelocityTransition() }
        if input.changedButton == .middle {
            guard case .pan = gesture else { return VelocityTransition() }
            state.mode = .idle
            return endGestureTransition()
        }
        if input.changedButton == .secondary {
            var transition = endGestureTransition()
            switch gesture {
            case let .band(band):
                var selection = band.extendSelection ? band.selectionBeforePress : []
                selection.reserveCapacity(selection.count + band.preview.count)
                for id in band.preview where !selection.contains(id) { selection.append(id) }
                setSelection(&state, selection, transition: &transition)
            case let .pendingBand(band):
                var selection = band.selectionBeforePress
                if let pressed = band.pressedNote {
                    if band.extendSelection {
                        if let index = selection.firstIndex(of: pressed) {
                            selection.remove(at: index)
                        } else {
                            selection.append(pressed)
                        }
                    } else if !selection.contains(pressed) {
                        selection = [pressed]
                    }
                } else if !band.extendSelection {
                    selection = []
                }
                setSelection(&state, selection, transition: &transition)
            case .relative, .paint, .ramp, .pan:
                return VelocityTransition()
            }
            state.mode = .idle
            return transition
        }
        guard input.changedButton == .primary else {
            return VelocityTransition()
        }
        switch gesture {
        case .relative, .paint, .ramp:
            break
        case .pendingBand, .band, .pan:
            return VelocityTransition()
        }


        var transition = endGestureTransition()
        switch gesture {
        case let .paint(paint):
            let updates = VelocityGesturePolicy.updates(paint.edit)
            if paint.edit.notes.isEmpty || paint.edit.preview.isEmpty {
                setSelection(&state, [], transition: &transition)
            } else if !updates.isEmpty {
                transition.effects.append(.setVelocities(
                    updates, expectedRevision: paint.edit.revision))
            }
        case let .ramp(edit):
            if edit.previousX != edit.pressX || edit.previousY != edit.pressY {
                let updates = VelocityGesturePolicy.updates(edit)
                if !updates.isEmpty {
                    transition.effects.append(.setVelocities(
                        updates, expectedRevision: edit.revision))
                }
            }
        case let .relative(edit):
            if edit.relativeActivated {
                let updates = VelocityGesturePolicy.updates(edit)
                if !updates.isEmpty {
                    transition.effects.append(.setVelocities(
                        updates, expectedRevision: edit.revision))
                }
            } else if edit.controlPress {
                var selection = edit.selectionBeforePress
                if let pressed = edit.pressedNote {
                    if let index = selection.firstIndex(of: pressed) {
                        selection.remove(at: index)
                    } else {
                        selection.append(pressed)
                    }
                }
                setSelection(&state, selection, transition: &transition)
            } else if let pressed = edit.pressedNote {
                setSelection(&state, [pressed], transition: &transition)
            } else {
                setSelection(&state, [], transition: &transition)
            }
        case .pendingBand, .band, .pan:
            break
        }
        state.mode = .idle
        return transition
    }

    private static func acceptPrompt(_ state: inout VelocityState) -> VelocityTransition {
        guard case let .prompt(prompt) = state.mode else { return VelocityTransition() }
        guard let value = VelocityPromptPolicy.value(draft: prompt.draft) else {
            var next = prompt
            next.error = VelocityPromptPolicy.error(draft: prompt.draft)
            state.mode = .prompt(next)
            return VelocityTransition(publication: .prompt)
        }
        state.mode = .idle
        var transition = VelocityTransition(publication: [.prompt, .interaction, .handles, .readout])
        guard prompt.revision == state.document.revision,
              prompt.track == state.document.selectedTrack,
              !prompt.noteIDs.isEmpty,
              prompt.noteIDs.allSatisfy({ state.document.note($0) != nil })
        else { return transition }

        var updates: [NoteVelocity] = []
        updates.reserveCapacity(prompt.noteIDs.count)
        for (index, id) in prompt.noteIDs.enumerated()
            where index >= prompt.beforeValues.count || prompt.beforeValues[index] != UInt8(value) {
            updates.append(NoteVelocity(noteID: id, velocity: value))
        }
        if !updates.isEmpty {
            transition.effects.append(.setVelocities(updates, expectedRevision: prompt.revision))
        }
        transition.effects.append(.notifyAcceptedVelocity(UInt8(value)))
        transition.accepted = true
        return transition
    }

    private static func makeEdit(_ state: borrowing VelocityState,
                                 notes: consuming [VelocityFrozenNote],
                                 axis: VelocityAxisModel, detentUnlock: Bool,
                                 input: borrowing DrawerPointerInput,
                                 selectionBeforePress: [NoteID], pressedNote: NoteID? = nil,
                                 controlPress: Bool = false,
                                 noteX: [NoteID: Double] = [:]) -> VelocityEditGesture {
        VelocityEditGesture(
            revision: state.document.revision, track: state.document.selectedTrack,
            notes: notes, axis: axis, detentUnlock: detentUnlock,
            activationDistance: state.body.geometry.dragActivationDistance,
            pressX: input.x, pressY: input.y,
            selectionBeforePress: selectionBeforePress, pressedNote: pressedNote,
            controlPress: controlPress, noteX: noteX)
    }

    private static func freeze(_ notes: borrowing [Note],
                               source: borrowing VelocityContextSource) -> [VelocityFrozenNote] {
        var frozen: [VelocityFrozenNote] = []
        frozen.reserveCapacity(notes.count)
        for index in notes.indices {
            frozen.append(freeze(notes[index], source: source))
        }
        return frozen
    }

    private static func freeze(_ note: borrowing Note,
                               source: borrowing VelocityContextSource) -> VelocityFrozenNote {
        VelocityFrozenNote(noteID: note.id, tick: note.tick, duration: note.duration,
                           pitch: note.pitch, velocity: note.velocity,
                           map: source.map(at: note.tick, key: Int(note.pitch)),
                           exactOrigin: note.velocity)
    }

    private static func axisForCurrentSelection(_ state: borrowing VelocityState,
                                                geometry: VelocityAxisGeometry)
        -> VelocityAxisModel {
        VelocityAxisModel(map: state.presentedContext.map, geometry: geometry,
                          activeValues: state.selectedNotes.map(\.velocity))
    }

    private static func hitTest(_ input: borrowing DrawerPointerInput,
                                scene: borrowing VelocityScene,
                                includeStems: Bool) -> NoteID? {
        var best: NoteID?
        var bestCircle = false
        var bestSelected = false
        var bestDistance = 0.0
        var bestOrder = 0
        for (order, handle) in scene.handles.enumerated() {
            let dx = handle.x - input.x
            let dy = handle.y - input.y
            let distance = dx * dx + dy * dy
            let circleHit = distance <= handle.hitRadius * handle.hitRadius
            let stemHit = includeStems
                && input.x >= handle.x - scene.geometry.durationLineHorizontalSlop
                && input.x <= handle.endX + scene.geometry.durationLineHorizontalSlop
                && abs(input.y - handle.y) <= scene.geometry.durationLineVerticalRadius
            if circleHit || stemHit {
                let better = best == nil
                    || (circleHit && !bestCircle)
                    || (circleHit == bestCircle && handle.selected && !bestSelected)
                    || (circleHit == bestCircle && handle.selected == bestSelected
                        && (distance < bestDistance
                            || (distance == bestDistance && order > bestOrder)))
                if better {
                    best = handle.noteID
                    bestCircle = circleHit
                    bestSelected = handle.selected
                    bestDistance = distance
                    bestOrder = order
                }
            }
        }
        return best
    }

    private static func updateBand(_ band: inout VelocityBandGesture, x: Double, y: Double,
                                   scene: borrowing VelocityScene) {
        band.x = x
        band.y = y
        let minX = min(band.pressX, x)
        let maxX = max(band.pressX, x)
        let minY = min(band.pressY, y)
        let maxY = max(band.pressY, y)
        band.preview.removeAll(keepingCapacity: true)
        band.preview.reserveCapacity(scene.handles.count)
        for handle in scene.handles {
            let diameter = 2 * handle.hitRadius
            let x0 = handle.x - handle.hitRadius
            let y0 = handle.y - handle.hitRadius
            if x0 + diameter >= minX, x0 <= maxX,
               y0 + diameter >= minY, y0 <= maxY {
                band.preview.append(handle.noteID)
            }
        }
    }

    private static func detentsUnlocked(_ state: borrowing VelocityState,
                                        modifiers: DrawerModifiers,
                                        allowShift: Bool) -> Bool {
        !state.detentsEnabled
            || modifiers.isExact(control: true)
            || (allowShift && modifiers.isExact(shift: true, control: true))
    }

    private static func setSelection(_ state: inout VelocityState, _ ids: [NoteID],
                                     transition: inout VelocityTransition) {
        guard ids != state.document.orderedSelection else { return }
        state.document.setOrderedSelection(ids)
        state.refreshPresentedContext()
        transition.effects.append(.setOrderedSelection(ids))
        transition.publication.formUnion(.content)
    }

    private static func cancelInteraction(_ state: inout VelocityState,
                                          restoreSelection: Bool,
                                          consumed: Bool) -> VelocityTransition {
        switch state.mode {
        case .idle:
            return VelocityTransition(consumed: consumed)
        case .prompt:
            state.mode = .idle
            return VelocityTransition(consumed: consumed,
                                      publication: [.prompt, .interaction, .handles, .readout])
        case .gesture:
            var transition = cancelGesture(&state, restoreSelection: restoreSelection)
            transition.consumed = consumed
            return transition
        }
    }

    private static func cancelGesture(_ state: inout VelocityState,
                                      restoreSelection: Bool) -> VelocityTransition {
        guard case let .gesture(gesture) = state.mode else { return VelocityTransition() }
        state.mode = .idle
        var transition = endGestureTransition()
        if restoreSelection {
            setSelection(&state, gesture.selectionBeforePress, transition: &transition)
        }
        return transition
    }

    private static func endGestureTransition() -> VelocityTransition {
        VelocityTransition(consumed: true,
                           publication: [.interaction, .handles, .transient, .readout])
    }
}
