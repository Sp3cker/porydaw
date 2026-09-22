import PorydawCore

// MARK: - State facts

struct VoiceLaneFacts: Sendable {
    var revision: UInt64 = 0
    var track: Int?
    var points: [LanePoint] = []
    var firstProgram: Int = -1
    var lengthTicks: Tick = 0
    var division: Int = 24
    var extendedClocks = false
}

struct VoiceViewFacts: Sendable {
    var plotOrigin: Double
    var plotWidth: Double
    var plotHeight: Double
    var devicePixelRatio: Double
    var baseFontPx: Double
    var dragDistance: Double
    var camera: EditorCamera
    var metrics: GridMetrics
}

struct VoiceTarget: Equatable, Sendable {
    var revision: UInt64
    var track: Int
    var tick: Tick
    var occurrence: VoiceOccurrence?
}

struct VoiceDragState: Equatable, Sendable {
    var revision: UInt64
    var track: Int
    var occurrence: VoiceOccurrence
    var identity: String
    var pressX: Double
    var previewTick: Tick
}

struct VoicePickerState: Equatable, Sendable {
    var target: VoiceTarget
    var filter = ""
    var program = -1

    var title: String { target.occurrence == nil ? "Insert voice change" : "Change voice" }
}

struct VoiceMenuState: Equatable, Sendable {
    var target: VoiceTarget
    var anchorX: Double
    var anchorY: Double
}

enum VoicePointerMode: Sendable {
    case idle
    case pendingDrag(VoiceDragState)
    case drag(VoiceDragState)
    case pan(revision: UInt64, previousX: Double)

    var drag: VoiceDragState? {
        switch self {
        case let .pendingDrag(value), let .drag(value):
            return value
        default:
            return nil
        }
    }

    var activeDrag: VoiceDragState? {
        if case let .drag(value) = self { return value }
        return nil
    }

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
}

enum VoiceModalMode: Sendable {
    case none
    case picker(VoicePickerState)
    case menu(VoiceMenuState)

    var picker: VoicePickerState? {
        if case let .picker(value) = self { return value }
        return nil
    }

    var menu: VoiceMenuState? {
        if case let .menu(value) = self { return value }
        return nil
    }

    var isOpen: Bool {
        if case .none = self { return false }
        return true
    }
}

struct VoicePresentationKey: Equatable, Sendable {
    var tick: Tick
    var playing: Bool
}

/// The complete synchronous interaction state. Document, bank and view owners
/// remain outside; this value only stores their latest facts.
struct VoiceChangesState: Sendable {
    var attached = false
    var lane = VoiceLaneFacts()
    var bank: [BankSlotView] = []
    var view: VoiceViewFacts?
    var editCursor: Tick = 0
    var presentedTick: Tick = 0
    var playing = false
    var contextSlot = -1
    var lastPresentation: VoicePresentationKey?
    var presentationCount: UInt64 = 0
    var contextChangeCount: UInt64 = 0

    var selectedOccurrence: VoiceOccurrence?
    var hoveredOccurrence: VoiceOccurrence?
    var hoverTick: Tick = 0
    var hoverLabel = ""
    var pointerMode: VoicePointerMode = .idle
    var modalMode: VoiceModalMode = .none
    var auditionedProgram: Int?

    var interactionActive: Bool { !pointerMode.isIdle || modalMode.isOpen }
    var effectiveContextTick: Tick { playing ? presentedTick : editCursor }
}

// MARK: - Typed input and output

struct VoicePointerPress: Sendable {
    var x: Double
    var y: Double
    var surface: VoiceInputSurface
    var button: DrawerPointerButton
    var target: VoiceTarget?
}

struct VoicePointerMove: Sendable {
    var x: Double
    var hit: VoiceOccurrence?
    var snappedTick: Tick
}

struct VoicePointerRelease: Sendable {
    var button: DrawerPointerButton
    var hit: VoiceOccurrence?
}

struct VoicePointerDoubleClick: Sendable {
    var target: VoiceTarget?
    var bank: [BankSlotView]
}

enum VoiceChangesEvent: Sendable {
    case attached(lane: VoiceLaneFacts, bank: [BankSlotView], view: VoiceViewFacts,
                  editCursor: Tick)
    case detached
    case documentChanged(lane: VoiceLaneFacts, bank: [BankSlotView], view: VoiceViewFacts,
                         editCursor: Tick)
    case viewChanged(VoiceViewFacts)
    case editCursorChanged(Tick)
    case playheadChanged(tick: Tick, playing: Bool)
    case escape
    case cancelAll
    case pointerPressed(VoicePointerPress)
    case pointerMoved(VoicePointerMove)
    case pointerReleased(VoicePointerRelease)
    case pointerLeft
    case pointerDoubleClicked(VoicePointerDoubleClick)
    case pickerFilterChanged(String)
    case pickerRowSelected(Int)
    case pickerRowHeld(Int)
    case pickerAuditionReleased
    case pickerSelectionMoved(Int)
    case pickerAccepted
    case pickerCancelled
    case menuActionActivated(Int)
    case menuDismissed
    case modalDismissed
    case auditionOwnerWillChange
}

enum VoiceChangesEffect: Sendable {
    case mutateCamera(deltaX: Double)
    case commit(VoiceLaneMutation)
    case audition(program: Int, key: Int, velocity: Int)
}

struct VoiceChangesOutcome: Sendable {
    var consumed = false
    var accepted = false
    var committed = false

    static let ignored = Self()
    static let handled = Self(consumed: true)
}

struct VoiceChangesTransition: Sendable {
    var state: VoiceChangesState
    var effects: [VoiceChangesEffect]
    var publication: VoiceChangesPublicationScope
    var outcome: VoiceChangesOutcome
}

// MARK: - Pure reducer

enum VoiceChangesInteraction {
    static func reduce(_ state: VoiceChangesState,
                       event: consuming VoiceChangesEvent) -> VoiceChangesTransition {
        var next = state
        var effects: [VoiceChangesEffect] = []
        var publication: VoiceChangesPublicationScope = []
        var outcome = VoiceChangesOutcome.ignored

        switch event {
        case let .attached(lane, bank, view, editCursor):
            stopAudition(&next, effects: &effects)
            let presentations = next.presentationCount
            let changes = next.contextChangeCount
            next = VoiceChangesState(
                attached: true, lane: lane, bank: bank, view: view,
                editCursor: editCursor, presentedTick: editCursor,
                contextSlot: contextSlot(lane: lane, tick: editCursor),
                presentationCount: presentations, contextChangeCount: changes)
            publication = [.content, .typography, .modal, .interaction]

        case .detached:
            stopAudition(&next, effects: &effects)
            let presentations = next.presentationCount
            let changes = next.contextChangeCount
            next = VoiceChangesState(
                presentationCount: presentations, contextChangeCount: changes)
            publication = .clear

        case let .documentChanged(lane, bank, view, editCursor):
            guard next.attached else { break }
            let revisionChanged = next.lane.revision != lane.revision
            let bankChanged = next.bank != bank
            let laneChanged = next.lane.track != lane.track
                || next.lane.points != lane.points
                || next.lane.firstProgram != lane.firstProgram
                || next.lane.lengthTicks != lane.lengthTicks
                || next.lane.division != lane.division
                || next.lane.extendedClocks != lane.extendedClocks
            let bankOnlyRevision = revisionChanged && bankChanged && !laneChanged
            let captureInvalidated = laneChanged || (revisionChanged && !bankOnlyRevision)
            if bankChanged || (captureInvalidated && next.modalMode.isOpen) {
                stopAudition(&next, effects: &effects)
            }
            next.lane = lane
            next.view = view
            next.bank = bank
            next.editCursor = editCursor
            if captureInvalidated {
                next.pointerMode = .idle
                next.modalMode = .none
                next.hoveredOccurrence = nil
                next.hoverTick = 0
                next.hoverLabel = ""
            } else {
                switch next.modalMode {
                case var .picker(picker):
                    if bankOnlyRevision { picker.target.revision = lane.revision }
                    let programs = visiblePrograms(bank: bank, filter: picker.filter)
                    if !programs.contains(picker.program) {
                        picker.program = programs.first ?? -1
                    }
                    next.modalMode = .picker(picker)
                case var .menu(menu):
                    if bankOnlyRevision { menu.target.revision = lane.revision }
                    next.modalMode = .menu(menu)
                case .none:
                    break
                }
            }
            if let selected = next.selectedOccurrence {
                next.selectedOccurrence = VoiceLanePolicy.occurrence(selected, in: lane.points)
            }
            next.contextSlot = contextSlot(lane: lane, tick: next.effectiveContextTick)
            publication = [.content, .typography, .modal, .interaction, .hover, .transient]

        case let .viewChanged(view):
            guard next.attached else { break }
            let projectionOnly = next.view.map {
                $0.plotOrigin == view.plotOrigin && $0.plotWidth == view.plotWidth
                    && $0.plotHeight == view.plotHeight
                    && $0.devicePixelRatio == view.devicePixelRatio
                    && $0.baseFontPx == view.baseFontPx
                    && $0.dragDistance == view.dragDistance
            } ?? false
            let fontChanged = next.view?.baseFontPx != view.baseFontPx
            next.view = view
            publication = projectionOnly
                ? .projection
                : fontChanged ? [.content, .typography] : .content
        case let .editCursorChanged(tick):
            guard next.attached else { break }
            next.editCursor = tick
            guard !next.playing else { break }
            let slot = contextSlot(lane: next.lane, tick: tick)
            if slot != next.contextSlot {
                next.contextChangeCount &+= 1
                next.contextSlot = slot
            }
            publication = .readout

        case let .playheadChanged(tick, playing):
            guard next.attached else { break }
            let key = VoicePresentationKey(tick: tick, playing: playing)
            guard next.lastPresentation != key else { break }
            next.lastPresentation = key
            next.presentationCount &+= 1
            let playingChanged = next.playing != playing
            next.playing = playing
            next.presentedTick = tick
            let slot = contextSlot(lane: next.lane, tick: next.effectiveContextTick)
            let contextChanged = next.contextSlot != slot
            next.contextSlot = slot
            if contextChanged || playingChanged {
                next.contextChangeCount &+= 1
                publication = .content
            } else {
                publication = .readout
            }

        case .escape:
            if next.modalMode.isOpen {
                stopAudition(&next, effects: &effects)
                next.modalMode = .none
                publication = [.modal, .interaction]
                outcome = .handled
            } else if !next.pointerMode.isIdle {
                next.pointerMode = .idle
                publication = [.markers, .transient, .interaction]
                outcome = .handled
            } else if next.hoveredOccurrence != nil || !next.hoverLabel.isEmpty {
                clearHover(&next)
                publication = [.markers, .hover]
                outcome = .handled
            }

        case .cancelAll:
            stopAudition(&next, effects: &effects)
            next.pointerMode = .idle
            next.modalMode = .none
            clearHover(&next)
            publication = [.markers, .hover, .transient, .modal, .interaction]

        case let .pointerPressed(input):
            guard next.attached else { break }
            if next.modalMode.isOpen {
                stopAudition(&next, effects: &effects)
                next.modalMode = .none
                publication = [.modal, .interaction]
                outcome = .handled
                break
            }
            if input.surface == .gutter {
                let markerChanged = clearHover(&next)
                publication = markerChanged ? [.markers, .hover] : .hover
                break
            }
            clearHover(&next)
            switch input.button {
            case .secondary:
                if let target = input.target {
                    next.modalMode = .menu(VoiceMenuState(
                        target: target, anchorX: input.x, anchorY: max(0, input.y)))
                }
                publication = [.markers, .hover, .modal, .interaction]
                outcome = .handled
            case .middle:
                next.pointerMode = .pan(revision: next.lane.revision, previousX: input.x)
                publication = [.markers, .hover, .interaction]
                outcome = .handled
            case .primary:
                if let target = input.target, let occurrence = target.occurrence {
                    next.selectedOccurrence = occurrence
                    let drag = VoiceDragState(
                        revision: target.revision, track: target.track,
                        occurrence: occurrence, identity: occurrence.text,
                        pressX: input.x, previewTick: occurrence.tick)
                    next.pointerMode = .pendingDrag(drag)
                } else {
                    next.selectedOccurrence = nil
                    next.pointerMode = .idle
                }
                publication = [.markers, .hover, .interaction]
                outcome = .handled
            default:
                break
            }

        case let .pointerMoved(input):
            guard next.attached else { break }
            switch next.pointerMode {
            case var .pendingDrag(drag):
                outcome = .handled
                guard let distance = next.view?.dragDistance,
                      abs(input.x - drag.pressX) >= distance else { break }
                drag.previewTick = input.snappedTick
                next.pointerMode = .drag(drag)
                clearHover(&next)
                publication = [.markers, .hover, .transient, .interaction]
            case var .drag(drag):
                outcome = .handled
                guard drag.previewTick != input.snappedTick else { break }
                drag.previewTick = input.snappedTick
                next.pointerMode = .drag(drag)
                publication = [.markers, .transient]
            case let .pan(revision, previousX):
                let delta = input.x - previousX
                next.pointerMode = .pan(revision: revision, previousX: input.x)
                if delta != 0 { effects.append(.mutateCamera(deltaX: delta)) }
                outcome = .handled
            case .idle:
                let markerChanged = applyHover(
                    &next, hit: input.hit, snappedTick: input.snappedTick)
                publication = markerChanged ? [.markers, .hover] : .hover
                outcome = .handled
            }

        case let .pointerReleased(input):
            switch (input.button, next.pointerMode) {
            case (.middle, .pan):
                next.pointerMode = .idle
                next.hoveredOccurrence = input.hit
                next.hoverTick = input.hit?.tick ?? 0
                publication = [.markers, .hover, .interaction]
                outcome = .handled
            case (.primary, .pendingDrag):
                next.pointerMode = .idle
                publication = [.markers, .transient, .interaction]
                outcome = .handled
            case let (.primary, .drag(drag)):
                next.pointerMode = .idle
                let mutation = VoiceChangesTransactions.move(
                    drag, revision: next.lane.revision, track: next.lane.track ?? -1,
                    points: next.lane.points)
                if let mutation { effects.append(.commit(mutation)) }
                publication = [.markers, .transient, .interaction]
                outcome = VoiceChangesOutcome(
                    consumed: true, accepted: mutation != nil, committed: mutation != nil)
            default:
                break
            }

        case .pointerLeft:
            guard next.pointerMode.isIdle else { break }
            let markerChanged = clearHover(&next)
            publication = markerChanged ? [.markers, .hover] : .hover

        case let .pointerDoubleClicked(input):
            guard next.attached else { break }
            let bankChanged = next.bank != input.bank
            stopAudition(&next, effects: &effects)
            next.bank = input.bank
            if let target = input.target {
                next.modalMode = .picker(openPicker(target, state: next))
            }
            publication = bankChanged
                ? [.content, .typography, .modal, .interaction]
                : [.modal, .interaction]
            outcome = .handled

        case let .pickerFilterChanged(text):
            guard case var .picker(picker) = next.modalMode else { break }
            let filter = String(text.prefix(64))
            guard filter != picker.filter else { break }
            stopAudition(&next, effects: &effects)
            picker.filter = filter
            picker.program = visiblePrograms(bank: next.bank, filter: filter).first ?? -1
            next.modalMode = .picker(picker)
            publication = .modal

        case let .pickerRowSelected(index):
            guard case var .picker(picker) = next.modalMode else { break }
            let programs = visiblePrograms(bank: next.bank, filter: picker.filter)
            let program = programs.indices.contains(index) ? programs[index] : -1
            guard picker.program != program else { break }
            stopAudition(&next, effects: &effects)
            picker.program = program
            next.modalMode = .picker(picker)
            publication = .modal

        case let .pickerRowHeld(index):
            guard case var .picker(picker) = next.modalMode,
                  targetIsCurrent(picker.target, lane: next.lane) else {
                stopAudition(&next, effects: &effects)
                break
            }
            let programs = visiblePrograms(bank: next.bank, filter: picker.filter)
            guard programs.indices.contains(index) else {
                stopAudition(&next, effects: &effects)
                break
            }
            stopAudition(&next, effects: &effects)
            let program = programs[index]
            picker.program = program
            next.modalMode = .picker(picker)
            if (0..<128).contains(program) {
                next.auditionedProgram = program
                effects.append(.audition(program: program, key: 60, velocity: 112))
            }
            publication = .modal

        case .pickerAuditionReleased:
            stopAudition(&next, effects: &effects)

        case let .pickerSelectionMoved(delta):
            guard case var .picker(picker) = next.modalMode else { break }
            let programs = visiblePrograms(bank: next.bank, filter: picker.filter)
            guard !programs.isEmpty else { break }
            let index: Int
            if let current = programs.firstIndex(of: picker.program) {
                index = min(max(current + delta, 0), programs.count - 1)
            } else {
                index = 0
            }
            let program = programs[index]
            guard program != picker.program else { break }
            stopAudition(&next, effects: &effects)
            picker.program = program
            next.modalMode = .picker(picker)
            publication = .modal

        case .pickerAccepted:
            guard case let .picker(picker) = next.modalMode, picker.program >= 0 else { break }
            stopAudition(&next, effects: &effects)
            next.modalMode = .none
            let mutation = VoiceChangesTransactions.picker(
                picker.target, program: picker.program, slotCount: next.bank.count,
                revision: next.lane.revision, track: next.lane.track ?? -1,
                points: next.lane.points)
            if let mutation { effects.append(.commit(mutation)) }
            publication = [.modal, .interaction]
            outcome = VoiceChangesOutcome(
                consumed: true, accepted: true, committed: mutation != nil)

        case .pickerCancelled:
            guard case .picker = next.modalMode else { break }
            stopAudition(&next, effects: &effects)
            next.modalMode = .none
            publication = [.modal, .interaction]

        case let .menuActionActivated(action):
            guard case let .menu(menu) = next.modalMode else { break }
            next.modalMode = .none
            publication = [.modal, .interaction]
            guard targetIsCurrent(menu.target, lane: next.lane) else { break }
            switch action {
            case VoiceChangesPagePolicy.changeVoiceAction,
                 VoiceChangesPagePolicy.insertVoiceChangeAction:
                next.modalMode = .picker(openPicker(menu.target, state: next))
                outcome = VoiceChangesOutcome(consumed: true, accepted: true)
            case VoiceChangesPagePolicy.deleteMarkerAction:
                let mutation = VoiceChangesTransactions.delete(
                    menu.target, revision: next.lane.revision,
                    track: next.lane.track ?? -1, points: next.lane.points)
                if let mutation { effects.append(.commit(mutation)) }
                outcome = VoiceChangesOutcome(
                    consumed: mutation != nil, accepted: mutation != nil,
                    committed: mutation != nil)
            default:
                break
            }

        case .menuDismissed:
            guard case .menu = next.modalMode else { break }
            next.modalMode = .none
            publication = [.modal, .interaction]

        case .modalDismissed:
            guard next.modalMode.isOpen else { break }
            stopAudition(&next, effects: &effects)
            next.modalMode = .none
            publication = [.modal, .interaction]

        case .auditionOwnerWillChange:
            stopAudition(&next, effects: &effects)
        }

        return VoiceChangesTransition(
            state: next, effects: effects, publication: publication, outcome: outcome)
    }

    private static func contextSlot(lane: VoiceLaneFacts, tick: Tick) -> Int {
        VoiceLanePolicy.slot(firstProgram: lane.firstProgram, tick: tick, points: lane.points)
    }

    private static func targetIsCurrent(_ target: VoiceTarget,
                                        lane: VoiceLaneFacts) -> Bool {
        target.revision == lane.revision && target.track == lane.track
    }

    private static func visiblePrograms(bank: borrowing [BankSlotView],
                                        filter: String) -> [Int] {
        var programs: [Int] = []
        programs.reserveCapacity(bank.count)
        for program in bank.indices {
            let label = VoiceLanePolicy.label(slot: program, view: bank[program])
            guard filter.isEmpty
                    || label.range(of: filter, options: .caseInsensitive) != nil
            else { continue }
            programs.append(program)
        }
        return programs
    }

    private static func openPicker(_ target: VoiceTarget,
                                   state: VoiceChangesState) -> VoicePickerState {
        let initial = target.occurrence?.value
            ?? VoiceLanePolicy.slot(
                firstProgram: state.lane.firstProgram, tick: target.tick,
                points: state.lane.points)
        let programs = visiblePrograms(bank: state.bank, filter: "")
        return VoicePickerState(
            target: target, program: programs.contains(initial) ? initial : (programs.first ?? -1))
    }

    @discardableResult
    private static func applyHover(_ state: inout VoiceChangesState,
                                   hit: VoiceOccurrence?, snappedTick: Tick) -> Bool {
        let markerChanged = state.hoveredOccurrence != hit
        if let hit {
            state.hoveredOccurrence = hit
            state.hoverTick = hit.tick
            state.hoverLabel = ""
            return markerChanged
        }
        let slot = VoiceLanePolicy.slot(
            firstProgram: state.lane.firstProgram, tick: snappedTick,
            points: state.lane.points)
        let label = state.bank.indices.contains(slot)
            ? VoiceLanePolicy.label(slot: slot, view: state.bank[slot]) : ""
        let hover = VoiceLanePolicy.hoverLabel(label)
        state.hoveredOccurrence = nil
        state.hoverTick = hover.isEmpty ? 0 : snappedTick
        state.hoverLabel = hover
        return markerChanged
    }

    @discardableResult
    private static func clearHover(_ state: inout VoiceChangesState) -> Bool {
        let markerChanged = state.hoveredOccurrence != nil
        state.hoveredOccurrence = nil
        state.hoverTick = 0
        state.hoverLabel = ""
        return markerChanged
    }

    private static func stopAudition(_ state: inout VoiceChangesState,
                                     effects: inout [VoiceChangesEffect]) {
        guard let program = state.auditionedProgram else { return }
        state.auditionedProgram = nil
        effects.append(.audition(program: program, key: 60, velocity: 0))
    }
}
