pragma ComponentBehavior: Bound
// Dispatch the first move synchronously; coalesce later samples until flush.
// Callers flush before press, release, cancel and exit to preserve ordering.
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

    function enqueue(x: real, y: real, buttons: int, modifiers: int): void {
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

    function flush(): void {
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
