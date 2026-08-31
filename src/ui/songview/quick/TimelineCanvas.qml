import QtQuick
import Porydaw.Ui

Item {
    id: root

    property rect rulerBandRect: Qt.rect(0, 0, 0, 0)
    property rect rollBandRect: Qt.rect(0, 0, 0, 0)
    property rect otherEventsBandRect: Qt.rect(0, 0, 0, 0)
    property bool rulerBandVisible: false
    property bool rollBandVisible: false
    property bool otherEventsBandVisible: false

    Component {
        id: bandTextDelegate

        Text {
            required property rect labelRect
            required property string labelText
            required property color labelColor
            required property font labelFont
            required property int labelHorizontalAlignment
            required property int labelVerticalAlignment

            x: labelRect.x
            y: labelRect.y
            width: labelRect.width
            height: labelRect.height
            text: labelText
            color: labelColor
            font: labelFont
            horizontalAlignment: labelHorizontalAlignment
            verticalAlignment: labelVerticalAlignment
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            elide: Text.ElideNone
            maximumLineCount: 1
            clip: true
        }
    }

    Item {
        x: root.rulerBandRect.x
        y: root.rulerBandRect.y
        width: root.rulerBandRect.width
        height: root.rulerBandRect.height
        clip: true
        visible: root.rulerBandVisible

        TimelineQuickItem {
            objectName: "timelineQuickRulerChrome"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.RulerChrome
            z: 0
        }

        TimelineQuickItem {
            objectName: "timelineQuickRulerMarks"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.RulerMarks
            z: 1
        }

        Item {
            anchors.fill: parent
            z: 2

            Repeater {
                model: timelineScene.rulerTextModel
                delegate: bandTextDelegate
            }
        }
    }

    Item {
        x: root.rollBandRect.x
        y: root.rollBandRect.y
        width: root.rollBandRect.width
        height: root.rollBandRect.height
        clip: true
        visible: root.rollBandVisible

        PianoRollCanvas {
            anchors.fill: parent
        }
    }

    Item {
        x: root.otherEventsBandRect.x
        y: root.otherEventsBandRect.y
        width: root.otherEventsBandRect.width
        height: root.otherEventsBandRect.height
        clip: true
        visible: root.otherEventsBandVisible

        TimelineQuickItem {
            objectName: "timelineQuickOtherEventsChrome"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.OtherEventsChrome
            z: 0
        }

        TimelineQuickItem {
            objectName: "timelineQuickOtherEventsMarkers"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.OtherEventsMarkers
            z: 1
        }

        Item {
            anchors.fill: parent
            z: 2

            Repeater {
                model: timelineScene.otherEventsTextModel
                delegate: bandTextDelegate
            }
        }
    }
}
