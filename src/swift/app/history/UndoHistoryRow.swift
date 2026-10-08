import QtBridge

/// One recorded step or the retained base state; the panel owns all role updates.
@MainActor
@QtBridgeable
public final class UndoHistoryRow {
    public var label: String
    public var applied: Bool
    public var isCurrent: Bool
    public var isSaved: Bool
    public var isBase: Bool

    init(label: String, applied: Bool, isCurrent: Bool, isSaved: Bool, isBase: Bool) {
        self.label = label
        self.applied = applied
        self.isCurrent = isCurrent
        self.isSaved = isSaved
        self.isBase = isBase
    }
}
