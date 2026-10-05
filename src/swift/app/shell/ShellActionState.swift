import QtBridge

/// ShellPresenter owns these values; QML reads their notifying properties.
@MainActor
@QtBridgeable
public final class ShellActionState {
    public var enabled: Bool
    public var checked: Bool
    public let checkable: Bool
    public let label: String
    public let menuLabel: String
    public let shortcut: String

    init(
        enabled: Bool, checked: Bool, checkable: Bool,
        label: String, menuLabel: String, shortcut: String
    ) {
        self.enabled = enabled
        self.checked = checked
        self.checkable = checkable
        self.label = label
        self.menuLabel = menuLabel
        self.shortcut = shortcut
    }

    @QtIgnored
    func update(enabled: Bool, checked: Bool) {
        if self.enabled != enabled { self.enabled = enabled }
        if self.checked != checked { self.checked = checked }
    }
}
