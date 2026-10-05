// Original two-column parameter selector, bound directly to the Swift page.
pragma ComponentBehavior: Bound
import QtQuick
import PorydawStyle as Controls
import QtQuick.Templates as T
import QtQuick.Layouts
import Porydaw.Ui
import PorydawApp as App

Item {
    id: root
    required final property App.AutomationPage pageModel
    required final property Item sceneRoot
    final property App.MouseHints hintService: null
    final property bool hintScopeAllowed: true
    required final property App.GridPalette pagePalette
    final property font defaultFont
    readonly property real inset: pageModel ? pageModel.selectorInset : 0
    readonly property real stroke: 1
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
                model: root.pageModel ? root.pageModel.tabs : null
                Controls.TabButton {
                    id: tab
                    required property var model
                    required property int index
                    required property string label
                    required property bool tempo
                    required property bool active
                    required property bool available
                    required property int eventCount
                    required property bool ghosted
                    required property bool included
                    readonly property bool tempoParameter: tempo
                    objectName: "automationParameterTab" + index
                    text: label
                    font: root.pageModel ? root.pageModel.captionFont : root.defaultFont
                    padding: root.inset
                    rightPadding: tempoParameter
                        ? root.inset + tapControl.width + (root.pageModel ? root.pageModel.pipExtent : 0)
                        : root.inset
                    Layout.fillWidth: true
                    Layout.preferredWidth: tempoParameter ? scroller.width : scroller.width / 2
                    Layout.minimumHeight: root.pageModel ? root.pageModel.minimumCellHeight : 0
                    Layout.columnSpan: tempoParameter ? 2 : 1
                    Layout.topMargin: root.stroke
                    Layout.bottomMargin: root.stroke
                    Layout.leftMargin: root.stroke
                    Layout.rightMargin: root.stroke
                    focusPolicy: Qt.StrongFocus
                    hoverEnabled: true
                    checkable: false
                    checked: active
                    enabled: available
                    Accessible.name: tab.text
                    down: pressArea.pressed
                    function activate(): void {
                        if (root.pageModel) root.pageModel.activateParameter(tab.index)
                    }
                    function ensureVisible(): void {
                        if (scroller.moving) return
                        if (tab.y < scroller.contentY) scroller.contentY = tab.y
                        else if (tab.y + tab.height > scroller.contentY + scroller.height)
                            scroller.contentY = tab.y + tab.height - scroller.height
                    }
                    onCheckedChanged: if (checked) ensureVisible()
                    onActiveFocusChanged: if (activeFocus) ensureVisible()
                    onClicked: activate()
                    T.ContextMenu.onRequested: position => {
                        const p = tab.mapToItem(root.sceneRoot, position.x, position.y)
                        if (root.pageModel) root.pageModel.openParameterMenu(tab.index, p.x, p.y)
                    }
                    MouseArea {
                        id: pressArea
                        objectName: "automationParameterTabPress" + tab.index
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        onPressed: mouse => {
                            tab.forceActiveFocus()
                            if (!root.pageModel) return
                            if (mouse.modifiers & Qt.ControlModifier)
                                root.pageModel.toggleGhostParameter(tab.index)
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
                        height: root.pageModel ? root.pageModel.minimumCellHeight : 0
                        anchors.right: parent.right
                        anchors.rightMargin: root.inset + (root.pageModel ? root.pageModel.pipExtent : 0)
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
                            objectName: "automationTempoTapLabel"
                            anchors.centerIn: parent
                            text: qsTr("Tap")
                            font: root.pageModel ? root.pageModel.captionFont : root.defaultFont
                            color: tapPress.pressed ? root.pagePalette.selectionText : root.pagePalette.primaryText
                            Accessible.ignored: true
                        }
                        MouseArea {
                            id: tapPress
                            anchors.fill: parent
                            onPressed: {
                                tapControl.forceActiveFocus()
                                if (root.pageModel) root.pageModel.tapTempoTap()
                            }
                        }
                        HoverHandler { id: tapHover }
                        Keys.onPressed: event => {
                            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                && event.modifiers === Qt.NoModifier && !event.isAutoRepeat) {
                                if (root.pageModel) root.pageModel.tapTempoTap()
                                event.accepted = true
                            }
                        }
                        Keys.onShortcutOverride: event => event.accepted =
                            (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                            && event.modifiers === Qt.NoModifier && !event.isAutoRepeat
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Tap tempo")
                        Accessible.focusable: true
                        Accessible.onPressAction: if (root.pageModel) root.pageModel.tapTempoTap()
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
                            opacity: tab.eventCount > 0 ? 1 : 0
                            Layout.preferredWidth: root.pageModel ? root.pageModel.pipExtent : 0
                            Layout.preferredHeight: width
                            radius: width / 2
                            color: root.pagePalette.automationNodeInk
                        }
                        Text {
                            objectName: "automationParameterTabText"
                            text: tab.text
                            textFormat: Text.PlainText
                            font: tab.font
                            fontSizeMode: Text.HorizontalFit
                            minimumPixelSize: root.pageModel ? root.pageModel.minimumFont.pixelSize : 0
                            elide: Text.ElideNone
                            Layout.fillWidth: true
                            color: tab.checked ? root.pagePalette.buttonPressedText : root.pagePalette.windowText
                        }
                        Text {
                            objectName: "automationParameterEventCount"
                            opacity: tab.checked && tab.eventCount > 0 ? 1 : 0
                            text: tab.eventCount === 1 ? qsTr("1 event") : qsTr("%1 events").arg(tab.eventCount)
                            textFormat: Text.PlainText
                            font: root.pageModel ? root.pageModel.minimumFont : root.defaultFont
                            color: tab.checked ? root.pagePalette.buttonPressedText : root.pagePalette.windowText
                        }
                        Text {
                            objectName: tab.tempoParameter ? "automationTempoTapDraft" : ""
                            visible: tab.tempoParameter && root.pageModel && root.pageModel.tapTempoTapCount > 0
                            text: root.pageModel && root.pageModel.tapTempoTapCount >= 2
                                ? qsTr("%1 BPM").arg(root.pageModel.tapTempoDraftBpm) : "..."
                            textFormat: Text.PlainText
                            font: root.pageModel ? root.pageModel.minimumFont : root.defaultFont
                            color: tab.checked ? root.pagePalette.buttonPressedText : root.pagePalette.windowText
                        }
                    }
                    background: Rectangle {
                        color: tab.checked ? root.pagePalette.tabPressedBackground
                            : tab.hovered ? root.pagePalette.tabHoverBackground
                                          : root.pagePalette.automationTabBackground
                        border.width: root.stroke
                        border.color: root.pagePalette.automationTabOutline
                        Rectangle {
                            visible: tab.ghosted
                            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                            anchors.margins: root.stroke
                            height: root.stroke
                            color: root.pagePalette.outline
                        }
                        Rectangle {
                            objectName: "automationParameterInclusionBar"
                            visible: tab.included && !tab.checked
                            anchors.top: parent.top; anchors.right: parent.right; anchors.bottom: parent.bottom
                            anchors.margins: root.stroke
                            width: root.pageModel ? root.pageModel.pipExtent : 0
                            color: root.pagePalette.tabPressedBackground
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
                        + (tab.included ? qsTr("; included in shared selection") : qsTr("; not in shared selection"))
                        + (tab.ghosted ? qsTr("; shown as ghost nodes") : "")
                }
            }
        }
    }
    Timer {
        id: idle
        interval: root.pageModel ? root.pageModel.tapTempoIdleCommitMs : 0
        onTriggered: if (root.pageModel) root.pageModel.tapTempoIdleElapsed()
    }
    Connections {
        target: root.pageModel
        function onTapTempoTapCountChanged(): void {
            if (root.pageModel && root.pageModel.tapTempoTapCount > 0) idle.restart()
            else idle.stop()
        }
    }
}
