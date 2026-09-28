import QtQuick
import Porydaw.Ui

Item {
    id: root

    required property Item bandSide
    required property Item plotSide
    required property QtObject gridModel

    TimelineRenderer {
        parent: root.plotSide
        objectName: "timelineRendererPlot"
        anchors.fill: parent
        band: 0
        contentSource: root.gridModel.scene
        contentRevision: root.gridModel.scene.contentRevision
        pixelsPerTick: root.gridModel.pixelsPerTick
        keyHeight: root.gridModel.rowHeight
        scrollX: root.gridModel.cameraScrollX
        scrollY: root.gridModel.cameraScrollY
        devicePixelRatio: root.gridModel.devicePixelRatio
        bandSelectionActive: root.gridModel.bandSelectionActive
        bandSelectionX: root.gridModel.bandSelectionX
        bandSelectionY: root.gridModel.bandSelectionY
        bandSelectionWidth: root.gridModel.bandSelectionWidth
        bandSelectionHeight: root.gridModel.bandSelectionHeight
        z: 0
    }

    Item {
        parent: root.bandSide
        objectName: "timelineQuickPianoKeyboardTextViewport"
        anchors.fill: parent
        clip: true
        z: 3

        TimelineRenderer {
            objectName: "timelineRendererKeyboard"
            anchors.fill: parent
            band: 1
            contentSource: root.gridModel.scene
            contentRevision: root.gridModel.scene.contentRevision
            pixelsPerTick: root.gridModel.pixelsPerTick
            keyHeight: root.gridModel.rowHeight
            scrollX: root.gridModel.cameraScrollX
            scrollY: root.gridModel.cameraScrollY
            devicePixelRatio: root.gridModel.devicePixelRatio
            hoverPitch: root.gridModel.hoverKey
        }
    }

    Rectangle {
        parent: root.bandSide
        objectName: "timelineQuickPianoHoverChip"
        x: root.gridModel.scene.hoverChipRect.x
        y: root.gridModel.scene.hoverChipRect.y
        width: root.gridModel.scene.hoverChipRect.width
        height: root.gridModel.scene.hoverChipRect.height
        visible: root.gridModel.scene.hoverChipVisible
        color: root.gridModel.scene.hoverChipFill
        radius: root.gridModel.scene.hoverChipRadius
        z: 8
    }

    Text {
        parent: root.bandSide
        objectName: "timelineQuickPianoHoverChipText"
        x: root.gridModel.scene.hoverChipRect.x
        y: root.gridModel.scene.hoverChipRect.y
        width: root.gridModel.scene.hoverChipRect.width
        height: root.gridModel.scene.hoverChipRect.height
        visible: root.gridModel.scene.hoverChipVisible
        text: root.gridModel.scene.hoverChipText
        color: root.gridModel.scene.hoverChipTextColor
        font: Qt.font(root.gridModel.scene.hoverChipFont)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        elide: Text.ElideNone
        maximumLineCount: 1
        clip: contentWidth > width || contentHeight > height
        z: 9
    }
}
