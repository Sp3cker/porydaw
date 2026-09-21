pragma ComponentBehavior: Bound
import QtQuick
import ".." as Shared

FocusScope {
    id: root
    objectName: "automationMenu"
    required property var model
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
    readonly property var appearance: ({background: "#2E2C29", outline: "#8C857F",
        text: "#F4F4F4", hoverBackground: "#44403C", hoverText: "#F4F4F4",
        disabledText: "#8C857F", separator: "#8C857F", font: Qt.font(model.captionFont)})
    onShowingChanged: {
        childOpen = false
        currentRow = -1
        childRow = -1
        if (showing) {
            forceActiveFocus(Qt.PopupFocusReason)
        }
        else closed()
    }
    function firstEnabled(level, start, step) {
        const count = level === panel ? model.menuRowCount : model.menuChildRowCount
        for (let i = start; i >= 0 && i < count; i += step) {
            const item = level.rowItem(i)
            if (item && item.model.enabled && !item.model.separator) return i
        }
        return -1
    }
    function hoverRow(level, index) {
        if (level === panel) {
            currentRow = index
            childOpen = !!level.rowItem(index)?.model.hasSubmenu
        } else childRow = index
    }
    function activateRow(level, index) {
        const item = level.rowItem(index)
        if (!item || !item.model.enabled || item.model.separator) return false
        if (item.model.hasSubmenu) {
            childOpen = true
            childRow = firstEnabled(submenu, 0, 1)
            return true
        }
        return model.consumeMenuAction(item.model.actionId)
    }
    function moveRow(delta) {
        const level = childOpen ? submenu : panel
        const current = childOpen ? childRow : currentRow
        let next = firstEnabled(level, current + delta, delta)
        if (next < 0) next = firstEnabled(level, delta > 0 ? 0
            : (childOpen ? model.menuChildRowCount : model.menuRowCount) - 1, delta)
        if (childOpen) childRow = next
        else currentRow = next
    }
    function currentActionId() {
        const item = (childOpen ? submenu : panel).rowItem(childOpen ? childRow : currentRow)
        return item ? item.model.actionId : -1
    }
    function dismiss() { model.dismissMenu() }
    MouseArea {
        objectName: "automationMenuUnderlay"
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: mouse => {
            const p = root.pageItem ? mapToItem(root.pageItem, mouse.x, mouse.y) : Qt.point(-1, -1)
            root.model.outsideMenuPress(p.x - root.model.plotOrigin, p.y, mouse.button)
        }
    }
    Shared.QuickMenuPanel {
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
        x: Math.max(0, Math.min(root.anchor.x, root.width - menuWidth))
        y: Math.max(0, Math.min(root.anchor.y, root.height - menuHeight))
        width: menuWidth
        height: menuHeight
        menuOrigin: Qt.point(0, 0)
        Accessible.role: Accessible.PopupMenu
        Accessible.name: qsTr("Automation actions")
        highlightedRow: root.currentRow
    }
    Shared.QuickMenuPanel {
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
        x: panel.x + panel.width + width <= root.width
            ? panel.x + panel.width : Math.max(0, panel.x - width)
        y: Math.max(0, Math.min(root.height - height, panel.y + root.currentRow * rowHeight))
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
