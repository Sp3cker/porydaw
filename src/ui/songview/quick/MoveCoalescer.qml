// Pointer-move coalescer: the retired C++ timeline applied each move's gesture
// state synchronously and queued only the scene rebuild behind a zero-timer,
// so a burst of move samples rebuilt once per event-loop turn. Swift
// presenters stay synchronous, so the same split lives at the QML edge: the
// first move of a turn dispatches immediately (single moves keep their
// synchronous semantics for gesture state and checks), and further moves in
// the same turn collapse to the latest sample, delivered by the armed flush.
// Callers flush before press, release, cancel and exit so gesture ordering is
// preserved.
import QtQuick

Timer {
    id: root

    interval: 0
    repeat: false

    property var dispatch: null
    property bool armed: false
    property bool pending: false
    property real pendingX: 0
    property real pendingY: 0
    property int pendingButtons: Qt.NoButton
    property int pendingModifiers: Qt.NoModifier

    function enqueue(x, y, buttons, modifiers) {
        if (!armed) {
            armed = true
            start()
            if (dispatch)
                dispatch(x, y, buttons, modifiers)
            return
        }
        pendingX = x
        pendingY = y
        pendingButtons = buttons
        pendingModifiers = modifiers
        pending = true
    }

    function flush() {
        stop()
        armed = false
        if (!pending)
            return
        pending = false
        if (dispatch)
            dispatch(pendingX, pendingY, pendingButtons, pendingModifiers)
    }

    onTriggered: flush()
}
