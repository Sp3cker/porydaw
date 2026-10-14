pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Layouts
import Porydaw.Ui
import Porydaw.Icons
import PorydawApp

Item {
    id: view
    objectName: "splitStudioSliceEditor"
    required property KitStudioWorkflow workflow
    required property KitStudioPresenter editor
    required property GridPalette colors
    required property real unit
    required property real paneSpacing
    required property Item dragLayer
    required property font monoFont
    Rectangle {
        anchors.fill: parent
        color: view.colors.windowBackground
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: view.paneSpacing

    RowLayout {
        Layout.fillWidth: true
        spacing: view.paneSpacing
        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: 2.5 * view.unit
            contentWidth: sourceTabs.implicitWidth
            contentHeight: sourceTabs.implicitHeight
            ScrollBar.vertical.policy: ScrollBar.AlwaysOff
            ScrollBar.horizontal.policy: ScrollBar.AsNeeded
            RowLayout {
                id: sourceTabs
                spacing: view.paneSpacing / 2
                Repeater {
                    model: view.editor.sourceRows
                    Rectangle {
                        id: sourceTab
                        required property int index
                        required property string name
                        required property bool active
                        Layout.preferredHeight: 2.5 * view.unit
                        Layout.preferredWidth: tabInner.implicitWidth + view.unit
                        radius: 0.46 * view.unit
                        color: sourceTab.active ? view.colors.menuBackground : "transparent"
                        border.color: view.colors.outline
                        border.width: 1
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 0.46 * view.unit + 1
                            color: view.colors.menuBackground
                            visible: sourceTab.active
                        }
                        RowLayout {
                            id: tabInner
                            z: 1
                            anchors.fill: parent
                            anchors.leftMargin: view.unit * 0.9
                            anchors.rightMargin: view.unit * 0.3
                            spacing: view.paneSpacing / 2
                            Label {
                                text: sourceTab.name
                                font.bold: sourceTab.active
                                color: sourceTab.active ? view.colors.windowText : view.colors.secondaryText
                                elide: Text.ElideRight
                            }
                            ToolButton {
                                text: "×"
                                Accessible.name: qsTr("Close %1").arg(sourceTab.name)
                                onClicked: view.workflow.closeSource(sourceTab.index)
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: view.workflow.selectSource(sourceTab.index)
                        }
                    }
                }
            }
        }
        IconToolButton {
            Layout.preferredHeight: 2.15 * view.unit
            glyph: Icons.zoomOut
            colors: view.colors
            unit: view.unit
            Accessible.name: qsTr("Zoom waveform out")
            onClicked: wave.model.zoom(wave.width / 2, -1)
        }
        IconToolButton {
            Layout.preferredHeight: 2.15 * view.unit
            glyph: Icons.zoomIn
            colors: view.colors
            unit: view.unit
            Accessible.name: qsTr("Zoom waveform in")
            onClicked: wave.model.zoom(wave.width / 2, 1)
        }
        Button {
            Layout.preferredHeight: 2.15 * view.unit
            text: qsTr("Fit")
            onClicked: wave.model.fit()
        }
    }
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(1, Math.round(view.unit / 13))
        color: view.colors.outline
    }
    SampleWaveform {
        id: wave
        objectName: "splitStudioWaveform"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: 17 * view.unit
        Layout.minimumHeight: 10 * view.unit
        focus: true
        model: view.editor.waveform
        colors: view.colors
        baseFontPx: view.unit
        onPressStarted: button => {
            if (button === Qt.LeftButton)
                view.workflow.stopAudition()
            wave.forceActiveFocus()
        }
        onClicked: (x, y) => {
            view.editor.clearLastAddedMarker()
            if (wave.model.handleAt(x, y) === 0)
                view.editor.addMarker(x)
        }
        onDoubleClicked: (x, y) => view.editor.removeMarkerAt(x, y)
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                view.workflow.removeSelectedMarker()
                event.accepted = true
            } else if (event.key === Qt.Key_Space && event.modifiers === Qt.NoModifier) {
                if (view.workflow.auditionPlaying) view.workflow.stopAudition()
                else view.editor.playSelectedSlice()
                event.accepted = true
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: view.paneSpacing
        StudioToggle {
            colors: view.colors
            unit: view.unit
            text: qsTr("Snap to zero")
            checked: view.editor.snap
            onToggled: view.editor.toggleSnap()
        }
    }
    Rectangle {
        id: tableBox
        Layout.fillWidth: true
        Layout.preferredHeight: tableHeader.height + Math.min(Math.max(view.editor.sliceCount, 1), 6) * 3.08 * view.unit
        Layout.minimumHeight: 7 * view.unit
        color: view.colors.menuBackground
        property bool dropHover: false
        property bool dropInvalid: false
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.max(1, Math.round(view.unit / 13))
            color: view.colors.outline
        }
        ColumnLayout {
            anchors.fill: parent
            anchors.topMargin: Math.max(1, Math.round(view.unit / 13))
            spacing: 0
            RowLayout {
                id: tableHeader
                Layout.fillWidth: true
                Layout.leftMargin: view.paneSpacing
                Layout.rightMargin: view.paneSpacing
                spacing: view.paneSpacing
                Item { Layout.preferredWidth: 3 * view.unit }
                Label {
                    Layout.preferredWidth: 2 * view.unit
                    horizontalAlignment: Text.AlignRight
                    text: qsTr("#")
                    font.pixelSize: Math.max(9, Math.round(view.unit * 0.92))
                    color: view.colors.secondaryText
                }
                Label {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 10 * view.unit
                    text: qsTr("Name")
                    font.pixelSize: Math.max(9, Math.round(view.unit * 0.92))
                    color: view.colors.secondaryText
                }
            }
            ListView {
                id: slices
                objectName: "splitStudioSlices"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: view.editor.sliceCount
                spacing: 0
                contentWidth: Math.max(width, 36 * view.unit)
                flickableDirection: Flickable.HorizontalAndVerticalFlick
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                Connections {
                    target: view.editor
                    function onSelectedSliceChanged(): void {
                        const row = view.editor.sliceOrdinal(view.editor.selectedSlice) - 1
                        if (row >= 0 && row < slices.count)
                            slices.positionViewAtIndex(row, ListView.Contain)
                    }
                }
                delegate: Rectangle {
                    id: sliceRow
                    required property int index
                    readonly property int sliceId: view.editor.slicesRevision >= 0 ? view.editor.sliceId(index) : 0
                    readonly property string sampleName: view.editor.slicesRevision >= 0 ? view.editor.sliceName(sliceId) : ""
                    readonly property int sliceNum: view.editor.slicesRevision >= 0 ? view.editor.sliceOrdinal(sliceId) : 0
                    readonly property bool isSelected: view.editor.selectedSlice === sliceId
                    property bool editing: false

                    width: slices.contentWidth
                    height: 3.08 * view.unit
                    color: isSelected ? view.colors.menuHoverBackground : "transparent"

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
                                color: "transparent"
                                z: 1
                                Drag.keys: ["porydaw-sample"]
                                Label {
                                    anchors.centerIn: parent
                                    text: "⋮⋮"
                                    color: sliceRow.isSelected ? view.colors.windowText : view.colors.secondaryText
                                }
                            }
                        }

                        Label {
                            Layout.preferredWidth: 2 * view.unit
                            horizontalAlignment: Text.AlignRight
                            text: sliceRow.sliceNum > 0 ? sliceRow.sliceNum : (sliceRow.index + 1)
                            color: sliceRow.isSelected ? view.colors.windowText : view.colors.secondaryText
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
                                font: view.monoFont
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
        DropZone {
            objectName: "splitStudioSliceDropZone"
            anchors.fill: parent
            anchors.topMargin: tableHeader.height + view.paneSpacing / 2
            anchors.margins: view.paneSpacing
            visible: view.editor.sliceCount === 0
            colors: view.colors
            unit: view.unit
            glyph: Icons.dropFiles
            dropHover: tableBox.dropHover
            dropInvalid: tableBox.dropInvalid
            Accessible.name: qsTr("Open File…")
            onActivated: view.workflow.requestOpenFile()
        }
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: tableBox.dropInvalid ? view.colors.errorText : view.colors.selectionEdge
            border.width: Math.max(2, Math.round(view.unit / 6))
            visible: (tableBox.dropHover || tableBox.dropInvalid) && view.editor.sliceCount > 0
        }
        DropArea {
            anchors.fill: parent
            onEntered: drag => {
                tableBox.dropHover = drag.hasUrls && view.workflow.areLoadableSources(drag.getDataAsString("text/uri-list"))
                tableBox.dropInvalid = drag.hasUrls && !tableBox.dropHover
            }
            onExited: {
                tableBox.dropHover = false
                tableBox.dropInvalid = false
            }
            onDropped: drop => {
                const loadable = tableBox.dropHover
                tableBox.dropHover = false
                tableBox.dropInvalid = false
                if (!loadable)
                    return
                for (let i = 0; i < drop.urls.length; ++i)
                    view.workflow.loadSource("%1".arg(drop.urls[i]))
                view.editor.selectNewestSlice()
                drop.acceptProposedAction()
            }
        }
    }
}
}
