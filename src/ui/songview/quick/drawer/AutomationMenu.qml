// The Automation context menu: the captured rows the page publishes for the
// point, lane or range that opened it.
//
// The page owns the capture (revision, track, parameter, point identity, the
// range, the before-state), the row set and every dispatch; this file renders
// those rows and delivers real pointer, keyboard and accessibility input back to
// that owner. It reads no document, re-resolves no target, and holds no action
// of its own beyond which row the keyboard is pointing at. A row the page
// published as unavailable is drawn disabled and never activates: no disabled
// action is presented as a successful no-op.
//
// Cancellation: an outside press, Escape, a section hide, a window deactivation
// or a document/track/parameter replacement all end the menu without an action.
pragma ComponentBehavior: Bound

import QtQuick

FocusScope {
    id: menuRoot

    objectName: "automationMenu"

    /// The page's published model for the current document. A `QtObject`-typed
    /// property cannot hold the bridged Swift object, so the page hands it over
    /// as the variant the rest of the composition uses for bridged owners.
    required property var model
    /// The page whose coordinate space the published anchor is stated in. The
    /// menu is composed into the container's modal layer, so the anchor is mapped
    /// from that page into whatever surface hosts this menu.
    property var pageItem: null

    signal closed()

    /// The page's own publication decides modality: this file renders the open
    /// menu and delivers the input that drives it. The flag is read through a
    /// `var`-typed bridge object, whose nested properties a binding does not
    /// track across this component boundary, so the menu follows the page's own
    /// change signal.
    property bool showing: false

    readonly property bool ready: menuRoot.model !== null && menuRoot.model !== undefined
    readonly property real baseFontPx: menuRoot.ready && menuRoot.model.baseFontPx > 0
                                       ? menuRoot.model.baseFontPx : 13
    readonly property real rowPadding: Math.max(1, Math.round(menuRoot.baseFontPx / 3))
    readonly property real rowHeight: Math.max(1, Math.round(menuRoot.baseFontPx * 1.6))
    /// The drawn rows: a list model is not a JavaScript array, so the panel reads
    /// the delegates it really composed — each carries the published row it was
    /// handed — instead of indexing the model. Only the Repeater's own delegates
    /// carry a model index, so the Repeater item itself is skipped.
    function rowAt(index) {
        var children = rows.children
        var row = 0
        for (var i = 0; i < children.length; ++i) {
            var child = children[i]
            if (child.index === undefined)
                continue
            if (row === index)
                return child
            row += 1
        }
        return null
    }

    readonly property int rowCount: {
        var count = 0
        var children = rows.children
        for (var i = 0; i < children.length; ++i) {
            if (children[i].index !== undefined)
                count += 1
        }
        return count
    }
    readonly property real rowsHeight: {
        var total = 0
        var children = rows.children
        for (var i = 0; i < children.length; ++i) {
            if (children[i].index !== undefined)
                total += children[i].height
        }
        return total
    }
    readonly property int actionCount: {
        var count = 0
        for (var i = 0; i < menuRoot.rowCount; ++i) {
            var item = menuRoot.rowAt(i)
            if (item && !item.model.separator)
                count += 1
        }
        return count
    }

    /// The page's published press anchor, in this menu's own parent space.
    readonly property var anchor: {
        var x = menuRoot.ready ? menuRoot.model.menuX : 0
        var y = menuRoot.ready ? menuRoot.model.menuY : 0
        if (menuRoot.pageItem && menuRoot.parent)
            return menuRoot.pageItem.mapToItem(menuRoot.parent, x, y)
        return Qt.point(x, y)
    }

    /// The row the keyboard points at: an action row, never a separator and
    /// never a disabled one.
    property int currentRow: -1

    anchors.fill: parent
    visible: showing
    enabled: showing

    onShowingChanged: {
        if (showing) {
            menuRoot.currentRow = menuRoot.firstEnabledRow(0, 1)
            menuRoot.forceActiveFocus(Qt.PopupFocusReason)
        } else {
            menuRoot.closed()
        }
    }

    /// The drawn delegate that carries one action id, or null: the panel matches
    /// the action the surface really clicked instead of a position a reused
    /// delegate may no longer hold.
    function rowForAction(actionId) {
        var children = rows.children
        for (var i = 0; i < children.length; ++i) {
            if (children[i].index !== undefined && children[i].model.actionId === actionId)
                return children[i]
        }
        return null
    }

    /// The first row at or after `index` in the given direction that carries an
    /// enabled action, or `-1` when the menu has none.
    function firstEnabledRow(index, direction) {
        for (var i = index; i >= 0 && i < menuRoot.rowCount; i += direction) {
            var item = menuRoot.rowAt(i)
            if (item && !item.model.separator && item.model.enabled)
                return i
        }
        return -1
    }

    function moveRow(delta) {
        if (menuRoot.actionCount === 0)
            return
        var start = menuRoot.currentRow + delta
        var next = menuRoot.firstEnabledRow(start, delta)
        if (next < 0)
            next = menuRoot.firstEnabledRow(delta > 0 ? 0 : menuRoot.rowCount - 1, delta)
        menuRoot.currentRow = next
    }

    /// One row activation through the page's captured target. `true` means the
    /// page consumed the action: a disabled or separator row never activates, and
    /// what the action writes is the page's own transaction.
    function activateRow(actionId) {
        if (!menuRoot.ready)
            return false
        var item = menuRoot.rowForAction(actionId)
        if (!item || item.model.separator || !item.model.enabled)
            return false
        return menuRoot.model.consumeMenuAction(actionId)
    }

    /// The current row's action id, or -1: the keyboard's own pointer into the
    /// drawn rows.
    function currentActionId() {
        var item = menuRoot.rowAt(menuRoot.currentRow)
        return item && item.index !== undefined ? item.model.actionId : -1
    }

    /// The keyboard's own activation: the current row's action id, resolved
    /// against the drawn rows exactly as a click is.
    function activateCurrentRow() {
        var item = menuRoot.rowAt(menuRoot.currentRow)
        return item ? menuRoot.activateRow(item.model.actionId) : false
    }

    function dismiss() {
        if (menuRoot.ready)
            menuRoot.model.dismissMenu()
    }

    // Every outside press dismisses and starts nothing, whichever button it
    // carries: no retarget, no row activation, no plot gesture.
    MouseArea {
        objectName: "automationMenuUnderlay"
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onPressed: menuRoot.dismiss()
    }

    Rectangle {
        id: panel

        objectName: "automationMenuPanel"
        x: Math.min(Math.max(menuRoot.anchor.x, 0), Math.max(0, menuRoot.width - width))
        y: Math.min(Math.max(menuRoot.anchor.y, 0), Math.max(0, menuRoot.height - height))
        width: Math.min(Math.max(1, Math.round(menuRoot.baseFontPx * 12)),
                        Math.max(1, menuRoot.width - 2))
        height: menuRoot.rowsHeight + 2
        color: "#2E2C29"
        border.width: 1
        border.color: "#8C857F"
        focus: true

        Keys.onUpPressed: (event) => {
            menuRoot.moveRow(-1)
            event.accepted = true
        }
        Keys.onDownPressed: (event) => {
            menuRoot.moveRow(1)
            event.accepted = true
        }
        Keys.onReturnPressed: (event) => {
            menuRoot.activateCurrentRow()
            event.accepted = true
        }
        Keys.onEnterPressed: (event) => {
            menuRoot.activateCurrentRow()
            event.accepted = true
        }
        Keys.onEscapePressed: (event) => {
            menuRoot.dismiss()
            event.accepted = true
        }
        // Only Return/Enter are claimed; bare Space stays the window's transport.
        Keys.onShortcutOverride: (event) => event.accepted =
            event.key === Qt.Key_Return || event.key === Qt.Key_Enter

        Accessible.role: Accessible.PopupMenu
        Accessible.name: qsTr("Automation actions")
        Accessible.focusable: true

        Column {
            id: rows

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            y: 1

            Repeater {
                model: menuRoot.model ? menuRoot.model.menuRows : []

                delegate: Rectangle {
                    id: row

                    required property int index
                    required property var model

                    objectName: row.model.separator
                               ? "automationMenuSeparator_" + row.index
                               : "automationMenuRow_" + row.model.actionId
                    width: rows.width
                    height: row.model.separator ? 1 : menuRoot.rowHeight
                    color: row.model.separator
                           ? "#8C857F"
                           : row.index === menuRoot.currentRow ? "#44403C" : "transparent"

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: menuRoot.rowPadding
                        anchors.rightMargin: menuRoot.rowPadding
                        visible: !row.model.separator
                        text: row.model.text
                        color: row.model.enabled ? "#F4F4F4" : "#8C857F"
                        font.pixelSize: Math.max(1, Math.round(menuRoot.baseFontPx))
                        textFormat: Text.PlainText
                        renderType: Text.NativeRendering
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        hoverEnabled: true
                        enabled: !row.model.separator && row.model.enabled

                        onEntered: if (!row.model.separator && row.model.enabled)
                                       menuRoot.currentRow = row.index
                        onClicked: menuRoot.activateRow(row.model.actionId)
                    }

                    Accessible.role: Accessible.MenuItem
                    Accessible.name: row.model.separator ? "" : row.model.text
                    Accessible.focusable: !row.model.separator && row.model.enabled
                    Accessible.onPressAction: menuRoot.activateRow(row.model.actionId)
                }
            }
        }
    }
}
