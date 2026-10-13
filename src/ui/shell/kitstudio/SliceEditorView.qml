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
                    required property bool closable
                    spacing: view.paneSpacing
                    Button {
                        text: sourceTab.name
                        checkable: true
                        checked: sourceTab.active
                        onClicked: view.workflow.selectSource(sourceTab.index)
                    }
                    ToolButton {
                        text: "×"
                        Accessible.name: qsTr("Close source")
                        enabled: sourceTab.closable
                        onClicked: view.workflow.closeSource(sourceTab.index)
                    }
                }
            }
        }
    }
    ScrollView {
        Layout.fillWidth: true
        Layout.preferredHeight: sliceTools.implicitHeight + view.unit
        contentWidth: sliceTools.implicitWidth
        contentHeight: sliceTools.implicitHeight
        ScrollBar.vertical.policy: ScrollBar.AlwaysOff
        RowLayout {
            id: sliceTools
            spacing: view.paneSpacing
            Label { text: qsTr("Slices"); color: view.colors.windowText }
            Button { text: qsTr("Open File…"); onClicked: view.workflow.requestOpenFile() }
            Button { text: qsTr("Add marker"); onClicked: view.editor.addMarkerAtCursor() }
            Button { text: qsTr("Remove marker"); onClicked: view.workflow.removeSelectedMarker() }
            Button {
                objectName: "splitStudioSliceSelection"
                text: qsTr("Slice selection")
                enabled: view.editor.selectionEndFrame > view.editor.selectionStartFrame
                onClicked: view.editor.sliceSelection()
            }
            CheckBox {
                text: qsTr("Snap to zero")
                checked: view.editor.snap
                onClicked: view.editor.toggleSnap()
            }
            ComboBox {
                objectName: "splitStudioSourceRate"
                model: view.editor.rateChoices
                currentIndex: view.workflow.sourceRateIndex(view.editor.sourceRate)
                onActivated: index => view.workflow.chooseSourceRate(index)
            }
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
            property int selectionAnchor: 0
            onPressed: mouse => {
                if (mouse.button === Qt.LeftButton) view.workflow.stopAudition()
                wave.forceActiveFocus()
                if (!view.editor.waveform) return
                panning = mouse.button === Qt.MiddleButton
                markerDrag = view.editor.waveform.handleAt(mouse.x, mouse.y) !== 0
                selectionAnchor = view.workflow.frameAt(mouse.x)
                view.editor.cursorFrame = selectionAnchor
                if (markerDrag || panning)
                    view.editor.waveform.press(mouse.x, mouse.y)
                else {
                    view.editor.selectionStartFrame = selectionAnchor
                    view.editor.selectionEndFrame = selectionAnchor
                }
            }
            onPositionChanged: mouse => {
                if (!pressed || !view.editor.waveform) return
                if (markerDrag || panning) view.editor.waveform.drag(mouse.x)
                else {
                    const frame = view.workflow.frameAt(mouse.x)
                    view.editor.selectionStartFrame = Math.min(selectionAnchor, frame)
                    view.editor.selectionEndFrame = Math.max(selectionAnchor, frame)
                    view.editor.cursorFrame = frame
                }
            }
            onReleased: if (view.editor.waveform) view.editor.waveform.release()
            onCanceled: if (view.editor.waveform) view.editor.waveform.release()
            onWheel: wheel => {
                if (view.editor.waveform) view.editor.waveform.zoom(wheel.x, wheel.angleDelta.y / 120)
                wheel.accepted = true
            }
            onDoubleClicked: if (view.editor.waveform) view.editor.waveform.fit()
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
    ListView {
        id: slices
        objectName: "splitStudioSlices"
        Layout.fillWidth: true
        Layout.preferredHeight: 7 * view.unit
        clip: true
        model: view.editor.sliceCount
        spacing: view.paneSpacing
        contentWidth: Math.max(width, 58 * view.unit)
        flickableDirection: Flickable.HorizontalAndVerticalFlick
        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: Item {
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
            width: slices.contentWidth
            height: 2.5 * view.unit
            RowLayout {
                anchors.fill: parent
                spacing: view.paneSpacing
                Item {
                    Layout.preferredWidth: 4 * view.unit
                    Layout.fillHeight: true
                    KitDragSource {
                        sliceName: sliceRow.sampleName
                        dragLayer: view.dragLayer
                        width: 4 * view.unit
                        height: 2.5 * view.unit
                        color: view.colors.buttonBackground
                        z: 1
                        Drag.keys: ["porydaw-sample"]
                        Label { anchors.centerIn: parent; text: qsTr("Drag"); color: view.colors.windowText }
                    }
                }
                TextField {
                    objectName: "splitStudioSliceName"
                    Layout.fillWidth: true
                    text: sliceRow.sampleName
                    Layout.minimumWidth: 10 * view.unit
                    onEditingFinished: view.editor.renameSlice(sliceRow.sliceId, text)
                }
                Label {
                    text: {
                        void view.editor.slicesRevision
                        return view.editor.sliceStartFrame(sliceRow.sliceId) + "–" + view.editor.sliceEndFrame(sliceRow.sliceId)
                    }
                    color: view.colors.windowText
                }
                CheckBox {
                    text: qsTr("Fade in")
                    checked: { void view.editor.slicesRevision; return view.editor.sliceFadeIn(sliceRow.sliceId) }
                    onClicked: { view.workflow.stopAudition(); view.editor.setSliceFades(sliceRow.sliceId, checked, view.editor.sliceFadeOut(sliceRow.sliceId)) }
                }
                CheckBox {
                    text: qsTr("Fade out")
                    checked: { void view.editor.slicesRevision; return view.editor.sliceFadeOut(sliceRow.sliceId) }
                    onClicked: { view.workflow.stopAudition(); view.editor.setSliceFades(sliceRow.sliceId, view.editor.sliceFadeIn(sliceRow.sliceId), checked) }
                }
                Button { text: qsTr("Play"); onClicked: view.editor.playSlice(sliceRow.sliceId) }
                Button { text: qsTr("Remove"); onClicked: view.workflow.removeSlice(sliceRow.sliceId) }
            }
        }
    }
    Label { Layout.fillWidth: true; text: view.editor.statusText; color: view.colors.windowText; wrapMode: Text.WordWrap }
}
