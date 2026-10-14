pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Dialogs as NativeDialogs
import PorydawStyle
import QtQuick.Layouts
import Porydaw.Ui
import Porydaw.Icons
import PorydawApp

ThemedWindow {
    id: studio
    objectName: "splitStudioWindow"
    required property KitStudioWorkflow workflow
    required property KitStudioPresenter editor
    required property SampleLibraryModel library
    required property ApplicationSession applicationSession
    readonly property real unit: applicationSession.baseFontPx
    readonly property real spacing: applicationSession.layoutSpaces.three
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
            workflow.persistGeometry(Math.round(width), Math.round(height), Math.round(libraryPane.width), Math.round(keyboardPane.height))
    }
    Component.onCompleted: {
        if (workflow.hasSavedWindowSize) {
            width = Math.max(minimumWidth, workflow.savedWindowWidth)
            height = Math.max(minimumHeight, workflow.savedWindowHeight)
        }
        if (workflow.savedLibraryWidth > 0)
            libraryPane.SplitView.preferredWidth = workflow.savedLibraryWidth
        if (workflow.savedKeyboardHeight > 0)
            keyboardPane.SplitView.preferredHeight = workflow.savedKeyboardHeight
        geometryReady = true
    }

    Shortcut { sequences: [StandardKey.Save]; context: Qt.WindowShortcut; enabled: !studio.workflow.saving; onActivated: studio.workflow.saveVoicegroup() }
    Shortcut { sequences: [StandardKey.Undo]; context: Qt.WindowShortcut; enabled: !studio.workflow.saving; onActivated: studio.workflow.undo() }
    Shortcut { sequences: [StandardKey.Redo]; context: Qt.WindowShortcut; enabled: !studio.workflow.saving; onActivated: studio.workflow.redo() }
    Shortcut { sequences: [StandardKey.Close]; context: Qt.WindowShortcut; enabled: !studio.workflow.saving; onActivated: studio.close() }
    Timer { interval: 1000 / 30; repeat: true; running: studio.workflow.auditionPlaying; onTriggered: studio.workflow.tickAudition() }
    Rectangle {
        anchors.fill: parent
        color: studio.colors.windowBackground
        z: -1
    }
    component Segment: Rectangle {
        id: seg
        required property string label
        required property bool active
        signal pressed
        Layout.preferredHeight: 2 * studio.unit
        Layout.preferredWidth: segLabel.implicitWidth + 2 * studio.spacing
        radius: studio.unit / 4
        color: seg.active ? studio.colors.tabSelectedBackground : "transparent"
        Accessible.role: Accessible.Button
        Accessible.name: seg.label
        Label {
            id: segLabel
            anchors.centerIn: parent
            text: seg.label
            font.bold: seg.active
            color: seg.active ? studio.colors.selectionText : studio.colors.secondaryText
        }
        MouseArea {
            anchors.fill: parent
            onClicked: seg.pressed()
        }
    }

    NativeDialogs.FileDialog {
        id: sourcePicker
        objectName: "splitStudioSourcePicker"
        title: qsTr("Open File")
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
        spacing: 0
        enabled: !studio.workflow.saving
        Rectangle {
            id: contextBar
            objectName: "splitStudioContextBar"
            Layout.fillWidth: true
            Layout.preferredHeight: 3.7 * studio.unit
            color: studio.colors.menuBackground
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 1.25 * studio.unit
                anchors.rightMargin: 1.25 * studio.unit
                spacing: studio.spacing
                Label { text: qsTr("Layout"); color: studio.colors.secondaryText }
                Rectangle {
                    Layout.preferredHeight: 2.2 * studio.unit
                    Layout.preferredWidth: segRow.implicitWidth + 2
                    color: "transparent"
                    border.color: studio.colors.outline
                    border.width: 1
                    radius: studio.unit / 4 + 1
                    RowLayout {
                        id: segRow
                        anchors.centerIn: parent
                        spacing: 0
                        Segment {
                            objectName: "splitStudioModeDrumkit"
                            label: qsTr("Drumkit")
                            active: studio.editor.mode === 0
                            onPressed: studio.editor.setMode(0)
                        }
                        Segment {
                            objectName: "splitStudioModeKeysplit"
                            label: qsTr("Keysplit")
                            active: studio.editor.mode === 1
                            onPressed: studio.editor.setMode(1)
                        }
                    }
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: Math.max(1, Math.round(studio.unit / 13))
                color: studio.colors.outline
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0
            SplitView {
                id: horizontalSplit
                Layout.fillWidth: true
                Layout.fillHeight: true
                orientation: Qt.Horizontal
                onResizingChanged: if (!resizing) studio.rememberGeometry()
                // The library pane draws its own edge; the handle only widens the grab area.
                handle: Rectangle {
                    id: libraryHandle
                    implicitWidth: Math.max(1, Math.round(studio.unit / 13))
                    color: studio.colors.menuBackground
                    containmentMask: Item { x: -studio.unit / 3; width: 2 * studio.unit / 3; height: libraryHandle.height }
                }
                SampleLibraryPane {
                    id: libraryPane
                    objectName: "splitStudioLibrary"
                    SplitView.preferredWidth: 18 * studio.unit
                    SplitView.minimumWidth: 14 * studio.unit
                    library: studio.library
                    colors: studio.colors
                    studioWindow: studio
                    unit: studio.unit
                    paneSpacing: studio.spacing
                }
                SplitView {
                    id: verticalSplit
                    SplitView.fillWidth: true
                    SplitView.minimumWidth: 45 * studio.unit
                    orientation: Qt.Vertical
                    onResizingChanged: if (!resizing) studio.rememberGeometry()
                    handle: Rectangle {
                        id: keyboardHandle
                        implicitHeight: Math.max(1, Math.round(studio.unit / 13))
                        color: studio.colors.outline
                        containmentMask: Item { y: -studio.unit / 3; height: 2 * studio.unit / 3; width: keyboardHandle.width }
                    }
                    Item {
                        SplitView.fillHeight: true
                        SplitView.minimumHeight: 18 * studio.unit
                        SliceEditorView {
                            id: sliceEditor
                            anchors.fill: parent
                            anchors.leftMargin: 1.25 * studio.unit
                            anchors.rightMargin: 1.25 * studio.unit
                            anchors.topMargin: 1.25 * studio.unit
                            anchors.bottomMargin: 1.25 * studio.unit
                            workflow: studio.workflow
                            editor: studio.editor
                            colors: studio.colors
                            unit: studio.unit
                            paneSpacing: studio.spacing
                            dragLayer: studio.contentItem
                            monoFont: studio.applicationSession.typographyFonts.tableMono
                        }
                    }
                    Rectangle {
                        id: keyboardPane
                        SplitView.preferredHeight: 14 * studio.unit
                        SplitView.minimumHeight: 12 * studio.unit
                        color: studio.colors.menuBackground
                        ZoneEditorView {
                            anchors.fill: parent
                            anchors.leftMargin: 1.25 * studio.unit
                            anchors.rightMargin: 1.25 * studio.unit
                            anchors.topMargin: 1.25 * studio.unit
                            anchors.bottomMargin: 1.25 * studio.unit
                            workflow: studio.workflow
                            editor: studio.editor
                            colors: studio.colors
                            unit: studio.unit
                            paneSpacing: studio.spacing
                            captionFont: studio.applicationSession.typographyFonts.captionMinimum
                        }
                    }
                }
            }
            KitInspector {
                Layout.preferredWidth: 22 * studio.unit
                Layout.minimumWidth: 17 * studio.unit
                Layout.fillHeight: true
                workflow: studio.workflow
                editor: studio.editor
                colors: studio.colors
                unit: studio.unit
                paneSpacing: studio.spacing
                captionFont: studio.applicationSession.typographyFonts.caption
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 4 * studio.unit
            color: studio.colors.windowBackground
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: Math.max(1, Math.round(studio.unit / 13))
                color: studio.colors.outline
            }
            RowLayout {
                id: footerRow
                anchors.fill: parent
                anchors.leftMargin: 1.25 * studio.unit
                anchors.rightMargin: 1.25 * studio.unit
                spacing: studio.spacing
                IconToolButton {
                    glyph: Icons.undo
                    colors: studio.colors
                    unit: studio.unit
                    Accessible.name: qsTr("Undo")
                    enabled: studio.editor.canUndo
                    onClicked: studio.workflow.undo()
                }
                IconToolButton {
                    glyph: Icons.redo
                    colors: studio.colors
                    unit: studio.unit
                    Accessible.name: qsTr("Redo")
                    enabled: studio.editor.canRedo
                    onClicked: studio.workflow.redo()
                }
                Label { objectName: "splitStudioMeta"; text: studio.editor.metaText; color: studio.colors.secondaryText }
                Item { Layout.fillWidth: true }
                Label { text: qsTr("Voicegroup"); color: studio.colors.secondaryText }
                ValidatedTextField {
                    id: voicegroupField
                    objectName: "splitStudioVoicegroupName"
                    colors: studio.colors
                    Layout.preferredWidth: 12 * studio.unit
                    Layout.preferredHeight: 2.15 * studio.unit
                    invalid: studio.editor.voicegroupNameInvalid
                    text: studio.editor.voicegroupName
                    onEditingFinished: studio.editor.setVoicegroupName(text)
                    Connections {
                        target: studio.editor
                        function onVoicegroupNameChanged(): void {
                            if (!voicegroupField.activeFocus) voicegroupField.text = studio.editor.voicegroupName
                        }
                    }
                }
                Button {
                    objectName: "splitStudioClose"
                    Layout.preferredHeight: 2.15 * studio.unit
                    text: qsTr("Close")
                    onClicked: studio.close()
                }
                Button {
                    id: saveButton
                    objectName: "splitStudioSave"
                    Layout.preferredHeight: 2.15 * studio.unit
                    enabled: studio.editor.canSave
                    onClicked: studio.workflow.saveVoicegroup()
                    background: Rectangle {
                        color: saveButton.enabled ? studio.colors.tabSelectedBackground : studio.colors.buttonBackground
                        radius: studio.unit / 4
                    }
                    contentItem: RowLayout {
                        spacing: studio.spacing / 2
                        Label {
                            text: qsTr("Save Voicegroup")
                            font.bold: true
                            color: studio.colors.selectionText
                        }
                        Rectangle {
                            Layout.preferredHeight: 1.4 * studio.unit
                            Layout.preferredWidth: hintLabel.implicitWidth + studio.spacing
                            color: "transparent"
                            border.color: studio.colors.selectionText
                            border.width: 1
                            radius: studio.unit / 6
                            opacity: saveButton.enabled ? 1 : 0.5
                            Label {
                                id: hintLabel
                                anchors.centerIn: parent
                                text: Qt.platform.os === "osx" ? qsTr("⌘S") : qsTr("Ctrl+S")
                                color: studio.colors.selectionText
                            }
                        }
                    }
                }
            }
        }
    }
    Dialog {
        id: closePrompt
        objectName: "splitStudioClosePrompt"
        parent: studio.workflow.promptForClose ? (studio.transientParent as Window).contentItem : studio.contentItem
        anchors.centerIn: parent
        width: 35 * studio.unit
        title: qsTr("Save Split Studio changes?")
        modal: true
        focus: true
        closePolicy: Popup.NoAutoClose
        visible: studio.workflow.promptOpen
        contentItem: ColumnLayout {
            spacing: studio.spacing
            Label { Layout.fillWidth: true; text: qsTr("Save the voicegroup before closing?"); wrapMode: Text.WordWrap; color: studio.colors.windowText }
            RowLayout {
                enabled: !studio.workflow.saving
                Button { text: qsTr("Save Voicegroup"); onClicked: studio.workflow.answerPrompt(0) }
                Button { text: qsTr("Discard"); onClicked: studio.workflow.answerPrompt(1) }
                Button { text: qsTr("Cancel"); onClicked: studio.workflow.answerPrompt(2) }
            }
        }
    }
    NativeDialogs.MessageDialog {
        id: overwritePrompt
        objectName: "splitStudioOverwritePrompt"
        parentWindow: studio
        title: qsTr("Split Studio")
        text: studio.workflow.overwritePromptText
        buttons: NativeDialogs.MessageDialog.Yes | NativeDialogs.MessageDialog.No
        visible: studio.workflow.overwritePromptOpen
        onAccepted: studio.workflow.answerOverwrite(true)
        onRejected: studio.workflow.answerOverwrite(false)
    }
}
