import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Porydaw.Ui

// The persistent window owns launch and close; this tree owns its deferred UI.
Item {
    id: content
    required property var root
    readonly property var shell: content.root.shellPresenter
    readonly property alias sceneLoader: editorScene
    readonly property alias menuBar: shellMenu
    readonly property alias header: transportBar
    readonly property alias footer: shellStatus

    Component.onCompleted: {
        shell.session.restoreDisplayModes()
        transportBar.presenter.restoreOutputVolume()
        transportBar.presenter.restoreTransportToggles()
        shell.settingsStore.restoreFromPreferences()
        root.dockSettingsReady = true
    }

    // Text metrics belong to the controls, not the first window frame.
    FontMetrics {
        id: bodyMetrics
        font: root.font
    }
    FontMetrics {
        id: captionMetrics
        font: Qt.font(root.chromeTypography.caption)
    }

    // Session publications update the mounted application controls.
    Connections {
        target: shell.session
        function onProjectOpenChanged() {
            shell.projectOpenChanged()
            ++root.actionRevision
        }
        function onProjectRootChanged() { shell.refreshWindowChrome() }
        function onSongOpenChanged() {
            gridContextMenu.menu.close()
            shell.songOpenChanged()
            ++root.actionRevision
        }
        function onSaveInProgressChanged() {
            shell.saveStateChanged()
            ++root.actionRevision
        }
        function onDocumentDirtyChanged() { shell.refreshWindowChrome() }
        function onSongDocumentDirtyChanged() { shell.refreshWindowChrome() }
        function onLastSaveErrorChanged() {
            if (shell.session.lastSaveError.length > 0)
                shell.statusText = shell.session.lastSaveError
        }
        function onCanUndoChanged() { ++root.actionRevision }
        function onCanRedoChanged() { ++root.actionRevision }
        function onGridCommandAvailabilityChanged() { ++root.actionRevision }
        function onTransportAvailabilityChanged() { ++root.actionRevision }
        function onNoteNameModeChanged() { ++root.actionRevision }
        function onOpenFailed(message) { shell.openFailed(message) }
        function onOperationFailed(message) { shell.operationFailed(message) }
        function onStatusMessage(message) { shell.statusText = message }
    }
    Connections {
        target: shell.session.sampleStudio()
        function onEditorOpenChanged() { ++root.actionRevision }
    }
    Connections {
        target: shell.session.songTabs
        function onSelectedTabShowsEventsChanged() { ++root.actionRevision }
        function onSelectedPageChanged() {
            gridContextMenu.menu.close()
            shell.refreshWindowChrome()
            ++root.actionRevision
        }
        function onSelectedIdChanged() {
            gridContextMenu.menu.close()
            ++root.actionRevision
        }
        function onTabCountChanged() { ++root.actionRevision }
    }
    Connections {
        target: shell.session.songOpen ? shell.session.gridPresenter() : null
        function onAppliedRevisionTextChanged() { gridContextMenu.menu.close() }
    }
    Connections {
        target: root.drawerSectionSource
        function onDrawerSectionPreferenceChanged() { ++root.actionRevision }
    }
    Connections {
        target: shell.session.songOpen ? shell.session.eventListPresenter() : null
        function onCurrentRowChanged() { ++root.actionRevision }
    }
    Connections {
        target: shell
        function onPolyphonyVisibleChanged() { ++root.actionRevision }
        function onEventListGateChanged() { ++root.actionRevision }
        function onChooseProjectRequested() { ensureProjectPicker().open() }
        function onAboutRequested() { ensureAboutDialog().open() }
        function onSettingsRequested(songFirst) { ensureSettingsDialog().showSettings(songFirst) }
        function onQuitRequested() { root.close() }
        function onCriticalRequested(title, message) {
            const dialog = ensureCriticalDialog()
            dialog.text = title
            dialog.informativeText = message
            dialog.open()
        }
    }

    // Menus, docks, editor and secondary windows instantiate together.
    // Window-scope shortcuts get native Qt ShortcutOverride arbitration; editor
    // strokes are routed only from the focused tab's raw key path below.
    Repeater {
        model: shell.windowActionIds
        delegate: Item {
            id: shortcutDelegate
            required property string modelData
            width: 0
            height: 0
            Shortcut {
                objectName: "shellShortcut_" + shortcutDelegate.modelData
                sequences: shell.actionSequences(shortcutDelegate.modelData)
                context: Qt.WindowShortcut
                enabled: {
                    root.actionRevision
                    return shell.actionEnabled(shortcutDelegate.modelData)
                }
                onActivated: shell.activate(shortcutDelegate.modelData)
            }
        }
    }

    ShellMenuBar {
        id: shellMenu
        shell: root.shellPresenter
        windowRoot: root
        actionRevision: root.actionRevision
    }
    // Deferred chrome: dialogs instantiate on first use, so startup never
    // pays for their font/button work; Loaders complete synchronously.
    function ensureSettingsDialog() {
        settingsDialogLoader.active = true
        return settingsDialogLoader.item
    }
    function ensureAboutDialog() {
        aboutDialogLoader.active = true
        return aboutDialogLoader.item
    }
    function ensureProjectPicker() {
        projectPickerLoader.active = true
        return projectPickerLoader.item
    }
    function ensureCriticalDialog() {
        criticalDialogLoader.active = true
        return criticalDialogLoader.item
    }
    Loader {
        id: settingsDialogLoader
        objectName: "shellSettingsLoader"
        active: false
        sourceComponent: SettingsDialog {
            objectName: "shellSettingsDialog"
            transientParent: root
            store: shell.settingsStore
            presenter: shell
            colors: root.colors
            applicationSession: shell.session
        }
    }
    Loader {
        id: aboutDialogLoader
        objectName: "shellAboutLoader"
        active: false
        sourceComponent: AboutDialog {
            colors: root.colors
            applicationSession: shell.session
            baseFontPx: shell.session.baseFontPx
        }
    }
    MidiImportHost {
        controller: shell.session.songDockController().midiImportController()
        hostWindow: root
        colors: root.colors
        applicationSession: shell.session
    }
    NewSongHost {
        controller: shell.session.songDockController().newSongController()
        hostWindow: root
        colors: root.colors
        applicationSession: shell.session
    }
    SampleStudioHost {
        workflow: shell.session.sampleStudio()
        hostWindow: root
        applicationSession: shell.session
        colors: root.colors
    }
    WavExportSurface {
        presenter: shell.session.wavExportPresenter()
        colors: root.colors
        windowRoot: root
        typography: root.chromeTypography
    }

    SplitView {
        id: shellBody
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: polyDock.visible ? polyDock.left : parent.right
        orientation: Qt.Horizontal

        SongsDockColumn {
            id: dockColumn
            SplitView.fillHeight: true
            SplitView.minimumWidth: 200
            SplitView.maximumWidth: 480
            SplitView.preferredWidth: Math.max(200, Math.min(480, shell.dockColumnWidth))
            controller: shell.session.songDockController()
            applicationSession: shell.session
            songsRatio: shell.dockSongsRatio
            colors: shell.session.palette
            onSongsRatioChanged: {
                if (root.dockSettingsReady && songsRatio !== shell.dockSongsRatio)
                    shell.setDockSongsRatio(songsRatio)
            }
            onWidthChanged: {
                if (root.dockSettingsReady && width >= 200 && width <= 480 && width !== shell.dockColumnWidth)
                    shell.setDockColumnWidth(Math.round(width))
            }
        }

        Loader {
            id: editorScene
            objectName: "shellSceneLoader"
            SplitView.fillWidth: true
            SplitView.fillHeight: true
            active: shell.sceneActive
            focus: true
            onActiveFocusChanged: {
                if (!item || activeFocus)
                    return
                let focus = root.activeFocusItem
                while (focus) {
                    if (focus.objectName === "drawerModalLayer"
                            && focus.parent === root.contentItem && focus.visible)
                        return
                    focus = focus.parent
                }
                shell.session.cancelGridInput(0)
            }
            sourceComponent: SongTabs {
                objectName: "shellSongTabs"
                controller: shell.session.songTabs
                layoutSpaces: shell.session.layoutSpaces
                shellRouter: shell
                onContextMenuAt: (x, y) => {
                    root.actionRevision++
                    gridContextMenu.menu.x = x
                    gridContextMenu.menu.y = y
                    gridContextMenu.menu.open()
                }
            }
            Text {
                objectName: "shellEmptySongMessage"
                anchors.centerIn: parent
                visible: !shell.session.songOpen && shell.sceneActive
                text: qsTr("Open a project and song to play with the Swift core.")
                font: Qt.font(root.chromeTypography.body)
                color: shell.session.palette.windowText
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
    Item {
        id: polyDock
        objectName: "shellPolyphonyDock"
        visible: shell.polyphonyVisible
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: Math.min(root.chromeBaseFontPx * 32, parent.width * 0.48)
        z: 2
        Rectangle {
            anchors.fill: parent
            color: root.colors.windowBackground
            border.color: root.colors.outline
        }
        Row {
            id: polyTitle
            width: parent.width
            height: Math.max(bodyMetrics.height, transportBar.toolExtent)
                    + 2 * root.chromeSpacing.half + 2
            Text {
                objectName: "shellPolyphonyTitle"
                width: parent.width - polyClose.width
                height: parent.height
                leftPadding: root.chromeSpacing.two
                text: qsTr("Polyphony Debugger")
                font: Qt.font(root.chromeTypography.body)
                color: root.colors.windowText
                verticalAlignment: Text.AlignVCenter
            }
            Button {
                id: polyClose
                objectName: "shellPolyphonyClose"
                height: parent.height
                font: Qt.font(root.chromeTypography.body)
                text: qsTr("×")
                onClicked: shell.activate("view.polyphony_debugger")
            }
        }
        PolyphonyPanel {
            id: polyPanel
            anchors.top: polyTitle.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            presenter: shell.session.polyphony
            colors: root.colors
            typography: root.chromeTypography
            layoutSpaces: root.chromeSpacing
            baseFontPx: root.chromeBaseFontPx
        }
        Timer {
            running: polyDock.visible && shell.session.songOpen
            repeat: true
            interval: 100
            onTriggered: shell.session.polyphony.poll()
        }
    }

    Loader {
        id: songConfirmation
        objectName: "songConfirmationLoader"
        active: shell.session.songDockController().confirmation.length > 0
        sourceComponent: SongConfirmDialog {
            controller: shell.session.songDockController()
            baseFontPx: root.chromeBaseFontPx
            layoutSpaces: root.chromeSpacing
        }
        onLoaded: {
            if (status === Loader.Ready)
                item.open()
        }
    }
    // Save-conflict prompt: modal, so local Space is allowed. The name field
    // reuses the New Song label law; Register stays disabled until valid.
    // Loader-gated like songConfirmation above; handlers and objectNames
    // inside are unchanged.
    Loader {
        id: saveConflictLoader
        objectName: "saveConflictLoader"
        active: shell.session.saveConflictSongLabel.length > 0
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
            onRejected: shell.session.cancelSaveConflict()
            onClosed: {
                if (shell.session.saveConflictSongLabel.length > 0)
                    shell.session.cancelSaveConflict()
            }
            contentItem: ColumnLayout {
                spacing: root.chromeSpacing.four
                Label {
                    objectName: "saveConflictMessage"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: shell.session.saveConflictDetail
                }
                TextField {
                    id: saveConflictNameField
                    objectName: "saveConflictNewName"
                    Layout.fillWidth: true
                    placeholderText: qsTr("mus_new_song")
                    onTextChanged: {
                        const previous = shell.session.saveConflictNewSongLabel
                        const proposed = text
                        const cursor = cursorPosition
                        const accepted = shell.session.acceptSaveConflictLabelEdit(previous, proposed)
                        if (accepted !== proposed) {
                            text = accepted
                            cursorPosition = Math.min(cursor, accepted.length)
                        }
                        shell.session.saveConflictNewSongLabel = accepted
                    }
                    onAccepted: {
                        if (saveConflictForkButton.enabled)
                            shell.session.resolveSaveConflictFork()
                    }
                }
                Label {
                    objectName: "saveConflictTaken"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: qsTr("A song named %1 already exists.").arg(saveConflictNameField.text)
                    visible: saveConflictNameField.text.length > 0
                        && shell.session.saveConflictLabelTaken(saveConflictNameField.text)
                }
            }
            footer: DialogButtonBox {
                Button {
                    id: saveConflictOverwriteButton
                    objectName: "saveConflictOverwrite"
                    text: qsTr("Overwrite")
                    DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                    onClicked: shell.session.resolveSaveConflictOverwrite()
                }
                Button {
                    id: saveConflictForkButton
                    objectName: "saveConflictFork"
                    text: qsTr("Register changes as New Song...")
                    DialogButtonBox.buttonRole: DialogButtonBox.ActionRole
                    enabled: saveConflictNameField.text.length > 0
                        && shell.session.saveConflictLabelValid(saveConflictNameField.text)
                        && !shell.session.saveConflictLabelTaken(saveConflictNameField.text)
                    onClicked: shell.session.resolveSaveConflictFork()
                }
                Button {
                    objectName: "saveConflictCancel"
                    text: qsTr("Cancel")
                    DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                    onClicked: shell.session.cancelSaveConflict()
                }
            }
        }
        onLoaded: {
            if (status === Loader.Ready)
                item.open()
        }
    }
    TransportBar {
        id: transportBar
        width: root.width
        enabled: shell.sceneActive
        songAvailable: shell.session.songOpen
        baseFontPx: root.chromeBaseFontPx
        presenter: shell.session.transportBarPresenter()
        shell: root.shellPresenter
        actionRevision: root.actionRevision
        colors: root.colors
        typography: root.chromeTypography
        layoutSpaces: root.chromeSpacing
    }
    ShellStatusBar {
        id: shellStatus
        root: content.root
        shell: root.shellPresenter
        bodyMetrics: bodyMetrics
        captionMetrics: captionMetrics
    }

    ShellGridContextMenu {
        id: gridContextMenu
        root: content.root
        shell: root.shellPresenter
        editorScene: editorScene
        bodyMetrics: bodyMetrics
    }

    Loader {
        id: projectPickerLoader
        objectName: "shellProjectPickerLoader"
        active: false
        sourceComponent: FolderDialog {
            objectName: "shellProjectPicker"
            title: qsTr("Open Project")
            onAccepted: shell.chooseProject(selectedFolder.toString())
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
