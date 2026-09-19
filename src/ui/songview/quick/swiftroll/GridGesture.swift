import Foundation

// Pointer interaction state machine for the piano grid. Each kind carries
// only the state that kind actually uses; transitions happen in updated(x:y:).
enum GridGesture {
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
        var hitNoteId: Int
    }

    struct Band {
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

    func updated(x: Double, y: Double, metrics: GridMetrics) -> GridGesture {
        switch self {
        case .pendingDraw(var state):
            let key = metrics.yToPitch(y)
            if key >= 0 { state.pressKey = key }
            guard abs(x - state.pressX) >= metrics.drawThreshold else {
                return .pendingDraw(state)
            }
            let anchor = metrics.snapTickDown(state.pressTick)
            let draw = Draw(
                anchorTick: anchor, tick: anchor,
                duration: metrics.snapTicks, key: state.pressKey)
            return GridGesture.draw(draw).updated(x: x, y: y, metrics: metrics)
        case .draw(var state):
            let tick = metrics.tickAtContentX(x)
            let grid = metrics.snapTicks
            if tick >= Double(state.anchorTick) {
                state.tick = state.anchorTick
                state.duration =
                    max(
                        state.anchorTick + grid,
                        metrics.snapTickUp(tick)) - state.anchorTick
            } else {
                state.tick = metrics.snapTickDown(tick)
                state.duration = state.anchorTick + grid - state.tick
            }
            let key = metrics.yToPitch(y)
            if key >= 0 { state.key = key }
            return .draw(state)
        case .move(var state):
            let tick = metrics.tickAtContentX(x)
            state.dTick =
                Int(
                    ((tick - state.pressTick)
                        / Double(metrics.snapTicks)).rounded())
                * metrics.snapTicks
            let key = metrics.yToPitch(y)
            if key >= 0 { state.dKey = key - state.pressKey }
            return .move(state)
        case .resize(var state):
            let tick = metrics.tickAtContentX(x)
            let desired = Double(state.gripTick) + (tick - state.pressTick)
            let snapped =
                state.leading
                ? min(
                    metrics.snapTick(desired),
                    metrics.snapTickDown(Double(state.oppositeTick) - 1.0))
                : max(
                    metrics.snapTick(desired),
                    metrics.snapTickUp(Double(state.oppositeTick) + 1.0))
            state.delta =
                abs(desired - Double(state.gripTick)) < abs(desired - Double(snapped))
                ? 0 : snapped - state.gripTick
            return .resize(state)
        case .pendingMenu(let state):
            guard abs(x - state.pressX) + abs(y - state.pressY) >= state.threshold else {
                return .pendingMenu(state)
            }
            return .band(
                Band(
                    pressX: state.pressX, pressY: state.pressY,
                    curX: x, curY: y))
        case .band(var state):
            state.curX = x
            state.curY = y
            return .band(state)
        }
    }
}
