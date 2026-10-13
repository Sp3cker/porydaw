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
    required property font captionFont
    property real keyboardZoom: 1
    readonly property real keyWidth: 2.25 * unit * keyboardZoom
    spacing: paneSpacing

    component Field: ColumnLayout {
        id: field
        required property string caption
        required property GridPalette colors
        required property font captionFont
        required property real paneSpacing
        default property alias content: fieldRow.data
        spacing: 0
        Label {
            text: field.caption
            font: field.captionFont
            color: field.enabled ? field.colors.secondaryText : field.colors.disabledText
        }
        RowLayout { id: fieldRow; spacing: field.paneSpacing }
    }

    Flow {
        Layout.fillWidth: true
        spacing: 2 * view.paneSpacing
        Field {
            caption: qsTr("Zone layout"); colors: view.colors; captionFont: view.captionFont; paneSpacing: 0
            Button { objectName: "splitStudioModeDrumkit"; text: qsTr("Drumkit"); checked: view.editor.mode === 0; onClicked: view.editor.setMode(0) }
            Button { objectName: "splitStudioModeKeysplit"; text: qsTr("Keysplit"); checked: view.editor.mode === 1; onClicked: view.editor.setMode(1) }
        }
        Field {
            caption: qsTr("Keyboard zoom"); colors: view.colors; captionFont: view.captionFont; paneSpacing: view.paneSpacing
            Button { Layout.preferredWidth: 2.5 * view.unit; text: "−"; Accessible.name: qsTr("Zoom keyboard out"); onClicked: view.keyboardZoom = Math.max(0.5, view.keyboardZoom / 1.25) }
            Button { Layout.preferredWidth: 2.5 * view.unit; text: "+"; Accessible.name: qsTr("Zoom keyboard in"); onClicked: view.keyboardZoom = Math.min(4, view.keyboardZoom * 1.25) }
        }
        Field {
            caption: qsTr("Place all slices on the keyboard, starting at key"); colors: view.colors; captionFont: view.captionFont; paneSpacing: view.paneSpacing
            SpinBox { id: firstKey; Layout.preferredWidth: 5 * view.unit; from: 0; to: 127; value: 60; editable: true; Accessible.name: qsTr("First key") }
            Label { text: view.workflow.keyName(firstKey.value); color: view.colors.windowText }
            CheckBox { id: whiteKeys; text: qsTr("White keys only") }
            Button { text: qsTr("Map Slices"); enabled: view.editor.sliceCount > 0; onClicked: view.editor.mapAllSlices(firstKey.value, whiteKeys.checked) }
        }
    }
    Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font: view.captionFont
        color: view.colors.secondaryText
        text: (view.editor.mode === 0
            ? qsTr("Drumkit: each key plays its own sample, with its own pitch, pan and envelope.")
            : qsTr("Keysplit: each sample covers a range of keys and plays at the pitch of the key pressed."))
            + qsTr(" Switching layouts is safe: both keep your edits, and Save to Song saves the one selected.")
    }
    function revealKeys(first: int, last: int): void {
        const flick = keyboardScroll.contentItem as Flickable
        const visibleWidth = keyboardScroll.width
        if (!flick || visibleWidth <= 0)
            return
        const left = first * view.keyWidth
        const right = (last + 1) * view.keyWidth
        if (left >= flick.contentX && right <= flick.contentX + visibleWidth)
            return
        flick.contentX = Math.max(0, Math.min(keyboardScroll.contentWidth - visibleWidth, (left + right - visibleWidth) / 2))
    }
    ScrollView {
        id: keyboardScroll
        objectName: "splitStudioKeyboardScroll"
        Layout.fillWidth: true
        Layout.preferredHeight: keyboardBoard.height + keyboardScroll.ScrollBar.horizontal.height
        contentWidth: 128 * view.keyWidth
        contentHeight: keyboardBoard.height
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOn
        ScrollBar.vertical.policy: ScrollBar.AlwaysOff
        onWidthChanged: if (width > 0 && !revealed) { revealed = true; view.revealKeys(36, 72) }
        property bool revealed: false
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
                        text: zone.locked ? zone.voiceType + qsTr(" (synth)") : zone.sampleName
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
        Flow {
            id: strip
            objectName: "splitStudioZoneStrip"
            required property int index
            required property int startKey
            required property int endKey
            required property string sampleName
            required property string voiceType
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
            onVisibleChanged: if (visible) view.revealKeys(startKey, endKey)
            Component.onCompleted: if (selected) view.revealKeys(startKey, endKey)
            Layout.fillWidth: true
            spacing: 2 * view.paneSpacing
            Field {
                visible: !strip.locked
                caption: qsTr("Sample"); colors: view.colors; captionFont: view.captionFont; paneSpacing: view.paneSpacing
                Label { text: strip.sampleName; color: view.colors.windowText }
            }
            Field {
                visible: strip.locked
                caption: qsTr("Synth voice"); colors: view.colors; captionFont: view.captionFont; paneSpacing: view.paneSpacing
                Label {
                    text: qsTr("%1 is a synth voice, not a sample. Split Studio keeps it as it is; you can only delete it here.").arg(strip.voiceType)
                    color: view.colors.windowText
                }
            }
            Field {
                visible: !strip.locked
                enabled: strip.rootKeyEnabled
                caption: qsTr("Plays at note (C4 = original pitch)"); colors: view.colors; captionFont: view.captionFont; paneSpacing: view.paneSpacing
                SpinBox { Layout.preferredWidth: 5 * view.unit; from: 0; to: 127; value: strip.rootKey; editable: true; Accessible.name: qsTr("Root key"); onValueModified: view.editor.setZoneRootKey(value) }
                Label { text: view.workflow.keyName(strip.rootKey); color: view.colors.windowText }
            }
            Field {
                visible: !strip.locked
                enabled: strip.pitchedEnabled
                caption: qsTr("Pitch"); colors: view.colors; captionFont: view.captionFont; paneSpacing: view.paneSpacing
                CheckBox { text: qsTr("Rises with each key"); checked: strip.pitched; onClicked: view.editor.setZonePitched(checked) }
            }
            Field {
                visible: !strip.locked
                enabled: strip.panEnabled
                caption: qsTr("Pan (Drumkit only)"); colors: view.colors; captionFont: view.captionFont; paneSpacing: view.paneSpacing
                SpinBox { Layout.preferredWidth: 6 * view.unit; from: -128; to: 126; stepSize: 2; value: strip.pan; editable: true; Accessible.name: qsTr("Pan"); onValueModified: view.editor.setZonePan(value) }
            }
            Field {
                visible: !strip.locked
                caption: qsTr("Attack"); colors: view.colors; captionFont: view.captionFont; paneSpacing: view.paneSpacing
                SpinBox { Layout.preferredWidth: 5 * view.unit; from: 0; to: 255; value: strip.attack; editable: true; Accessible.name: qsTr("Attack"); onValueModified: view.editor.setZoneAdsr(value, strip.decay, strip.sustain, strip.release) }
            }
            Field {
                visible: !strip.locked
                caption: qsTr("Decay"); colors: view.colors; captionFont: view.captionFont; paneSpacing: view.paneSpacing
                SpinBox { Layout.preferredWidth: 5 * view.unit; from: 0; to: 255; value: strip.decay; editable: true; Accessible.name: qsTr("Decay"); onValueModified: view.editor.setZoneAdsr(strip.attack, value, strip.sustain, strip.release) }
            }
            Field {
                visible: !strip.locked
                caption: qsTr("Sustain"); colors: view.colors; captionFont: view.captionFont; paneSpacing: view.paneSpacing
                SpinBox { Layout.preferredWidth: 5 * view.unit; from: 0; to: 255; value: strip.sustain; editable: true; Accessible.name: qsTr("Sustain"); onValueModified: view.editor.setZoneAdsr(strip.attack, strip.decay, value, strip.release) }
            }
            Field {
                visible: !strip.locked
                caption: qsTr("Release"); colors: view.colors; captionFont: view.captionFont; paneSpacing: view.paneSpacing
                SpinBox { Layout.preferredWidth: 5 * view.unit; from: 0; to: 255; value: strip.release; editable: true; Accessible.name: qsTr("Release"); onValueModified: view.editor.setZoneAdsr(strip.attack, strip.decay, strip.sustain, value) }
            }
            Field {
                caption: " "; colors: view.colors; captionFont: view.captionFont; paneSpacing: view.paneSpacing
                Button { text: qsTr("Delete Zone"); onClicked: view.editor.deleteZone(strip.index) }
            }
        }
    }
    Item { Layout.fillHeight: true }
}
