import QtQuick

Item {
    id: toolTip

    required property rect bandRect
    required property bool bandVisible
    required property Item overlayRoot
    required property var model
    required property font controlFont

    readonly property var appearance: model.appearance
    readonly property color backgroundColor: appearance.toolTipBackground
    readonly property color textColor: appearance.toolTipText
    readonly property color outlineColor: appearance.toolTipOutline
    readonly property real logicalX: bandRect.x + model.toolTipPosition.x
    readonly property real logicalY: bandRect.y + model.toolTipPosition.y

    objectName: "timelineTrackHeaderToolTip"
    x: Math.max(0, Math.min(Math.max(0, overlayRoot.width - width), logicalX))
    y: Math.max(0, Math.min(Math.max(0, overlayRoot.height - height), logicalY))
    width: Math.min(overlayRoot.width, toolTipText.implicitWidth + 8)
    height: Math.min(overlayRoot.height, toolTipText.implicitHeight + 6)
    visible: bandVisible && model.toolTipVisible && model.toolTipText.length > 0
    enabled: false

    Rectangle {
        anchors.fill: parent
        color: toolTip.backgroundColor
        border.color: toolTip.outlineColor
        border.width: 1
    }

    Text {
        id: toolTipText

        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        anchors.topMargin: 3
        anchors.bottomMargin: 3
        clip: true
        color: toolTip.textColor
        font: toolTip.controlFont
        text: toolTip.model.toolTipText
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        elide: Text.ElideRight
        maximumLineCount: 1
        verticalAlignment: Text.AlignVCenter
    }
}
