import QtQuick

Column {
    id: group
    property string caption: "PCM"
    property var channels
    property var colors
    property real em: 12
    width: parent.width
    spacing: 0

    Text {
        height: Math.round(group.em * 1.5)
        text: group.caption
        color: group.colors.disabledText
        font.pixelSize: group.em
        font.weight: Font.DemiBold
        verticalAlignment: Text.AlignVCenter
    }
    Flow {
        width: parent.width
        spacing: Math.round(group.em / 3)
        Repeater {
            model: group.channels
            delegate: Rectangle {
                required property string label
                required property int state
                width: Math.round(group.em * 46 / 12)
                height: Math.round(group.em * 34 / 12)
                radius: group.em / 4
                color: state === 3 ? "#2859A4"
                    : state === 2 ? "#B98527"
                    : state === 1 ? "#228445" : group.colors.buttonBackground
                Text {
                    anchors.fill: parent
                    text: label
                    color: state === 0 ? group.colors.disabledText : "#FFFFFF"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: group.em * 0.83
                    font.weight: Font.DemiBold
                    lineHeight: 0.95
                }
            }
        }
    }
    Item { height: Math.round(group.em / 3) }
}
