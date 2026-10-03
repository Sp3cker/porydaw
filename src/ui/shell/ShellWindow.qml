import QtQuick
import PorydawApp
import Porydaw.Ui
ThemedWindow {
    id: root
    objectName: "shellWindow"
    readonly property alias shellPresenter: shell
    readonly property var sceneLoader: applicationContent.item ? applicationContent.item.sceneLoader : null
    readonly property var drawerSectionSource: shell.session.songTabs.selectedPage
                                               ? shell.session.songTabs.selectedPage.drawerPresenter() : null
    colors: shell.session.palette
    property bool establishApplicationIdentity: false
    property int actionRevision: 0
    property var normalFrame: null
    property bool sessionStatePersisted: false
    property bool windowPrepared: false
    readonly property int bodyFontPx: shell.session.bodyFontPx
    property int chromeBaseFontPx: shell.session.baseFontPx
    property var chromeTypography: shell.session.typographyFonts
    property var chromeSpacing: shell.session.layoutSpaces
    property font typographyCaptureFont: Application.font
    width: root.chromeBaseFontPx * 92
    height: root.chromeBaseFontPx * 57
    title: shell.windowTitle
    visible: root.windowPrepared
    color: shell.session.palette.windowBackground
    font: Qt.font(root.chromeTypography.body)
    contentItem.enabled: shell.sceneActive
    menuBar: applicationContent.item ? applicationContent.item.menuBar : null
    header: applicationContent.item ? applicationContent.item.header : null
    footer: applicationContent.item ? applicationContent.item.footer : null

    ShellPresenter {
        id: shell
        objectName: "shellPresenter"
    }

    FontLoader {
        id: regularFont
        source: shell.regularFontSource
    }
    FontLoader {
        id: semiboldFont
        source: shell.semiboldFontSource
    }
    FontLoader {
        id: monoFont
        source: shell.monoFontSource
    }
    FontLoader {
        id: iconsFont
        source: shell.iconsFontSource
    }

    Component.onCompleted: {
        // Bundled faces load synchronously from local files; never show text if packaging broke.
        if (regularFont.status !== FontLoader.Ready
                || semiboldFont.status !== FontLoader.Ready
                || monoFont.status !== FontLoader.Ready
                || iconsFont.status !== FontLoader.Ready) {
            console.error("Cannot load the required bundled fonts")
            Qt.exit(1)
            return
        }
        const naturalWidth = root.width === root.chromeBaseFontPx * 92
        const naturalHeight = root.height === root.chromeBaseFontPx * 57
        // The requested pixel size needs no matching or measurement of an unused system face.
        shell.session.configureTypography(root.typographyCaptureFont.pixelSize)
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
        shell.restoreAppearance()
        shell.chromeRestored()
        if (shell.windowMaximized)
            root.visibility = Window.Maximized
        root.windowPrepared = true
    }

    Connections {
        target: root
        enabled: !shell.contentRequested
        function onFrameSwapped() { shell.firstFrameRendered() }
    }

    // This separate document is not parsed or instantiated before the window presents.
    Loader {
        id: applicationContent
        objectName: "shellContentLoader"
        anchors.fill: parent
        // Mounted chrome releases services before constructing the workspace.
        asynchronous: false
        focus: true
        active: shell.contentRequested && shell.sceneActive
        Component.onCompleted: setSource(Qt.resolvedUrl("ShellContent.qml"), {root: root})
        onLoaded: {
            shell.contentReady()
            item.loadWorkspace()
        }
        onItemChanged: acknowledgeRemoval()
        onStatusChanged: {
            if (status === Loader.Error) {
                console.error("Cannot load the required application content: " + source)
                Qt.exit(1)
            }
            acknowledgeRemoval()
        }
        onActiveChanged: acknowledgeRemoval()

        function acknowledgeRemoval() {
            if (!shell.sceneActive && !active && !item && status === Loader.Null)
                shell.sceneDestroyed()
        }
    }

    // Close remains operational even when deferred content has never existed.
    Connections {
        target: shell.session
        function onAllTabsClosed() { shell.allTabsClosed() }
        function onCloseCancelled() { shell.closeCancelled() }
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
        function onSceneActiveChanged() {
            ++root.actionRevision
            applicationContent.acknowledgeRemoval()
        }
    }

}
