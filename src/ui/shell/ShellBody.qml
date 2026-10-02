import QtQuick
import QtQuick.Controls
import Porydaw.Ui

Item {
    id: body
    required property var root
    required property int transportToolExtent
    readonly property var shell: body.root.shellPresenter
    readonly property alias sceneLoader: editorScene
    property bool dockSettingsReady: false

    Component.onCompleted: body.dockSettingsReady = true

    FontMetrics {
        id: bodyMetrics
        font: root.font
    }

    Connections {
        target: shell.session
        function onSongOpenChanged() { gridContextMenu.menu.close() }
    }
    Connections {
        target: shell.session.songTabs
        function onSelectedPageChanged() { gridContextMenu.menu.close() }
        function onSelectedIdChanged() { gridContextMenu.menu.close() }
    }
    Connections {
        target: shell.session.songOpen ? shell.session.gridPresenter() : null
        function onAppliedRevisionTextChanged() { gridContextMenu.menu.close() }
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
                if (body.dockSettingsReady && songsRatio !== shell.dockSongsRatio)
                    shell.setDockSongsRatio(songsRatio)
            }
            onWidthChanged: {
                if (body.dockSettingsReady && width >= 200 && width <= 480 && width !== shell.dockColumnWidth)
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
            height: Math.max(bodyMetrics.height, body.transportToolExtent)
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
    ShellGridContextMenu {
        id: gridContextMenu
        root: body.root
        shell: root.shellPresenter
        editorScene: editorScene
        bodyMetrics: bodyMetrics
    }
}
