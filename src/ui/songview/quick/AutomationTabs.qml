// Compact parameter selector for the automation gutter: the nine standard
// parameter identities as native Basic TabButtons in two columns, one related
// pair per row in catalog order (mix, pitch, echo), with song-global Tempo
// spanning the last row. Qt owns focus, activation and accessibility
// plumbing; the canvas owns parameter identity, the parameter menu and
// shared-selection semantics. The grid scrolls inside the gutter: a
// Flickable owns the vertical overflow, so the tab stack may be taller than
// the drawer's body floor allows without clipping or fighting the drawer.
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

    // One shared pip list for the whole grid, same one-snapshot discipline:
    // one bool per catalog index, true where the document holds written
    // events for that identity.
    readonly property var pips: root.canvas.parameterPips

    // One shared ghost list, same one-snapshot discipline: catalog indexes
    // the user ghost-enabled for display-only plot curves.
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
                    // Ghost-enabled tabs show their nodes as ineditable ghosts
                    // in the plot; the bottom rule is that user toggle.
                    // Shared-selection inclusion keeps its own mark instead.
                    readonly property bool ghostShown:
                        root.ghostParams.includes(tab.index)
                    // The selection bar marks scope beyond the lane being
                    // edited: the active tab already carries the checked
                    // fill, so inclusion is only drawn where it adds
                    // information.
                    readonly property bool inclusionMarked:
                        tab.selectionIncluded && !tab.checked
                    readonly property bool hasEvents: root.pips[tab.index] === true

                    objectName: "automationParameterTab" + index
                    text: modelData
                    font: root.appearance.font
                    padding: root.appearance.inset
                    // The pip cell is always reserved — drawn or not — so every
                    // label's left edge aligns down the gutter.
                    leftPadding: root.appearance.inset + root.appearance.pipExtent
                                 + root.appearance.inset
                    focusPolicy: Qt.StrongFocus
                    // The QTabBar-style hover fill must not depend on the
                    // platform's useHoverEffects default.
                    hoverEnabled: true
                    Layout.fillWidth: true
                    Layout.minimumHeight: root.appearance.minimumCellHeight
                    Layout.columnSpan: tab.tempoParameter ? 2 : 1

                    // Display-only indicator: the canvas stays the sole
                    // parameter authority, so neither a click, Space, nor an
                    // exclusivity group may write `checked` — the explicit
                    // press/click handlers below own activation.
                    checkable: false
                    checked: root.canvas.activeParameter === tab.index

                    // Press-down dispatch through the canvas, which reads the
                    // live modifiers — AbstractButton signals carry none:
                    // plain press activates (matching QTabBar), command-press
                    // toggles the ghost. Clicked stays the fallback for
                    // assistive-tech presses and keyboard activation; a real
                    // command-click already toggled on press, so the canvas
                    // never toggles twice.
                    onPressed: {
                        tab.forceActiveFocus()
                        root.canvas.parameterPressed(tab.index)
                    }
                    onClicked: root.canvas.parameterClicked(tab.index)

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

                    contentItem: Text {
                        text: tab.text
                        font: tab.font
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: root.appearance.minimumFont.pixelSize
                        textFormat: Text.PlainText
                        horizontalAlignment: Text.AlignLeft
                        elide: Text.ElideNone
                        verticalAlignment: Text.AlignVCenter
                        color: tab.checked ? root.appearance.tabSelectedText
                                           : tab.hovered ? root.appearance.tabHoverText
                                                         : root.appearance.tabText
                        Accessible.ignored: true
                    }

                    // Distinct indicators: the active tab takes the selected
                    // tab fill, a user ghost-enabled tab takes the yellow
                    // bottom rule, shared-selection inclusion takes the
                    // right-edge bar (never a full-cell outline, never on the
                    // tab being edited), and keyboard focus paints the inner
                    // focus ring over every state.
                    background: Rectangle {
                        color: tab.checked ? root.appearance.tabSelectedBackground
                                           : tab.hovered ? root.appearance.tabHoverBackground
                                                         : root.appearance.tabBackground
                        border.width: root.appearance.stroke
                        border.color: root.appearance.tabOutline

                        // Written-event pip: the same fixed identity red as the
                        // lane nodes, drawn on the active tab too; independent
                        // of the inclusion rule and the checked fill.
                        Rectangle {
                            visible: tab.hasEvents
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: root.appearance.inset
                            width: root.appearance.pipExtent
                            height: root.appearance.pipExtent
                            radius: width / 2
                            color: root.appearance.pipColor
                            Accessible.ignored: true
                        }

                        // Ghost toggle: bottom rule, drawn even on the active
                        // tab — a pin there waits until another lane
                        // activates.
                        Rectangle {
                            visible: tab.ghostShown
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: root.appearance.stroke
                            height: root.appearance.stroke
                            color: root.appearance.selectionOutline
                        }

                        // Shared-selection inclusion: right-edge bar using the
                        // selected fill, so the two marks never share geometry.
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
                }
            }
        }
    }
}
