// Original two-column parameter selector, bound directly to the Swift page.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as Controls
import QtQuick.Layouts
import Porydaw.Ui

Item {
    id: root
    required property var pageModel
    required property Item sceneRoot
    property var hintService: null
    property bool hintScopeAllowed: true
    required property var pagePalette
    readonly property real baseFontPx: pageModel.baseFontPx
    readonly property real inset: Math.round(baseFontPx / 3)
    readonly property real stroke: Math.max(1, Math.round(baseFontPx / 13))
    Flickable {
        id: scroller
        objectName: "automationTabsScroller"
        anchors.fill: parent
        interactive: false
        clip: true
        contentWidth: width
        contentHeight: grid.implicitHeight
        GridLayout {
            id: grid
            width: scroller.width
            columns: 2
            columnSpacing: 0
            rowSpacing: 0
            Repeater {
                model: root.pageModel.tabs
                Controls.TabButton {
                    id: tab
                    required property var model
                    readonly property bool tempoParameter: model.tempo
                    objectName: "automationParameterTab" + model.index
                    text: model.label
                    font: Qt.font(root.pageModel.titleFont)
                    padding: root.inset
                    rightPadding: tempoParameter ? root.inset + tapControl.width : root.inset
                    Layout.fillWidth: true
                    Layout.preferredWidth: tempoParameter ? scroller.width : scroller.width / 2
                    Layout.minimumHeight: root.baseFontPx * 4 / 3
                    Layout.columnSpan: tempoParameter ? 2 : 1
                    Layout.topMargin: root.stroke
                    Layout.bottomMargin: root.stroke
                    Layout.leftMargin: root.stroke
                    Layout.rightMargin: root.stroke
                    focusPolicy: Qt.StrongFocus
                    hoverEnabled: true
                    checkable: false
                    checked: model.active
                    enabled: model.available
                    Accessible.name: tab.text
                    down: pressArea.pressed
                    function activate() { root.pageModel.activateParameter(model.index) }
                    function ensureVisible() {
                        if (scroller.moving) return
                        if (y < scroller.contentY) scroller.contentY = y
                        else if (y + height > scroller.contentY + scroller.height)
                            scroller.contentY = y + height - scroller.height
                    }
                    onCheckedChanged: if (checked) ensureVisible()
                    onActiveFocusChanged: if (activeFocus) ensureVisible()
                    onClicked: activate()
                    Controls.ContextMenu.onRequested: position => {
                        const p = tab.mapToItem(root.sceneRoot, position.x, position.y)
                        root.pageModel.openParameterMenu(tab.model.index, p.x, p.y)
                    }
                    MouseArea {
                        id: pressArea
                        objectName: "automationParameterTabPress" + tab.model.index
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        onPressed: mouse => {
                            tab.forceActiveFocus()
                            if (mouse.modifiers & Qt.ControlModifier)
                                root.pageModel.toggleGhostParameter(tab.model.index)
                            else tab.activate()
                        }
                    }
                    HoverHint {
                        source: tab
                        hintService: root.hintService
                        scopeAllowed: root.hintScopeAllowed
                        profile: tab.tempoParameter && tapHover.hovered
                            ? HintProfiles.TapTempo : HintProfiles.GhostParameter
                    }
                    Item {
                        id: tapControl
                        objectName: tab.tempoParameter ? "automationTempoTapButton" : ""
                        visible: tab.tempoParameter
                        width: tapLabel.implicitWidth + 2 * root.inset
                        height: tab.height - 2 * root.stroke
                        anchors.right: parent.right
                        anchors.rightMargin: root.inset
                        anchors.verticalCenter: parent.verticalCenter
                        activeFocusOnTab: true
                        Rectangle {
                            anchors.fill: parent
                            color: tapPress.pressed ? root.pagePalette.selectionRing : root.pagePalette.chromeBackground
                            border.width: root.stroke
                            border.color: root.pagePalette.outline
                        }
                        Text {
                            id: tapLabel
                            anchors.centerIn: parent
                            text: qsTr("Tap")
                            font: Qt.font(root.pageModel.captionFont)
                            color: tapPress.pressed ? root.pagePalette.selectionText : root.pagePalette.primaryText
                            Accessible.ignored: true
                        }
                        MouseArea {
                            id: tapPress
                            anchors.fill: parent
                            onPressed: { tapControl.forceActiveFocus(); root.pageModel.tapTempoTap() }
                        }
                        HoverHandler { id: tapHover }
                        Keys.onPressed: event => {
                            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                && event.modifiers === Qt.NoModifier && !event.isAutoRepeat) {
                                root.pageModel.tapTempoTap(); event.accepted = true
                            }
                        }
                        Keys.onShortcutOverride: event => event.accepted =
                            (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                            && event.modifiers === Qt.NoModifier && !event.isAutoRepeat
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Tap tempo")
                        Accessible.focusable: true
                        Accessible.onPressAction: root.pageModel.tapTempoTap()
                    }
                    Keys.priority: Keys.AfterItem
                    Keys.onPressed: event => {
                        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                            && event.modifiers === Qt.NoModifier && !event.isAutoRepeat) {
                            activate(); event.accepted = true
                        }
                    }
                    Keys.onShortcutOverride: event => event.accepted =
                        (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        && event.modifiers === Qt.NoModifier && !event.isAutoRepeat
                    contentItem: RowLayout {
                        spacing: root.inset
                        Rectangle {
                            opacity: tab.model.eventCount > 0 ? 1 : 0
                            Layout.preferredWidth: root.baseFontPx / 2
                            Layout.preferredHeight: width
                            radius: width / 2
                            color: root.pagePalette.primaryText
                        }
                        Text {
                            objectName: "automationParameterTabText"
                            text: tab.text
                            textFormat: Text.PlainText
                            font: tab.font
                            fontSizeMode: Text.HorizontalFit
                            minimumPixelSize: Math.round(root.pageModel.baseFontPx / 2)
                            elide: Text.ElideNone
                            Layout.fillWidth: true
                            color: tab.checked ? root.pagePalette.selectionText : tab.hovered ? root.pagePalette.windowText : root.pagePalette.secondaryText
                        }
                        Text {
                            objectName: "automationParameterEventCount"
                            opacity: tab.checked && tab.model.eventCount > 0 ? 1 : 0
                            text: tab.model.eventCount === 1 ? qsTr("1 event") : qsTr("%1 events").arg(tab.model.eventCount)
                            textFormat: Text.PlainText
                            font: Qt.font(root.pageModel.captionFont)
                            color: root.pagePalette.selectionText
                        }
                        Text {
                            objectName: tab.tempoParameter ? "automationTempoTapDraft" : ""
                            visible: tab.tempoParameter && root.pageModel.tapTempoTapCount > 0
                            text: root.pageModel.tapTempoTapCount >= 2 ? qsTr("%1 BPM").arg(root.pageModel.tapTempoDraftBpm) : "..."
                            textFormat: Text.PlainText
                            font: Qt.font(root.pageModel.captionFont)
                            color: tab.checked ? root.pagePalette.selectionText : tab.hovered ? root.pagePalette.windowText : root.pagePalette.secondaryText
                        }
                    }
                    background: Rectangle {
                        color: tab.checked ? root.pagePalette.selectionRing
                            : tab.hovered ? root.pagePalette.selectionFill : root.pagePalette.chromeBackground
                        border.width: root.stroke
                        border.color: root.pagePalette.outline
                        Rectangle {
                            visible: tab.model.ghosted
                            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                            anchors.margins: root.stroke
                            height: root.stroke
                            color: root.pagePalette.outline
                        }
                        Rectangle {
                            visible: tab.model.included && !tab.checked
                            anchors.top: parent.top; anchors.right: parent.right; anchors.bottom: parent.bottom
                            anchors.margins: root.stroke
                            width: root.baseFontPx / 2
                            color: root.pagePalette.selectionRing
                        }
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: root.stroke
                            color: "transparent"
                            border.width: root.stroke
                            border.color: tab.visualFocus ? root.pagePalette.primaryText : "transparent"
                        }
                    }
                    Accessible.selected: tab.checked
                    Accessible.description: (tab.tempoParameter ? qsTr("Song-global tempo parameter") : qsTr("Track automation parameter"))
                        + (tab.model.included ? qsTr("; included in shared selection") : qsTr("; not in shared selection"))
                        + (tab.model.ghosted ? qsTr("; shown as ghost nodes") : "")
                }
            }
        }
    }
    Timer {
        id: idle
        interval: root.pageModel.tapTempoIdleCommitMs
        onTriggered: root.pageModel.tapTempoIdleElapsed()
    }
    Connections {
        target: root.pageModel
        function onTapTempoTapCountChanged() {
            if (root.pageModel.tapTempoTapCount > 0) idle.restart()
            else idle.stop()
        }
    }
}
