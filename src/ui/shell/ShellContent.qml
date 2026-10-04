pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Dialogs
import QtQuick.Layouts
import Porydaw.Ui
import PorydawApp

// The shell owns chrome and dialogs independently of its deferred workspace.
Item {
    id: content
    required final property ShellWindow root
    final readonly property ShellPresenter shell: content.root.shellPresenter
    final readonly property SongDockController songDock: content.shell.session.songDockController()
    final readonly property alias sceneLoader: workspace
    final readonly property alias menuBar: shellMenu
    final readonly property alias header: transportBar
    final readonly property alias footer: shellStatus

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
        font: content.root.chromeTypography.caption
    }

    // Session publications update the mounted application controls.
    Connections {
        target: content.shell.session
        function onProjectOpenChanged(): void {
            content.shell.projectOpenChanged()
            content.shell.refreshActionStates()
        }
        function onProjectRootChanged(): void { content.shell.refreshWindowChrome() }
        function onSongOpenChanged(): void {
            content.shell.songOpenChanged()
            content.shell.refreshActionStates()
        }
        function onSaveInProgressChanged(): void {
            content.shell.saveStateChanged()
            content.shell.refreshActionStates()
        }
        function onDocumentDirtyChanged(): void { content.shell.refreshWindowChrome() }
        function onSongDocumentDirtyChanged(): void { content.shell.refreshWindowChrome() }
        function onLastSaveErrorChanged(): void {
            if (content.shell.session.lastSaveError.length > 0)
                content.shell.statusText = content.shell.session.lastSaveError
        }
        function onCanUndoChanged(): void { content.shell.refreshActionStates() }
        function onCanRedoChanged(): void { content.shell.refreshActionStates() }
        function onGridCommandAvailabilityChanged(): void { content.shell.refreshActionStates() }
        function onTransportAvailabilityChanged(): void { content.shell.refreshActionStates() }
        function onNoteNameModeChanged(): void { content.shell.refreshActionStates() }
        function onOpenFailed(message: string): void { content.shell.openFailed(message) }
        function onOperationFailed(message: string): void { content.shell.operationFailed(message) }
        function onStatusMessage(message: string): void { content.shell.statusText = message }
    }
    Connections {
        target: content.shell.session.sampleStudio()
        function onEditorOpenChanged(): void { content.shell.refreshActionStates() }
    }
    Connections {
        target: content.songDock
        function onSongsChanged(): void { content.shell.refreshActionStates() }
    }
    Connections {
        target: content.shell.session.songTabs
        function onSelectedTabShowsEventsChanged(): void { content.shell.refreshActionStates() }
        function onSelectedPageChanged(): void {
            content.shell.refreshWindowChrome()
            content.shell.refreshActionStates()
        }
        function onSelectedIdChanged(): void { content.shell.refreshActionStates() }
        function onTabCountChanged(): void { content.shell.refreshActionStates() }
    }
    Connections {
        target: content.root.drawerSectionSource
        function onDrawerSectionPreferenceChanged(): void { content.shell.refreshActionStates() }
    }
    Connections {
        target: content.shell.session.songOpen ? content.shell.session.eventListPresenter() : null
        function onCurrentRowChanged(): void { content.shell.refreshActionStates() }
        function onRowsPublished(): void { content.shell.refreshActionStates() }
        function onAttachedChanged(): void { content.shell.refreshActionStates() }
        function onVisibleChanged(): void { content.shell.refreshActionStates() }
        function onEditingChanged(): void { content.shell.refreshActionStates() }
        function onMenuOpenChanged(): void { content.shell.refreshActionStates() }
    }
    Connections {
        target: content.shell
        function onPolyphonyVisibleChanged(): void { content.shell.refreshActionStates() }
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
            final readonly property ShellActionState actionState: content.shell.action(modelData)
            width: 0
            height: 0
            Shortcut {
                objectName: "shellShortcut_" + shortcutDelegate.modelData
                sequences: content.shell.actionSequences(shortcutDelegate.modelData)
                context: Qt.WindowShortcut
                enabled: shortcutDelegate.actionState.enabled
                onActivated: content.shell.activate(shortcutDelegate.modelData)
            }
        }
    }

    ShellMenuBar {
        id: shellMenu
        shell: content.root.shellPresenter
        windowRoot: content.root
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
        controller: content.songDock.midiImportController()
        hostWindow: content.root
        colors: content.root.colors
        applicationSession: content.shell.session
    }
    NewSongHost {
        controller: content.songDock.newSongController()
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
                content.shell.refreshActionStates()
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
                    function applyAcceptedLabel(accepted: string, proposed: string, cursor: int): void {
                        if (accepted !== proposed) {
                            saveConflictNameField.text = accepted
                            saveConflictNameField.cursorPosition = Math.min(cursor, accepted.length)
                        }
                        content.shell.session.saveConflictNewSongLabel = accepted
                    }
                    onTextChanged: {
                        const previous = content.shell.session.saveConflictNewSongLabel
                        const proposed = text
                        const cursor = cursorPosition
                        saveConflictNameField.applyAcceptedLabel(
                            content.shell.session.acceptSaveConflictLabelEdit(previous, proposed),
                            proposed, cursor)
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
            onAccepted: content.shell.chooseProject(selectedFolder)
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
