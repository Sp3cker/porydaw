import QtQuick

Item {
    id: toolTip

    required property Item overlayRoot
    required property rect plotRect
    required property bool bandVisible
    required property var model
    required property font controlFont

    readonly property var appearance: model.toolTipAppearance
    readonly property color backgroundColor: appearance.toolTipBackground
    readonly property color textColor: appearance.toolTipText
    readonly property color outlineColor: appearance.toolTipOutline
    // Plot input coordinates are plot-local: the anchor translates them into
    // canvas space via the published plot rect (the band rect would miss the
    // gutter offset).
    readonly property rect anchorRect: Qt.rect(plotRect.x + model.toolTipPosition.x,
                                               plotRect.y + model.toolTipPosition.y, 1, 1)
    readonly property real horizontalPadding: 4
    readonly property real verticalPadding: 3
    readonly property real edgeMargin: 4
    readonly property real verticalGap: 2
    readonly property real maximumWidth: Math.max(0, overlayRoot.width - 2 * edgeMargin)
    readonly property real preferredX: anchorRect.x + (anchorRect.width - width) / 2
    readonly property real belowY: anchorRect.y + anchorRect.height + verticalGap
    readonly property real aboveY: anchorRect.y - height - verticalGap

    objectName: "timelineOtherEventsToolTip"
    width: Math.min(maximumWidth, toolTipTextItem.implicitWidth + 2 * horizontalPadding)
    height: Math.min(overlayRoot.height, toolTipTextItem.implicitHeight + 2 * verticalPadding)
    x: Math.max(0, Math.min(Math.max(0, overlayRoot.width - width), preferredX))
    y: belowY + height <= overlayRoot.height ? belowY : Math.max(0, aboveY)
    visible: bandVisible && model.toolTipVisible && model.toolTipText.length > 0
             && width > 0 && height > 0
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
        text: toolTip.model.toolTipText
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        wrapMode: Text.WordWrap
    }
}
