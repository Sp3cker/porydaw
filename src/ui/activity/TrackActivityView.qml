import QtQuick

Item {
    id: root

    Repeater {
        model: trackActivityModel

        delegate: Rectangle {
            required property real rowY
            required property int meterHeight
            required property color dimColor
            required property color activeColor
            required property real leftHeight
            required property real rightHeight

            x: 0
            y: rowY
            width: root.width
            height: meterHeight
            color: dimColor

            Rectangle {
                x: 0
                width: parent.width * 0.5
                height: leftHeight
                anchors.bottom: parent.bottom
                color: parent.activeColor
            }

            Rectangle {
                x: parent.width * 0.5
                width: parent.width * 0.5
                height: rightHeight
                anchors.bottom: parent.bottom
                color: parent.activeColor
            }
        }
    }
}
