pragma ComponentBehavior: Bound

import QtQuick
import PorydawApp
import Porydaw.Ui

Item {
    id: cell
    final required property EventListPage page
    final required property EventListTable tableOwner
    final required property EventListPresenter controller

        required property int row
        required property int column
        final required property EventListRowHandle edit
        final required property font cellFont
        final required property int alignment
        final property int rowKind

        property real pressX: 0
        property real pressY: 0
        property bool pressWasCurrent: false

        readonly property bool rawRow: rowKind === 0
        readonly property bool endRow: rowKind === 2
        readonly property bool editing: cell.page.editingRow === row && cell.page.editingColumn === column
        readonly property bool current: cell.page.controller && cell.page.controller.currentRow === row
                                        && cell.page.currentColumn === column
        final property bool selected
        readonly property bool numericEditor: column >= 2 && column <= 4
        readonly property bool tickEditor: column === 0
        readonly property bool blobEditor: column === 5
        final property bool editable
        final property string displayedText
        final property string editorText
        readonly property int horizontalAlignment: (alignment & Text.AlignRight)
                                                  ? Text.AlignRight : Text.AlignLeft

        Binding {
            cell.rowKind: cell.edit.rowKind
            cell.selected: cell.edit.selected
            cell.editable: (cell.edit.editableMask & (1 << cell.column)) !== 0
            cell.displayedText: cell.textForColumn(cell.column)
            cell.editorText: cell.column === 1 ? cell.edit.editType
                             : cell.column === 5 ? cell.edit.editData : cell.displayedText
            when: cell.edit !== null
            restoreMode: Binding.RestoreNone
        }

        implicitWidth: cell.page.columnWidth(column)
        implicitHeight: cell.page.rowHeight

        function textForColumn(column: int): string {
            switch (column) {
            case 0: return edit.c0
            case 1: return edit.c1
            case 2: return edit.c2
            case 3: return edit.c3
            case 4: return edit.c4
            case 5: return edit.c5
            case 6: return edit.c6
            default: return ""
            }
        }

        function focusEditor(): void {
            if (!editor.visible)
                return
            editor.forceActiveFocus(Qt.MouseFocusReason)
            editor.selectAll()
        }

        function finishEditor(returnNavigationFocus: bool): void {
            if (!editing)
                return
            const finished = cell.page.finishCellEdit(true, editor.text, returnNavigationFocus)
            if (!finished && returnNavigationFocus)
                focusEditor()
        }

        function stepEditor(delta: int): bool {
            if (!cell.page.controller || !cell.page.controller.canStepEditing())
                return false
            editor.text = cell.page.controller.steppedEditingText(editor.text, delta)
            return true
        }


        Rectangle {
            objectName: "eventListRowStripe"
            anchors.fill: parent
            color: cell.selected ? cell.page.tableSelectedBackground
                  : cell.page.controller && cell.page.controller.playRow === cell.row ? cell.page.playheadTint
                  : cell.row % 2 ? cell.page.tableAlternateBackground : cell.page.tableBackground
            border.width: cell.current ? 1 : 0
            border.color: cell.page.focusOutline
        }

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: cell.page.tableOutline
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: cell.page.tableOutline
        }

        Text {
            objectName: "eventListCell_" + cell.row + "_" + cell.column
            anchors.fill: parent
            anchors.leftMargin: cell.page.cellHorizontalPadding
            anchors.rightMargin: cell.page.cellHorizontalPadding
            visible: !cell.editing || cell.column === 1
            clip: true
            color: cell.selected ? cell.page.tableSelectedText
                                 : cell.endRow ? (cell.row % 2 ? cell.page.tableText
                                                             : cell.page.tableSecondaryText)
                                               : cell.page.tableText
            font: cell.cellFont
            text: cell.displayedText
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            elide: Text.ElideRight
            maximumLineCount: 1
            horizontalAlignment: cell.horizontalAlignment
            verticalAlignment: Text.AlignVCenter
        }

        Rectangle {
            anchors.fill: parent
            visible: editor.visible
            color: cell.page.inputBackground
            border.width: 1
            border.color: editor.activeFocus ? cell.page.focusOutline : cell.page.inputOutline
        }


        TextInput {
            id: editor

            objectName: !visible ? "" : cell.tickEditor ? "eventListTickEditor"
                                                    : cell.numericEditor ? "eventListNumericEditor"
                                                                         : "eventListBlobEditor"
            anchors.fill: parent
            visible: cell.editing && cell.column !== 1
            clip: true
            color: cell.page.inputText
            font: cell.cellFont
            leftPadding: cell.page.cellHorizontalPadding
            rightPadding: cell.page.cellHorizontalPadding
            topPadding: 1
            bottomPadding: 1
            selectionColor: cell.page.tableSelectedBackground
            selectedTextColor: cell.page.tableSelectedText
            renderType: TextInput.NativeRendering
            horizontalAlignment: cell.horizontalAlignment
            verticalAlignment: TextInput.AlignVCenter
            selectByMouse: true
            persistentSelection: true
            inputMethodHints: cell.tickEditor || cell.numericEditor ? Qt.ImhDigitsOnly
                                                                     : Qt.ImhNone

            HoverHandler {
                id: cellEditorHint

                cursorShape: Qt.IBeamCursor
            }

            onVisibleChanged: {
                if (visible)
                    text = cell.editorText
            }
            onEditingFinished: cell.finishEditor(false)
            onActiveFocusChanged: {
                if (!activeFocus && cell.editing)
                    cell.page.finishCellEdit(false, "", false)
            }

            Keys.onReturnPressed: (event) => {
                cell.finishEditor(true)
                event.accepted = true
            }
            Keys.onEnterPressed: (event) => {
                cell.finishEditor(true)
                event.accepted = true
            }
            Keys.onEscapePressed: (event) => {
                cell.page.finishCellEdit(false, "", true)
                event.accepted = true
            }
            Keys.onUpPressed: (event) => {
                if (cell.stepEditor(event.modifiers & Qt.ControlModifier ? 10 : 1))
                    event.accepted = true
            }
            Keys.onDownPressed: (event) => {
                if (cell.stepEditor(event.modifiers & Qt.ControlModifier ? -10 : -1))
                    event.accepted = true
            }
        }

        MouseArea {
            id: cellMouse

            anchors.fill: parent
            enabled: !cell.editing
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            preventStealing: cell.rawRow
            cursorShape: cell.editable ? Qt.IBeamCursor : Qt.ArrowCursor

            onPressed: (mouse) => {
                // Re-arm the group before this drag owns it, so the last
                // gesture's outside release cannot block publication.
                cellHint.releaseInside = true
                cell.pressX = mouse.x
                cell.pressY = mouse.y
                cell.pressWasCurrent = cell.page.controller && cell.page.controller.currentRow === cell.row
                                       && cell.selected
                cell.page.currentColumn = cell.column
                if (mouse.button === Qt.RightButton) {
                    if (!cell.selected)
                        cell.page.selectRow(cell.row, Qt.NoModifier)
                } else {
                    cell.page.selectRow(cell.row, mouse.modifiers)
                }
                if (cell.page.controller)
                    cell.page.controller.setPointerDown(true)
                cell.page.dragFromRow = mouse.button === Qt.LeftButton && cell.rawRow ? cell.row : -1
                cell.page.dragDropGap = -1
                cell.page.draggingRows = false
            }

            onPositionChanged: (mouse) => {
                if (!pressed || !(mouse.buttons & Qt.LeftButton) || cell.page.dragFromRow !== cell.row)
                    return
                if (!cell.page.draggingRows) {
                    const dx = mouse.x - cell.pressX
                    const dy = mouse.y - cell.pressY
                    const distance = Math.sqrt(dx * dx + dy * dy)
                    if (distance < Qt.styleHints.startDragDistance)
                        return
                    cell.page.draggingRows = true
                }
                cell.page.updateDragGap(cell, mouse)
            }

            onReleased: (mouse) => {
                const moved = cell.page.draggingRows && cell.page.dragFromRow === cell.row
                const gap = cell.page.dragDropGap
                if (cell.page.controller)
                    cell.page.controller.setPointerDown(false)

                if (mouse.button === Qt.RightButton) {
                    cell.page.controller.focusRow(cell.row)
                    const position = cell.mapToItem(cell.page, mouse.x, mouse.y)
                    cell.page.controller.openRowMenu(position.x, position.y)
                } else if (moved) {
                    if (gap >= 0)
                        cell.page.controller.commitDrop(cell.row, gap)
                    cell.page.navigationFocusRequested()
                } else {
                    if (cell.pressWasCurrent && mouse.modifiers === Qt.NoModifier)
                        cell.page.beginCellEdit(cell)
                    cell.page.navigationFocusRequested()
                }
                cellHint.settleRelease(cellMouse.mapToItem(null, mouse.x, mouse.y))
                cell.page.resetPointerState()
            }

            onCanceled: {
                cellHint.settleRelease(cellHint.point.scenePosition)
                cell.page.resetPointerState()
            }
            onDoubleClicked: (mouse) => {
                if (mouse.button === Qt.LeftButton)
                    cell.page.beginCellEdit(cell)
            }
        }

        HoverHint {
            id: cellHint

            source: cell
            gestureOwning: cellMouse.pressed
            profile: cell.editing
                     ? (cellEditorHint.hovered
                        ? HintProfiles.TextSelection : HintProfiles.Empty)
                     : HintProfiles.EventRows
        }
}
