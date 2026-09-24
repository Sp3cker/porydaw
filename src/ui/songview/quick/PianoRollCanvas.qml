import QtQuick
import "./swiftroll" as SwiftRoll

Item {
    id: root

    required property Item gutterSide
    required property Item bandSide
    required property Item plotSide
    required property QtObject timelineScene

    // Keep pitch rows below pre-roll shading and time marks.
    SwiftRoll.TimelineQuickItem {
        parent: root.plotSide
        objectName: "timelineQuickPianoGridRows"
        anchors.fill: parent
        rects: root.timelineScene.pianoGridRows
        z: 0
    }

    SwiftRoll.TimelineQuickItem {
        parent: root.plotSide
        objectName: "timelineQuickPianoGridTime"
        anchors.fill: parent
        rects: root.timelineScene.pianoGridTime
        z: 1
    }

    SwiftRoll.TimelineQuickItem {
        parent: root.plotSide
        objectName: "timelineQuickPianoNoteFills"
        anchors.fill: parent
        rects: root.timelineScene.pianoNoteFills
        z: 2
    }

    SwiftRoll.TimelineQuickItem {
        parent: root.plotSide
        objectName: "timelineQuickPianoDrawPreviewFill"
        anchors.fill: parent
        rects: root.timelineScene.pianoDrawPreviewFill
        z: 3
    }

    Item {
        parent: root.plotSide
        anchors.fill: parent
        z: 4

        Repeater {
            model: root.timelineScene.pianoNoteTextModel

            delegate: Text {
                required property var labelRect
                required property string labelText
                required property string labelColor
                required property var labelFont
                required property int labelHorizontalAlignment
                required property int labelVerticalAlignment

                x: labelRect.x
                y: labelRect.y
                width: labelRect.width
                height: labelRect.height
                text: labelText
                color: labelColor
                font: Qt.font(labelFont)
                horizontalAlignment: labelHorizontalAlignment
                verticalAlignment: labelVerticalAlignment
                textFormat: Text.PlainText
                renderType: Text.NativeRendering
                elide: Text.ElideNone
                maximumLineCount: 1
                clip: contentWidth > width || contentHeight > height
            }
        }
    }

    SwiftRoll.TimelineQuickItem {
        parent: root.plotSide
        objectName: "timelineQuickPianoNoteBordersAndSelection"
        anchors.fill: parent
        rects: root.timelineScene.pianoNoteBordersAndSelection
        z: 5
    }

    SwiftRoll.TimelineQuickItem {
        parent: root.plotSide
        objectName: "timelineQuickPianoOverlay"
        anchors.fill: parent
        rects: root.timelineScene.pianoOverlay
        z: 6
    }

    SwiftRoll.TimelineQuickItem {
        parent: root.gutterSide
        objectName: "timelineQuickPianoKeyboardKeys"
        anchors.fill: parent
        rects: root.timelineScene.pianoKeyboardKeys
        z: 0
    }

    SwiftRoll.TimelineQuickItem {
        parent: root.gutterSide
        objectName: "timelineQuickPianoKeyboardHighlights"
        anchors.fill: parent
        rects: root.timelineScene.pianoKeyboardHighlights
        z: 1
    }

    // Drum labels and hover chips may span the gutter and plot so full pad
    // names stay readable. Their coordinates are already band-local because
    // the gutter starts at band-local x = 0.
    Rectangle {
        parent: root.bandSide
        objectName: "timelineQuickPianoHoverChip"
        x: root.timelineScene.hoverChipRect.x
        y: root.timelineScene.hoverChipRect.y
        width: root.timelineScene.hoverChipRect.width
        height: root.timelineScene.hoverChipRect.height
        visible: root.timelineScene.hoverChipVisible
        color: root.timelineScene.hoverChipFill
        radius: root.timelineScene.hoverChipRadius
        z: 8
    }

    Item {
        parent: root.bandSide
        anchors.fill: parent
        z: 3

        Repeater {
            model: root.timelineScene.pianoKeyboardTextModel

            delegate: Item {
                required property var labelRect
                required property string labelText
                required property string labelColor
                required property var labelFont
                required property int labelHorizontalAlignment
                required property int labelVerticalAlignment
                required property string labelBackground
                required property var labelBackgroundRect

                x: labelRect.x
                y: labelRect.y
                width: labelRect.width
                height: labelRect.height

                Rectangle {
                    x: labelBackgroundRect.x - labelRect.x
                    y: labelBackgroundRect.y - labelRect.y
                    width: labelBackgroundRect.width
                    height: labelBackgroundRect.height
                    visible: labelBackgroundRect.width > 0 && labelBackgroundRect.height > 0
                    color: labelBackground
                }

                Text {
                    anchors.fill: parent
                    text: labelText
                    color: labelColor
                    font: Qt.font(labelFont)
                    horizontalAlignment: labelHorizontalAlignment
                    verticalAlignment: labelVerticalAlignment
                    textFormat: Text.PlainText
                    renderType: Text.NativeRendering
                    elide: Text.ElideNone
                    maximumLineCount: 1
                    clip: contentWidth > width || contentHeight > height
                }
            }
        }
    }

    Text {
        parent: root.bandSide
        objectName: "timelineQuickPianoHoverChipText"
        x: root.timelineScene.hoverChipRect.x
        y: root.timelineScene.hoverChipRect.y
        width: root.timelineScene.hoverChipRect.width
        height: root.timelineScene.hoverChipRect.height
        visible: root.timelineScene.hoverChipVisible
        text: root.timelineScene.hoverChipText
        color: root.timelineScene.hoverChipTextColor
        font: Qt.font(root.timelineScene.hoverChipFont)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        elide: Text.ElideNone
        maximumLineCount: 1
        clip: contentWidth > width || contentHeight > height
        z: 9
    }

    Item {
        parent: root.plotSide
        anchors.fill: parent
        z: 7

        Repeater {
            model: root.timelineScene.pianoLoadingTextModel

            delegate: Text {
                required property var labelRect
                required property string labelText
                required property string labelColor
                required property var labelFont
                required property int labelHorizontalAlignment
                required property int labelVerticalAlignment

                x: labelRect.x
                y: labelRect.y
                width: labelRect.width
                height: labelRect.height
                text: labelText
                color: labelColor
                font: Qt.font(labelFont)
                horizontalAlignment: labelHorizontalAlignment
                verticalAlignment: labelVerticalAlignment
                textFormat: Text.PlainText
                renderType: Text.NativeRendering
                elide: Text.ElideNone
                maximumLineCount: 1
                clip: contentWidth > width || contentHeight > height
            }
        }
    }
}
