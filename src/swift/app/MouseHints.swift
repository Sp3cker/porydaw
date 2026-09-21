import QtBridge

/// Session-owned hint text. QML delivers live source lifetime and scope; tokens
/// are identities only, never retained QObject pointers or remembered focus.
@MainActor
@QtBridgeable
public final class MouseHints {
    @QtTracked public var text = ""
    private var nextToken = 0
    private var owner = 0
    private var currentProfile = 0
    private var windowActive = false

    public init() {}

    public func allocateSourceToken() -> Int {
        nextToken += 1
        return nextToken
    }

    public func claim(sourceToken: Int, profile: Int) {
        guard windowActive, sourceToken > 0, sourceToken <= nextToken else { return }
        owner = sourceToken
        guard profile != currentProfile else { return }
        currentProfile = profile
        text = Self.profileText(profile)
    }

    public func clear(sourceToken: Int) {
        guard sourceToken > 0, owner == sourceToken else { return }
        owner = 0
        currentProfile = 0
        text = ""
    }

    public func setWindowActive(active: Bool) {
        guard active != windowActive else { return }
        windowActive = active
        if !active {
            owner = 0
            currentProfile = 0
            text = ""
        }
        scopeRefresh()
    }

    @QtSignal public func scopeRefresh()

    // hintprofiles.cpp is the wording/profile oracle. Qt's Control modifier
    // is Command on macOS; these are descriptions, not another shortcut map.
    private static func profileText(_ profile: Int) -> String {
        let shift = "⇧", control = "⌘", alt = "⌥"
        let horizontal = shift + "Wheel: scroll horizontally"
        let page = control + " or " + shift + " Wheel: page step"
        let fine = shift + "Drag: adjust finely"
        let extend = shift + "Click: extend selection"
        let range = shift + "Click: select range"
        let neutral = control + "Drag: snap to neutral value"
        let ticks = alt + "Drag: draw in ticks"
        let parts: [String]
        switch profile {
        case 1, 7: parts = [extend]
        case 2: parts = [page]
        case 3: parts = [control + "Click: deselect item", page]
        case 4: parts = [control + "Click: toggle item", range, page]
        case 5: parts = [range, page]
        case 8: parts = [fine]
        case 9: parts = [fine, page]
        case 10: parts = [shift + "Right-drag: select time", control + "Wheel: zoom key height", horizontal]
        case 11: parts = [control + "Wheel: zoom key height", horizontal]
        case 12: parts = [horizontal]
        case 13: parts = [control + "Drag: select time across tracks with notes", horizontal]
        case 14: parts = [control + "Click: add track to selection", shift + "Click: add range to selection"]
        case 15: parts = [shift + "Drag: constrain to axis", ticks, neutral, horizontal]
        case 16: parts = [shift + "Drag: constrain to value", neutral, horizontal]
        case 17: parts = [shift + "Drag: draw ramp", ticks, neutral, horizontal]
        case 18: parts = [control + "Drag: draw freehand", shift + "Drag: hold value", alt + "Right-drag: draw in ticks", horizontal]
        case 19: parts = [control + "Drag: paint velocities without detents", shift + "Drag: draw ramp", control + "Right-drag: marquee adds notes", horizontal]
        case 20: parts = [control + "Click: set exact velocity"]
        case 21: parts = [alt + "Drag: move with fine time", horizontal]
        case 22: parts = [alt + "Drag: move in time finely"]
        case 23: parts = [shift + " or " + alt + " Drag: draw line"]
        case 24: parts = [control + "Click: toggle row", range, shift + control + "Click: add range"]
        case 25: parts = [control + "Click: toggle ghost parameter"]
        case 26: parts = [fine, control + "Wheel: step by ten"]
        case 27: parts = ["Tap: set song tempo"]
        default: parts = []
        }
        return parts.joined(separator: " · ")
    }
}
