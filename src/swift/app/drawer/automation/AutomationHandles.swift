import QtBridge

// Qt-owned automation records. Equality and snapshots live in the plain value
// descriptors; these handles are allocated only after reconciliation finds a
// changed row.

// MARK: - Published records

/// One published selector tab: the parameter's label, whether it is the active
/// one, whether its curve is pinned as a ghost, whether the shared selection
/// covers it, and its own event count.
@MainActor
@QtBridgeable
public final class AutomationTabHandle {
    public var index: Int = 0
    public var label: String = ""
    public var tempo: Bool = false
    public var active: Bool = false
    public var ghosted: Bool = false
    public var included: Bool = false
    public var available: Bool = true
    public var eventCount: Int = 0
    public var primitiveName: String = "automationParameterTab"

    public init() {}

    init(_ value: borrowing AutomationTabValue) {
        index = value.index
        label = value.label
        tempo = value.tempo
        active = value.active
        ghosted = value.ghosted
        included = value.included
        available = value.available
        eventCount = value.eventCount
        primitiveName = value.primitiveName
    }
}

/// One published node: its projected position, its paint radii, its interaction
/// state and the identity a capture can revalidate.
@MainActor
@QtBridgeable
public final class AutomationNodeHandle {
    public var x: Double = 0
    public var y: Double = 0
    public var tick: Double = 0
    public var value: Int = 0
    public var radius: Double = 0
    public var ringRadius: Double = 0
    public var outlineWidth: Double = 0
    public var fillColor: String = ""
    public var outlineColor: String = ""
    public var ringColor: String = ""
    public var selected: Bool = false
    public var hovered: Bool = false
    /// The synthetic engine-default node rather than a written occurrence.
    public var projected: Bool = false
    /// The origin phantom: the rightmost node left of the plot, drawn at the edge.
    public var phantom: Bool = false
    public var identity: String = ""
    public var primitiveName: String = "automationNode"

    public init() {}

    init(_ value: borrowing AutomationNodeValue) {
        x = value.x
        y = value.y
        tick = value.tick
        self.value = value.value
        radius = value.radius
        ringRadius = value.ringRadius
        outlineWidth = value.outlineWidth
        fillColor = value.fillColor
        outlineColor = value.outlineColor
        ringColor = value.ringColor
        selected = value.selected
        hovered = value.hovered
        projected = value.projected
        phantom = value.phantom
        identity = value.identity
        primitiveName = value.primitiveName
    }
}

/// One published ramp segment: the drawn span from its start to the next value.
@MainActor
@QtBridgeable
public final class AutomationRampHandle {
    public var x0: Double = 0
    public var y0: Double = 0
    public var dx: Double = 0
    public var dy: Double = 0
    public var color: String = ""
    public var primitiveName = "automationRamp"

    public init() {}

    init(_ value: borrowing AutomationRampValue) {
        x0 = value.x0
        y0 = value.y0
        dx = value.dx
        dy = value.dy
        color = value.color
        primitiveName = value.primitiveName
    }
}

/// One published menu row: the captured action, its label and its availability.
/// A separator carries no action and is never activatable.
@MainActor
@QtBridgeable
public final class AutomationMenuRowHandle {
    public var actionId: Int = 0
    public var text: String = ""
    public var enabled: Bool = true
    public var separator: Bool = false
    public var checkable: Bool = false
    public var checked: Bool = false
    public var hasSubmenu: Bool = false
    public var shortcutText: String = ""
    public var primitiveName: String = "automationMenuRow"

    public init() {}

    init(actionId: Int, text: String, enabled: Bool) {
        self.actionId = actionId
        self.text = text
        self.enabled = enabled
    }

    init(separator: Bool) {
        self.separator = separator
        actionId = -1
        enabled = false
        primitiveName = "automationMenuSeparator"
    }

    init(_ value: borrowing AutomationMenuRowValue) {
        actionId = value.actionId
        text = value.text
        enabled = value.enabled
        separator = value.separator
        checkable = value.checkable
        checked = value.checked
        hasSubmenu = value.hasSubmenu
        shortcutText = ""
        primitiveName = value.separator ? "automationMenuSeparator" : "automationMenuRow"
    }
}
