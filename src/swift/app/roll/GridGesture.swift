import Foundation
import PorydawCore

struct GridBandRect: Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

enum GridHitZone: Equatable, Sendable {
    case none, body, leftEdge, rightEdge
}

struct GridNoteHit: Equatable, Sendable {
    var noteID: NoteID
    var tick: Int
    var duration: Int
    var zone: GridHitZone
}

struct GridDisplayedNote: Equatable, Sendable {
    var tick: Int
    var end: Int
    var pitch: Int
}

// Pointer interaction state machine for the piano grid. Each kind carries
// only the state that kind actually uses; transitions happen in updated(x:y:).
enum GridGesture: Equatable, Sendable {
    case pendingDraw(PendingDraw)
    case draw(Draw)
    case move(Move)
    case resize(Resize)
    case pendingMenu(PendingMenu)
    case band(Band)

    var isRight: Bool {
        switch self {
        case .pendingMenu, .band: return true
        default: return false
        }
    }

    var drawPreview: (tick: Int, duration: Int, pitch: Int)? {
        guard case .draw(let state) = self else { return nil }
        return (state.tick, state.duration, state.key)
    }

    var selectionBand: GridBandRect? {
        guard case .band(let state) = self else { return nil }
        let x0 = min(state.pressX, state.curX)
        let x1 = max(state.pressX, state.curX)
        let y0 = min(state.pressY, state.curY)
        let y1 = max(state.pressY, state.curY)
        return GridBandRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    struct PendingDraw: Equatable, Sendable {
        var pressX: Double
        var pressY: Double
        var pressTick: Double
        var pressKey: Int
    }

    struct Draw: Equatable, Sendable {
        var anchorTick: Int
        var tick: Int
        var duration: Int
        var key: Int
    }

    struct Move: Equatable, Sendable {
        var pressTick: Double
        var pressKey: Int
        var dTick: Int = 0
        var dKey: Int = 0
    }

    struct Resize: Equatable, Sendable {
        var pressTick: Double
        var gripTick: Int
        var oppositeTick: Int
        var leading: Bool
        var delta: Int = 0
    }

    struct PendingMenu: Equatable, Sendable {
        var pressX: Double
        var pressY: Double
        var threshold: Double
        var hitNoteId: NoteID
    }

    struct Band: Equatable, Sendable {
        var pressX: Double
        var pressY: Double
        var curX: Double
        var curY: Double
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

    func updated(x: Double, y: Double, metrics: borrowing GridMetrics,
                 camera: borrowing EditorCamera) -> GridGesture {
        func pitch(_ y: Double) -> Int {
            camera.projection.pitch(
                atY: y, keyHeight: camera.snapshot.keyHeight,
                scrollY: camera.snapshot.scrollY, dpr: metrics.dpr) ?? -1
        }
        switch self {
        case .pendingDraw(var state):
            let key = pitch(y)
            if key >= 0 { state.pressKey = key }
            guard abs(x - state.pressX) >= metrics.drawThreshold else {
                return .pendingDraw(state)
            }
            let anchor = metrics.snapTickDown(state.pressTick, camera: camera)
            let draw = Draw(
                anchorTick: anchor, tick: anchor,
                duration: metrics.snapTicks(camera: camera), key: state.pressKey)
            return GridGesture.draw(draw).updated(
                x: x, y: y, metrics: metrics, camera: camera)
        case .draw(var state):
            let tick = camera.tickAtContentX(x)
            let grid = metrics.snapTicks(camera: camera)
            if tick >= Double(state.anchorTick) {
                state.tick = state.anchorTick
                state.duration = max(
                    state.anchorTick + grid,
                    metrics.snapTickUp(tick, camera: camera)) - state.anchorTick
            } else {
                state.tick = metrics.snapTickDown(tick, camera: camera)
                state.duration = state.anchorTick + grid - state.tick
            }
            let key = pitch(y)
            if key >= 0 { state.key = key }
            return .draw(state)
        case .move(var state):
            let tick = camera.tickAtContentX(x)
            let grid = metrics.snapTicks(camera: camera)
            state.dTick = Int(((tick - state.pressTick) / Double(grid)).rounded()) * grid
            let key = pitch(y)
            if key >= 0 { state.dKey = key - state.pressKey }
            return .move(state)
        case .resize(var state):
            let tick = camera.tickAtContentX(x)
            let desired = Double(state.gripTick) + (tick - state.pressTick)
            let snapped = state.leading
                ? min(
                    metrics.snapTick(desired, camera: camera),
                    metrics.snapTickDown(Double(state.oppositeTick) - 1.0, camera: camera))
                : max(
                    metrics.snapTick(desired, camera: camera),
                    metrics.snapTickUp(Double(state.oppositeTick) + 1.0, camera: camera))
            state.delta =
                abs(desired - Double(state.gripTick)) < abs(desired - Double(snapped))
                ? 0 : snapped - state.gripTick
            return .resize(state)
        case .pendingMenu(let state):
            guard abs(x - state.pressX) + abs(y - state.pressY) >= state.threshold else {
                return .pendingMenu(state)
            }
            return .band(Band(
                pressX: state.pressX, pressY: state.pressY, curX: x, curY: y))
        case .band(var state):
            state.curX = x
            state.curY = y
            return .band(state)
        }
    }

    static func displayedNote(_ note: borrowing GridNote, selected: Bool,
                              gesture: GridGesture?) -> GridDisplayedNote {
        var tick = note.tick
        var end = note.tick + note.duration
        var pitch = note.pitch
        guard selected, let gesture else {
            return GridDisplayedNote(tick: tick, end: end, pitch: pitch)
        }
        switch gesture {
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
        return GridDisplayedNote(tick: tick, end: end, pitch: pitch)
    }
}

struct GridPrimaryPress: Sendable {
    var x: Double
    var y: Double
    var tick: Double
    var key: Int
    var modifiers: DrawerModifiers
    var hit: GridNoteHit?
    var selected: Set<NoteID>
}

struct GridSecondaryPress: Sendable {
    var x: Double
    var y: Double
    var threshold: Double
    var hitNoteID: NoteID
    var orderedSelection: [NoteID]
}

enum GridGestureInput {
    case primaryPress(GridPrimaryPress)
    case primaryMove(x: Double, y: Double, metrics: GridMetrics, camera: EditorCamera)
    case primaryRelease(x: Double, y: Double, metrics: GridMetrics, camera: EditorCamera)
    case secondaryPress(GridSecondaryPress)
    case secondaryMove(x: Double, y: Double, metrics: GridMetrics, camera: EditorCamera)
    case secondaryRelease(x: Double, y: Double, metrics: GridMetrics, camera: EditorCamera)
    case keyboardMove(key: Int)
    case keyboardEnd
    case escape
    case cancel
}

enum GridSelectionEffect: Equatable, Sendable {
    case none
    case clear
    case replace([NoteID])
    case add(NoteID)
    case remove(NoteID)
    case band(base: [NoteID], rect: GridBandRect)
}

enum GridCommitEffect: Equatable, Sendable {
    case add(tick: Int, duration: Int, pitch: Int)
    case move(dTick: Int, dKey: Int)
    case resize(delta: Int, leading: Bool)
}

struct GridContextMenuEffect: Equatable, Sendable {
    var x: Double
    var y: Double
}

struct GridAuditionEffect: Equatable, Sendable {
    var stopKey: Int?
    var startKey: Int?
}

struct GridGestureEffects: Equatable, Sendable {
    var selection: GridSelectionEffect = .none
    var commit: GridCommitEffect?
    var contextMenu: GridContextMenuEffect?
    var audition = GridAuditionEffect()
}

struct GridGestureTransition: Equatable, Sendable {
    var state: GridGestureState
    var effects = GridGestureEffects()
    var handled = true
}

/// Outer interaction state. The adapter installs a reduced value before it
/// executes effects, so synchronous session callbacks always observe the new
/// gesture and never an inout reduction in progress.
struct GridGestureState: Equatable, Sendable {
    var active: GridGesture?
    var selectionAtRightPress: [NoteID] = []
    var keyboardAuditionKey: Int?
    var activeNoteID = NoteID()

    func reduce(_ input: consuming GridGestureInput) -> GridGestureTransition {
        var next = self
        var effects = GridGestureEffects()

        switch input {
        case .primaryPress(let press):
            guard next.active == nil, press.key >= 0 else {
                return GridGestureTransition(state: self, handled: false)
            }
            next.selectionAtRightPress = []
            if let hit = press.hit {
                if press.modifiers.control {
                    effects.selection = press.selected.contains(hit.noteID)
                        ? .remove(hit.noteID) : .add(hit.noteID)
                } else if press.modifiers.shift {
                    effects.selection = .add(hit.noteID)
                } else if !press.selected.contains(hit.noteID) {
                    effects.selection = .replace([hit.noteID])
                }
                next.activeNoteID = hit.noteID
                switch hit.zone {
                case .leftEdge:
                    next.active = .resize(
                        pressTick: press.tick, gripTick: hit.tick,
                        oppositeTick: hit.tick + hit.duration, leading: true)
                case .rightEdge:
                    next.active = .resize(
                        pressTick: press.tick, gripTick: hit.tick + hit.duration,
                        oppositeTick: hit.tick, leading: false)
                case .none, .body:
                    next.active = .move(pressTick: press.tick, pressKey: press.key)
                }
            } else {
                if !press.modifiers.shift && !press.modifiers.control {
                    effects.selection = .clear
                }
                next.activeNoteID = NoteID()
                next.active = .pendingDraw(GridGesture.PendingDraw(
                    pressX: press.x, pressY: press.y,
                    pressTick: press.tick, pressKey: press.key))
            }

        case let .primaryMove(x, y, metrics, camera):
            guard let active = next.active, !active.isRight else {
                return GridGestureTransition(state: self, handled: false)
            }
            next.active = active.updated(x: x, y: y, metrics: metrics, camera: camera)

        case let .primaryRelease(x, y, metrics, camera):
            guard let active = next.active, !active.isRight else {
                return GridGestureTransition(state: self, handled: false)
            }
            let updated = active.updated(x: x, y: y, metrics: metrics, camera: camera)
            switch updated {
            case .pendingDraw(let state):
                effects.commit = .add(
                    tick: metrics.snapTickDown(state.pressTick, camera: camera),
                    duration: metrics.snapTicks(camera: camera), pitch: state.pressKey)
            case .draw(let state):
                effects.commit = .add(tick: state.tick, duration: state.duration, pitch: state.key)
            case .move(let state):
                effects.commit = .move(dTick: state.dTick, dKey: state.dKey)
            case .resize(let state):
                effects.commit = .resize(delta: state.delta, leading: state.leading)
            case .pendingMenu, .band:
                break
            }
            next.active = nil
            next.activeNoteID = NoteID()

        case .secondaryPress(let press):
            guard next.active == nil else {
                return GridGestureTransition(state: self, handled: false)
            }
            next.selectionAtRightPress = press.orderedSelection
            next.activeNoteID = NoteID()
            next.active = .pendingMenu(GridGesture.PendingMenu(
                pressX: press.x, pressY: press.y, threshold: press.threshold,
                hitNoteId: press.hitNoteID))

        case let .secondaryMove(x, y, metrics, camera):
            guard let active = next.active, active.isRight else {
                return GridGestureTransition(state: self, handled: false)
            }
            let updated = active.updated(x: x, y: y, metrics: metrics, camera: camera)
            next.active = updated
            if let rect = updated.selectionBand {
                effects.selection = .band(base: next.selectionAtRightPress, rect: rect)
            }

        case let .secondaryRelease(x, y, metrics, camera):
            guard let active = next.active, active.isRight else {
                return GridGestureTransition(state: self, handled: false)
            }
            let updated = active.updated(x: x, y: y, metrics: metrics, camera: camera)
            if case .pendingMenu = updated {
                effects.contextMenu = GridContextMenuEffect(x: x, y: y)
            } else if let rect = updated.selectionBand {
                effects.selection = .band(base: next.selectionAtRightPress, rect: rect)
            }
            next.active = nil
            next.activeNoteID = NoteID()
            next.selectionAtRightPress = []

        case .keyboardMove(let key):
            guard (0...127).contains(key), key != next.keyboardAuditionKey else {
                return GridGestureTransition(state: self, handled: false)
            }
            effects.audition = GridAuditionEffect(
                stopKey: next.keyboardAuditionKey, startKey: key)
            next.keyboardAuditionKey = key

        case .keyboardEnd:
            guard let key = next.keyboardAuditionKey else {
                return GridGestureTransition(state: self, handled: false)
            }
            effects.audition.stopKey = key
            next.keyboardAuditionKey = nil

        case .escape:
            if next.active == nil {
                effects.selection = .clear
            } else {
                effects = next.cancellationEffects()
                next.cancel()
            }

        case .cancel:
            effects = next.cancellationEffects()
            next.cancel()
        }
        return GridGestureTransition(state: next, effects: effects)
    }

    private func cancellationEffects() -> GridGestureEffects {
        var effects = GridGestureEffects()
        if case .band = active {
            effects.selection = .replace(selectionAtRightPress)
        }
        effects.audition.stopKey = keyboardAuditionKey
        return effects
    }

    private mutating func cancel() {
        active = nil
        activeNoteID = NoteID()
        selectionAtRightPress = []
        keyboardAuditionKey = nil
    }
}
