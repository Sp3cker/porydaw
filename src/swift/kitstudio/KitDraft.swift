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

    public private(set) var drumkitZones: [KitZone] = []
    public private(set) var keysplitZones: [KitZone] = []
    private var clean = Snapshot()
    private var undoEntries: [Snapshot] = []
    private var redoEntries: [Snapshot] = []

    public init() {}

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
        undoEntries.append(snapshot())
        redoEntries.removeAll()
        drumkitZones = zones
        return true
    }

    @discardableResult
    public func setKeysplitZones(_ zones: [KitZone]) -> Bool {
        guard Self.valid(zones) else { return false }
        undoEntries.append(snapshot())
        redoEntries.removeAll()
        keysplitZones = zones
        return true
    }

    public func undo() {
        guard let previous = undoEntries.popLast() else { return }
        redoEntries.append(snapshot())
        restore(previous)
    }

    public func redo() {
        guard let next = redoEntries.popLast() else { return }
        undoEntries.append(snapshot())
        restore(next)
    }

    public var canUndo: Bool { !undoEntries.isEmpty }
    public var canRedo: Bool { !redoEntries.isEmpty }
    public var dirty: Bool { snapshot() != clean }

    private func restore(_ snapshot: Snapshot) {
        drumkitZones = snapshot.drumkitZones
        keysplitZones = snapshot.keysplitZones
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
