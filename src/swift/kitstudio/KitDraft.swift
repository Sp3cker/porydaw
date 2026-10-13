/// Window-local kit state; every history entry contains both mode views.
@MainActor
public final class KitDraft {
    public struct Snapshot: Equatable, Sendable {
        public var drumkitZones: [KitZone]
        public var keysplitZones: [KitZone]

        public init(drumkitZones: [KitZone] = [], keysplitZones: [KitZone] = []) {
            self.drumkitZones = drumkitZones
            self.keysplitZones = keysplitZones
        }
    }

    struct MarkerKey: Hashable {
        var source: Int
        var frame: Int
    }
    struct SliceKey: Hashable {
        var source: Int
        var identity: Int
    }
    private struct HistoryState {
        var zones: Snapshot
        var session: KitSourceSession.Snapshot?
        var markers: [MarkerKey: Int]
        var slices: [SliceKey: Int]
    }

    var markerIds: [MarkerKey: Int] = [:]
    var sliceIds: [SliceKey: Int] = [:]
    private var session: KitSourceSession?
    private var editing = false
    public private(set) var drumkitZones: [KitZone] = []
    public private(set) var keysplitZones: [KitZone] = []
    private var clean = Snapshot()
    private var undoEntries: [HistoryState] = []
    private var redoEntries: [HistoryState] = []

    public init() {}

    func attachSession(_ session: KitSourceSession) {
        precondition(self.session == nil, "A draft belongs to one window session")
        self.session = session
    }

    /// Groups source and zone mutations into one window-local undo step.
    func edit(_ change: () -> Void) {
        precondition(!editing, "Draft edits cannot nest")
        let before = historyState()
        editing = true
        change()
        editing = false
        if before.zones != snapshot() || before.session != session?.snapshot() {
            undoEntries.append(before)
            redoEntries.removeAll()
        }
    }

    /// Replaces both views and starts a clean history.
    public func load(_ snapshot: Snapshot) {
        // Invalid bind-time state is a programmer error; user-editable zone setters return false.
        precondition(Self.valid(snapshot.drumkitZones) && Self.valid(snapshot.keysplitZones))
        restore(snapshot)
        clean = snapshot
        undoEntries.removeAll()
        redoEntries.removeAll()
    }

    /// Keeps history while marking the current values as applied.
    public func markClean() { clean = snapshot() }

    public func snapshot() -> Snapshot {
        Snapshot(drumkitZones: drumkitZones, keysplitZones: keysplitZones)
    }

    @discardableResult
    public func setDrumkitZones(_ zones: [KitZone]) -> Bool {
        guard Self.valid(zones) else { return false }
        if !editing {
            undoEntries.append(historyState())
            redoEntries.removeAll()
        }
        drumkitZones = zones
        return true
    }

    @discardableResult
    public func setKeysplitZones(_ zones: [KitZone]) -> Bool {
        guard Self.valid(zones) else { return false }
        if !editing {
            undoEntries.append(historyState())
            redoEntries.removeAll()
        }
        keysplitZones = zones
        return true
    }

    public func undo() {
        guard let previous = undoEntries.popLast() else { return }
        redoEntries.append(historyState())
        restoreHistory(previous)
    }

    public func redo() {
        guard let next = redoEntries.popLast() else { return }
        undoEntries.append(historyState())
        restoreHistory(next)
    }

    public var canUndo: Bool { !undoEntries.isEmpty }
    public var canRedo: Bool { !redoEntries.isEmpty }
    public var dirty: Bool { snapshot() != clean }

    private func restore(_ snapshot: Snapshot) {
        drumkitZones = snapshot.drumkitZones
        keysplitZones = snapshot.keysplitZones
    }

    private func historyState() -> HistoryState {
        HistoryState(zones: snapshot(), session: session?.snapshot(), markers: markerIds, slices: sliceIds)
    }

    private func restoreHistory(_ state: HistoryState) {
        restore(state.zones)
        if let snapshot = state.session { session?.restore(snapshot) }
        markerIds = state.markers
        sliceIds = state.slices
    }

    private static func valid(_ zones: [KitZone]) -> Bool {
        var previousEnd = -1
        for zone in zones {
            guard zone.startKey >= 0, zone.endKey <= 127,
                zone.startKey <= zone.endKey, zone.startKey > previousEnd
            else { return false }
            previousEnd = zone.endKey
        }
        return true
    }
}
