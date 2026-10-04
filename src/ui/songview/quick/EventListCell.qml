pragma ComponentBehavior: Bound

import QtQuick
import PorydawApp

Item {
    id: cell
    required property Item page
    required property Item tableOwner
    required property EventListPresenter controller

        required property int row
        required property int column
        required property var display
        required property var edit
        required property var tickString
        required property font cellFont
        required property int alignment
        required property var rowKind

        property real pressX: 0
        property real pressY: 0
        property bool pressWasCurrent: false

        readonly property bool rawRow: rowKind === 0
        readonly property bool endRow: rowKind === 2
        readonly property bool editing: cell.page.editingRow === row && cell.page.editingColumn === column
        readonly property bool current: cell.page.controller && cell.page.controller.currentRow === row
                                        && cell.page.currentColumn === column
        readonly property bool selected: cell.page.rowIsSelected(row)
        readonly property bool numericEditor: column >= 2 && column <= 4
        readonly property bool tickEditor: column === 0
        readonly property bool blobEditor: column === 5
        readonly property bool editable: {
            const editValue = edit
            return cell.page.controller && cell.page.controller.isCellEditable(row, column)
        }
        readonly property string displayedText: tickEditor ? cell.page.valueText(tickString)
                                                           : cell.page.valueText(display)
        readonly property string editorText: tickEditor ? cell.page.valueText(tickString)
                                                        : cell.page.valueText(edit)
        readonly property int horizontalAlignment: (alignment & Text.AlignRight)
                                                  ? Text.AlignRight : Text.AlignLeft

        implicitWidth: cell.page.columnWidth(column)
        implicitHeight: cell.page.rowHeight

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
                                       && cell.page.rowIsSelected(cell.row)
                cell.page.currentColumn = cell.column
                if (mouse.button === Qt.RightButton) {
                    if (!cell.page.rowIsSelected(cell.row))
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
