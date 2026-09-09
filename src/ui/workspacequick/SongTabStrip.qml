// The open-song tab strip: one accessible tab button per open song. The strip
// emits semantic requests only — select, background close, and pointer reorder
// go through WorkspaceQuickHost, whose controller validates and applies every
// policy decision; the model's selection is read-only here. Tabs never take
// active focus on pointer press (keyboard traversal is opt-in through the tab
// chain), window-level Ctrl+Tab/Ctrl+Shift+Tab shortcuts drive the standard
// next/previous tab navigation from any focus state — a focused page, no page
// focus, or a tab — with editable items keeping the usual ShortcutOverride
// first refusal, and a strip too narrow for all tabs keeps every tab
// reachable by flicking and by the selected-tab auto-reveal.
// Titles carry the model's dirty marker, tooltips carry the model's mid path.
import QtQuick
import Porydaw.Ui

Rectangle {
    id: strip

    color: workspaceChrome.background

    readonly property real chromeSpacing: workspaceChrome.spacing

    function showTooltip(tab) {
        if (!tab.tooltip || tab.tooltip.length === 0) {
            hideTooltip()
            return
        }
        const center = tab.mapToItem(strip, tab.width / 2, 0).x
        tooltipLabel.text = tab.tooltip
        tooltip.x = Math.max(0, Math.min(center - tooltip.width / 2, width - tooltip.width))
        tooltip.y = height + chromeSpacing
        tooltipTimer.restart()
    }

    function hideTooltip() {
        tooltipTimer.stop()
        tooltip.visible = false
    }

    // Standard next/previous tab navigation: window-scoped shortcuts work
    // from every focus state — a focused page canvas, no page focus, or a
    // focused tab — instead of only inside the strip's key subtree. Qt's
    // shortcut machinery gives editable items their ShortcutOverride first
    // refusal automatically, so text/IME input still wins.
    Shortcut {
        sequence: "Ctrl+Tab"
        onActivated: workspaceHost.requestSelect(
            workspaceHost.neighborSession(workspaceTabs.selectedIndex, 1))
    }
    Shortcut {
        sequence: "Ctrl+Shift+Tab"
        onActivated: workspaceHost.requestSelect(
            workspaceHost.neighborSession(workspaceTabs.selectedIndex, -1))
    }

    component SongTabButton: Item {
        id: tab

        required property int index
        required property string songKey
        required property var session
        required property string title
        required property string tooltip

        readonly property bool isSelected: ListView.isCurrentItem
        // Press anchor in the ListView content frame, which stays fixed while
        // this delegate's own drag translation moves beneath the cursor.
        property real pressContentX: 0
        property bool dragActive: false

        objectName: "songTab:" + songKey
        width: Math.max(workspaceChrome.minimumTabWidth,
                        titleText.implicitWidth + 2 * workspaceChrome.paddingHorizontal
                                + workspaceChrome.closeSize + chromeSpacing)
        height: ListView.view ? ListView.view.height : workspaceChrome.stripHeight
        activeFocusOnTab: true

        transform: Translate {
            id: dragTranslate

            x: 0
        }

        Keys.onPressed: (event) => {
            // Activation keys only; Ctrl+Tab navigation is the window-level
            // shortcuts' job above.
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space) {
                workspaceHost.requestSelect(tab.session)
                event.accepted = true
            }
        }

        Rectangle {
            id: background

            anchors.fill: parent
            color: tab.isSelected ? workspaceChrome.tabSelectedBackground
                  : tabBody.containsMouse ? workspaceChrome.tabHoverBackground
                  : workspaceChrome.tabBackground
            border.width: workspaceChrome.borderWidth
            border.color: tab.activeFocus ? workspaceChrome.focus : workspaceChrome.tabOutline
            radius: workspaceChrome.radius
        }

        Text {
            id: titleText

            x: workspaceChrome.paddingHorizontal
            width: parent.width - 2 * workspaceChrome.paddingHorizontal
                   - workspaceChrome.closeSize - chromeSpacing
            anchors.verticalCenter: parent.verticalCenter
            text: tab.title
            textFormat: Text.PlainText
            color: tab.isSelected ? workspaceChrome.tabSelectedText
                   : tabBody.containsMouse ? workspaceChrome.tabHoverText
                   : workspaceChrome.tabText
            font: workspaceChrome.font
            elide: Text.ElideRight
            renderType: Text.NativeRendering
        }

        MouseArea {
            id: tabBody

            anchors.fill: parent
            hoverEnabled: true
            // An intentional tab drag keeps its press: once the threshold is
            // crossed the ListView must not steal the gesture into a flick,
            // or the release destination never reaches requestMove. Wheel
            // scrolling over the strip is unaffected.
            preventStealing: true
            cursorShape: Qt.PointingHandCursor

            onPressed: (mouse) => {
                tab.pressContentX = tabBody.mapToItem(tabList.contentItem, mouse.x, mouse.y).x
                tab.dragActive = false
                strip.hideTooltip()
            }
            onPositionChanged: (mouse) => {
                // Hover never drags: only a held left press owns a reorder.
                if (!tabBody.pressed || !(mouse.buttons & Qt.LeftButton))
                    return
                const cursorX = tabBody.mapToItem(tabList.contentItem, mouse.x, mouse.y).x
                if (!tab.dragActive
                    && Math.abs(cursorX - tab.pressContentX) > workspaceChrome.dragThreshold) {
                    tab.dragActive = true
                    strip.hideTooltip()
                }
                if (tab.dragActive)
                    dragTranslate.x = cursorX - tab.pressContentX
            }
            onReleased: (mouse) => {
                if (tab.dragActive) {
                    const point = tabBody.mapToItem(tabList.contentItem, mouse.x, mouse.y)
                    let destination = tabList.indexAt(point.x, tabList.height / 2)
                    if (destination === -1)
                        destination = point.x >= tabList.contentX + tabList.width
                                      ? tabList.count - 1 : 0
                    dragTranslate.x = 0
                    tab.dragActive = false
                    workspaceHost.requestMove(tab.session, destination)
                } else {
                    workspaceHost.requestSelect(tab.session)
                }
            }
            onCanceled: {
                dragTranslate.x = 0
                tab.dragActive = false
            }
            onContainsMouseChanged: {
                if (containsMouse)
                    strip.showTooltip(tab)
                else
                    strip.hideTooltip()
            }
        }
        Item {
            id: closeButton

            objectName: "songTabClose:" + tab.songKey
            width: workspaceChrome.closeSize
            height: workspaceChrome.closeSize
            anchors.right: parent.right
            anchors.rightMargin: workspaceChrome.paddingHorizontal / 2
            anchors.verticalCenter: parent.verticalCenter

            Text {
                anchors.centerIn: parent
                text: "\u2715"
                textFormat: Text.PlainText
                color: closeArea.containsMouse || closeArea.pressed
                       ? workspaceChrome.tabText : workspaceChrome.disabledText
                font: workspaceChrome.font
                renderType: Text.NativeRendering
            }

            MouseArea {
                id: closeArea

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: workspaceHost.requestClose(tab.session)
            }

            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Close %1").arg(tab.title)
            Accessible.onPressAction: workspaceHost.requestClose(tab.session)
        }

        Accessible.role: Accessible.PageTab
        Accessible.name: tab.title
        Accessible.description: tab.tooltip
        Accessible.selected: tab.isSelected
        Accessible.focusable: true
        Accessible.onPressAction: workspaceHost.requestSelect(tab.session)
    }

    ListView {
        id: tabList

        objectName: "songTabStripList"
        anchors.fill: parent
        clip: true
        orientation: ListView.Horizontal
        interactive: true
        model: workspaceTabs
        currentIndex: workspaceTabs.selectedIndex
        onCurrentIndexChanged: if (tabList.currentIndex >= 0)
            tabList.positionViewAtIndex(tabList.currentIndex, ListView.Contain)
        delegate: SongTabButton {}
    }

    Rectangle {
        id: tooltip

        visible: false
        z: 1
        width: tooltipLabel.implicitWidth + 2 * workspaceChrome.paddingHorizontal
        height: tooltipLabel.implicitHeight + workspaceChrome.spacing
        color: workspaceChrome.tooltipBackground
        border.width: workspaceChrome.borderWidth
        border.color: workspaceChrome.tooltipOutline
        radius: workspaceChrome.radius

        Text {
            id: tooltipLabel

            anchors.centerIn: parent
            color: workspaceChrome.tooltipText
            font: workspaceChrome.font
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            renderType: Text.NativeRendering
        }
    }

    Timer {
        id: tooltipTimer

        interval: 700
        onTriggered: tooltip.visible = tooltipLabel.text.length > 0
    }
}
