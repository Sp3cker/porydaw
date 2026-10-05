import QtBridge

/// Checks-only recorder owner, created by the resize suite only after opt-in.
/// QML reads preparation results outside capture; capture endpoints never publish state.
@MainActor
@QtBridgeable
public final class WindowResizeAllocationFixture: QmlInstantiableStatus {
    private var allocationProbe: AllocationProbe?
    private var allocationPreparationAttempted = false

    public var allocationWarmup: Int = 0
    public var allocationIterations: Int = 0
    public var allocationError: String = ""

    public required init() {}

    public func componentComplete() {}

    /// Load once before any captured operation, never during ordinary checks.
    public func prepareWindowAllocationCapture() -> Bool {
        if allocationPreparationAttempted { return allocationProbe != nil }
        allocationPreparationAttempted = true
        do {
            guard let options = try AllocationBenchmarkOptions.load(for: AllocationScenario.windowResize.rawValue)
            else {
                allocationError = "window-resize allocation scenario was not requested"
                return false
            }
            let probe = try AllocationProbe.load()
            allocationWarmup = options.warmup
            allocationIterations = options.iterations
            allocationProbe = probe
            return true
        } catch {
            allocationError = "window-resize allocation capture: \(error)"
            return false
        }
    }

    public func resetAllocationCapture() {
        allocationProbe?.reset()
    }

    // No observer writes or result/string construction at these boundaries.
    // The empty control uses these same bridge calls and the same event turn.
    public func beginAllocationCapture() {
        allocationProbe?.begin()
    }

    public func pauseAllocationCapture() {
        allocationProbe?.pause()
    }

    public func reportAllocationCapture(label: String, operations: Int) -> Bool {
        guard let probe = allocationProbe, operations > 0 else {
            allocationError = "window-resize allocation report requires a probe and positive operations"
            return false
        }
        probe.report(label: label, operations: UInt64(operations))
        return true
    }
}
