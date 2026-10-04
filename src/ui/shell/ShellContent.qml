pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Dialogs
import QtQuick.Layouts
import Porydaw.Ui

// The shell owns chrome and dialogs independently of its deferred workspace.
Item {
    id: content
    required property var root
    readonly property var shell: content.root.shellPresenter
    readonly property alias sceneLoader: workspace
    readonly property alias menuBar: shellMenu
    readonly property alias header: transportBar
    readonly property alias footer: shellStatus

    Component.onCompleted: {
        content.shell.session.restoreDisplayModes()
        transportBar.presenter.restoreOutputVolume()
        transportBar.presenter.restoreTransportToggles()
        content.shell.settingsStore.restoreFromPreferences()
    }

    function loadWorkspace(): void {
        workspace.setSource(Qt.resolvedUrl("ShellBody.qml"), {
            root: content.root,
            transportToolExtent: Qt.binding(content.workspaceTransportToolExtent)
        })
    }

    function workspaceTransportToolExtent(): int {
        return transportBar.toolExtent
    }

    // Text metrics belong to the controls, not the first window frame.
    FontMetrics {
        id: bodyMetrics
        font: content.root.font
    }
    FontMetrics {
        id: captionMetrics
        font: Qt.font(content.root.chromeTypography.caption)
    }

    // Session publications update the mounted application controls.
    Connections {
        target: content.shell.session
        function onProjectOpenChanged(): void {
            content.shell.projectOpenChanged()
            ++content.root.actionRevision
        }
        function onProjectRootChanged(): void { content.shell.refreshWindowChrome() }
        function onSongOpenChanged(): void {
            content.shell.songOpenChanged()
            ++content.root.actionRevision
        }
        function onSaveInProgressChanged(): void {
            content.shell.saveStateChanged()
            ++content.root.actionRevision
        }
        function onDocumentDirtyChanged(): void { content.shell.refreshWindowChrome() }
        function onSongDocumentDirtyChanged(): void { content.shell.refreshWindowChrome() }
        function onLastSaveErrorChanged(): void {
            if (content.shell.session.lastSaveError.length > 0)
                content.shell.statusText = content.shell.session.lastSaveError
        }
        function onCanUndoChanged(): void { ++content.root.actionRevision }
        function onCanRedoChanged(): void { ++content.root.actionRevision }
        function onGridCommandAvailabilityChanged(): void { ++content.root.actionRevision }
        function onTransportAvailabilityChanged(): void { ++content.root.actionRevision }
        function onNoteNameModeChanged(): void { ++content.root.actionRevision }
        function onOpenFailed(message: string): void { content.shell.openFailed(message) }
        function onOperationFailed(message: string): void { content.shell.operationFailed(message) }
        function onStatusMessage(message: string): void { content.shell.statusText = message }
    }
    Connections {
        target: content.shell.session.sampleStudio()
        function onEditorOpenChanged(): void { ++content.root.actionRevision }
    }
    Connections {
        target: content.shell.session.songTabs
        function onSelectedTabShowsEventsChanged(): void { ++content.root.actionRevision }
        function onSelectedPageChanged(): void {
            content.shell.refreshWindowChrome()
            ++content.root.actionRevision
        }
        function onSelectedIdChanged(): void { ++content.root.actionRevision }
        function onTabCountChanged(): void { ++content.root.actionRevision }
    }
    Connections {
        target: content.root.drawerSectionSource
        function onDrawerSectionPreferenceChanged(): void { ++content.root.actionRevision }
    }
    Connections {
        target: content.shell.session.songOpen ? content.shell.session.eventListPresenter() : null
        function onCurrentRowChanged(): void { ++content.root.actionRevision }
    }
    Connections {
        target: content.shell
        function onPolyphonyVisibleChanged(): void { ++content.root.actionRevision }
        function onEventListGateChanged(): void { ++content.root.actionRevision }
        function onChooseProjectRequested(): void { content.ensureProjectPicker().open() }
        function onAboutRequested(): void { content.ensureAboutDialog().open() }
        function onSettingsRequested(songFirst: bool): void { content.ensureSettingsDialog().showSettings(songFirst) }
        function onQuitRequested(): void { content.root.close() }
        function onCriticalRequested(title: string, message: string): void {
            const dialog = content.ensureCriticalDialog()
            dialog.text = title
            dialog.informativeText = message
            dialog.open()
        }
    }

    // Window-scope shortcuts get native Qt ShortcutOverride arbitration; editor
    // strokes stay on the focused tab's raw key path.
    Repeater {
        model: content.shell.windowActionIds
        delegate: Item {
            id: shortcutDelegate
            required property string modelData
            width: 0
            height: 0
            Shortcut {
                objectName: "shellShortcut_" + shortcutDelegate.modelData
                sequences: content.shell.actionSequences(shortcutDelegate.modelData)
                context: Qt.WindowShortcut
                enabled: {
                    content.root.actionRevision
                    return content.shell.actionEnabled(shortcutDelegate.modelData)
                }
                onActivated: content.shell.activate(shortcutDelegate.modelData)
            }
        }
    }

    ShellMenuBar {
        id: shellMenu
        shell: content.root.shellPresenter
        windowRoot: content.root
        actionRevision: content.root.actionRevision
    }
    // Deferred chrome: dialogs instantiate on first use, so startup never
    // pays for their font/button work; Loaders complete synchronously.
    function ensureSettingsDialog(): SettingsDialog {
        settingsDialogLoader.active = true
        return settingsDialogLoader.item as SettingsDialog
    }
    function ensureAboutDialog(): AboutDialog {
        aboutDialogLoader.active = true
        return aboutDialogLoader.item as AboutDialog
    }
    function ensureProjectPicker(): FolderDialog {
        projectPickerLoader.active = true
        return projectPickerLoader.item as FolderDialog
    }
    function ensureCriticalDialog(): MessageDialog {
        criticalDialogLoader.active = true
        return criticalDialogLoader.item as MessageDialog
    }
    Loader {
        id: settingsDialogLoader
        objectName: "shellSettingsLoader"
        active: false
        sourceComponent: SettingsDialog {
            objectName: "shellSettingsDialog"
            transientParent: content.root
            store: content.shell.settingsStore
            presenter: content.shell
            colors: content.root.colors
            applicationSession: content.shell.session
        }
    }
    Loader {
        id: aboutDialogLoader
        objectName: "shellAboutLoader"
        active: false
        sourceComponent: AboutDialog {
            colors: content.root.colors
            applicationSession: content.shell.session
            baseFontPx: content.shell.session.baseFontPx
        }
    }
    MidiImportHost {
        controller: content.shell.session.songDockController().midiImportController()
        hostWindow: content.root
        colors: content.root.colors
        applicationSession: content.shell.session
    }
    NewSongHost {
        controller: content.shell.session.songDockController().newSongController()
        hostWindow: content.root
        colors: content.root.colors
        applicationSession: content.shell.session
    }
    SampleStudioHost {
        workflow: content.shell.session.sampleStudio()
        hostWindow: content.root
        applicationSession: content.shell.session
        colors: content.root.colors
    }
    WavExportSurface {
        presenter: content.shell.session.wavExportPresenter()
        colors: content.root.colors
        windowRoot: content.root
        typography: content.root.chromeTypography
    }

    Loader {
        id: workspace
        objectName: "shellWorkspaceLoader"
        anchors.fill: parent
        asynchronous: false
        active: content.shell.sceneActive
        visible: status === Loader.Ready
        focus: true
        onLoaded: {
            if (content.shell.sceneActive) {
                content.shell.workspaceReady()
                ++content.root.actionRevision
            }
        }
        onStatusChanged: {
            if (status === Loader.Error) {
                console.error("Cannot load the required application workspace: " + source)
                Qt.exit(1)
            }
        }
    }

    // Save-conflict prompt stays shell-owned, including before workspace mounting.
    // The name field reuses the New Song label law; Register requires a valid name.
    Loader {
        id: saveConflictLoader
        objectName: "saveConflictLoader"
        active: content.shell.session.saveConflictSongLabel.length > 0
        sourceComponent: Dialog {
            objectName: "saveConflictDialog"
            parent: Overlay.overlay
            anchors.centerIn: parent
            modal: true
            focus: true
            title: qsTr("Song Changed on Disk")
            closePolicy: Popup.CloseOnEscape
            onOpened: {
                saveConflictNameField.text = ""
                saveConflictNameField.forceActiveFocus()
            }
            onRejected: content.shell.session.cancelSaveConflict()
            onClosed: {
                if (content.shell.session.saveConflictSongLabel.length > 0)
                    content.shell.session.cancelSaveConflict()
            }
            contentItem: ColumnLayout {
                spacing: content.root.chromeSpacing.four
                Label {
                    objectName: "saveConflictMessage"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: content.shell.session.saveConflictDetail
                }
                TextField {
                    id: saveConflictNameField
                    objectName: "saveConflictNewName"
                    Layout.fillWidth: true
                    placeholderText: qsTr("mus_new_song")
                    onTextChanged: {
                        const previous = content.shell.session.saveConflictNewSongLabel
                        const proposed = text
                        const cursor = cursorPosition
                        const accepted = content.shell.session.acceptSaveConflictLabelEdit(previous, proposed)
                        if (accepted !== proposed) {
                            text = accepted
                            cursorPosition = Math.min(cursor, accepted.length)
                        }
                        content.shell.session.saveConflictNewSongLabel = accepted
                    }
                    onAccepted: {
                        if (saveConflictForkButton.enabled)
                            content.shell.session.resolveSaveConflictFork()
                    }
                }
                Label {
                    objectName: "saveConflictTaken"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: qsTr("A song named %1 already exists.").arg(saveConflictNameField.text)
                    visible: saveConflictNameField.text.length > 0
                        && content.shell.session.saveConflictLabelTaken(saveConflictNameField.text)
                }
            }
            footer: DialogButtonBox {
                Button {
                    id: saveConflictOverwriteButton
                    objectName: "saveConflictOverwrite"
                    text: qsTr("Overwrite")
                    DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                    onClicked: content.shell.session.resolveSaveConflictOverwrite()
                }
                Button {
                    id: saveConflictForkButton
                    objectName: "saveConflictFork"
                    text: qsTr("Register changes as New Song...")
                    DialogButtonBox.buttonRole: DialogButtonBox.ActionRole
                    enabled: saveConflictNameField.text.length > 0
                        && content.shell.session.saveConflictLabelValid(saveConflictNameField.text)
                        && !content.shell.session.saveConflictLabelTaken(saveConflictNameField.text)
                    onClicked: content.shell.session.resolveSaveConflictFork()
                }
                Button {
                    objectName: "saveConflictCancel"
                    text: qsTr("Cancel")
                    DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                    onClicked: content.shell.session.cancelSaveConflict()
                }
            }
        }
        onLoaded: {
            if (status === Loader.Ready)
                (saveConflictLoader.item as Dialog).open()
        }
    }
    TransportBar {
        id: transportBar
        width: content.root.width
        enabled: content.shell.sceneActive
        songAvailable: content.shell.session.songOpen
        baseFontPx: content.root.chromeBaseFontPx
        presenter: content.shell.session.transportBarPresenter()
        shell: content.root.shellPresenter
        actionRevision: content.root.actionRevision
        colors: content.root.colors
        typography: content.root.chromeTypography
        layoutSpaces: content.root.chromeSpacing
    }
    ShellStatusBar {
        id: shellStatus
        root: content.root
        shell: content.root.shellPresenter
        bodyMetrics: bodyMetrics
        captionMetrics: captionMetrics
    }

    Loader {
        id: projectPickerLoader
        objectName: "shellProjectPickerLoader"
        active: false
        sourceComponent: FolderDialog {
            objectName: "shellProjectPicker"
            title: qsTr("Open Project")
            onAccepted: content.shell.chooseProject(selectedFolder.toString())
        }
    }
    Loader {
        id: criticalDialogLoader
        objectName: "shellCriticalLoader"
        active: false
        sourceComponent: MessageDialog {
            objectName: "shellCriticalDialog"
            buttons: MessageDialog.Ok
        }
    }
}
