// Controlled integer input: the owner applies valueCommitted to its model.
// Appearance is injected; no popup session or document is required.
import QtQuick
import Porydaw.Ui

Item {
    id: control

    required property var appearance
    property var hintService: null
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
    // When false the field is a plain numeric editor: no scrub drag, wheel
    // stepping, or arrow/PageUp/PageDown adjustments, and pointer text
    // selection is enabled instead.
    property bool adjustmentsEnabled: true
    property alias textInput: focusLeaf

    signal valueCommitted(int committed)
    signal editingAccepted(int committed)

    function selectAll() {
        focusLeaf.selectAll()
    }
    function focusInput(reason) {
        focusLeaf.forceActiveFocus(reason)
    }



    // Returns the displayed, validated integer. A null result leaves an
    // intermediate draft corrected in place and must not accept a dialog.
    function commitDisplayed() {
        if (!state.finishEditing())
            return null
        return Number.parseInt(input.text, 10)
    }

    implicitWidth: Math.max(fontMetrics.advanceWidth(String(minimumValue)),
                            fontMetrics.advanceWidth(String(maximumValue)))
                   + 2 * (appearance.horizontalPadding + appearance.borderWidth)
    implicitHeight: fontMetrics.height + 2 * (appearance.verticalPadding + appearance.borderWidth)

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

        function syncText() {
            // External value changes always refresh the draft text, even
            // while the input has focus.
            input.text = String(control.value)
        }

        function clampValue(candidate) {
            if (isNaN(candidate))
                return control.value
            return Math.max(control.minimumValue, Math.min(control.maximumValue, candidate))
        }

        function commitSteps(steps) {
            const next = clampValue(control.value + steps)
            if (next !== control.value)
                control.valueCommitted(next)
        }

        // Full vertical displacement of the active drag; upward is positive.
        function pressDragDistance() {
            return scrubDrag.centroid.pressPosition.y - scrubDrag.centroid.position.y
        }

        function scrubTo(distance) {
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

        // QAbstractSpinBox::interpret parity: acceptable text becomes the
        // value; empty or intermediate drafts revert to the current value
        // (correction mode CorrectToPreviousValue). The validator already
        // rejects non-numeric inserts, so the parse only sees digit text.
        function finishEditing() {
            const trimmed = input.text.trim()
            const parsed = Number.parseInt(trimmed, 10)
            const acceptable = trimmed !== "" && !Number.isNaN(parsed)
                && parsed >= control.minimumValue && parsed <= control.maximumValue
            const fixed = acceptable ? parsed : control.value
            input.text = String(fixed)
            if (fixed !== control.value)
                control.valueCommitted(fixed)
            return acceptable
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
        selectionColor: control.appearance?.selection ?? control.appearance?.focus ?? "transparent"
        selectedTextColor: control.appearance?.selectionText ?? control.appearance?.text ?? "transparent"
        renderType: TextInput.NativeRendering
        horizontalAlignment: TextInput.AlignHCenter
        verticalAlignment: TextInput.AlignVCenter
        inputMethodHints: Qt.ImhDigitsOnly
        validator: IntValidator {
            bottom: control.minimumValue
            top: control.inputMaximumValue
        }
        // The editor never takes focus: the focusLeaf sibling owns keyboard
        // focus and edits this text through direct API calls, so a focused
        // field never claims a ShortcutOverride for keys it does not handle.
        // Pointer presses still reach it for text selection when adjustments
        // are disabled. TextInput defaults activeFocusOnTab to true, so the
        // tab chain must exclude it explicitly. The caret follows the leaf's
        // focus since the editor itself never focuses.
        activeFocusOnPress: false
        activeFocusOnTab: false
        persistentSelection: true
        selectByMouse: !control.adjustmentsEnabled
        cursorVisible: focusLeaf.activeFocus
        Accessible.ignored: true

        // One hint group over the field: Shift + vertical drag adjusts more
        // finely, Control + wheel steps by ten. The deferred tap-select-all
        // below supersedes ordinary Shift-click text selection, so the
        // generic selection profile is never advertised alongside the
        // drag/wheel alternatives. The macOS Shift-wheel axis compensation
        // inside the WheelHandler is part of the same stepping action, not
        // a distinct alternative. While the existing scrub drag holds the
        // grab, HoverHint retains the originating profile; when the drag
        // ends, the group settles from the drag's actual final centroid
        // position mapped into the field, so an outside release clears
        // even with frozen hover membership.
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
                Qt.callLater(function () {
                    if (focusLeaf.activeFocus)
                        input.selectAll()
                })
            }
        }

        // Plain-editor pointer focus: with adjustments disabled the press
        // moves keyboard focus to the leaf while drag text selection stays
        // with the input's own selectByMouse handling. A PointHandler only
        // takes a passive grab, so the press still reaches the TextInput.
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
                    // Settle the hint group from the drag's actual final
                    // centroid position: an outside release clears even
                    // when Qt froze hover membership during the grab.
                    scrubHint.settleRelease(scrubDrag.centroid.scenePosition)
                }
            }
            onCentroidChanged: state.scrubTo(state.pressDragDistance())
        }

        // QAbstractSpinBox::wheelEvent parity (Qt 6): accumulate angle deltas
        // into a persistent remainder; each full 120-unit notch becomes one
        // step. On macOS Shift converts a mouse wheel's horizontal axis back
        // to the vertical step axis. Control multiplies the step by 10.
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

    // The public focus leaf: a plain Item so Qt's ShortcutOverride phase is
    // never claimed by the editor for keys it does not handle — a bare Space
    // reaches the window shortcut while the field holds focus. Key presses
    // that do arrive are applied to the inner TextInput through its own API;
    // nothing is forwarded or synthesized.
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

        function selectAll() {
            input.selectAll()
        }

        onActiveFocusChanged: {
            // Focus loss finishes the draft like the original editingFinished:
            // an adjusting field commits or corrects, a plain editor only
            // corrects (its owner cancels on focus loss).
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
            if (event.modifiers & Qt.ControlModifier) {
                if (event.key === Qt.Key_A) {
                    input.selectAll()
                    event.accepted = true
                } else if (event.key === Qt.Key_C) {
                    input.copy()
                    event.accepted = true
                } else if (event.key === Qt.Key_X) {
                    input.cut()
                    event.accepted = true
                } else if (event.key === Qt.Key_V) {
                    // paste() inserts clipboard text without the per-character
                    // filter the digit branch applies; roll back a draft that
                    // falls outside the numeric character domain.
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
                } else if (event.key === Qt.Key_Z) {
                    input.undo()
                    event.accepted = true
                } else if (event.key === Qt.Key_Y) {
                    input.redo()
                    event.accepted = true
                }
                return
            }
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
                // The IntValidator accepts digits and a leading minus; the
                // editor's own insert API applies the same characters without
                // routing the key event through the input.
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
