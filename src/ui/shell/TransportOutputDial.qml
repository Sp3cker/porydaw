import QtQuick
import QtQuick.Controls.Basic as Basic
import Porydaw.Ui

Item {
    id: dial
    required property QtObject colors
    required property int baseFontPx
    property int value: 100
    signal valueCommitted(int percent)

    objectName: "transportOutputVolume"
    readonly property real inset: Math.max(1, Math.round(baseFontPx / 12))
    readonly property bool hovered: outputHover.hovered
    readonly property real radiusPx: Math.min(width, height) / 2 - inset
    implicitWidth: Math.round(baseFontPx * 5 / 3) + 2 * Math.round(baseFontPx / 4)
    implicitHeight: implicitWidth
    activeFocusOnTab: true
    Accessible.role: Accessible.Slider
    Accessible.name: qsTr("Application output volume")
    Basic.ToolTip.text: qsTr("Application output volume. Does not change the song volume or saved song settings.")
    Basic.ToolTip.visible: hovered

    Repeater {
        model: 11
        delegate: Rectangle {
            required property int index
            readonly property real angle: (240 - index * 30) * Math.PI / 180
            width: dial.inset
            height: index === 0 || index === 10 ? dial.inset * 3 : dial.inset * 2
            radius: width / 2
            color: dial.colors.outline
            x: dial.width / 2 + Math.cos(angle) * (dial.radiusPx - height / 2) - width / 2
            y: dial.height / 2 - Math.sin(angle) * (dial.radiusPx - height / 2) - height / 2
            rotation: 90 - (240 - index * 30)
        }
    }
    Rectangle {
        id: face
        anchors.centerIn: parent
        width: dial.radiusPx * 1.35
        height: width
        radius: width / 2
        border.width: dial.inset
        border.color: dial.colors.outline
        color: dial.colors.buttonBackground
    }
    Rectangle {
        anchors.centerIn: face
        width: face.width * 0.35
        height: width
        radius: width / 2
        color: dial.colors.buttonHoverBackground
    }
    Rectangle {
        readonly property real angle: (240 - dial.value * 3) * Math.PI / 180
        width: dial.inset * 2
        height: width
        radius: width / 2
        color: dial.colors.buttonText
        x: dial.width / 2 + Math.cos(angle) * face.width * 0.32 - width / 2
        y: dial.height / 2 - Math.sin(angle) * face.height * 0.32 - height / 2
    }
    HoverHandler { id: outputHover }
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        property real dragLastY: 0
        property real stepAccumulator: 0
        onPressed: mouse => {
            dragLastY = mouse.y
            stepAccumulator = 0
            dial.forceActiveFocus(Qt.MouseFocusReason)
        }
        onPositionChanged: mouse => {
            if (!pressed) return
            const rate = mouse.modifiers & Qt.ShiftModifier ? 0.2 : 0.5
            stepAccumulator += (mouse.y - dragLastY) * rate
            dragLastY = mouse.y
            const steps = Math.trunc(stepAccumulator)
            if (steps !== 0) {
                stepAccumulator -= steps
                dial.valueCommitted(Math.max(0, Math.min(100, dial.value + steps)))
            }
        }
        onWheel: wheel => {
            dial.valueCommitted(Math.max(0, Math.min(100,
                dial.value + Math.trunc(wheel.angleDelta.y / 120) * 10)))
            wheel.accepted = true
        }
    }
    Keys.onUpPressed: event => { dial.valueCommitted(Math.min(100, dial.value + 1)); event.accepted = true }
    Keys.onDownPressed: event => { dial.valueCommitted(Math.max(0, dial.value - 1)); event.accepted = true }
}
