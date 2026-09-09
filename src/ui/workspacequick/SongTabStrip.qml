// Stock TabBar owns overflow and keyboard behavior; delegates only issue
// semantic session commands.
import QtQuick
import QtQuick.Controls
import Porydaw.Ui

TabBar {
    id: strip
    topPadding: 0
    bottomPadding: 0

    // Fired after WorkspaceUi accepts a pointer/Enter/accessibility
    // activation; WorkspaceSongs.qml enters the editor on it.
    signal sessionAccepted(int reason)

    // Shared semantic activation: select, and report entry only when the
    // model now selects this session. Never dispatched from onClicked.
    function activateSession(session, reason) {
        workspaceUi.selectSongTab(session)
        if (workspaceTabs.selectedSession === session)
            sessionAccepted(reason)
    }

    // Returns the cyclic neighbor session, or null for an empty model.
    function neighborSession(row, step) {
        if (count === 0)
            return null
        return workspaceTabs.songAt(((row + step) % count + count) % count)
    }

    function syncCurrentIndex() {
        setCurrentIndex(workspaceTabs.selectedIndex)
    }

    background: Rectangle {
        objectName: "songTabStripBackground"
        color: workspaceChrome.background

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: workspaceChrome.borderWidth
            color: workspaceChrome.tabOutline
        }
    }

    // Window shortcuts select a tab without changing focus.
    Shortcut {
        sequence: "Ctrl+Tab"
        onActivated: {
            const next = strip.neighborSession(workspaceTabs.selectedIndex, 1)
            if (next !== null)
                workspaceUi.selectSongTab(next)
        }
    }
    Shortcut {
        sequence: "Ctrl+Shift+Tab"
        onActivated: {
            const next = strip.neighborSession(workspaceTabs.selectedIndex, -1)
            if (next !== null)
                workspaceUi.selectSongTab(next)
        }
    }

    Component.onCompleted: syncCurrentIndex()

    Repeater {
        model: workspaceTabs

        delegate: TabButton {
            id: songTab

            required property string songKey
            required property var session
            required property string title
            required property string tooltip
            required property int index

            objectName: "songTab:" + songKey
            text: title
            width: implicitWidth
            height: strip.height - 4 * workspaceChrome.borderWidth
            focusPolicy: Qt.TabFocus
            leftPadding: workspaceChrome.paddingHorizontal
            rightPadding: workspaceChrome.paddingHorizontal + workspaceChrome.closeSize
                           + workspaceChrome.spacing
            Keys.priority: Keys.BeforeItem

            // Pointer activation dispatches immediately; the editor is
            // entered only through sessionAccepted when accepted.
            onPressed: strip.activateSession(session, Qt.MouseFocusReason)
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space) {
                    // Same activation as pointer/accessibility; accepting
                    // here prevents a second stock key activation.
                    strip.activateSession(session, Qt.OtherFocusReason)
                    event.accepted = true
                } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                    // Local wrap navigation stays in the strip: focus the
                    // accepted session's tab, never the editor.
                    const step = event.key === Qt.Key_Right ? 1 : -1
                    const next = strip.neighborSession(workspaceTabs.selectedIndex, step)
                    if (next !== null) {
                        workspaceUi.selectSongTab(next)
                        if (workspaceTabs.selectedSession === next) {
                            const accepted = strip.itemAt(workspaceTabs.selectedIndex)
                            if (accepted !== null)
                                accepted.forceActiveFocus(Qt.OtherFocusReason)
                        }
                    }
                    event.accepted = true
                }
            }

            contentItem: Text {
                text: songTab.text
                textFormat: Text.PlainText
                color: songTab.checked ? workspaceChrome.tabSelectedText
                       : songTab.hovered ? workspaceChrome.tabHoverText
                       : workspaceChrome.tabText
                font: workspaceChrome.font
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                renderType: Text.NativeRendering
            }
            background: Rectangle {
                color: songTab.checked ? workspaceChrome.tabSelectedBackground
                       : songTab.hovered ? workspaceChrome.tabHoverBackground
                       : workspaceChrome.tabBackground
                border.width: workspaceChrome.borderWidth
                border.color: songTab.activeFocus ? workspaceChrome.focus
                                                  : workspaceChrome.tabOutline
                radius: workspaceChrome.radius
            }

            ToolTip.text: songTab.tooltip
            ToolTip.visible: songTab.hovered && songTab.tooltip.length > 0
            ToolTip.delay: 700

            // Nested close: its own activation only — a background close that
            // never selects and never emits the parent tab's activation.
            ToolButton {
                id: closeButton

                objectName: "songTabClose:" + songTab.songKey
                width: workspaceChrome.closeSize
                height: workspaceChrome.closeSize
                anchors.right: parent.right
                anchors.rightMargin: workspaceChrome.paddingHorizontal / 2
                anchors.verticalCenter: parent.verticalCenter
                focusPolicy: Qt.TabFocus
                text: "\u2715"
                font: workspaceChrome.font
                onClicked: workspaceUi.requestCloseTab(songTab.session)

                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Close %1").arg(songTab.title)
            }

            Accessible.role: Accessible.PageTab
            Accessible.name: songTab.title
            Accessible.description: songTab.tooltip
            Accessible.selected: songTab.checked
            Accessible.focusable: true
            Accessible.onPressAction: strip.activateSession(session, Qt.OtherFocusReason)
        }

        onItemAdded: strip.syncCurrentIndex()
        onItemRemoved: strip.syncCurrentIndex()
    }

    Connections {
        target: workspaceTabs
        function onSelectionChanged() { strip.syncCurrentIndex() }
        function onSelectedIndexChanged() { strip.syncCurrentIndex() }
    }
}
