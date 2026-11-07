pragma ComponentBehavior: Bound
pragma ValueTypeBehavior: Addressable, Assertable

import QtQuick
import QtQuick.Controls.Fusion as Fusion
import Porydaw.Icons
import PorydawApp

// Fusion's SpinBox with glyph step arrows. A focused TextInput claims Space and Undo before QML
// handlers run, so a plain focus leaf edits the text through its API, as DragInput does.
Fusion.SpinBox {
    id: control

    editable: true

    property NumberFieldFormat numberFormat: NumberFieldFormat {}
    textFromValue: function(value: int, locale: var): string {
        return control.numberFormat.text(value)
    }
    valueFromText: function(text: string, locale: var): real {
        return control.numberFormat.value(text, control.value)
    }

    // SpinBox commits contentItem.text itself on Return release and on focus loss.
    contentItem: FocusScope {
        id: editor

        property alias text: input.text

        z: 2
        implicitWidth: input.implicitWidth
        implicitHeight: input.implicitHeight

        function syncText(): void {
            input.text = control.displayText
        }
        function selectAll(): void {
            input.selectAll()
        }

        Component.onCompleted: syncText()
        Connections {
            target: control
            function onDisplayTextChanged(): void { editor.syncText() }
        }
        // Resyncs after SpinBox commits a Return release or focus loss, which run after the leaf.
        Timer {
            id: resync
            interval: 0
            onTriggered: editor.syncText()
        }

        TextInput {
            id: input

            anchors.fill: parent
            font: control.font
            color: control.palette.text
            selectionColor: control.palette.highlight
            selectedTextColor: control.palette.highlightedText
            horizontalAlignment: Qt.AlignHCenter
            verticalAlignment: Qt.AlignVCenter
            readOnly: !control.editable
            validator: control.validator
            inputMethodHints: control.inputMethodHints
            clip: width < implicitWidth
            activeFocusOnPress: false
            activeFocusOnTab: false
            selectByMouse: control.editable
            persistentSelection: true
            cursorVisible: leaf.activeFocus && control.editable
            Accessible.ignored: true

            PointHandler {
                acceptedButtons: Qt.LeftButton
                onActiveChanged: {
                    if (active)
                        leaf.forceActiveFocus(Qt.MouseFocusReason)
                }
            }
        }

        Item {
            id: leaf

            anchors.fill: parent
            focus: true

            // Typed characters and caret keys stay local; Space, Undo and Redo do not.
            function editsText(event: KeyEvent): bool {
                if (!control.editable)
                    return false
                if (event.matches(StandardKey.SelectAll) || event.matches(StandardKey.Copy)
                        || event.matches(StandardKey.Cut) || event.matches(StandardKey.Paste))
                    return true
                if (event.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.AltModifier))
                    return false
                switch (event.key) {
                case Qt.Key_Backspace:
                case Qt.Key_Delete:
                case Qt.Key_Left:
                case Qt.Key_Right:
                case Qt.Key_Home:
                case Qt.Key_End:
                    return true
                case Qt.Key_Space:
                    return false
                }
                return event.key < Qt.Key_Escape && event.text.length > 0
            }

            onActiveFocusChanged: {
                if (!activeFocus)
                    resync.restart()
            }

            Keys.onShortcutOverride: (event) => event.accepted = editsText(event)
            Keys.onReleased: (event) => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                    resync.restart()
                event.accepted = false
            }
            Keys.onPressed: (event) => {
                event.accepted = editsText(event)
                if (!event.accepted)
                    return
                const shift = (event.modifiers & Qt.ShiftModifier) !== 0
                if (event.matches(StandardKey.SelectAll)) {
                    input.selectAll()
                } else if (event.matches(StandardKey.Copy)) {
                    input.copy()
                } else if (event.matches(StandardKey.Cut)) {
                    input.cut()
                } else if (event.matches(StandardKey.Paste)) {
                    input.paste()
                } else if (event.key === Qt.Key_Backspace) {
                    if (input.selectedText.length > 0)
                        input.remove(input.selectionStart, input.selectionEnd)
                    else if (input.cursorPosition > 0)
                        input.remove(input.cursorPosition - 1, input.cursorPosition)
                } else if (event.key === Qt.Key_Delete) {
                    if (input.selectedText.length > 0)
                        input.remove(input.selectionStart, input.selectionEnd)
                    else
                        input.remove(input.cursorPosition, input.cursorPosition + 1)
                } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Home) {
                    const target = event.key === Qt.Key_Home ? 0 : Math.max(0, input.cursorPosition - 1)
                    if (shift)
                        input.moveCursorSelection(target, TextInput.SelectCharacters)
                    else
                        input.cursorPosition = target
                } else if (event.key === Qt.Key_Right || event.key === Qt.Key_End) {
                    const target = event.key === Qt.Key_End
                        ? input.text.length : Math.min(input.text.length, input.cursorPosition + 1)
                    if (shift)
                        input.moveCursorSelection(target, TextInput.SelectCharacters)
                    else
                        input.cursorPosition = target
                } else {
                    if (input.selectedText.length > 0)
                        input.remove(input.selectionStart, input.selectionEnd)
                    input.insert(input.cursorPosition, event.text)
                }
            }

            Accessible.role: Accessible.EditableText
            Accessible.editable: control.editable
            Accessible.focusable: true
        }
    }

    up.indicator: Rectangle {
        x: control.mirrored ? 1 : control.width - width - 1
        y: 1
        height: control.height / 2 - 1
        implicitWidth: Math.round(control.font.pixelSize * 1.25)
        implicitHeight: Math.round(control.font.pixelSize * 0.75)
        radius: 2
        color: control.up.pressed
            ? (Fusion.Fusion.buttonColor(control.palette, false, true, true) as color) : "transparent"

        AppIcon {
            anchors.fill: parent
            icon: Icons.spinUp
            color: control.palette.buttonText
        }
    }

    down.indicator: Rectangle {
        x: control.mirrored ? 1 : control.width - width - 1
        y: control.height - height - 1
        height: control.height / 2 - 1
        implicitWidth: Math.round(control.font.pixelSize * 1.25)
        implicitHeight: Math.round(control.font.pixelSize * 0.75)
        radius: 2
        color: control.down.pressed
            ? (Fusion.Fusion.buttonColor(control.palette, false, true, true) as color) : "transparent"

        AppIcon {
            anchors.fill: parent
            icon: Icons.spinDown
            color: control.palette.buttonText
        }
    }
}
