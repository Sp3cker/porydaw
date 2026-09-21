// The Voice Changes context menu: the typed rows the page publishes for the
// point that opened it.
//
// The page owns the capture (revision, track, occurrence, tick), the row set
// and every dispatch; this file renders those rows and delivers real pointer,
// keyboard and accessibility input back to that owner. It reads no document,
// re-resolves no target, and holds no action of its own beyond which row the
// keyboard is pointing at.
//
// Cancellation: an outside press, Escape, a section hide, a window deactivation
// or a document/track replacement all end the menu without an action — the
// outside press dismisses and starts nothing, which is the legacy "outside
// right press dismisses without retarget".
import QtQuick

pragma ComponentBehavior: Bound

FocusScope {
    id: menuRoot

    objectName: "voiceChangeMenu"

    /// The page's published model for the current document. A `QtObject`-typed
    /// property cannot hold the bridged Swift object, so the page hands it over
    /// as the variant the rest of the composition uses for bridged owners.
    required property var model
    /// The page whose coordinate space the published anchor is stated in. The
    /// menu is composed into the container's modal layer, so the anchor is mapped
    /// from that page into whatever surface hosts this menu.
    property var pageItem: null

    signal closed()

    /// The page's published press anchor, in this menu's own parent space.
    readonly property var anchor: {
        var x = menuRoot.model ? menuRoot.model.menuX : 0
        var y = menuRoot.model ? menuRoot.model.menuY : 0
        if (menuRoot.pageItem && menuRoot.parent)
            return menuRoot.pageItem.mapToItem(menuRoot.parent, x, y)
        return Qt.point(x, y)
    }

    readonly property bool ready: menuRoot.model !== null && menuRoot.model !== undefined
    /// The page's own publication decides modality: this file renders the open
    /// menu and delivers the input that drives it. The flag is read through a
    /// `var`-typed bridge object, whose nested properties a binding does not
    /// track across this component boundary, so the menu follows the page's own
    /// change signal — the same shape the drawer uses for its presenter's
    /// preference records.
    property bool showing: false

    readonly property real baseFontPx: menuRoot.model && menuRoot.model.baseFontPx > 0
                                       ? menuRoot.model.baseFontPx : 13
    readonly property real rowPadding: Math.max(1, Math.round(menuRoot.baseFontPx / 3))
    readonly property real rowHeight: Math.max(1, Math.round(menuRoot.baseFontPx * 1.6))

    property int currentRow: 0

    // The page composes this modal into the container's unclipped modal layer
    // when the container hosts it, and into the page itself otherwise; either way
    // it fills the surface it was given.
    anchors.fill: parent
    visible: showing
    enabled: showing

    onShowingChanged: {
        if (showing) {
            currentRow = 0
            menuRoot.forceActiveFocus(Qt.PopupFocusReason)
        } else {
            menuRoot.closed()
        }
    }

    function activateRow(index) {
        if (!menuRoot.model || index < 0)
            return false
        return menuRoot.model.activateMenuRow(index)
    }

    function moveRow(delta) {
        var rows = menuRoot.model ? menuRoot.model.menuRows : []
        if (rows.length === 0)
            return
        currentRow = Math.min(Math.max(currentRow + delta, 0), rows.length - 1)
    }

    // Every outside press dismisses and starts nothing, whichever button it
    // carries: no retarget, no row activation, no plot gesture.
    MouseArea {
        objectName: "voiceMenuUnderlay"
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onPressed: menuRoot.model.dismissVoiceMenu()
    }

    Rectangle {
        id: panel

        objectName: "voiceMenuPanel"
        x: Math.min(Math.max(menuRoot.anchor.x, 0), Math.max(0, menuRoot.width - width))
        y: Math.min(Math.max(menuRoot.anchor.y, 0), Math.max(0, menuRoot.height - height))
        width: Math.min(Math.max(1, Math.round(menuRoot.baseFontPx * 12)),
                        Math.max(1, menuRoot.width - 2))
        height: rows.implicitHeight + 2
        color: menuRoot.model && menuRoot.model.menuOpen
               ? Qt.rgba(0.18, 0.17, 0.16, 0.97) : "transparent"
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
            menuRoot.activateRow(menuRoot.currentRow)
            event.accepted = true
        }
        Keys.onEnterPressed: (event) => {
            menuRoot.activateRow(menuRoot.currentRow)
            event.accepted = true
        }
        Keys.onEscapePressed: (event) => {
            menuRoot.model.dismissVoiceMenu()
            event.accepted = true
        }
        // Only Return/Enter are claimed; bare Space stays the window's transport.
        Keys.onShortcutOverride: (event) => event.accepted =
            event.key === Qt.Key_Return || event.key === Qt.Key_Enter

        Accessible.role: Accessible.PopupMenu
        Accessible.name: qsTr("Voice change actions")
        Accessible.focusable: true

        Column {
            id: rows

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            y: 1

            Repeater {
                model: (menuRoot.model ? menuRoot.model.menuRows : [])

                delegate: Rectangle {
                    id: row

                    required property int index
                    required property var model

                    objectName: "voiceMenuRow_" + model.actionId
                    width: rows.width
                    height: menuRoot.rowHeight
                    color: row.index === menuRoot.currentRow ? "#2A2724" : "transparent"

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: menuRoot.rowPadding
                        anchors.rightMargin: menuRoot.rowPadding
                        text: row.model.text
                        color: "#F4F4F4"
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

                        onEntered: menuRoot.currentRow = row.index
                        onClicked: menuRoot.activateRow(row.index)
                    }

                    Accessible.role: Accessible.MenuItem
                    Accessible.name: row.model.text
                    Accessible.focusable: true
                    Accessible.onPressAction: menuRoot.activateRow(row.index)
                }
            }
        }
    }
}
