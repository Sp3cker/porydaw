pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Layouts
import Porydaw.Ui
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
    function selectNewest(): void {
        const newest = view.editor.newestSliceId()
        if (newest !== 0)
            view.editor.selectSlice(newest)
    }
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
        ToolButton {
            Layout.preferredHeight: 2.15 * view.unit
            text: "−"
            Accessible.name: qsTr("Zoom waveform out")
            onClicked: if (view.editor.waveform) view.editor.waveform.zoom(wave.width / 2, -1)
        }
        ToolButton {
            Layout.preferredHeight: 2.15 * view.unit
            text: "+"
            Accessible.name: qsTr("Zoom waveform in")
            onClicked: if (view.editor.waveform) view.editor.waveform.zoom(wave.width / 2, 1)
        }
        Button {
            Layout.preferredHeight: 2.15 * view.unit
            text: qsTr("Fit")
            onClicked: if (view.editor.waveform) view.editor.waveform.fit()
        }
    }
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(1, Math.round(view.unit / 13))
        color: view.colors.outline
    }
    Item {
        id: wave
        objectName: "splitStudioWaveform"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: 17 * view.unit
        Layout.minimumHeight: 10 * view.unit
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
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: view.colors.selectionEdge
            border.width: Math.max(2, Math.round(view.unit / 6))
            visible: tableBox.dropHover
        }
        DropArea {
            anchors.fill: parent
            onEntered: drop => {
                tableBox.dropHover = drop.hasUrls
            }
            onExited: tableBox.dropHover = false
            onDropped: drop => {
                tableBox.dropHover = false
                if (!drop.hasUrls || drop.urls.length === 0)
                    return
                for (let i = 0; i < drop.urls.length; ++i)
                    view.workflow.loadSource("%1".arg(drop.urls[i]))
                view.selectNewest()
                drop.acceptProposedAction()
            }
        }
    }
}
}
