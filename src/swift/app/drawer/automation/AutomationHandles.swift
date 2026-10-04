import QtBridge


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

struct AutomationNodeValue {
    var x: Double = 0
    var y: Double = 0
    var tick: Double = 0
    var value: Int = 0
    var radius: Double = 0
    var ringRadius: Double = 0
    var outlineWidth: Double = 0
    var outlineColor: QmlColor = PaletteMath.qmlColor(argb: 0)
    var ringColor: QmlColor = PaletteMath.qmlColor(argb: 0)
    var selected: Bool = false
    var hovered: Bool = false
    var projected: Bool = false
    var phantom: Bool = false
    var identity: AutomationPointIdentity?
    var primitiveName: String = "automationNode"
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
    public var outlineColor: QmlColor = PaletteMath.qmlColor(argb: 0)
    public var ringColor: QmlColor = PaletteMath.qmlColor(argb: 0)
    public var selected: Bool = false
    public var hovered: Bool = false
    /// The synthetic engine-default node rather than a written occurrence.
    public var projected: Bool = false
    /// The origin phantom: the rightmost node left of the plot, drawn at the edge.
    public var phantom: Bool = false
    public var identity: String = ""
    public var primitiveName: String = "automationNode"

    public init() {}

    public var outerRadius: Double = 0
    public var ringWidth: Double = 0
    public var ringOuterRadius: Double = 0
    public var hoverOuterRadius: Double = 0

    private var pointIdentity: AutomationPointIdentity?

    @QtIgnored
    convenience init(_ value: AutomationNodeValue) {
        self.init()
        _ = update(value)
    }

    @QtIgnored
    func update(_ next: AutomationNodeValue) -> Bool {
        guard
            x != next.x || y != next.y || tick != next.tick || value != next.value
                || radius != next.radius || ringRadius != next.ringRadius
                || outlineWidth != next.outlineWidth || outlineColor != next.outlineColor
                || ringColor != next.ringColor || selected != next.selected || hovered != next.hovered
                || projected != next.projected || phantom != next.phantom
                || pointIdentity != next.identity || primitiveName != next.primitiveName
        else { return false }
        setPublished(x, next.x) { x = $0 }
        setPublished(y, next.y) { y = $0 }
        setPublished(tick, next.tick) { tick = $0 }
        setPublished(value, next.value) { value = $0 }
        setPublished(radius, next.radius) { radius = $0 }
        setPublished(ringRadius, next.ringRadius) { ringRadius = $0 }
        setPublished(outlineWidth, next.outlineWidth) { outlineWidth = $0 }
        setPublished(outlineColor, next.outlineColor) { outlineColor = $0 }
        setPublished(ringColor, next.ringColor) { ringColor = $0 }
        setPublished(selected, next.selected) { selected = $0 }
        setPublished(hovered, next.hovered) { hovered = $0 }
        setPublished(projected, next.projected) { projected = $0 }
        setPublished(phantom, next.phantom) { phantom = $0 }
        setPublished(primitiveName, next.primitiveName) { primitiveName = $0 }
        setPublished(outerRadius, next.radius + next.outlineWidth) { outerRadius = $0 }
        setPublished(ringWidth, next.outlineWidth * 12.0 / 5.0) { ringWidth = $0 }
        setPublished(ringOuterRadius, next.ringRadius + next.outlineWidth * 6.0 / 5.0) {
            ringOuterRadius = $0
        }
        setPublished(hoverOuterRadius, next.radius + next.outlineWidth + 2) { hoverOuterRadius = $0 }
        if pointIdentity != next.identity {
            pointIdentity = next.identity
            identity = next.identity.map(AutomationPage.identityText) ?? ""
        }
        return true
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

/// One retained hover presentation shared by the plot's rings and labels.
@MainActor
@QtBridgeable
public final class AutomationHoverDisplay {
    public var visible: Bool = false
    public var text: String = ""
    public var hasNode: Bool = false
    public var nodeTick: Double = 0
    public var guideX: Double = 0
    public var ghostY: Double = 0
    public var hasGhost: Bool = false
    public var x: Double = 0
    public var y: Double = 0
    public var width: Double = 0
    public var height: Double = 0

    public init() {}

    @QtIgnored
    func update(
        visible: Bool, text: String = "", hasNode: Bool = false,
        nodeTick: Double = 0, guideX: Double = 0, ghostY: Double = 0,
        hasGhost: Bool = false, rect: (x: Double, y: Double, width: Double, height: Double) = (0, 0, 0, 0)
    ) {
        setPublished(self.visible, visible) { self.visible = $0 }
        setPublished(self.text, text) { self.text = $0 }
        setPublished(self.hasNode, hasNode) { self.hasNode = $0 }
        setPublished(self.nodeTick, nodeTick) { self.nodeTick = $0 }
        setPublished(self.guideX, guideX) { self.guideX = $0 }
        setPublished(self.ghostY, ghostY) { self.ghostY = $0 }
        setPublished(self.hasGhost, hasGhost) { self.hasGhost = $0 }
        setPublished(x, rect.x) { x = $0 }
        setPublished(y, rect.y) { y = $0 }
        setPublished(width, rect.width) { width = $0 }
        setPublished(height, rect.height) { height = $0 }
    }
}
