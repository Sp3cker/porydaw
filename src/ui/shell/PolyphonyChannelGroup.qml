import QtQuick
import Porydaw.Ui

Column {
    id: group
    property string caption: "PCM"
    property var channels
    property var colors
    required property real em
    required property var typography
    width: parent.width
    spacing: 0

    Text {
        objectName: "polyphonyGroupCaption"
        height: Math.round(group.em * 1.5)
        text: group.caption
        font: Qt.font(group.typography.body)
        color: group.colors.secondaryText
        verticalAlignment: Text.AlignVCenter
    }
    Flow {
        width: parent.width
        spacing: Math.round(group.em * 4 / 12)
        Repeater {
            model: group.channels
            delegate: Rectangle {
                required property string label
                required property int state
                objectName: "polyphonyChannelCell"
                width: Math.round(group.em * 46 / 12)
                height: Math.round(group.em * 34 / 12)
                radius: group.em / 4
                color: state === 3 ? group.colors.polyphonyShadowFill
                    : state === 2 ? group.colors.polyphonyReleasingFill
                    : state === 1 ? group.colors.polyphonyActiveFill : group.colors.buttonBackground
                Text {
                    anchors.fill: parent
                    text: label
                    color: state === 2 ? group.colors.polyphonyReleasingText
                        : state === 1 || state === 3 ? group.colors.polyphonyCellText : group.colors.secondaryText
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font: Qt.font(group.typography.caption)
                    lineHeight: 0.95
                }
            }
        }
    }
    Item { height: Math.round(group.em * 4 / 12) }
}
