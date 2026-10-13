pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Layouts
import Porydaw.Ui
import PorydawApp

ColumnLayout {
    id: view
    objectName: "splitStudioZoneEditor"
    required property KitStudioWorkflow workflow
    required property KitStudioPresenter editor
    required property GridPalette colors
    required property real unit
    required property real paneSpacing
    property real keyboardZoom: 1
    readonly property real keyWidth: 2.25 * unit * keyboardZoom
    spacing: paneSpacing

    RowLayout {
        Layout.fillWidth: true
        Label { text: qsTr("Zones"); color: view.colors.windowText }
        Button { objectName: "splitStudioModeDrumkit"; text: qsTr("Drumkit"); checked: view.editor.mode === 0; onClicked: view.editor.setMode(0) }
        Button { objectName: "splitStudioModeKeysplit"; text: qsTr("Keysplit"); checked: view.editor.mode === 1; onClicked: view.editor.setMode(1) }
        Button { text: "−"; Accessible.name: qsTr("Zoom keyboard out"); onClicked: view.keyboardZoom = Math.max(0.5, view.keyboardZoom / 1.25) }
        Button { text: "+"; Accessible.name: qsTr("Zoom keyboard in"); onClicked: view.keyboardZoom = Math.min(4, view.keyboardZoom * 1.25) }
        SpinBox { id: firstKey; from: 0; to: 127; value: 60; editable: true }
        CheckBox { id: whiteKeys; text: qsTr("White keys only") }
        Button { text: qsTr("Map all slices"); enabled: view.editor.sliceCount > 0; onClicked: view.editor.mapAllSlices(firstKey.value, whiteKeys.checked) }
        Item { Layout.fillWidth: true }
    }
    ScrollView {
        id: keyboardScroll
        objectName: "splitStudioKeyboardScroll"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 8 * view.unit
        contentWidth: 128 * view.keyWidth
        contentHeight: keyboardBoard.height
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOn
        ScrollBar.vertical.policy: ScrollBar.AlwaysOff
        Item {
            id: keyboardBoard
            width: 128 * view.keyWidth
            height: 8 * view.unit
            function keyAt(x: real): int { return Math.max(0, Math.min(127, Math.floor(x / view.keyWidth))) }
            Repeater {
                model: 128
                Rectangle {
                    id: keyCell
                    required property int index
                    readonly property bool blackKey: [1, 3, 6, 8, 10].indexOf(index % 12) !== -1
                    x: index * view.keyWidth
                    y: 3 * view.unit
                    width: view.keyWidth
                    height: 5 * view.unit
                    color: blackKey ? view.colors.chromeBackground : view.colors.windowBackground
                    border.color: view.colors.windowText
                    border.width: view.unit / 13
                    Label { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; text: keyCell.index; color: view.colors.windowText }
                    MouseArea {
                        anchors.fill: parent
                        onPressed: view.editor.playKey(keyCell.index)
                        onReleased: view.workflow.stopAudition()
                        onCanceled: view.workflow.stopAudition()
                    }
                }
            }
            Repeater {
                model: view.editor.zoneRows
                Rectangle {
                    id: zone
                    required property int index
                    required property int startKey
                    required property int endKey
                    required property string sampleName
                    required property bool selected
                    required property bool locked
                    required property string voiceType
                    property int moveDelta: 0
                    property int startDelta: 0
                    property int endDelta: 0
                    x: (startKey + moveDelta + startDelta) * view.keyWidth
                    width: (endKey - startKey + 1 + endDelta - startDelta) * view.keyWidth
                    height: 3 * view.unit
                    color: selected ? view.colors.tabSelectedBackground : view.colors.buttonBackground
                    border.color: view.colors.windowText
                    border.width: view.unit / 13
                    Label {
                        anchors.fill: parent
                        anchors.margins: view.paneSpacing
                        text: zone.locked ? qsTr("Locked: ") + zone.voiceType : zone.sampleName
                        color: zone.selected ? view.colors.selectionText : view.colors.windowText
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                    MouseArea {
                        id: bodyDrag
                        anchors.fill: parent
                        enabled: !zone.locked
                        property int pressKey: 0
                        onPressed: mouse => {
                            pressKey = keyboardBoard.keyAt(mapToItem(keyboardBoard, mouse.x, mouse.y).x)
                        }
                        onPositionChanged: mouse => {
                            if (!pressed) return
                            const key = keyboardBoard.keyAt(mapToItem(keyboardBoard, mouse.x, mouse.y).x)
                            zone.moveDelta = Math.max(-zone.startKey, Math.min(127 - zone.endKey, key - pressKey))
                        }
                        onReleased: {
                            const key = zone.startKey + zone.moveDelta
                            zone.moveDelta = 0
                            const index = zone.index
                            const editor = view.editor
                            editor.selectZone(index)
                            editor.moveZone(index, key)
                        }
                        onCanceled: zone.moveDelta = 0
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: zone.locked
                        onClicked: view.editor.selectZone(zone.index)
                    }
                    MouseArea {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: view.unit / 2
                        enabled: !zone.locked
                        cursorShape: Qt.SizeHorCursor
                        onPositionChanged: mouse => {
                            if (pressed) zone.startDelta = Math.min(zone.endKey, keyboardBoard.keyAt(mapToItem(keyboardBoard, mouse.x, mouse.y).x)) - zone.startKey
                        }
                        onReleased: {
                            const start = zone.startKey + zone.startDelta
                            zone.startDelta = 0
                            const index = zone.index
                            const end = zone.endKey
                            const editor = view.editor
                            editor.selectZone(index)
                            editor.resizeZone(index, start, end)
                        }
                        onCanceled: zone.startDelta = 0
                    }
                    MouseArea {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: view.unit / 2
                        enabled: !zone.locked
                        cursorShape: Qt.SizeHorCursor
                        onPositionChanged: mouse => {
                            if (pressed) zone.endDelta = Math.max(zone.startKey, keyboardBoard.keyAt(mapToItem(keyboardBoard, mouse.x, mouse.y).x)) - zone.endKey
                        }
                        onReleased: {
                            const end = zone.endKey + zone.endDelta
                            zone.endDelta = 0
                            const index = zone.index
                            const start = zone.startKey
                            const editor = view.editor
                            editor.selectZone(index)
                            editor.resizeZone(index, start, end)
                        }
                        onCanceled: zone.endDelta = 0
                    }
                }
            }
            DropArea {
                anchors.fill: parent
                keys: ["porydaw-sample", "porydaw-library"]
                onDropped: drop => {
                    const event = drop as DragEvent
                    if (!event) return
                    const key = keyboardBoard.keyAt(event.x)
                    const source = event.source as KitDragSource
                    if (!source) return
                    if (source.sliceName.length > 0) view.editor.dropSample(source.sliceName, key)
                    else if (source.libraryPath.length > 0) view.workflow.dropLibrarySample(source.libraryPath, key)
                    else return
                    event.acceptProposedAction()
                }
            }
        }
    }
    Repeater {
        model: view.editor.zoneRows
        ScrollView {
            id: strip
            objectName: "splitStudioZoneStrip"
            required property int index
            required property int rootKey
            required property bool pitched
            required property int pan
            required property int attack
            required property int decay
            required property int sustain
            required property int release
            required property bool locked
            required property bool selected
            required property bool panEnabled
            required property bool pitchedEnabled
            required property bool rootKeyEnabled
            visible: selected
            Layout.fillWidth: true
            Layout.preferredHeight: 4 * view.unit
            contentWidth: fields.implicitWidth
            contentHeight: fields.implicitHeight
            ScrollBar.horizontal.policy: ScrollBar.AsNeeded
            ScrollBar.vertical.policy: ScrollBar.AlwaysOff
            RowLayout {
                id: fields
                spacing: view.paneSpacing
                Label { text: strip.locked ? qsTr("Locked zone") : qsTr("Root key"); enabled: strip.rootKeyEnabled || strip.locked; color: view.colors.windowText }
                SpinBox { from: 0; to: 127; value: strip.rootKey; enabled: strip.rootKeyEnabled; editable: true; onValueModified: view.editor.setZoneRootKey(value) }
                CheckBox { text: qsTr("Pitched"); checked: strip.pitched; enabled: strip.pitchedEnabled; onClicked: view.editor.setZonePitched(checked) }
                Label { text: qsTr("Pan"); enabled: strip.panEnabled; color: view.colors.windowText }
                SpinBox { from: -128; to: 126; stepSize: 2; value: strip.pan; enabled: strip.panEnabled; editable: true; onValueModified: view.editor.setZonePan(value) }
                Label { text: qsTr("A"); enabled: !strip.locked; color: view.colors.windowText }
                SpinBox { from: 0; to: 255; value: strip.attack; enabled: !strip.locked; editable: true; onValueModified: view.editor.setZoneAdsr(value, strip.decay, strip.sustain, strip.release) }
                Label { text: qsTr("D"); enabled: !strip.locked; color: view.colors.windowText }
                SpinBox { from: 0; to: 255; value: strip.decay; enabled: !strip.locked; editable: true; onValueModified: view.editor.setZoneAdsr(strip.attack, value, strip.sustain, strip.release) }
                Label { text: qsTr("S"); enabled: !strip.locked; color: view.colors.windowText }
                SpinBox { from: 0; to: 255; value: strip.sustain; enabled: !strip.locked; editable: true; onValueModified: view.editor.setZoneAdsr(strip.attack, strip.decay, value, strip.release) }
                Label { text: qsTr("R"); enabled: !strip.locked; color: view.colors.windowText }
                SpinBox { from: 0; to: 255; value: strip.release; enabled: !strip.locked; editable: true; onValueModified: view.editor.setZoneAdsr(strip.attack, strip.decay, strip.sustain, value) }
                Button { text: qsTr("Delete zone"); onClicked: view.editor.deleteZone(strip.index) }
            }
        }
    }
}
