import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Dialogs
import QtQml.Models
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

    // Cocoa uses the primary NativeText suffix as the same key equivalent the
    // old QAction supplied. ShortcutOverride arbitrates it before keyDown;
    // an Action.shortcut here would incorrectly add another Qt map entry.
    function nativeMenuText(actionId) {
        const shortcut = shell.actionShortcut(actionId)
        const label = shell.actionLabel(actionId)
        return shortcut.length > 0 ? label + "\t" + shortcut : label
    }

    // A Swift method's internal reads do not install QML binding dependencies.
    // Re-evaluate delivery and menus on the same notifications as the native
    // updateWindowActions/updateGridActions slots, without duplicating policy.
    Connections {
        target: shell.session
        function onProjectOpenChanged() {
            shell.refreshWindowChrome()
            ++root.actionRevision
        }
        function onProjectRootChanged() { shell.refreshWindowChrome() }
        function onSongOpenChanged() {
            shell.songOpenChanged()
            ++root.actionRevision
        }
        function onSaveInProgressChanged() {
            shell.saveStateChanged()
            ++root.actionRevision
        }
        function onDocumentDirtyChanged() { shell.refreshWindowChrome() }
        function onCanUndoChanged() { ++root.actionRevision }
        function onCanRedoChanged() { ++root.actionRevision }
        function onGridCommandAvailabilityChanged() { ++root.actionRevision }
        function onTransportAvailabilityChanged() { ++root.actionRevision }
        function onVelocityColorModeChanged() { ++root.actionRevision }
        function onNoteNameModeChanged() { ++root.actionRevision }
        function onOpenFailed(message) { shell.openFailed(message) }
        function onOperationFailed(message) { shell.operationFailed(message) }
        function onAllTabsClosed() { shell.allTabsClosed() }
        function onCloseCancelled() { shell.closeCancelled() }
    }
    Connections {
        target: shell.session.songTabs
        function onSelectedTabShowsEventsChanged() { ++root.actionRevision }
        function onSelectedPageChanged() {
            shell.refreshWindowChrome()
            ++root.actionRevision
        }
        function onSelectedIdChanged() { ++root.actionRevision }
        function onTabCountChanged() { ++root.actionRevision }
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
        if (!sessionStatePersisted) {
            const frame = normalFrame || { x: root.x, y: root.y, width: root.width, height: root.height }
            shell.persistSessionState(frame.x, frame.y, frame.width, frame.height,
                                      root.visibility === Window.Maximized, shell.polyphonyVisible)
            sessionStatePersisted = true
        }
    }
    Connections {
        target: shell
        function onCloseReadyChanged() {
            if (shell.closeReady)
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

    menuBar: MenuBar {
        Menu {
            id: fileMenu
            objectName: "shellFileMenu"
            title: qsTr("&File")
            onAboutToShow: ++root.actionRevision
            MenuSeparator {}
            Instantiator {
                model: shell.fileActionIds
                delegate: MenuItem {
                    // No submenu/check visuals: skips per-item image loads at launch.
                    arrow: null
                    indicator: null
                    required property string modelData
                    objectName: "shellAction_" + modelData
                    text: root.nativeMenuText(modelData)
                    enabled: {
                        root.actionRevision
                        return shell.actionEnabled(modelData)
                    }
                    onTriggered: shell.activate(modelData)
                }
                onObjectAdded: (index, object) => fileMenu.insertItem(index < 2 ? index : index + 1, object)
                onObjectRemoved: (index, object) => fileMenu.removeItem(object)
            }
        }
        Menu {
            id: editMenu
            objectName: "shellEditMenu"
            title: qsTr("&Edit")
            onAboutToShow: ++root.actionRevision
            Component.onCompleted: {
                editTopItems.active = true
                editClipboardItems.active = true
                editNotesItems.active = true
                editTailItems.active = true
            }
            Instantiator {
                id: editTopItems
                active: false
                model: shell.editTopActionIds
                delegate: MenuItem {
                    arrow: null
                    indicator: null
                    required property string modelData
                    objectName: "shellAction_" + modelData
                    text: root.nativeMenuText(modelData)
                    enabled: {
                        root.actionRevision
                        return shell.actionEnabled(modelData)
                    }
                    onTriggered: shell.activate(modelData)
                }
                onObjectAdded: (index, object) => editMenu.insertItem(index, object)
                onObjectRemoved: (index, object) => editMenu.removeItem(object)
            }
            MenuSeparator { objectName: "shellEditSectionSeparator" }
            Instantiator {
                id: editClipboardItems
                active: false
                model: shell.editClipboardActionIds
                delegate: MenuItem {
                    arrow: null
                    indicator: null
                    required property string modelData
                    objectName: "shellAction_" + modelData
                    text: root.nativeMenuText(modelData)
                    enabled: {
                        root.actionRevision
                        return shell.actionEnabled(modelData)
                    }
                    onTriggered: shell.activate(modelData)
                }
                onObjectAdded: (index, object) =>
                    editMenu.insertItem(shell.editTopActionIds.length + 1 + index, object)
                onObjectRemoved: (index, object) => editMenu.removeItem(object)
            }
            Menu {
                id: timeMenu
                objectName: "shellTimeMenu"
                title: qsTr("&Time")
                onAboutToShow: ++root.actionRevision
                Instantiator {
                    model: shell.timeActionIds
                    delegate: MenuItem {
                        arrow: null
                        indicator: null
                        required property string modelData
                        objectName: "shellAction_" + modelData
                        text: root.nativeMenuText(modelData)
                        enabled: {
                            root.actionRevision
                            return shell.actionEnabled(modelData)
                        }
                        onTriggered: shell.activate(modelData)
                    }
                    onObjectAdded: (index, object) => timeMenu.insertItem(index, object)
                    onObjectRemoved: (index, object) => timeMenu.removeItem(object)
                }
            }
            Instantiator {
                id: editNotesItems
                active: false
                model: shell.editNotesActionIds
                delegate: MenuItem {
                    arrow: null
                    indicator: null
                    required property string modelData
                    objectName: "shellAction_" + modelData
                    text: root.nativeMenuText(modelData)
                    enabled: {
                        root.actionRevision
                        return shell.actionEnabled(modelData)
                    }
                    onTriggered: shell.activate(modelData)
                }
                onObjectAdded: (index, object) =>
                    editMenu.insertItem(shell.editTopActionIds.length
                                        + shell.editClipboardActionIds.length + 2 + index, object)
                onObjectRemoved: (index, object) => editMenu.removeItem(object)
            }
            Menu {
                id: tracksMenu
                objectName: "shellTracksMenu"
                title: qsTr("Tr&acks")
                onAboutToShow: ++root.actionRevision
                Instantiator {
                    model: shell.tracksActionIds
                    delegate: MenuItem {
                        arrow: null
                        indicator: null
                        required property string modelData
                        objectName: "shellAction_" + modelData
                        text: root.nativeMenuText(modelData)
                        enabled: {
                            root.actionRevision
                            return shell.actionEnabled(modelData)
                        }
                        onTriggered: shell.activate(modelData)
                    }
                    onObjectAdded: (index, object) => tracksMenu.insertItem(index, object)
                    onObjectRemoved: (index, object) => tracksMenu.removeItem(object)
                }
            }
            Instantiator {
                id: editTailItems
                active: false
                model: shell.editTailActionIds
                delegate: MenuItem {
                    arrow: null
                    indicator: null
                    required property string modelData
                    objectName: "shellAction_" + modelData
                    text: root.nativeMenuText(modelData)
                    enabled: {
                        root.actionRevision
                        return shell.actionEnabled(modelData)
                    }
                    onTriggered: shell.activate(modelData)
                }
                onObjectAdded: (index, object) =>
                    editMenu.insertItem(shell.editTopActionIds.length
                                        + shell.editClipboardActionIds.length
                                        + shell.editNotesActionIds.length + 3 + index, object)
                onObjectRemoved: (index, object) => editMenu.removeItem(object)
            }
        }
        Menu {
            id: transportMenu
            objectName: "shellTransportMenu"
            title: qsTr("&Transport")
            onAboutToShow: ++root.actionRevision
            Instantiator {
                model: shell.transportActionIds
                delegate: MenuItem {
                    arrow: null
                    required property string modelData
                    objectName: "shellAction_" + modelData
                    text: root.nativeMenuText(modelData)
                    checkable: shell.actionCheckable(modelData)
                    checked: {
                        root.actionRevision
                        return shell.actionChecked(modelData)
                    }
                    enabled: {
                        root.actionRevision
                        return shell.actionEnabled(modelData)
                    }
                    onTriggered: shell.activate(modelData)
                }
                onObjectAdded: (index, object) => transportMenu.insertItem(index, object)
                onObjectRemoved: (index, object) => transportMenu.removeItem(object)
            }
        }
        Menu {
            id: viewMenu
            objectName: "shellViewMenu"
            title: qsTr("&View")
            onAboutToShow: ++root.actionRevision
            Instantiator {
                model: shell.viewActionIds
                delegate: MenuItem {
                    arrow: null
                    required property string modelData
                    objectName: "shellAction_" + modelData
                    text: root.nativeMenuText(modelData)
                    checkable: shell.actionCheckable(modelData)
                    checked: {
                        root.actionRevision
                        return shell.actionChecked(modelData)
                    }
                    enabled: {
                        root.actionRevision
                        return shell.actionEnabled(modelData)
                    }
                    onTriggered: shell.activate(modelData)
                }
                onObjectAdded: (index, object) => viewMenu.insertItem(index, object)
                onObjectRemoved: (index, object) => viewMenu.removeItem(object)
            }
        }
        Menu {
            id: helpMenu
            objectName: "shellHelpMenu"
            title: qsTr("&Help")
            onAboutToShow: ++root.actionRevision
            // Qt Quick Controls offers no QAction::AboutRole equivalent, so the
            // item stays in the Help menu on every platform, as it did on
            // non-macOS builds of the old app.
            MenuItem {
                arrow: null
                indicator: null
                objectName: "shellAction_help.about"
                text: root.nativeMenuText("help.about")
                enabled: {
                    root.actionRevision
                    return shell.actionEnabled("help.about")
                }
                onTriggered: shell.activate("help.about")
            }
        }
    }
    SettingsDialog {
        id: settingsDialog
        objectName: "shellSettingsDialog"
        transientParent: root
        store: shell.settingsStore
        colors: root.colors
        applicationSession: shell.session
    }
    AboutDialog {
        id: aboutDialog
        colors: root.colors
        applicationSession: shell.session
        baseFontPx: shell.session.baseFontPx
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
                if (item && !activeFocus)
                    shell.session.cancelGridInput(0)
            }
            sourceComponent: SongTabs {
                objectName: "shellSongTabs"
                controller: shell.session.songTabs
                layoutSpaces: shell.session.layoutSpaces
                shellRouter: shell
                onContextMenuAt: (x, y) => {
                    root.actionRevision++
                    gridContextMenu.x = x
                    gridContextMenu.y = y
                    gridContextMenu.open()
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
    footer: Rectangle {
        readonly property int statusTopInset: 3
        readonly property int statusBottomInset: 2
        readonly property int statusGripHeight: 13 + 4
        implicitHeight: Math.max(captionMetrics.height, bodyMetrics.height, statusGripHeight)
                        + statusTopInset + statusBottomInset
        color: shell.session.palette.windowBackground
        Text {
            objectName: "shellStatusText"
            anchors.left: parent.left
            anchors.right: polyMeter.visible ? polyMeter.left : parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: parent.statusTopInset
            anchors.bottomMargin: parent.statusBottomInset
            anchors.leftMargin: root.chromeSpacing.two
            anchors.rightMargin: root.chromeSpacing.two
            text: shell.statusText
            font: Qt.font(root.chromeTypography.caption)
            color: root.colors.windowText
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        Row {
            id: polyMeter
            objectName: "shellPolyMeter"
            anchors.right: parent.right
            anchors.rightMargin: root.chromeSpacing.two
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: (parent.statusTopInset - parent.statusBottomInset) / 2
            spacing: bodyMetrics.advanceWidth(" ") / 2
            visible: presenter.polyMeterVisible
            readonly property var presenter: shell.session.transportBarPresenter()
            Text {
                objectName: "shellPolyPcmCaption"
                text: qsTr("PCM")
                font: Qt.font(root.chromeTypography.body)
                color: root.colors.windowText
            }
            Rectangle {
                implicitWidth: pcmValue.implicitWidth + polyMeter.spacing * 2
                implicitHeight: bodyMetrics.height
                color: root.colors.polyphonyValueBackground
                Text {
                    id: pcmValue
                    objectName: "shellPolyPcmValue"
                    anchors.fill: parent
                    anchors.leftMargin: polyMeter.spacing
                    anchors.rightMargin: polyMeter.spacing
                    text: polyMeter.presenter.pcmText
                    font: Qt.font(root.chromeTypography.bodyMono)
                    color: root.colors.polyphonyValueText
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Text {
                text: "·"
                color: root.colors.windowText
                font: Qt.font(root.chromeTypography.body)
            }
            Text {
                objectName: "shellPolyCgbCaption"
                text: qsTr("CGB")
                color: root.colors.windowText
                font: Qt.font(root.chromeTypography.body)
            }
            Rectangle {
                implicitWidth: cgbValue.implicitWidth + polyMeter.spacing * 2
                implicitHeight: bodyMetrics.height
                color: root.colors.polyphonyValueBackground
                Text {
                    id: cgbValue
                    objectName: "shellPolyCgbValue"
                    anchors.fill: parent
                    anchors.leftMargin: polyMeter.spacing
                    anchors.rightMargin: polyMeter.spacing
                    text: polyMeter.presenter.cgbText
                    font: Qt.font(root.chromeTypography.bodyMono)
                    color: root.colors.polyphonyValueText
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Text {
                visible: polyMeter.presenter.lostVisible
                text: "·"
                color: root.colors.windowText
                font: Qt.font(root.chromeTypography.body)
            }
            Rectangle {
                visible: polyMeter.presenter.lostVisible
                implicitWidth: lostValue.implicitWidth + polyMeter.spacing * 2
                implicitHeight: bodyMetrics.height
                color: root.colors.polyphonyValueBackground
                Text {
                    id: lostValue
                    objectName: "shellPolyLostValue"
                    anchors.fill: parent
                    anchors.leftMargin: polyMeter.spacing
                    anchors.rightMargin: polyMeter.spacing
                    text: polyMeter.presenter.lostText
                    color: root.colors.polyphonyValueText
                    font: Qt.font(root.chromeTypography.body)
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Text {
                visible: polyMeter.presenter.lostVisible
                text: qsTr("notes lost")
                font: Qt.font(root.chromeTypography.body)
                color: root.colors.windowText
            }
        }
    }

    Basic.Menu {
        id: gridContextMenu
        objectName: "shellGridContextMenu"
        parent: Overlay.overlay
        popupType: Popup.Item
        font: Qt.font(root.chromeTypography.body)
        palette.window: root.colors.menuBackground
        palette.dark: root.colors.outline
        onAboutToShow: ++root.actionRevision
        Instantiator {
            model: shell.contextActionIds
            delegate: Basic.MenuItem {
                id: contextAction
                required property string modelData
                objectName: "shellContextAction_" + modelData
                text: shell.actionLabel(modelData)
                readonly property string shortcutText: shell.actionShortcut(modelData)
                readonly property color foreground: !enabled ? root.colors.disabledText
                    : down ? root.colors.buttonPressedText : root.colors.windowText
                Accessible.description: shortcutText
                hoverEnabled: true
                padding: root.chromeSpacing.one
                contentItem: Item {
                    implicitWidth: caption.implicitWidth + (hint.visible
                        ? hint.implicitWidth + bodyMetrics.averageCharacterWidth * 2 : 0)
                    implicitHeight: Math.max(caption.implicitHeight, hint.implicitHeight)
                    Text {
                        id: caption
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: contextAction.text
                        font: contextAction.font
                        color: contextAction.foreground
                    }
                    Text {
                        id: hint
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: text.length > 0
                        text: contextAction.shortcutText
                        font: contextAction.font
                        color: contextAction.foreground
                    }
                }
                background: Rectangle {
                    color: contextAction.down ? root.colors.buttonPressedBackground
                        : contextAction.highlighted ? root.colors.menuHoverBackground
                        : root.colors.menuBackground
                }
                enabled: {
                    root.actionRevision
                    return shell.actionEnabled(modelData)
                }
                onTriggered: shell.activate(modelData)
            }
            onObjectAdded: (index, object) => gridContextMenu.insertItem(index, object)
            onObjectRemoved: (index, object) => gridContextMenu.removeItem(object)
        }
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
