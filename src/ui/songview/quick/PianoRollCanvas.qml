import QtQuick
import Porydaw.Ui
import PorydawApp

Item {
    id: root

    required property Item bandSide
    required property Item plotSide
    required property PianoGrid gridModel

    DisplayList {
        parent: root.plotSide
        objectName: "timelineRendererPlot"
        anchors.fill: parent
        clip: true
        source: root.gridModel.scene
        list: 0
        revision: root.gridModel.scene.displayRevision
        z: 0
    }

    Item {
        parent: root.bandSide
        objectName: "timelineQuickPianoKeyboardTextViewport"
        anchors.fill: parent
        clip: true
        z: 3

        DisplayList {
            objectName: "timelineRendererKeyboard"
            anchors.fill: parent
            clip: true
            source: root.gridModel.scene
            list: 1
            revision: root.gridModel.scene.displayRevision
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
