import QtQuick

Item {
    id: cell
    required property Item page
    required property Item tableOwner
    required property QtObject controller

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
        readonly property bool editing: page.editingRow === row && page.editingColumn === column
        readonly property bool current: page.controller && page.controller.currentRow === row
                                        && page.currentColumn === column
        readonly property bool selected: page.rowIsSelected(row)
        readonly property bool numericEditor: column >= 2 && column <= 4
        readonly property bool tickEditor: column === 0
        readonly property bool blobEditor: column === 5
        readonly property bool editable: {
            const editValue = edit
            return page.controller && page.controller.isCellEditable(row, column)
        }
        readonly property string displayedText: tickEditor ? page.valueText(tickString)
                                                           : page.valueText(display)
        readonly property string editorText: tickEditor ? page.valueText(tickString)
                                                        : page.valueText(edit)
        readonly property int horizontalAlignment: (alignment & Text.AlignRight)
                                                  ? Text.AlignRight : Text.AlignLeft

        implicitWidth: page.columnWidth(column)
        implicitHeight: page.rowHeight

        function focusEditor() {
            if (!editor.visible)
                return
            editor.forceActiveFocus(Qt.MouseFocusReason)
            editor.selectAll()
        }

        function finishEditor(returnNavigationFocus) {
            if (!editing)
                return
            const finished = page.finishCellEdit(true, editor.text, returnNavigationFocus)
            if (!finished && returnNavigationFocus)
                focusEditor()
        }

        function stepEditor(delta) {
            if (!page.controller || !page.controller.canStepEditing())
                return false
            editor.text = page.controller.steppedEditingText(editor.text, delta)
            return true
        }


        Rectangle {
            objectName: "eventListRowStripe"
            anchors.fill: parent
            color: cell.selected ? page.tableSelectedBackground
                  : page.controller && page.controller.playRow === cell.row ? page.playheadTint
                  : cell.row % 2 ? page.tableAlternateBackground : page.tableBackground
            border.width: cell.current ? 1 : 0
            border.color: page.focusOutline
        }

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: page.tableOutline
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: page.tableOutline
        }

        Text {
            objectName: "eventListCell_" + cell.row + "_" + cell.column
            anchors.fill: parent
            anchors.leftMargin: page.cellHorizontalPadding
            anchors.rightMargin: page.cellHorizontalPadding
            visible: !cell.editing || cell.column === 1
            clip: true
            color: cell.selected ? page.tableSelectedText
                                 : cell.endRow ? (cell.row % 2 ? page.tableText
                                                             : page.tableSecondaryText)
                                               : page.tableText
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
            color: page.inputBackground
            border.width: 1
            border.color: editor.activeFocus ? page.focusOutline : page.inputOutline
        }


        TextInput {
            id: editor

            objectName: !visible ? "" : cell.tickEditor ? "eventListTickEditor"
                                                    : cell.numericEditor ? "eventListNumericEditor"
                                                                         : "eventListBlobEditor"
            anchors.fill: parent
            visible: cell.editing && cell.column !== 1
            clip: true
            color: page.inputText
            font: cell.cellFont
            leftPadding: page.cellHorizontalPadding
            rightPadding: page.cellHorizontalPadding
            topPadding: 1
            bottomPadding: 1
            selectionColor: page.tableSelectedBackground
            selectedTextColor: page.tableSelectedText
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
                    page.finishCellEdit(false, "", false)
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
                page.finishCellEdit(false, "", true)
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
                cell.pressWasCurrent = page.controller && page.controller.currentRow === cell.row
                                       && page.rowIsSelected(cell.row)
                page.currentColumn = cell.column
                if (mouse.button === Qt.RightButton) {
                    if (!page.rowIsSelected(cell.row))
                        page.selectRow(cell.row, Qt.NoModifier)
                } else {
                    page.selectRow(cell.row, mouse.modifiers)
                }
                if (page.controller)
                    page.controller.setPointerDown(true)
                page.dragFromRow = mouse.button === Qt.LeftButton && cell.rawRow ? cell.row : -1
                page.dragDropGap = -1
                page.draggingRows = false
            }

            onPositionChanged: (mouse) => {
                if (!pressed || !(mouse.buttons & Qt.LeftButton) || page.dragFromRow !== cell.row)
                    return
                if (!page.draggingRows) {
                    const dx = mouse.x - cell.pressX
                    const dy = mouse.y - cell.pressY
                    const distance = Math.sqrt(dx * dx + dy * dy)
                    if (distance < Qt.styleHints.startDragDistance)
                        return
                    page.draggingRows = true
                }
                page.updateDragGap(cell, mouse)
            }

            onReleased: (mouse) => {
                const moved = page.draggingRows && page.dragFromRow === cell.row
                const gap = page.dragDropGap
                if (page.controller)
                    page.controller.setPointerDown(false)

                if (mouse.button === Qt.RightButton) {
                    page.controller.focusRow(cell.row)
                    const position = cell.mapToItem(page, mouse.x, mouse.y)
                    page.controller.openRowMenu(position.x, position.y)
                } else if (moved) {
                    if (gap >= 0)
                        page.controller.commitDrop(cell.row, gap)
                    page.navigationFocusRequested()
                } else {
                    if (cell.pressWasCurrent && mouse.modifiers === Qt.NoModifier)
                        page.beginCellEdit(cell)
                    page.navigationFocusRequested()
                }
                cellHint.settleRelease(cellMouse.mapToItem(null, mouse.x, mouse.y))
                page.resetPointerState()
            }

            onCanceled: {
                cellHint.settleRelease(cellHint.point.scenePosition)
                page.resetPointerState()
            }
            onDoubleClicked: (mouse) => {
                if (mouse.button === Qt.LeftButton)
                    page.beginCellEdit(cell)
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
