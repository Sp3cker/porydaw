pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Dialogs as NativeDialogs
import PorydawStyle
import QtQuick.Layouts
import Porydaw.Ui
import PorydawApp

ThemedWindow {
    id: studio
    objectName: "splitStudioWindow"
    required property KitStudioWorkflow workflow
    required property KitStudioPresenter editor
    required property SampleLibraryModel library
    required property ApplicationSession applicationSession
    readonly property real unit: applicationSession.baseFontPx
    readonly property real spacing: applicationSession.layoutSpaces.one
    property bool geometryReady: false
    flags: Qt.Window
    width: 85 * unit
    height: 58 * unit
    minimumWidth: 70 * unit
    minimumHeight: 43 * unit
    font: applicationSession.typographyFonts.body
    title: editor.titleText
    color: colors.windowBackground
    onActiveChanged: if (!active) workflow.stopAudition()
    onClosing: close => {
        close.accepted = false
        rememberGeometry()
        workflow.closeRequested()
    }
    function present(): void {
        show()
        raise()
        requestActivate()
    }
    function rememberGeometry(): void {
        if (geometryReady)
            workflow.persistGeometry(Math.round(width), Math.round(height), Math.round(libraryColumn.width), Math.round(sliceEditor.height))
    }
    Component.onCompleted: {
        if (workflow.hasSavedWindowSize) {
            width = Math.max(minimumWidth, workflow.savedWindowWidth)
            height = Math.max(minimumHeight, workflow.savedWindowHeight)
        }
        if (workflow.savedLibraryWidth > 0)
            libraryColumn.SplitView.preferredWidth = workflow.savedLibraryWidth
        if (workflow.savedSliceHeight > 0)
            sliceEditor.SplitView.preferredHeight = workflow.savedSliceHeight
        geometryReady = true
    }

    Shortcut { sequences: [StandardKey.Save]; context: Qt.WindowShortcut; enabled: !studio.workflow.saving; onActivated: studio.workflow.saveToSong() }
    Shortcut { sequences: [StandardKey.Undo]; context: Qt.WindowShortcut; enabled: !studio.workflow.saving; onActivated: studio.workflow.undo() }
    Shortcut { sequences: [StandardKey.Redo]; context: Qt.WindowShortcut; enabled: !studio.workflow.saving; onActivated: studio.workflow.redo() }
    Shortcut { sequences: [StandardKey.Close]; context: Qt.WindowShortcut; enabled: !studio.workflow.saving; onActivated: studio.close() }
    Timer { interval: 1000 / 30; repeat: true; running: studio.workflow.auditionPlaying; onTriggered: studio.workflow.tickAudition() }

    NativeDialogs.FileDialog {
        id: sourcePicker
        objectName: "splitStudioSourcePicker"
        title: qsTr("Open Split Studio Source")
        parentWindow: studio
        fileMode: NativeDialogs.FileDialog.OpenFile
        nameFilters: [qsTr("Audio files (*.wav *.aif *.aiff *.mp3 *.flac *.ogg)"), qsTr("All files (*)")]
        onAccepted: studio.workflow.chooseSource(selectedFile)
        onRejected: studio.workflow.cancelSource()
    }
    Connections {
        target: studio.workflow
        function onPickerRequestedChanged(): void {
            if (studio.workflow.pickerRequested) {
                sourcePicker.currentFolder = studio.workflow.pickerFolder
                sourcePicker.open()
            } else sourcePicker.close()
        }
        function onWindowOpenChanged(): void { if (!studio.workflow.windowOpen) studio.rememberGeometry() }
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: studio.spacing
        spacing: studio.spacing
        enabled: !studio.workflow.saving
        KitSlotPicker {
            Layout.fillWidth: true
            editor: studio.editor
            colors: studio.colors
            unit: studio.unit
            paneSpacing: studio.spacing
        }
        RowLayout {
            objectName: "splitStudioConflictBar"
            Layout.fillWidth: true
            visible: studio.editor.conflictVisible
            Label { Layout.fillWidth: true; text: studio.editor.conflictText; color: studio.colors.windowText; wrapMode: Text.WordWrap }
            Button { text: qsTr("Reload"); onClicked: studio.editor.answerConflict(false) }
            Button { text: qsTr("Keep mine"); onClicked: studio.editor.answerConflict(true) }
        }
        RowLayout {
            Layout.fillWidth: true
            visible: studio.editor.usedByText.length > 0
            Label { Layout.fillWidth: true; text: studio.editor.usedByText; color: studio.colors.windowText; wrapMode: Text.WordWrap }
            CheckBox { text: qsTr("Save a copy"); checked: studio.workflow.copySharedKit; onClicked: studio.workflow.copySharedKit = checked }
        }
        SplitView {
            id: horizontalSplit
            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: Qt.Horizontal
            onResizingChanged: if (!resizing) studio.rememberGeometry()
            handle: Rectangle { implicitWidth: studio.spacing; color: studio.colors.chromeBackground }
            ColumnLayout {
                id: libraryColumn
                SplitView.preferredWidth: 22 * studio.unit
                SplitView.minimumWidth: 17 * studio.unit
                spacing: studio.spacing
                SampleLibraryPane {
                    objectName: "splitStudioLibrary"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    library: studio.library
                    colors: studio.colors
                    studioWindow: studio
                    unit: studio.unit
                    paneSpacing: studio.spacing
                }
                Repeater {
                    model: studio.library.files
                    Item {
                        id: libraryDragRow
                        required property string path
                        required property string name
                        required property bool selected
                        Layout.fillWidth: true
                        Layout.preferredHeight: 2.5 * studio.unit
                        visible: selected
                        KitDragSource {
                            id: libraryChip
                            libraryPath: libraryDragRow.path
                            width: libraryDragRow.width
                            height: libraryDragRow.height
                            color: studio.colors.buttonBackground
                            z: 1
                            Drag.active: libraryDrag.drag.active
                            Drag.keys: ["porydaw-library"]
                            Drag.hotSpot.x: libraryDrag.mouseX
                            Drag.hotSpot.y: libraryDrag.mouseY
                            Drag.source: libraryChip
                            Drag.supportedActions: Qt.CopyAction
                            Label { anchors.fill: parent; anchors.margins: studio.spacing; text: qsTr("Drag to a key: ") + libraryDragRow.name; color: studio.colors.windowText; elide: Text.ElideRight }
                            MouseArea {
                                id: libraryDrag
                                anchors.fill: parent
                                drag.target: libraryChip
                                onPressed: {
                                    const target = studio.contentItem
                                    const point = libraryChip.mapToItem(target, 0, 0)
                                    const x = point.x
                                    const y = point.y
                                    libraryChip.parent = target
                                    libraryChip.x = x
                                    libraryChip.y = y
                                }
                                onReleased: { libraryChip.Drag.drop(); libraryChip.parent = libraryDragRow; libraryChip.x = 0; libraryChip.y = 0 }
                                onCanceled: { libraryChip.parent = libraryDragRow; libraryChip.x = 0; libraryChip.y = 0 }
                            }
                        }
                    }
                }
            }
            SplitView {
                id: verticalSplit
                SplitView.fillWidth: true
                SplitView.minimumWidth: 45 * studio.unit
                orientation: Qt.Vertical
                onResizingChanged: if (!resizing) studio.rememberGeometry()
                handle: Rectangle { implicitHeight: studio.spacing; color: studio.colors.chromeBackground }
                SliceEditorView {
                    id: sliceEditor
                    SplitView.preferredHeight: 25 * studio.unit
                    SplitView.minimumHeight: 18 * studio.unit
                    workflow: studio.workflow
                    editor: studio.editor
                    colors: studio.colors
                    unit: studio.unit
                    paneSpacing: studio.spacing
                    dragLayer: studio.contentItem
                }
                ZoneEditorView {
                    SplitView.fillHeight: true
                    SplitView.minimumHeight: 15 * studio.unit
                    workflow: studio.workflow
                    editor: studio.editor
                    colors: studio.colors
                    unit: studio.unit
                    paneSpacing: studio.spacing
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Button { text: qsTr("Undo"); enabled: studio.editor.canUndo; onClicked: studio.workflow.undo() }
            Button { text: qsTr("Redo"); enabled: studio.editor.canRedo; onClicked: studio.workflow.redo() }
            Item { Layout.fillWidth: true }
            Button {
                objectName: "splitStudioSave"
                text: qsTr("Save to Song")
                enabled: studio.editor.canSave && !studio.editor.conflictVisible
                onClicked: studio.workflow.saveToSong()
            }
            Button { objectName: "splitStudioClose"; text: qsTr("Close"); onClicked: studio.close() }
        }
    }
    Dialog {
        id: closePrompt
        objectName: "splitStudioClosePrompt"
        parent: studio.contentItem
        anchors.centerIn: parent
        width: 35 * studio.unit
        title: qsTr("Save Split Studio changes?")
        modal: true
        closePolicy: Popup.NoAutoClose
        visible: studio.workflow.promptOpen
        contentItem: ColumnLayout {
            spacing: studio.spacing
            Label { Layout.fillWidth: true; text: qsTr("Save to Song before closing or changing the bound song?"); wrapMode: Text.WordWrap; color: studio.colors.windowText }
            RowLayout {
                Button { text: qsTr("Save"); onClicked: studio.workflow.answerPrompt(0) }
                Button { text: qsTr("Discard"); onClicked: studio.workflow.answerPrompt(1) }
                Button { text: qsTr("Cancel"); onClicked: studio.workflow.answerPrompt(2) }
            }
        }
    }
    Dialog {
        objectName: "splitStudioRetargetPrompt"
        parent: studio.contentItem
        anchors.centerIn: parent
        width: 35 * studio.unit
        title: qsTr("Save changes before choosing another kit?")
        modal: true
        closePolicy: Popup.NoAutoClose
        visible: studio.editor.retargetVisible && !studio.workflow.saving
        contentItem: RowLayout {
            spacing: studio.spacing
            Button { text: qsTr("Save"); onClicked: studio.editor.answerRetarget(0) }
            Button { text: qsTr("Discard"); onClicked: studio.editor.answerRetarget(1) }
            Button { text: qsTr("Cancel"); onClicked: studio.editor.answerRetarget(2) }
        }
    }
}
