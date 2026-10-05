pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: toolTip

    required property Item overlayRoot
    required property rect anchorRect
    required property string toolTipText
    required property bool visibleForControl
    required property font controlFont
    required property color backgroundColor
    required property color textColor
    required property color outlineColor

    readonly property real horizontalPadding: controlFont.pixelSize * 4 / 13
    readonly property real verticalPadding: controlFont.pixelSize * 3 / 13
    readonly property real edgeMargin: controlFont.pixelSize * 4 / 13
    readonly property real verticalGap: controlFont.pixelSize * 2 / 13
    readonly property real maximumWidth: Math.max(0, overlayRoot.width - 2 * edgeMargin)
    readonly property real preferredX: anchorRect.x + (anchorRect.width - width) / 2
    readonly property real belowY: anchorRect.y + anchorRect.height + verticalGap
    readonly property real aboveY: anchorRect.y - height - verticalGap

    width: Math.min(maximumWidth, toolTipTextItem.implicitWidth + 2 * horizontalPadding)
    height: Math.min(overlayRoot.height, toolTipTextItem.implicitHeight + 2 * verticalPadding)
    x: Math.max(0, Math.min(Math.max(0, overlayRoot.width - width), preferredX))
    y: belowY + height <= overlayRoot.height ? belowY : Math.max(0, aboveY)
    visible: visibleForControl && toolTipText.length > 0 && width > 0 && height > 0
    enabled: false
    clip: true

    Rectangle {
        anchors.fill: parent
        color: toolTip.backgroundColor
        border.color: toolTip.outlineColor
        border.width: 1
    }

    Text {
        id: toolTipTextItem

        x: toolTip.horizontalPadding
        y: toolTip.verticalPadding
        width: Math.max(0, parent.width - 2 * toolTip.horizontalPadding)
        color: toolTip.textColor
        font: toolTip.controlFont
        text: toolTip.toolTipText
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        wrapMode: Text.WordWrap
    }
}
