pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import Porydaw.Ui
import PorydawApp

Item {
    id: body
    required final property ShellWindow root
    required property int transportToolExtent
    final readonly property ShellPresenter shell: body.root.shellPresenter
    final readonly property SongDockController songDock: body.shell.session.songDockController()
    property bool dockSettingsReady: false

    Component.onCompleted: body.dockSettingsReady = true

    FontMetrics {
        id: bodyMetrics
        font: body.root.font
    }

    Connections {
        target: body.shell.session
        function onSongOpenChanged(): void { gridContextMenu.menu.close() }
    }
    Connections {
        target: body.shell.session.songTabs
        function onSelectedPageChanged(): void { gridContextMenu.menu.close() }
        function onSelectedIdChanged(): void { gridContextMenu.menu.close() }
    }
    Connections {
        target: body.shell.session.songOpen ? body.shell.session.gridPresenter() : null
        function onAppliedRevisionTextChanged(): void { gridContextMenu.menu.close() }
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
            SplitView.preferredWidth: Math.max(200, Math.min(480, body.shell.dockColumnWidth))
            controller: body.songDock
            applicationSession: body.shell.session
            songsRatio: body.shell.dockSongsRatio
            colors: body.shell.session.palette
            onSongsRatioChanged: {
                if (body.dockSettingsReady && songsRatio !== body.shell.dockSongsRatio)
                    body.shell.setDockSongsRatio(songsRatio)
            }
            onWidthChanged: {
                if (body.dockSettingsReady && width >= 200 && width <= 480 && width !== body.shell.dockColumnWidth)
                    body.shell.setDockColumnWidth(Math.round(width))
            }
        }

        SongTabs {
            id: editorScene
            objectName: "shellSongTabs"
            SplitView.fillWidth: true
            SplitView.fillHeight: true
            focus: true
            controller: body.shell.session.songTabs
            layoutSpaces: body.shell.session.layoutSpaces
            shellRouter: body.shell
            onContextMenuAt: (x, y) => {
                body.shell.refreshActionStates()
                gridContextMenu.menu.x = x
                gridContextMenu.menu.y = y
                gridContextMenu.menu.open()
            }
            Text {
                objectName: "shellEmptySongMessage"
                anchors.centerIn: parent
                visible: !body.shell.session.songOpen
                text: qsTr("Open a project and song to play with the Swift core.")
                font: body.root.chromeTypography.body
                color: body.shell.session.palette.windowText
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
    Item {
        id: polyDock
        objectName: "shellPolyphonyDock"
        visible: body.shell.polyphonyVisible
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: Math.min(body.root.chromeBaseFontPx * 32, parent.width * 0.48)
        z: 2
        Rectangle {
            anchors.fill: parent
            color: body.root.colors.windowBackground
            border.color: body.root.colors.outline
        }
        Row {
            id: polyTitle
            width: parent.width
            height: Math.max(bodyMetrics.height, body.transportToolExtent)
                    + 2 * body.root.chromeSpacing.half + 2
            Text {
                objectName: "shellPolyphonyTitle"
                width: parent.width - polyClose.width
                height: parent.height
                leftPadding: body.root.chromeSpacing.two
                text: qsTr("Polyphony Debugger")
                font: body.root.chromeTypography.body
                color: body.root.colors.windowText
                verticalAlignment: Text.AlignVCenter
            }
            Button {
                id: polyClose
                objectName: "shellPolyphonyClose"
                height: parent.height
                font: body.root.chromeTypography.body
                text: qsTr("×")
                onClicked: body.shell.activate("view.polyphony_debugger")
            }
        }
        PolyphonyPanel {
            id: polyPanel
            anchors.top: polyTitle.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            presenter: body.shell.session.polyphony
            colors: body.root.colors
            typography: body.root.chromeTypography
            layoutSpaces: body.root.chromeSpacing
            baseFontPx: body.root.chromeBaseFontPx
        }
        Timer {
            running: polyDock.visible && body.shell.session.songOpen
            repeat: true
            interval: 100
            onTriggered: body.shell.session.polyphony.poll()
        }
    }

    Loader {
        id: songConfirmation
        objectName: "songConfirmationLoader"
        active: body.songDock.confirmation.length > 0
        sourceComponent: SongConfirmDialog {
            controller: body.songDock
            baseFontPx: body.root.chromeBaseFontPx
            layoutSpaces: body.root.chromeSpacing
        }
        onLoaded: {
            if (status === Loader.Ready)
                (songConfirmation.item as SongConfirmDialog).open()
        }
    }
    ShellGridContextMenu {
        id: gridContextMenu
        root: body.root
        shell: body.root.shellPresenter
        editorScene: editorScene
        bodyMetrics: bodyMetrics
    }
}
