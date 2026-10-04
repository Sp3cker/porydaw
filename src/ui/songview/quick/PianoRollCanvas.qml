pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Ui
import PorydawApp

Item {
    id: root

    final required property Item bandSide
    final required property Item plotSide
    final required property PianoGrid gridModel
    Binding {
        when: root.gridModel !== null
        restoreMode: Binding.RestoreNone
        plotDisplay.revision: root.gridModel?.scene?.displayRevision
        keyboardDisplay.revision: root.gridModel?.scene?.displayRevision
        hoverChip.x: root.gridModel?.scene?.hoverChipX
        hoverChip.y: root.gridModel?.scene?.hoverChipY
        hoverChip.width: root.gridModel?.scene?.hoverChipWidth
        hoverChip.height: root.gridModel?.scene?.hoverChipHeight
        hoverChip.color: root.gridModel?.scene?.hoverChipFill
        hoverChip.radius: root.gridModel?.scene?.hoverChipRadius
        hoverChipText.x: root.gridModel?.scene?.hoverChipX
        hoverChipText.y: root.gridModel?.scene?.hoverChipY
        hoverChipText.width: root.gridModel?.scene?.hoverChipWidth
        hoverChipText.height: root.gridModel?.scene?.hoverChipHeight
        hoverChipText.text: root.gridModel?.scene?.hoverChipText
        hoverChipText.color: root.gridModel?.scene?.hoverChipTextColor
        hoverChipText.font: root.gridModel?.scene?.hoverChipFont
    }

    DisplayList {
        id: plotDisplay
        parent: root.plotSide
        objectName: "timelineRendererPlot"
        anchors.fill: parent
        clip: true
        source: root.gridModel?.scene ?? null
        list: 0
        z: 0
    }

    Item {
        parent: root.bandSide
        objectName: "timelineQuickPianoKeyboardTextViewport"
        anchors.fill: parent
        clip: true
        z: 3

        DisplayList {
            id: keyboardDisplay
            objectName: "timelineRendererKeyboard"
            anchors.fill: parent
            clip: true
            source: root.gridModel?.scene ?? null
            list: 1
        }
    }

    Rectangle {
        id: hoverChip
        parent: root.bandSide
        objectName: "timelineQuickPianoHoverChip"
        visible: root.gridModel !== null && root.gridModel.scene.hoverChipVisible
        z: 8
    }

    Text {
        id: hoverChipText
        parent: root.bandSide
        objectName: "timelineQuickPianoHoverChipText"
        visible: root.gridModel !== null && root.gridModel.scene.hoverChipVisible
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
