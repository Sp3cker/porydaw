import QtQuick

Item {
    id: root

    required property var laneModel
    signal hintChanged(string text)
    readonly property rect canvasRect: Qt.rect(laneModel.canvasRect.x, laneModel.canvasRect.y, laneModel.canvasRect.width, laneModel.canvasRect.height)
    readonly property string laneTitle: laneModel.laneTitle
    readonly property string liveValueText: laneModel.liveValueText
    readonly property string upperValueText: laneModel.upperValueText
    readonly property string lowerValueText: laneModel.lowerValueText
    readonly property string endLabel: laneModel.endLabel
    readonly property bool bipolar: laneModel.bipolar

    onActiveFocusChanged: laneModel.setFocused(activeFocus)
    Keys.onShortcutOverride: event => {
        if ([Qt.Key_Space, Qt.Key_Escape, Qt.Key_Return, Qt.Key_Enter, Qt.Key_Delete, Qt.Key_Backspace].indexOf(event.key) >= 0)
            event.accepted = true;
    }
    Keys.onPressed: event => {
        event.accepted = laneModel.keyPressed(event.key, event.isAutoRepeat);
    }

    Item {
        x: root.canvasRect.x
        y: root.canvasRect.y
        width: root.canvasRect.width
        height: root.canvasRect.height
        clip: true

        Rectangle {
            anchors.fill: parent
            color: "#D4CCC7"
        }

        Repeater {
            model: root.laneModel.marks
            delegate: Rectangle {
                required property var model
                x: model.x - root.canvasRect.x
                y: model.y - root.canvasRect.y
                width: model.width
                height: model.height
                radius: model.radius
                color: model.color
                border.color: model.borderColor
                border.width: model.borderWidth
                rotation: model.angle
                transformOrigin: Item.Left
                antialiasing: model.radius > 0 || model.angle !== 0
            }
        }
    }

    MouseArea {
        x: root.canvasRect.x
        y: root.canvasRect.y
        width: root.canvasRect.width
        height: root.canvasRect.height
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        hoverEnabled: true
        cursorShape: Qt.CrossCursor
        onEntered: root.hintChanged(qsTr("Drag: draw or move a node · Shift/Alt: straight line · Alt-drag node: fine movement"))
        onExited: root.hintChanged("")
        onPressed: mouse => {
            root.forceActiveFocus(Qt.MouseFocusReason);
            root.laneModel.beginPointer(mouse.x + x, mouse.y + y, mouse.modifiers);
        }
        onPositionChanged: mouse => {
            if (pressed)
                root.laneModel.updatePointer(mouse.x + x, mouse.y + y, mouse.modifiers);
        }
        onReleased: mouse => {
            root.laneModel.endPointer(mouse.x + x, mouse.y + y, mouse.modifiers);
        }
        onCanceled: root.laneModel.cancelPointer()
        onWheel: wheel => {
            if (!root.bipolar) {
                wheel.accepted = false;
                return;
            }
            root.laneModel.wheelRange(wheel.angleDelta.y, wheel.pixelDelta.y, wheel.phase === Qt.ScrollMomentum);
            wheel.accepted = true;
        }
    }
}
