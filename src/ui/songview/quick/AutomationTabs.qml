// Compact parameter selector for the automation gutter: the nine standard
// parameter identities as native Basic TabButtons in an at-most-three-column
// grid. Qt owns checking, focus, activation and accessibility plumbing; the
// canvas owns parameter identity, the parameter menu and shared-selection
// semantics. The grid's intrinsic height is published to
// AutomationCanvas::minimumContentHeight so the drawer allocates only what
// the labels need — never the other way around.
import QtQuick
import QtQuick.Controls.Basic as Controls
import QtQuick.Layouts
import Porydaw.Ui

Item {
    id: root

    required property var canvas
    required property Item sceneRoot

    readonly property var appearance: canvas.parameterAppearance

    // Widest complete label advance at the floor font plus the two text
    // insets. Reading the metrics font and the label list here keeps the
    // requirement bound to the floor font and the catalog even if update
    // order lags; FontMetrics owns the measurement values themselves.
    readonly property real minimumCellWidth: {
        let widest = 0
        const floorFont = labelMetrics.font
        const labels = root.canvas.parameterLabels
        if (floorFont.pixelSize > 0) {
            for (let i = 0; i < labels.length; ++i)
                widest = Math.max(widest, labelMetrics.advanceWidth(labels[i]))
        }
        return widest + 2 * root.appearance.inset
    }

    // The only local layout policy: at most three uniform columns, each wide
    // enough for the widest floor-font label; never fewer than one.
    readonly property int columnCount:
        Math.min(3, Math.max(1, Math.floor(width / minimumCellWidth)))

    FontMetrics {
        id: labelMetrics
        font: root.appearance.minimumFont
    }

    GridLayout {
        id: grid

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right

        columns: root.columnCount
        columnSpacing: 0
        rowSpacing: 0
        uniformCellWidths: true
        uniformCellHeights: true

        Repeater {
            model: root.canvas.parameterLabels

            Controls.TabButton {
                id: tab

                required property int index
                required property string modelData

                // Song-global Tempo closes the catalog, after the CC identities.
                readonly property bool tempoParameter:
                    tab.index === root.canvas.parameterLabels.length - 1
                readonly property bool selectionIncluded:
                    root.canvas.selectedParameters.includes(tab.index)

                objectName: "automationParameterTab" + index
                text: modelData
                font: root.appearance.font
                padding: root.appearance.inset
                focusPolicy: Qt.StrongFocus
                Layout.fillWidth: true
                Layout.minimumHeight: root.appearance.minimumCellHeight

                // Native checkable/autoExclusive presentation; the canvas
                // stays the sole parameter authority.
                checked: root.canvas.activeParameter === tab.index

                onClicked: root.canvas.activateParameter(tab.index)

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
                // Claim only the plain activation keys before window-level
                // shortcuts (the transport play/pause Space binding) can take
                // them from this focused label: an item beats a shortcut only
                // by accepting the ShortcutOverride event. Modified or
                // auto-repeat variants stay unclaimed and continue to the
                // shared SongView policy, matching onPressed below.
                Keys.onShortcutOverride: (event) => event.accepted =
                    (event.key === Qt.Key_Space || event.key === Qt.Key_Return
                     || event.key === Qt.Key_Enter)
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
                    wrapMode: Text.NoWrap
                    elide: Text.ElideNone
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: root.appearance.text
                    Accessible.ignored: true
                }

                // Distinct indicators: the active parameter fills with the
                // chrome color, shared-selection inclusion outlines the cell,
                // and keyboard focus draws the inner focus ring.
                background: Rectangle {
                    color: tab.checked ? root.appearance.currentFill
                                       : root.appearance.background
                    border.width: root.appearance.stroke
                    border.color: tab.selectionIncluded
                                  ? root.appearance.selectionOutline : "transparent"

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: root.appearance.stroke
                        color: "transparent"
                        border.width: root.appearance.stroke
                        border.color: tab.visualFocus
                                      ? root.appearance.focusOutline : "transparent"
                    }
                }

                Accessible.selected: tab.selectionIncluded
                Accessible.description:
                    (tab.tempoParameter ? qsTr("Song-global tempo parameter")
                                        : qsTr("Track automation parameter"))
                    + (tab.selectionIncluded
                       ? qsTr("; included in shared selection")
                       : qsTr("; not in shared selection"))
            }
        }
    }

    Binding {
        target: root.canvas
        property: "minimumContentHeight"
        value: Math.ceil(grid.implicitHeight)
    }
}
