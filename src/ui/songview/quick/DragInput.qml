// Controlled integer input: the owner applies valueCommitted to its model.
// Appearance is injected; no popup session or document is required.
import QtQuick

Item {
    id: control

    required property var appearance
    property var hintService: null
    property bool hintScopeAllowed: true

    property int value: 0
    property int minimumValue: 0
    property int maximumValue: 127
    property string inputObjectName: ""
    property string accessibleName: ""
    property string accessibleDescription: ""
    property alias textInput: input

    signal valueCommitted(int committed)
    signal editingAccepted(int committed)

    function selectAll() {
        input.selectAll()
    }
    function focusInput(reason) {
        input.forceActiveFocus(reason)
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
        border.color: input.activeFocus ? control.appearance.focus : control.appearance.outline
    }

    TextInput {
        id: input

        objectName: control.inputObjectName
        anchors.fill: parent
        clip: true
        color: control.appearance.text
        font: control.appearance.font
        padding: control.appearance.borderWidth
        leftPadding: control.appearance.horizontalPadding + control.appearance.borderWidth
        rightPadding: control.appearance.horizontalPadding + control.appearance.borderWidth
        topPadding: control.appearance.verticalPadding + control.appearance.borderWidth
        bottomPadding: control.appearance.verticalPadding + control.appearance.borderWidth
        selectionColor: control.appearance.focus
        selectedTextColor: control.appearance.text
        renderType: TextInput.NativeRendering
        horizontalAlignment: TextInput.AlignHCenter
        verticalAlignment: TextInput.AlignVCenter
        activeFocusOnTab: true
        inputMethodHints: Qt.ImhDigitsOnly
        validator: IntValidator {
            bottom: control.minimumValue
            top: control.maximumValue
        }
        // Host policy marker; printable ShortcutOverride precedes QML handlers.
        readonly property bool yieldsTransportPlayPauseShortcut: true

        onEditingFinished: state.finishEditing()
        onActiveFocusChanged: {
            if (!activeFocus && !acceptableInput)
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
            // The step modifier (Control; Command on macOS) multiplies the
            // arrow-key step by 10, matching QAbstractSpinBox::keyPressEvent.
            state.commitSteps(event.modifiers & Qt.ControlModifier ? 10 : 1)
            event.accepted = true
        }
        Keys.onDownPressed: (event) => {
            state.commitSteps(event.modifiers & Qt.ControlModifier ? -10 : -1)
            event.accepted = true
        }
        Keys.onPressed: (event) => {
            // Page keys always step by 10 and never apply the step modifier.
            if (event.key === Qt.Key_PageUp) {
                state.commitSteps(10)
                event.accepted = true
            } else if (event.key === Qt.Key_PageDown) {
                state.commitSteps(-10)
                event.accepted = true
            }
        }

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

            source: input
            hintService: control.hintService
            scopeAllowed: control.hintScopeAllowed
            cursorShape: Qt.SizeVerCursor
            gestureOwning: scrubDrag.active
            profile: HintProfiles.DragScrub
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: {
                input.forceActiveFocus(Qt.MouseFocusReason)
                // The text input settles its own caret and selection handling
                // on release; defer select-all so it survives dispatch order.
                Qt.callLater(function () {
                    if (input.activeFocus)
                        input.selectAll()
                })
            }
        }

        DragHandler {
            id: scrubDrag

            acceptedButtons: Qt.LeftButton
            target: null
            dragThreshold: control.appearance.dragThreshold
            xAxis.enabled: false
            onActiveChanged: {
                if (active) {
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
            onWheel: (event) => {
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

        Accessible.role: Accessible.EditableText
        Accessible.name: control.accessibleName
        Accessible.description: control.accessibleDescription
        Accessible.editable: true
    }
}
