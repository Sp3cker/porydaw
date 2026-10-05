pragma ComponentBehavior: Bound
// Controlled integer input: the owner applies valueCommitted to its model.
// Appearance is injected; no popup session or document is required.
import QtQuick
import Porydaw.Ui
import PorydawApp

Item {
    id: control

    required final property PromptStyle appearance
    final property MouseHints hintService: null
    property bool hintScopeAllowed: true

    property int value: 0
    property int minimumValue: 0
    property int maximumValue: 127
    property string inputObjectName: ""
    // Allows a form to display an out-of-range draft so Return can reject it.
    // Commit still uses maximumValue; other consumers retain the same limit.
    property int inputMaximumValue: maximumValue
    property string accessibleName: ""
    property string accessibleDescription: ""
    // Plain editors allow pointer selection but disable drag, wheel
    // and arrow/Page-key adjustments.
    property bool adjustmentsEnabled: true
    property alias textInput: focusLeaf

    signal valueCommitted(int committed)
    signal editingAccepted(int committed)

    function selectAll(): void {
        focusLeaf.selectAll()
    }
    function focusInput(reason: int): void {
        focusLeaf.forceActiveFocus(reason)
    }



    // Returns the displayed, validated integer. A null result leaves an
    // intermediate draft corrected in place and must not accept a dialog.
    function commitDisplayed(): var {
        if (!state.finishEditing())
            return null
        return Number.parseInt(input.text, 10)
    }

    implicitWidth: Math.max(fontMetrics.advanceWidth("" + control.minimumValue),
                            fontMetrics.advanceWidth("" + control.maximumValue))
                   + 2 * (control.appearance.horizontalPadding + control.appearance.borderWidth)
    implicitHeight: fontMetrics.height + 2 * (control.appearance.verticalPadding + control.appearance.borderWidth)

    onValueChanged: state.syncText()
    Component.onCompleted: state.syncText()

    QtObject {
        id: state

        property bool dragging: false
        property real lastDragDistance: 0
        property real stepAccumulator: 0
        // Persistent wheel angle remainder (QAbstractSpinBox parity).
        property int wheelRemainder: 0
        // DragSpinBox behavioral rates: steps accumulated per DIP dragged.
        readonly property real normalStepsPerPixel: 0.5
        readonly property real shiftStepsPerPixel: 0.2

        function syncText(): void {
            // External value changes always refresh the draft text, even
            // while the input has focus.
            input.text = "" + control.value
        }

        function clampValue(candidate: real): real {
            if (candidate !== candidate)
                return control.value
            return Math.max(control.minimumValue, Math.min(control.maximumValue, candidate))
        }

        function commitSteps(steps: int): void {
            const next = clampValue(control.value + steps)
            if (next !== control.value)
                control.valueCommitted(next)
        }

        // Full vertical displacement of the active drag; upward is positive.
        function pressDragDistance(): real {
            return scrubDrag.centroid.pressPosition.y - scrubDrag.centroid.position.y
        }

        function scrubTo(distance: real): void {
            if (!scrubDrag.active)
                return
            if (!dragging) {
                if (Math.abs(distance) <= control.appearance.dragThreshold)
                    return
                dragging = true
                lastDragDistance = distance > 0 ? control.appearance.dragThreshold
                                                : -control.appearance.dragThreshold
            }
            const rate = (scrubDrag.centroid.modifiers & Qt.ShiftModifier)
                ? shiftStepsPerPixel : normalStepsPerPixel
            stepAccumulator += (distance - lastDragDistance) * rate
            lastDragDistance = distance
            const steps = Math.trunc(stepAccumulator)
            if (steps !== 0) {
                stepAccumulator -= steps
                commitSteps(steps)
            }
        }

        // QAbstractSpinBox correction parity: empty/intermediate drafts revert
        // to the current value; acceptable digit text commits.
        function finishEditing(): bool {
            const trimmed = input.text.trim()
            const parsed = Number.parseInt(trimmed, 10)
            const acceptable = trimmed !== "" && parsed === parsed
                && parsed >= control.minimumValue && parsed <= control.maximumValue
            const fixed = acceptable ? parsed : control.value
            input.text = "" + fixed
            if (fixed !== control.value)
                control.valueCommitted(fixed)
            return acceptable
        }

        function selectAllIfFocused(): void {
            if (focusLeaf.activeFocus)
                input.selectAll()
        }
    }

    FontMetrics {
        id: fontMetrics
        font: control.appearance.font
    }

    Rectangle {
        anchors.fill: parent
        color: control.appearance.background
        radius: control.appearance.radius
        border.width: control.appearance.borderWidth
        border.color: focusLeaf.activeFocus ? control.appearance.focus : control.appearance.outline
    }

    TextInput {
        id: input

        anchors.fill: parent
        clip: true
        color: control.appearance.text
        font: control.appearance.font
        padding: control.appearance.borderWidth
        leftPadding: control.appearance.horizontalPadding + control.appearance.borderWidth
        rightPadding: control.appearance.horizontalPadding + control.appearance.borderWidth
        topPadding: control.appearance.verticalPadding + control.appearance.borderWidth
        bottomPadding: control.appearance.verticalPadding + control.appearance.borderWidth
        selectionColor: control.appearance.selection
        selectedTextColor: control.appearance.selectionText
        renderType: TextInput.NativeRendering
        horizontalAlignment: TextInput.AlignHCenter
        verticalAlignment: TextInput.AlignVCenter
        inputMethodHints: Qt.ImhDigitsOnly
        validator: IntValidator {
            bottom: control.minimumValue
            top: control.inputMaximumValue
        }
        // The sibling leaf owns keyboard focus and caret visibility, letting
        // unhandled shortcuts escape; pointer selection remains with this input.
        activeFocusOnPress: false
        activeFocusOnTab: false
        persistentSelection: true
        selectByMouse: !control.adjustmentsEnabled
        cursorVisible: focusLeaf.activeFocus
        Accessible.ignored: true

        // One scrub profile survives the owner's grab; settling from actual
        // release coordinates clears it outside even with frozen hover.
        HoverHint {
            id: scrubHint
            objectName: control.inputObjectName + "ScrubHint"

            source: input
            hintService: control.hintService
            scopeAllowed: control.hintScopeAllowed && control.adjustmentsEnabled
            cursorShape: Qt.SizeVerCursor
            gestureOwning: scrubDrag.active
            profile: HintProfiles.DragScrub
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton
            enabled: control.adjustmentsEnabled
            onTapped: {
                focusLeaf.forceActiveFocus(Qt.MouseFocusReason)
                // The text input settles its own caret and selection handling
                // on release; defer select-all so it survives dispatch order.
                Qt.callLater(state.selectAllIfFocused)
            }
        }

        // A passive grab focuses plain editors without stealing text selection.
        PointHandler {
            acceptedButtons: Qt.LeftButton
            enabled: !control.adjustmentsEnabled
            onActiveChanged: {
                if (active)
                    focusLeaf.forceActiveFocus(Qt.MouseFocusReason)
            }
        }

        DragHandler {
            id: scrubDrag

            acceptedButtons: Qt.LeftButton
            enabled: control.adjustmentsEnabled
            target: null
            dragThreshold: control.appearance.dragThreshold
            xAxis.enabled: false
            onActiveChanged: {
                if (active) {
                    focusLeaf.forceActiveFocus(Qt.MouseFocusReason)
                    state.dragging = false
                    state.stepAccumulator = 0
                    // Re-arm containment so the previous gesture's outside
                    // release cannot block the next gesture's publication.
                    scrubHint.releaseInside = true
                    // Evaluate immediately so the threshold-crossing movement
                    // is not dropped.
                    state.scrubTo(state.pressDragDistance())
                } else {
                    // Actual release containment overrides frozen hover.
                    scrubHint.settleRelease(scrubDrag.centroid.scenePosition)
                }
            }
            onCentroidChanged: state.scrubTo(state.pressDragDistance())
        }

        // Accumulate 120-unit angle notches; macOS Shift uses the horizontal
        // axis and Control steps by ten, matching QAbstractSpinBox.
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            enabled: control.adjustmentsEnabled
            onWheel: (event) => {
                focusLeaf.forceActiveFocus(Qt.MouseFocusReason)
                const useHorizontal = Qt.platform.os === "osx"
                    && (event.modifiers & Qt.ShiftModifier)
                state.wheelRemainder += useHorizontal ? event.angleDelta.x : event.angleDelta.y
                const steps = Math.trunc(state.wheelRemainder / 120)
                if (steps !== 0) {
                    state.wheelRemainder -= steps * 120
                    state.commitSteps(event.modifiers & Qt.ControlModifier ? steps * 10 : steps)
                }
                event.accepted = true
            }
        }
    }

    // The plain focus leaf applies local text keys through the TextInput API.
    // Only implemented commands claim ShortcutOverride; bare Space reaches transport.
    Item {
        id: focusLeaf

        objectName: control.inputObjectName
        anchors.fill: parent
        activeFocusOnTab: true

        property alias text: input.text
        readonly property string selectedText: input.selectedText
        property alias acceptableInput: input.acceptableInput

        // Host policy marker; printable ShortcutOverride precedes QML handlers.
        readonly property bool yieldsTransportPlayPauseShortcut: true

        function selectAll(): void {
            input.selectAll()
        }

        onActiveFocusChanged: {
            // Focus loss commits/corrects adjusting fields; plain editors only
            // correct invalid text because their owner cancels on focus loss.
            if (!activeFocus && (control.adjustmentsEnabled || !input.acceptableInput))
                state.finishEditing()
        }

        Keys.onReturnPressed: (event) => {
            const committed = control.commitDisplayed()
            if (committed !== null)
                control.editingAccepted(committed)
            event.accepted = true
        }
        Keys.onEnterPressed: (event) => {
            const committed = control.commitDisplayed()
            if (committed !== null)
                control.editingAccepted(committed)
            event.accepted = true
        }

        // Own the text commands implemented below; bare Space stays window-owned.
        Keys.onShortcutOverride: (event) => {
            event.accepted = event.matches(StandardKey.SelectAll)
                || event.matches(StandardKey.Copy) || event.matches(StandardKey.Cut)
                || event.matches(StandardKey.Paste) || event.matches(StandardKey.Undo)
                || event.matches(StandardKey.Redo)
                || ((event.key === Qt.Key_Home || event.key === Qt.Key_End)
                    && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier))
        }

        Keys.onUpPressed: (event) => {
            if (!control.adjustmentsEnabled)
                return
            // The step modifier (Control; Command on macOS) multiplies the
            // arrow-key step by 10, matching QAbstractSpinBox::keyPressEvent.
            state.commitSteps(event.modifiers & Qt.ControlModifier ? 10 : 1)
            event.accepted = true
        }
        Keys.onDownPressed: (event) => {
            if (!control.adjustmentsEnabled)
                return
            state.commitSteps(event.modifiers & Qt.ControlModifier ? -10 : -1)
            event.accepted = true
        }

        Keys.onPressed: (event) => {
            event.accepted = false
            if (control.adjustmentsEnabled) {
                // Page keys always step by 10 and never apply the step modifier.
                if (event.key === Qt.Key_PageUp) {
                    state.commitSteps(10)
                    event.accepted = true
                    return
                } else if (event.key === Qt.Key_PageDown) {
                    state.commitSteps(-10)
                    event.accepted = true
                    return
                }
            }
            if (event.matches(StandardKey.SelectAll)) {
                input.selectAll()
                event.accepted = true
            } else if (event.matches(StandardKey.Copy)) {
                input.copy()
                event.accepted = true
            } else if (event.matches(StandardKey.Cut)) {
                input.cut()
                event.accepted = true
            } else if (event.matches(StandardKey.Paste)) {
                // Clipboard insertion bypasses the character filter; restore
                // the prior draft and selection when the result is not numeric.
                const priorText = input.text
                const priorCursor = input.cursorPosition
                const priorStart = input.selectionStart
                const priorEnd = input.selectionEnd
                input.paste()
                const pasted = input.text
                let inDomain = true
                for (let i = 0; i < pasted.length; ++i) {
                    const ch = pasted.charAt(i)
                    if (ch >= "0" && ch <= "9")
                        continue
                    if (ch === "-" && i === 0 && control.minimumValue < 0)
                        continue
                    inDomain = false
                    break
                }
                if (!inDomain) {
                    input.text = priorText
                    if (priorStart !== priorEnd) {
                        input.select(priorStart, priorEnd)
                        if (priorCursor === priorStart)
                            input.moveCursorSelection(priorStart, TextInput.SelectCharacters)
                    } else {
                        input.cursorPosition = priorCursor
                    }
                }
                event.accepted = true
            } else if (event.matches(StandardKey.Undo)) {
                input.undo()
                event.accepted = true
            } else if (event.matches(StandardKey.Redo)) {
                input.redo()
                event.accepted = true
            }
            if (event.accepted || (event.modifiers & Qt.ControlModifier))
                return
            const shift = (event.modifiers & Qt.ShiftModifier) !== 0
            if (event.key === Qt.Key_Backspace) {
                if (input.selectedText.length > 0)
                    input.remove(input.selectionStart, input.selectionEnd)
                else if (input.cursorPosition > 0)
                    input.remove(input.cursorPosition - 1, input.cursorPosition)
                event.accepted = true
            } else if (event.key === Qt.Key_Delete) {
                if (input.selectedText.length > 0)
                    input.remove(input.selectionStart, input.selectionEnd)
                else
                    input.remove(input.cursorPosition, input.cursorPosition + 1)
                event.accepted = true
            } else if (event.key === Qt.Key_Left) {
                if (shift)
                    input.moveCursorSelection(input.cursorPosition - 1, TextInput.SelectCharacters)
                else
                    input.cursorPosition = Math.max(0, input.cursorPosition - 1)
                event.accepted = true
            } else if (event.key === Qt.Key_Right) {
                if (shift)
                    input.moveCursorSelection(input.cursorPosition + 1, TextInput.SelectCharacters)
                else
                    input.cursorPosition = Math.min(input.text.length, input.cursorPosition + 1)
                event.accepted = true
            } else if (event.key === Qt.Key_Home) {
                if (shift)
                    input.moveCursorSelection(0, TextInput.SelectCharacters)
                else
                    input.cursorPosition = 0
                event.accepted = true
            } else if (event.key === Qt.Key_End) {
                if (shift)
                    input.moveCursorSelection(input.text.length, TextInput.SelectCharacters)
                else
                    input.cursorPosition = input.text.length
                event.accepted = true
            } else if (event.text.length === 1
                       && ((event.text >= "0" && event.text <= "9")
                           || (event.text === "-" && control.minimumValue < 0
                               && (input.cursorPosition === 0
                                   || (input.selectionStart === 0
                                       && input.selectedText.length > 0))
                               && (input.text.indexOf("-") < 0
                                   || (input.selectionStart === 0
                                       && input.selectedText.indexOf("-") >= 0))))) {
                // Insert the validator's digit/minus domain without delivering
                // the key to TextInput, which would claim unhandled shortcuts.
                if (input.selectedText.length > 0)
                    input.remove(input.selectionStart, input.selectionEnd)
                input.insert(input.cursorPosition, event.text)
                event.accepted = true
            }
        }

        Accessible.role: Accessible.EditableText
        Accessible.name: control.accessibleName
        Accessible.description: control.accessibleDescription
        Accessible.editable: true
        Accessible.focusable: true
    }
}
