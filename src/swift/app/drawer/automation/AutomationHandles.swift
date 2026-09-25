import QtBridge

// The Automation page's bridged records: the published selector tab, node,
// ramp and menu-row handles QML reads. Each carries its own equality so the
// publication sync paths can leave unchanged storage untouched.

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

    @QtIgnored
    func matches(_ other: AutomationTabHandle) -> Bool {
        index == other.index && label == other.label && tempo == other.tempo
            && active == other.active && ghosted == other.ghosted && included == other.included
            && available == other.available && eventCount == other.eventCount
            && primitiveName == other.primitiveName
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

    @QtIgnored
    func matches(_ other: AutomationNodeHandle) -> Bool {
        x == other.x && y == other.y && tick == other.tick && value == other.value
            && radius == other.radius && ringRadius == other.ringRadius
            && outlineWidth == other.outlineWidth && fillColor == other.fillColor
            && outlineColor == other.outlineColor && ringColor == other.ringColor
            && selected == other.selected && hovered == other.hovered
            && projected == other.projected && phantom == other.phantom
            && identity == other.identity && primitiveName == other.primitiveName
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

    @QtIgnored
    func matches(_ other: AutomationMenuRowHandle) -> Bool {
        actionId == other.actionId && text == other.text && enabled == other.enabled
            && separator == other.separator && primitiveName == other.primitiveName
            && checkable == other.checkable && checked == other.checked
            && hasSubmenu == other.hasSubmenu && shortcutText == other.shortcutText
    }
}
