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

    func updated(x: Double, y: Double, metrics: GridMetrics, grid: RollGrid,
                 camera: EditorCamera, scale: ScaleProjection) -> GridGesture {
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
                state.duration = max(
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
            let gridTicks = Int(grid.snapTicksAt(TimeDefaults.tick(from: max(0, state.pressTick)),
                                                 camera: camera))
            state.dTick = Int(((tick - state.pressTick) / Double(gridTicks)).rounded()) * gridTicks
            if scale.fold {
                let projection = camera.projection
                let currentRow = projection.row(atY: y, keyHeight: camera.snapshot.keyHeight,
                                                  scrollY: camera.snapshot.scrollY, dpr: metrics.dpr)
                let grabRow = projection.row(forPitch: state.pressKey)
                if currentRow != PitchProjection.hiddenRow,
                   grabRow != PitchProjection.hiddenRow {
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
            let snapped = state.leading
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
