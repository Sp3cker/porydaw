pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import Porydaw.Ui
import PorydawApp as App

FocusScope {
    id: panel
    objectName: "undoHistoryDock"
    required property App.UndoHistoryPanel presenter
    required property App.GridPalette colors
    required property App.TypographyFonts typography
    required property App.LayoutSpaces layoutSpaces
    required property real baseFontPx
    readonly property real em: baseFontPx
    readonly property real margin: Math.round(em * 8 / 12)
    readonly property real rowHeight: Math.ceil(metrics.height + 2 * layoutSpaces.one)
    property int highlightedRow: -1
    property bool userMovedHighlight: false
    signal closeRequested()

    function synchronizeHighlight(): void {
        const requested = panel.userMovedHighlight ? panel.highlightedRow : panel.presenter.currentRow
        panel.highlightedRow = historyList.count === 0 ? -1
            : Math.max(0, Math.min(historyList.count - 1, requested))
        if (panel.highlightedRow >= 0)
            historyList.positionViewAtIndex(panel.highlightedRow, ListView.Contain)
    }

    function activateRow(row: int): void {
        if (!panel.presenter.canJump)
            return
        panel.userMovedHighlight = false
        panel.highlightedRow = row
        panel.presenter.activate(row)
    }

    onVisibleChanged: {
        if (visible) {
            panel.userMovedHighlight = false
            panel.synchronizeHighlight()
            historyList.forceActiveFocus(Qt.OtherFocusReason)
        }
    }
    Component.onCompleted: panel.synchronizeHighlight()

    FontMetrics { id: metrics; font: panel.typography.body }
    Connections {
        target: panel.presenter
        function onCurrentRowChanged(): void { panel.synchronizeHighlight() }
    }

    Rectangle { anchors.fill: parent; color: panel.colors.windowBackground }

    ListView {
        id: historyList
        objectName: "undoHistoryList"
        anchors.fill: parent
        anchors.margins: panel.margin
        model: panel.presenter.rows
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        keyNavigationEnabled: false
        activeFocusOnTab: true
        focus: true
        currentIndex: panel.highlightedRow
        onCountChanged: panel.synchronizeHighlight()
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Keys.onPressed: event => {
            if ((event.modifiers & ~Qt.KeypadModifier) !== Qt.NoModifier)
                return
            if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                panel.userMovedHighlight = true
                const direction = event.key === Qt.Key_Up ? -1 : 1
                panel.highlightedRow += direction
                panel.synchronizeHighlight()
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                panel.activateRow(panel.highlightedRow)
                event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
                panel.closeRequested()
                event.accepted = true
            }
        }

        delegate: Rectangle {
            id: row
            required property App.UndoHistoryRow display
            required property int index
            readonly property App.UndoHistoryRow step: row.display
            readonly property bool dimmed: !(row.step && row.step.applied)
            objectName: "undoHistoryRow_" + index
            width: historyList.width
            height: panel.rowHeight
            color: panel.colors.windowBackground
            border.color: index === panel.highlightedRow ? panel.colors.selectionRing : panel.colors.windowBackground
            border.width: index === panel.highlightedRow ? 2 : 0
            Accessible.role: Accessible.ListItem
            Accessible.name: row.step ? row.step.label : ""
            Accessible.selected: index === panel.highlightedRow

            Text {
                id: positionMarker
                objectName: "undoHistoryPositionMarker"
                width: panel.em * 1.5
                height: parent.height
                text: row.step && row.step.isCurrent ? "›" : ""
                font: panel.typography.bodyBold
                color: panel.colors.windowText
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                Accessible.ignored: true
            }
            Text {
                id: savedMarker
                objectName: "undoHistorySavedMarker"
                x: positionMarker.width
                width: panel.em * 1.5
                height: parent.height
                text: row.step && row.step.isSaved ? qsTr("S") : ""
                font: panel.typography.bodyBold
                color: row.dimmed ? panel.colors.secondaryText : panel.colors.windowText
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                Accessible.ignored: true
            }
            Text {
                objectName: "undoHistoryLabel"
                x: positionMarker.width + savedMarker.width
                width: row.width - x - panel.layoutSpaces.one
                height: parent.height
                text: row.step ? row.step.label : ""
                font: panel.typography.body
                color: row.dimmed ? panel.colors.secondaryText : panel.colors.windowText
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
            TapHandler {
                onTapped: {
                    historyList.forceActiveFocus(Qt.MouseFocusReason)
                    panel.activateRow(row.index)
                }
            }
        }
    }
}
