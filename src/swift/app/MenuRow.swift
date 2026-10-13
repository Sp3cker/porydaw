import QtBridge

/// Shared popup-menu presentation; each presenter owns its action IDs and dispatch.
@MainActor
@QtBridgeable
public final class MenuRow {
    public var actionId: Int
    public var text: String
    public var enabled: Bool
    public var separator: Bool
    public var checkable: Bool
    public var checked: Bool
    public var hasSubmenu: Bool
    public var shortcutText: String

    init(
        actionId: Int = 0, text: String = "", enabled: Bool = true,
        separator: Bool = false, checkable: Bool = false, checked: Bool = false,
        hasSubmenu: Bool = false, shortcutText: String = ""
    ) {
        self.actionId = actionId
        self.text = text
        // A separator is never interactive; the delegate binds Item.enabled to this role.
        self.enabled = enabled && !separator
        self.separator = separator
        self.checkable = checkable
        self.checked = checked
        self.hasSubmenu = hasSubmenu
        self.shortcutText = shortcutText
    }

    @QtIgnored
    func matches(_ other: MenuRow) -> Bool {
        actionId == other.actionId && text == other.text && enabled == other.enabled
            && separator == other.separator && checkable == other.checkable
            && checked == other.checked && hasSubmenu == other.hasSubmenu
            && shortcutText == other.shortcutText
    }
}
