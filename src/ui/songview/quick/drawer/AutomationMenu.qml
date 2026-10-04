pragma ComponentBehavior: Bound
import QtQuick
import Porydaw.Ui

FocusScope {
    id: root
    objectName: "automationMenu"
    required property var model
    property var hintService: pageItem ? pageItem.hintService : null
    property var pageItem: null
    property bool showing: false
    property bool childOpen: false
    property int currentRow: -1
    property int childRow: -1
    signal closed()
    anchors.fill: parent
    visible: showing
    enabled: showing
    readonly property real rowHeight: Math.round(model.baseFontPx * 1.6)
    readonly property point anchor: pageItem && parent
        ? pageItem.mapToItem(parent, model.menuX, model.menuY) : Qt.point(model.menuX, model.menuY)
    readonly property var menuColors: root.pageItem ? root.pageItem.gridPalette : null
    readonly property var appearance: root.menuColors ? menuAppearance : null
    QtObject {
        id: menuAppearance
        readonly property color background: root.menuColors ? root.menuColors.menuBackground : "transparent"
        readonly property color outline: root.menuColors ? root.menuColors.outline : "transparent"
        readonly property color text: root.menuColors ? root.menuColors.windowText : "transparent"
        readonly property color hoverBackground: root.menuColors ? root.menuColors.menuHoverBackground : "transparent"
        readonly property color hoverText: root.menuColors ? root.menuColors.windowText : "transparent"
        readonly property color disabledText: root.menuColors ? root.menuColors.disabledText : "transparent"
        readonly property color separator: root.menuColors ? root.menuColors.separator : "transparent"
        readonly property font font: Qt.font(root.model.captionFont)
    }
    onShowingChanged: {
        childOpen = false
        currentRow = -1
        childRow = -1
        if (showing)
            claimMenuFocus()
        else
            closed()
    }
    // Focus lands in the same pass the menu becomes showable: claiming while
    // still disabled would drop focus to the window root, so every stage re-checks.
    function claimMenuFocus(): void {
        if (root.showing && root.visible && root.enabled)
            root.forceActiveFocus(Qt.PopupFocusReason)
    }
    onVisibleChanged: claimMenuFocus()
    onEnabledChanged: claimMenuFocus()
    function firstEnabled(level: QuickMenuPanel, start: int, step: int): int {
        const count = level === panel ? model.menuRowCount : model.menuChildRowCount
        for (let i = start; i >= 0 && i < count; i += step) {
            const item = level.rowItem(i)
            if (item && item.model.enabled && !item.model.separator) return i
        }
        return -1
    }
    function hoverRow(level: QuickMenuPanel, index: int): void {
        if (level === panel) {
            currentRow = index
            childOpen = !!level.rowItem(index)?.model.hasSubmenu
        } else childRow = index
    }
    function activateRow(level: QuickMenuPanel, index: int): bool {
        const item = level.rowItem(index)
        if (!item || !item.model.enabled || item.model.separator) return false
        if (item.model.hasSubmenu) {
            childOpen = true
            childRow = firstEnabled(submenu, 0, 1)
            return true
        }
        return model.consumeMenuAction(item.model.actionId)
    }
    function moveRow(delta: int): void {
        const level = childOpen ? submenu : panel
        const current = childOpen ? childRow : currentRow
        let next = firstEnabled(level, current + delta, delta)
        if (next < 0) next = firstEnabled(level, delta > 0 ? 0
            : (childOpen ? model.menuChildRowCount : model.menuRowCount) - 1, delta)
        if (childOpen) childRow = next
        else currentRow = next
    }
    function currentActionId(): int {
        const item = (childOpen ? submenu : panel).rowItem(childOpen ? childRow : currentRow)
        return item ? item.model.actionId : -1
    }
    function dismiss(): void { root.model.dismissMenu() }
    MouseArea {
        id: underlay
        objectName: "automationMenuUnderlay"
        anchors.fill: parent
        onPressed: mouse => {
            const p = root.pageItem ? mapToItem(root.pageItem, mouse.x, mouse.y) : Qt.point(-1, -1)
            root.model.outsideMenuPress(p.x - root.model.plotOrigin, p.y, mouse.button)
        }
        HoverHint {
            source: underlay
            hintService: root.hintService
            scopeAllowed: root.showing
        }
    }
    QuickMenuPanel {
        id: panel
        objectName: "automationMenuPanel"
        host: root
        menuModel: root.model.menuRows
        appearance: root.appearance
        rootLevel: true
        rowObjectNamePrefix: "automationMenuRow_"
        rowHeight: root.rowHeight
        checkX: Math.round(root.model.baseFontPx * 0.3)
        checkWidth: Math.round(root.model.baseFontPx * 1.1)
        textX: Math.round(root.model.baseFontPx * 1.7)
        textRight: menuWidth - textX
        arrowRight: menuWidth - Math.round(root.model.baseFontPx * 0.4)
        arrowWidth: Math.round(root.model.baseFontPx * 0.8)
        menuWidth: Math.min(root.width, root.model.baseFontPx * 18)
        menuHeight: Math.min(root.height, root.model.menuRowCount * rowHeight + 2)
        readonly property point origin: MenuPlacement.clampOrigin(
            root.anchor, menuWidth, menuHeight, root.width, root.height)
        x: origin.x
        y: origin.y
        width: menuWidth
        height: menuHeight
        menuOrigin: Qt.point(0, 0)
        Accessible.role: Accessible.PopupMenu
        Accessible.name: qsTr("Automation actions")
        highlightedRow: root.currentRow
    }
    QuickMenuPanel {
        id: submenu
        objectName: "automationMenuSubmenu"
        visible: root.childOpen
        host: root
        menuModel: root.model.menuChildRows
        appearance: root.appearance
        rowObjectNamePrefix: "automationMenuChildRow_"
        rowHeight: root.rowHeight
        checkX: panel.checkX
        checkWidth: panel.checkWidth
        textX: panel.textX
        textRight: menuWidth - Math.round(root.model.baseFontPx * 0.5)
        menuWidth: panel.menuWidth
        menuHeight: Math.min(root.height, root.model.menuChildRowCount * rowHeight + 2)
        readonly property point origin: MenuPlacement.flyoutOrigin(
            panel.x, panel.width, panel.y + root.currentRow * rowHeight,
            width, height, root.width, root.height)
        x: origin.x
        y: origin.y
        width: menuWidth
        height: menuHeight
        menuOrigin: Qt.point(0, 0)
        highlightedRow: root.childRow
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (childOpen) childOpen = false
            else dismiss()
        } else if (event.key === Qt.Key_Up) moveRow(-1)
        else if (event.key === Qt.Key_Down) moveRow(1)
        else if (event.key === Qt.Key_Right) activateRow(panel, currentRow)
        else if (event.key === Qt.Key_Left) childOpen = false
        else if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
            const level = childOpen ? submenu : panel
            const count = childOpen ? model.menuChildRowCount : model.menuRowCount
            const next = firstEnabled(level, event.key === Qt.Key_Home ? 0 : count - 1,
                                      event.key === Qt.Key_Home ? 1 : -1)
            if (childOpen) childRow = next
            else currentRow = next
        }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            activateRow(childOpen ? submenu : panel, childOpen ? childRow : currentRow)
        event.accepted = true
    }
    Keys.onShortcutOverride: event => event.accepted = true
    Keys.onReleased: event => event.accepted = true
}
