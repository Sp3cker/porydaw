import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import PorydawApp
import Porydaw.Ui

ThemedWindow {
    id: root
    objectName: "shellWindow"
    readonly property alias shellPresenter: shell
    readonly property alias sceneLoader: editorScene
    readonly property var drawerSectionSource: shell.session.songTabs.selectedPage
                                               ? shell.session.songTabs.selectedPage.drawerPresenter() : null
    colors: shell.session.palette
    property bool establishApplicationIdentity: false
    property int actionRevision: 0
    property bool dockSettingsReady: false
    property var normalFrame: null
    property bool sessionStatePersisted: false
    readonly property int bodyFontPx: shell.session.bodyFontPx
    property int chromeBaseFontPx: shell.session.baseFontPx
    property var chromeTypography: shell.session.typographyFonts
    property var chromeSpacing: shell.session.layoutSpaces
    property font typographyCaptureFont: Application.font
    width: root.chromeBaseFontPx * 92
    height: root.chromeBaseFontPx * 57
    title: shell.windowTitle
    visible: true
    color: shell.session.palette.windowBackground
    font: Qt.font(root.chromeTypography.body)

    ShellPresenter {
        id: shell
        objectName: "shellPresenter"
    }

    FontInfo {
        id: baseFontInfo
        font: root.typographyCaptureFont
    }
    FontLoader {
        source: "qrc:/fonts/AtkinsonHyperlegibleNext-Regular.ttf"
    }
    FontLoader {
        source: "qrc:/fonts/AtkinsonHyperlegibleNext-SemiBold.ttf"
    }
    FontLoader {
        id: monoFont
        source: "qrc:/fonts/AtkinsonHyperlegibleMono-Regular.ttf"
    }
    FontMetrics {
        id: bodyMetrics
        font: root.font
    }
    FontMetrics {
        id: captionMetrics
        font: Qt.font(root.chromeTypography.caption)
    }

    Component.onCompleted: {
        const naturalWidth = root.width === root.chromeBaseFontPx * 92
        const naturalHeight = root.height === root.chromeBaseFontPx * 57
        shell.session.configureTypography(baseFontInfo.pixelSize)
        root.chromeBaseFontPx = shell.session.baseFontPx
        root.chromeTypography = shell.session.typographyFonts
        root.chromeSpacing = shell.session.layoutSpaces
        if (naturalWidth)
            root.width = root.chromeBaseFontPx * 92
        if (naturalHeight)
            root.height = root.chromeBaseFontPx * 57
        if (establishApplicationIdentity) {
            Qt.application.name = "porydaw"
            Qt.application.organization = "sp3cker"
            Qt.application.domain = ""
        }
        shell.configureSettings(Qt.application.name)
        if (shell.windowX >= 0) {
            const centerX = shell.windowX + shell.windowWidth / 2
            const centerY = shell.windowY + shell.windowHeight / 2
            for (const screen of Qt.application.screens) {
                if (centerX >= screen.virtualX && centerX < screen.virtualX + screen.width
                        && centerY >= screen.virtualY && centerY < screen.virtualY + screen.height) {
                    root.x = shell.windowX
                    root.y = shell.windowY
                    root.width = shell.windowWidth
                    root.height = shell.windowHeight
                    break
                }
            }
        }
        if (shell.windowMaximized)
            root.visibility = Window.Maximized
        root.dockSettingsReady = true
        shell.session.restoreDisplayModes()
        transportBar.presenter.restoreOutputVolume()
        transportBar.presenter.restoreTransportToggles()
        shell.settingsStore.restoreFromPreferences()
        shell.restoreAppearance()
        shell.openStartup()
    }

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
        function onAllTabsClosed() { shell.allTabsClosed() }
        function onCloseCancelled() { shell.closeCancelled() }
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
        function onChooseProjectRequested() { projectPicker.open() }
        function onAboutRequested() { aboutDialog.open() }
        function onSettingsRequested(songFirst) { settingsDialog.showSettings(songFirst) }
        function onQuitRequested() { root.close() }
        function onCriticalRequested(title, message) {
            criticalDialog.text = title
            criticalDialog.informativeText = message
            criticalDialog.open()
        }
    }
    onActiveChanged: {
        if (!active)
            shell.session.cancelGridInput(3)
    }
    onVisibleChanged: {
        if (!visible)
            shell.session.cancelGridInput(2)
    }
    function trackNormalFrame() {
        if (visibility !== Window.Maximized && width > 0 && height > 0)
            normalFrame = { x: x, y: y, width: width, height: height }
    }
    onXChanged: trackNormalFrame()
    onYChanged: trackNormalFrame()
    onWidthChanged: trackNormalFrame()
    onHeightChanged: trackNormalFrame()
    onVisibilityChanged: trackNormalFrame()
    onClosing: close => {
        if (!shell.beginClose()) {
            close.accepted = false
            return
        }
    }
    Connections {
        target: shell
        function onCloseReadyChanged() {
            if (!shell.closeReady)
                return
            if (!root.sessionStatePersisted) {
                const frame = root.normalFrame || {
                    x: root.x, y: root.y, width: root.width, height: root.height
                }
                shell.persistSessionState(frame.x, frame.y, frame.width, frame.height,
                                          root.visibility === Window.Maximized, shell.polyphonyVisible)
                root.sessionStatePersisted = true
            }
            root.close()
        }
        function onSceneActiveChanged() { ++root.actionRevision }
    }

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

    menuBar: ShellMenuBar {
        shell: root.shellPresenter
        windowRoot: root
        actionRevision: root.actionRevision
    }
    SettingsDialog {
        id: settingsDialog
        objectName: "shellSettingsDialog"
        transientParent: root
        store: shell.settingsStore
        presenter: shell
        colors: root.colors
        applicationSession: shell.session
    }
    AboutDialog {
        id: aboutDialog
        colors: root.colors
        applicationSession: shell.session
        baseFontPx: shell.session.baseFontPx
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
            onItemChanged: {
                if (!item && !shell.sceneActive)
                    shell.sceneDestroyed()
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
    header: TransportBar {
        id: transportBar
        width: root.width
        songAvailable: shell.session.songOpen
        baseFontPx: root.chromeBaseFontPx
        presenter: shell.session.transportBarPresenter()
        shell: root.shellPresenter
        actionRevision: root.actionRevision
        colors: root.colors
        typography: root.chromeTypography
        layoutSpaces: root.chromeSpacing
    }
    footer: ShellStatusBar {
        root: root
        shell: root.shellPresenter
        bodyMetrics: bodyMetrics
        captionMetrics: captionMetrics
    }

    ShellGridContextMenu {
        id: gridContextMenu
        root: root
        shell: root.shellPresenter
        editorScene: editorScene
        bodyMetrics: bodyMetrics
    }

    FolderDialog {
        id: projectPicker
        objectName: "shellProjectPicker"
        title: qsTr("Open Project")
        onAccepted: shell.chooseProject(selectedFolder.toString())
    }
    MessageDialog {
        id: criticalDialog
        objectName: "shellCriticalDialog"
        buttons: MessageDialog.Ok
    }
}
