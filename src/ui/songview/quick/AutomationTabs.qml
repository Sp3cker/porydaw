// Compact parameter selector for the automation gutter: catalog identities
// as native Basic TabButtons in two columns, followed by a full-width Tempo
// row. The canvas owns parameter identity, the parameter menu and shared
// selection semantics. A Flickable owns vertical overflow, so the catalog
// can grow without increasing the drawer's minimum height.
import QtQuick
import QtQuick.Controls.Basic as Controls
import QtQuick.Layouts
import Porydaw.Ui

Item {
    id: root

    required property var canvas
    required property Item sceneRoot

    readonly property var appearance: canvas.parameterAppearance

    // One shared inclusion list for the whole grid: the canvas getter builds
    // a QList per read, so the tabs read a single root-level snapshot
    // instead of one per-tab copy.
    readonly property var selectedParams: root.canvas.selectedParameters

    readonly property var eventCounts: root.canvas.parameterEventCounts

    readonly property var ghostParams: root.canvas.ghostParameters

    Flickable {
        id: gutterScroller

        anchors.fill: parent
        interactive: false
        clip: true
        contentWidth: width
        contentHeight: grid.implicitHeight

        GridLayout {
            id: grid

            width: gutterScroller.width

            // Two cells per row: each row pairs the identities that belong
            // together, so the grid halves the labels' cumulative height
            // while still filling the gutter's width in two equal columns.
            columns: 2
            rowSpacing: 0

            Repeater {
                model: root.canvas.parameterLabels

                Controls.TabButton {
                    id: tab

                    required property int index
                    required property string modelData

                    // Song-global Tempo closes the catalog, after the CC
                    // identities, on its own full-width row.
                    readonly property bool tempoParameter:
                        tab.index === root.canvas.parameterLabels.length - 1
                    readonly property bool selectionIncluded:
                        root.selectedParams.includes(tab.index)
                    readonly property bool ghostShown:
                        root.ghostParams.includes(tab.index)
                    readonly property bool inclusionMarked:
                        tab.selectionIncluded && !tab.checked
                    readonly property var eventCount: root.eventCounts[tab.index] ?? 0
                    readonly property bool hasEvents: tab.eventCount > 0

                    objectName: "automationParameterTab" + index
                    text: modelData
                    font: root.appearance.font
                    padding: root.appearance.inset
                    // The tempo row's Tap button sits outside the content
                    // layout (below): reserve its width plus the row gap so
                    // the draft readout never slides under it.
                    rightPadding: tab.tempoParameter
                                  ? root.appearance.inset
                                    + tapTempoButton.implicitWidth
                                    + root.appearance.inset
                                  : root.appearance.inset
                    focusPolicy: Qt.StrongFocus
                    // The QTabBar-style hover fill must not depend on the
                    // platform's useHoverEffects default.
                    hoverEnabled: true
                    Layout.fillWidth: true
                    Layout.minimumHeight: root.appearance.minimumCellHeight
                    Layout.columnSpan: tab.tempoParameter ? 2 : 1
                    Layout.topMargin: root.appearance.stroke
                    Layout.bottomMargin: root.appearance.stroke
                    Layout.rightMargin: (tab.tempoParameter || tab.index % 2 === 1)
                                        ? root.appearance.pointHitRadius : 0

                    checkable: false
                    checked: root.canvas.activeParameter === tab.index

                    down: pressArea.pressed
                    onClicked: root.canvas.parameterClicked(tab.index)

                    MouseArea {
                        id: pressArea
                        acceptedButtons: Qt.LeftButton
                        anchors.fill: parent
                        onPressed: (mouse) => {
                            tab.forceActiveFocus()
                            root.canvas.parameterPressed(tab.index, mouse.modifiers)
                        }
                    }

                    // One hint group per tab: Control + click toggles the
                    // ghost parameter instead of normal activation. The
                    // description shows unconditionally, without mirroring
                    // canGhostParameter and without touching the tab's
                    // activation, hover or ghost-color behavior.
                    // Qt broadens a handler's parent's accepted mouse buttons.
                    // Keep the handler off the TabButton so a right press does
                    // not take ClickFocus before its context menu opens.
                    Item {
                        anchors.fill: parent

                        HoverHint {
                            source: tab
                            profile: (tab.tempoParameter && tapTempoButton.hovered
                                      && root.canvas.parametersEnabled)
                                         ? HintProfiles.TapTempo
                                         : HintProfiles.GhostParameter
                        }
                    }

                    // Tempo row tap-tempo button: a plain Item (never a
                    // Controls.Button) so a bare Space stays unclaimed for
                    // the transport play/pause shortcut. Presses register
                    // the tap (press, not release, so the draft updates
                    // immediately) and are consumed here so the surrounding
                    // TabButton never activates. It lives outside the
                    // contentItem RowLayout, declared after pressArea, so it
                    // stacks above the tab-wide press area instead of being
                    // occluded by it; rightPadding above reserves its slot.
                    Item {
                        id: tapTempoButton

                        objectName: tab.tempoParameter
                                    ? "automationTempoTapButton" : ""
                        visible: tab.tempoParameter
                        enabled: root.canvas.parametersEnabled
                        opacity: enabled ? 1.0 : 0.5
                        readonly property bool hovered: tapHoverHandler.hovered
                        implicitWidth: tapLabelItem.implicitWidth
                                       + 2 * root.appearance.inset
                        implicitHeight: root.appearance.minimumCellHeight
                        width: implicitWidth
                        height: implicitHeight
                        anchors.right: parent.right
                        anchors.rightMargin: root.appearance.inset
                        anchors.verticalCenter: parent.verticalCenter
                        activeFocusOnTab: true

                        Rectangle {
                            anchors.fill: parent
                            color: tapPressArea.pressed
                                       ? root.appearance.tabSelectedBackground
                                   : tapTempoButton.hovered
                                       ? root.appearance.tabHoverBackground
                                   : root.appearance.tabBackground
                            border.width: root.appearance.stroke
                            border.color: root.appearance.tabOutline
                        }

                        Text {
                            id: tapLabelItem

                            anchors.centerIn: parent
                            font: tab.font
                            text: qsTr("Tap")
                            textFormat: Text.PlainText
                            color: root.appearance.tabText
                            Accessible.ignored: true
                        }

                        MouseArea {
                            id: tapPressArea

                            acceptedButtons: Qt.LeftButton
                            enabled: tapTempoButton.enabled
                            anchors.fill: parent
                            onPressed: (mouse) => {
                                tapTempoButton.forceActiveFocus()
                                root.canvas.tapTempo()
                            }
                        }

                        HoverHandler {
                            id: tapHoverHandler
                        }

                        // Same activation-key contract as the tab
                        // above: only plain Return/Enter (no auto
                        // repeat) activates, and only those keys are
                        // claimed from window shortcuts — bare Space
                        // stays with the transport.
                        Keys.priority: Keys.AfterItem
                        Keys.onPressed: (event) => {
                            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                    && !event.isAutoRepeat
                                    && event.modifiers === Qt.NoModifier) {
                                root.canvas.tapTempo()
                                event.accepted = true
                            }
                        }
                        Keys.onShortcutOverride: (event) => event.accepted =
                            (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                            && event.modifiers === Qt.NoModifier && !event.isAutoRepeat

                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Tap tempo")
                        Accessible.description:
                            root.canvas.tapTempoTapCount >= 2
                                ? qsTr("Draft tempo: %1 BPM").arg(
                                      root.canvas.tapTempoDraftBpm)
                                : root.canvas.tapTempoTapCount > 0
                                    ? qsTr("Listening for tempo taps")
                                    : qsTr("Tap repeatedly to set the song tempo")
                        Accessible.focusable: true
                        Accessible.onPressAction: root.canvas.tapTempo()
                    }

                    // Keyboard focus or a checked change must never leave the
                    // tab outside the Flickable viewport: scroll by the
                    // minimum contentY delta that fits the tab fully into
                    // view (standard ensure-visible — no recentering, no
                    // animation). Reacts only to checked/focus transitions,
                    // never tracks continuously, and stands down while the
                    // user's drag or flick is still in progress.
                    onCheckedChanged: if (checked) tab.ensureVisible()
                    onActiveFocusChanged: if (activeFocus) tab.ensureVisible()

                    function ensureVisible() {
                        if (gutterScroller.moving) return
                        const top = tab.y
                        const bottom = top + tab.height
                        if (top < gutterScroller.contentY)
                            gutterScroller.contentY = top
                        else if (bottom > gutterScroller.contentY + gutterScroller.height)
                            gutterScroller.contentY = bottom - gutterScroller.height
                    }

                    // Extend the advertised activation keys only where the native
                    // button left them unhandled; auto-repeat and modified Return
                    // stay editing input. Unhandled keys continue to the shared
                    // SongView policy exactly once.
                    Keys.priority: Keys.AfterItem
                    Keys.onPressed: (event) => {
                        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                && !event.isAutoRepeat
                                && event.modifiers === Qt.NoModifier) {
                            root.canvas.activateParameter(tab.index)
                            event.accepted = true
                        }
                    }
                    // Claim only the plain Return/Enter activation keys before
                    // window-level shortcuts can take them from this focused
                    // label: an item beats a shortcut only by accepting the
                    // ShortcutOverride event. Bare Space stays unclaimed here so
                    // the transport play/pause window shortcut outranks
                    // incidental focus in this persistent control. Modified or
                    // auto-repeat variants stay unclaimed and continue to the
                    // shared SongView policy, matching onPressed below.
                    Keys.onShortcutOverride: (event) => event.accepted =
                        (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        && event.modifiers === Qt.NoModifier && !event.isAutoRepeat

                    // Right-click and the context-menu key route through the
                    // platform event into the existing owned parameter menu.
                    Controls.ContextMenu.onRequested: (position) => {
                        const p = tab.mapToItem(root.sceneRoot, position.x, position.y)
                        root.canvas.openParameterMenu(tab.index, p.x, p.y)
                    }

                    contentItem: RowLayout {
                        spacing: root.appearance.inset

                        Rectangle {
                            opacity: tab.hasEvents ? 1.0 : 0.0
                            Layout.preferredWidth: root.appearance.pipExtent
                            Layout.preferredHeight: root.appearance.pipExtent
                            Layout.alignment: Qt.AlignVCenter
                            radius: width / 2
                            color: root.appearance.pipColor
                            Accessible.ignored: true
                        }

                        Text {
                            id: tabLabel
                            objectName: "automationParameterTabText"
                            text: tab.text
                            font: tab.font
                            fontSizeMode: Text.HorizontalFit
                            minimumPixelSize: root.appearance.minimumFont.pixelSize
                            textFormat: Text.PlainText
                            horizontalAlignment: Text.AlignLeft
                            elide: Text.ElideNone
                            verticalAlignment: Text.AlignVCenter
                            Layout.fillWidth: true
                            color: tab.checked ? root.appearance.tabSelectedText
                                               : tab.hovered ? root.appearance.tabHoverText
                                                             : root.appearance.tabText
                            Accessible.ignored: true
                        }

                        Text {
                            objectName: "automationParameterEventCount"
                            // Reserve the same space while switching parameters.
                            opacity: tab.checked && tab.hasEvents ? 0.7 : 0.0
                            text: tab.eventCount === 1 ? qsTr("1 event")
                                                      : qsTr("%1 events").arg(tab.eventCount)
                            font: root.appearance.minimumFont
                            color: tabLabel.color
                            horizontalAlignment: Text.AlignRight
                            verticalAlignment: Text.AlignVCenter
                            Accessible.ignored: true
                        }

                        // Live tap-tempo draft readout: appears only once
                        // the canvas accumulator is listening, and stays
                        // out of the accessible tree — the Tap button
                        // below carries the accessible description.
                        Text {
                            objectName: tab.tempoParameter
                                        ? "automationTempoTapDraft" : ""
                            visible: tab.tempoParameter
                                     && root.canvas.tapTempoTapCount > 0
                            text: root.canvas.tapTempoTapCount >= 2
                                      ? "%1 BPM".arg(root.canvas.tapTempoDraftBpm)
                                      : "…"
                            font: root.appearance.minimumFont
                            color: root.appearance.tabText
                            verticalAlignment: Text.AlignVCenter
                            Accessible.ignored: true
                        }

                    }

                    // Distinct indicators: the active tab takes the selected
                    background: Rectangle {
                        color: tab.checked ? root.appearance.tabSelectedBackground
                                           : tab.hovered ? root.appearance.tabHoverBackground
                                                         : root.appearance.tabBackground
                        border.width: root.appearance.stroke
                        border.color: root.appearance.tabOutline

                        Rectangle {
                            visible: tab.ghostShown
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: root.appearance.stroke
                            height: root.appearance.stroke
                            color: root.appearance.ghostEdge
                        }

                        Rectangle {
                            visible: tab.inclusionMarked
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.topMargin: root.appearance.stroke
                            anchors.rightMargin: root.appearance.stroke
                            anchors.bottomMargin: root.appearance.stroke
                            width: root.appearance.pipExtent
                            color: root.appearance.tabSelectedBackground
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: root.appearance.stroke
                            color: "transparent"
                            border.width: root.appearance.stroke
                            border.color: tab.visualFocus
                                          ? root.appearance.focusOutline : "transparent"
                        }
                    }

                    // Tab selection for screen readers, never shared-time
                    // inclusion; inclusion stays text-only in the description.
                    Accessible.selected: tab.checked
                    Accessible.description:
                        (tab.tempoParameter ? qsTr("Song-global tempo parameter")
                                            : qsTr("Track automation parameter"))
                        + (tab.selectionIncluded
                           ? qsTr("; included in shared selection")
                           : qsTr("; not in shared selection"))
                        + (tab.ghostShown ? qsTr("; shown as ghost nodes") : "")
                        + (tab.checked && tab.hasEvents
                           ? qsTr("; %1 events").arg(tab.eventCount) : "")
                }
            }
        }
    }
}
