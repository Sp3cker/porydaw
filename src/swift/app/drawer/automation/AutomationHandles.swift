import PorydawDocument
import QtBridge


// MARK: - Published records

/// One selector tab's label, active/ghost/selection state, availability and count.
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

struct AutomationNodeValue: Equatable {
    var x: Double = 0
    var y: Double = 0
    var tick: Double = 0
    var value: Int = 0
    var radius: Double = 0
    var ringRadius: Double = 0
    var outlineWidth: Double = 0
    var outlineColor: QmlColor = .clear
    var ringColor: QmlColor = .clear
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
    public var outlineColor: QmlColor = .clear
    public var ringColor: QmlColor = .clear
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

    @QtIgnored var current = AutomationNodeValue()

    @QtIgnored
    convenience init(_ value: AutomationNodeValue) {
        self.init()
        _ = update(value)
    }

    @QtIgnored
    func update(_ next: AutomationNodeValue) -> Bool {
        guard current != next else { return false }
        let identityChanged = current.identity != next.identity
        current = next
        publish(\.x, next.x)
        publish(\.y, next.y)
        publish(\.tick, next.tick)
        publish(\.value, next.value)
        publish(\.radius, next.radius)
        publish(\.ringRadius, next.ringRadius)
        publish(\.outlineWidth, next.outlineWidth)
        publish(\.outlineColor, next.outlineColor)
        publish(\.ringColor, next.ringColor)
        publish(\.selected, next.selected)
        publish(\.hovered, next.hovered)
        publish(\.projected, next.projected)
        publish(\.phantom, next.phantom)
        publish(\.primitiveName, next.primitiveName)
        publish(\.outerRadius, next.radius + next.outlineWidth)
        publish(\.ringWidth, next.outlineWidth * 12.0 / 5.0)
        publish(\.ringOuterRadius, next.ringRadius + next.outlineWidth * 6.0 / 5.0)
        publish(\.hoverOuterRadius, next.radius + next.outlineWidth + 2)
        if identityChanged {
            publish(\.identity, next.identity.map(AutomationPage.identityText) ?? "")
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
        publish(\.visible, visible)
        publish(\.text, text)
        publish(\.hasNode, hasNode)
        publish(\.nodeTick, nodeTick)
        publish(\.guideX, guideX)
        publish(\.ghostY, ghostY)
        publish(\.hasGhost, hasGhost)
        publish(\.x, rect.x)
        publish(\.y, rect.y)
        publish(\.width, rect.width)
        publish(\.height, rect.height)
    }
}
