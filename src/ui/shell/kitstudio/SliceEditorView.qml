pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Layouts
import Porydaw.Ui
import PorydawApp

ColumnLayout {
    id: view
    objectName: "splitStudioSliceEditor"
    required property KitStudioWorkflow workflow
    required property KitStudioPresenter editor
    required property GridPalette colors
    required property real unit
    required property real paneSpacing
    required property Item dragLayer
    spacing: paneSpacing

    ScrollView {
        Layout.fillWidth: true
        Layout.preferredHeight: sourceTabs.implicitHeight + view.unit
        contentWidth: sourceTabs.implicitWidth
        contentHeight: sourceTabs.implicitHeight
        ScrollBar.vertical.policy: ScrollBar.AlwaysOff
        RowLayout {
            id: sourceTabs
            Repeater {
                model: view.editor.sourceRows
                RowLayout {
                    id: sourceTab
                    required property int index
                    required property string name
                    required property bool active
                    spacing: view.paneSpacing
                    Button {
                        text: sourceTab.name
                        checkable: true
                        checked: sourceTab.active
                        onClicked: view.workflow.selectSource(sourceTab.index)
                    }
                    ToolButton {
                        text: "×"
                        Accessible.name: qsTr("Close %1").arg(sourceTab.name)
                        onClicked: view.workflow.closeSource(sourceTab.index)
                    }
                }
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: view.paneSpacing
        Item { Layout.fillWidth: true }
        ToolButton {
            text: "−"
            Accessible.name: qsTr("Zoom waveform out")
            onClicked: if (view.editor.waveform) view.editor.waveform.zoom(wave.width / 2, -1)
        }
        ToolButton {
            text: "＋"
            Accessible.name: qsTr("Zoom waveform in")
            onClicked: if (view.editor.waveform) view.editor.waveform.zoom(wave.width / 2, 1)
        }
        Button {
            text: qsTr("Fit")
            onClicked: if (view.editor.waveform) view.editor.waveform.fit()
        }
    }
    Item {
        id: wave
        objectName: "splitStudioWaveform"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 6 * view.unit
        focus: true
        function resizeModel(): void {
            if (view.editor.waveform) {
                view.editor.waveform.setViewport(width, height)
                view.editor.waveform.setBaseFontPx(view.unit)
            }
        }
        onWidthChanged: resizeModel()
        onHeightChanged: resizeModel()
        Component.onCompleted: resizeModel()
        Connections {
            target: view.editor
            function onWaveformChanged(): void { wave.resizeModel() }
        }
        Rectangle { anchors.fill: parent; color: view.colors.windowBackground }
        DisplayList {
            anchors.fill: parent
            clip: true
            source: view.editor.waveform
            list: 0
            revision: view.editor.waveform ? view.editor.waveform.displayRevision : 0
        }
        MouseArea {
            id: waveInput
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            property bool markerDrag: false
            property bool panning: false
            property bool moved: false
            onPressed: mouse => {
                if (mouse.button === Qt.LeftButton) view.workflow.stopAudition()
                wave.forceActiveFocus()
                if (!view.editor.waveform) return
                moved = false
                panning = mouse.button === Qt.MiddleButton
                markerDrag = !panning && view.editor.waveform.handleAt(mouse.x, mouse.y) !== 0
                if (markerDrag || panning) {
                    view.editor.waveform.press(mouse.x, mouse.y)
                }
            }
            onPositionChanged: mouse => {
                moved = true
                if (!pressed || !view.editor.waveform) return
                if (markerDrag || panning) view.editor.waveform.drag(mouse.x)
            }
            onReleased: {
                if (view.editor.waveform) view.editor.waveform.release()
            }
            onCanceled: {
                if (view.editor.waveform) view.editor.waveform.release()
            }
            onClicked: mouse => {
                view.editor.clearLastAddedMarker()
                if (mouse.button === Qt.LeftButton && !moved && !markerDrag && !panning) {
                    view.editor.addMarker(mouse.x)
                }
            }
            onDoubleClicked: mouse => {
                if (mouse.button === Qt.LeftButton) {
                    view.editor.removeMarkerAt(mouse.x, mouse.y)
                }
            }
            onWheel: wheel => {
                if (view.editor.waveform) view.editor.waveform.zoom(wheel.x, wheel.angleDelta.y / 120)
                wheel.accepted = true
            }
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                view.workflow.removeSelectedMarker()
                event.accepted = true
            } else if (event.key === Qt.Key_Space && event.modifiers === Qt.NoModifier) {
                if (view.workflow.auditionPlaying) view.workflow.stopAudition()
                else if (view.editor.sliceCount > 0) view.editor.playSlice(view.editor.sliceId(0))
                event.accepted = true
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: view.paneSpacing
        CheckBox {
            text: qsTr("Snap to zero")
            checked: view.editor.snap
            onClicked: view.editor.toggleSnap()
        }
    }
    ListView {
        id: slices
        objectName: "splitStudioSlices"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 7 * view.unit
        clip: true
        model: view.editor.sliceCount
        spacing: view.paneSpacing
        contentWidth: Math.max(width, 36 * view.unit)
        flickableDirection: Flickable.HorizontalAndVerticalFlick
        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: Rectangle {
            id: sliceRow
            required property int index
            readonly property int sliceId: {
                void view.editor.slicesRevision
                return view.editor.sliceId(index)
            }
            readonly property string sampleName: {
                void view.editor.slicesRevision
                return view.editor.sliceName(sliceId)
            }
            readonly property int sliceNum: {
                void view.editor.slicesRevision
                return view.editor.sliceOrdinal(sliceId)
            }
            readonly property bool isSelected: view.editor.selectedSlice === sliceId
            property bool editing: false

            width: slices.contentWidth
            height: 2.5 * view.unit
            color: isSelected ? view.colors.selectionFill : "transparent"
            border.color: isSelected ? view.colors.selectionEdge : "transparent"
            border.width: isSelected ? 1 : 0
            radius: 2

            MouseArea {
                anchors.fill: parent
                enabled: !sliceRow.editing
                onClicked: view.editor.selectSlice(sliceRow.sliceId)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: view.paneSpacing
                anchors.rightMargin: view.paneSpacing
                spacing: view.paneSpacing

                Item {
                    Layout.preferredWidth: 3 * view.unit
                    Layout.fillHeight: true
                    KitDragSource {
                        sliceName: sliceRow.sampleName
                        dragLayer: view.dragLayer
                        width: parent.width
                        height: parent.height
                        color: view.colors.buttonBackground
                        z: 1
                        Drag.keys: ["porydaw-sample"]
                        Label {
                            anchors.centerIn: parent
                            text: "⋮⋮"
                            color: view.colors.windowText
                        }
                    }
                }

                Label {
                    Layout.preferredWidth: 2 * view.unit
                    horizontalAlignment: Text.AlignRight
                    text: sliceRow.sliceNum > 0 ? sliceRow.sliceNum : (sliceRow.index + 1)
                    color: view.colors.windowText
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 10 * view.unit

                    Label {
                        id: nameLabel
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: sliceRow.sampleName
                        color: view.colors.windowText
                        visible: !sliceRow.editing
                        elide: Text.ElideRight

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.IBeamCursor
                            onClicked: {
                                view.editor.selectSlice(sliceRow.sliceId)
                                sliceRow.editing = true
                                nameEdit.text = sliceRow.sampleName
                                nameEdit.forceActiveFocus()
                                nameEdit.selectAll()
                            }
                        }
                    }

                    ValidatedTextField {
                        id: nameEdit
                        objectName: "splitStudioSliceName"
                        anchors.fill: parent
                        visible: sliceRow.editing
                        colors: view.colors
                        text: sliceRow.sampleName
                        invalid: visible && view.editor.isSliceNameInvalid(sliceRow.sliceId, text)

                        function commit(): void {
                            if (!sliceRow.editing) return
                            if (!invalid && text.length > 0) {
                                view.editor.renameSlice(sliceRow.sliceId, text)
                                sliceRow.editing = false
                            } else {
                                text = sliceRow.sampleName
                                sliceRow.editing = false
                            }
                        }

                        function cancel(): void {
                            text = sliceRow.sampleName
                            sliceRow.editing = false
                        }

                        onAccepted: commit()
                        onActiveFocusChanged: {
                            if (!activeFocus && sliceRow.editing) {
                                commit()
                            }
                        }
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                cancel()
                                event.accepted = true
                            }
                        }
                    }
                }

                ToolButton {
                    text: "▶"
                    Accessible.name: qsTr("Play")
                    onClicked: view.editor.playSlice(sliceRow.sliceId)
                }

                ToolButton {
                    text: "✕"
                    Accessible.name: qsTr("Remove")
                    onClicked: view.workflow.removeSlice(sliceRow.sliceId)
                }
            }
        }
    }
}
