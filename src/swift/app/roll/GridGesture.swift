import Foundation
import PorydawCore

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

    func updated(x: Double, y: Double, metrics: GridMetrics,
                 camera: EditorCamera) -> GridGesture {
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
        case .velocity(var state):
            state.preview = min(127, max(1, state.original + Int((state.pressY - y).rounded())))
            return .velocity(state)
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
        case .pan(var state):
            state.deltaX = x - state.pressX
            state.deltaY = y - state.pressY
            state.pressX = x
            state.pressY = y
            return .pan(state)
        }
    }
}
