import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Dialogs
import QtCore
import QtQml.Models
import PorydawApp
import "qrc:/porydaw/swiftroll" as SwiftRoll
import "qrc:/porydaw/docks" as Docks

ApplicationWindow {
    id: root
    objectName: "shellWindow"
    readonly property alias shellPresenter: shell
    readonly property alias sceneLoader: editorScene
    readonly property QtObject colors: shell.session.palette
    property bool establishApplicationIdentity: false
    property int actionRevision: 0
    readonly property int bodyFontPx: Math.max(1, Math.round(baseFontInfo.pixelSize * 1.125))
    width: bodyFontPx * 72
    height: bodyFontPx * 48
    title: qsTr("Porydaw")
    visible: true
    color: shell.session.palette.windowBackground
    font: Qt.font({ family: regularFont.name || baseFontInfo.family,
                    pixelSize: bodyFontPx, hintingPreference: Font.PreferNoHinting,
                    features: { "tnum": 1 } })

    ShellPresenter {
        id: shell
        objectName: "shellPresenter"
    }

    FontInfo {
        id: baseFontInfo
        font: Application.font
    }
    FontLoader {
        id: regularFont
        source: "qrc:/fonts/AtkinsonHyperlegibleNext-Regular.ttf"
    }
    FontLoader {
        source: "qrc:/fonts/AtkinsonHyperlegibleNext-SemiBold.ttf"
    }
    FontLoader {
        source: "qrc:/fonts/AtkinsonHyperlegibleMono-Regular.ttf"
    }
    FontMetrics {
        id: bodyMetrics
        font: root.font
    }

    // Executable startup establishes QGuiApplication's native settings identity.
    // Restore appearance only after the complete shell has been constructed.
    Loader {
        id: appearanceStore
        active: false
        sourceComponent: Settings {
            category: "theme"
        }
        onLoaded: {
            const settings = appearanceStore.item
            shell.restoreAppearance(String(settings.value("mode")),
                                    String(settings.value("grid-line-contrast")),
                                    Qt.application.name)
            settings.setValue("mode", shell.themeMode)
            settings.setValue("grid-line-contrast", shell.gridLineContrast)
            shell.openStartup()
        }
    }

    Settings {
        id: dockSettings
        category: "swiftDock"
        property int columnWidth: 280
    }
    Component.onCompleted: {
        if (establishApplicationIdentity) {
            Qt.application.name = "porydaw"
            Qt.application.organization = "sp3cker"
            Qt.application.domain = ""
        }
        appearanceStore.active = true
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
        function onProjectOpenChanged() { ++root.actionRevision }
        function onSongOpenChanged() {
            shell.songOpenChanged()
            ++root.actionRevision
        }
        function onSaveInProgressChanged() {
            shell.saveStateChanged()
            ++root.actionRevision
        }
        function onCanUndoChanged() { ++root.actionRevision }
        function onCanRedoChanged() { ++root.actionRevision }
        function onGridCommandAvailabilityChanged() { ++root.actionRevision }
        function onOpenFailed(message) { shell.openFailed(message) }
        function onOperationFailed(message) { shell.operationFailed(message) }
        function onAllTabsClosed() { shell.allTabsClosed() }
        function onCloseCancelled() { shell.closeCancelled() }
    }
    Connections {
        target: shell
        function onChooseProjectRequested() { projectPicker.open() }
        function onQuitRequested() { root.close() }
        function onInformationRequested(title, message) {
            informationDialog.text = title
            informationDialog.informativeText = message
            informationDialog.open()
        }
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
    onClosing: close => {
        if (!shell.beginClose())
            close.accepted = false
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
                    required property string modelData
                    objectName: "shellAction_" + modelData
                    text: root.nativeMenuText(modelData)
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
    }

    SplitView {
        id: shellBody
        anchors.fill: parent
        orientation: Qt.Horizontal

        Docks.SongsDockColumn {
            id: dockColumn
            SplitView.minimumWidth: 200
            SplitView.maximumWidth: 480
            SplitView.preferredWidth: Math.max(200, Math.min(480, dockSettings.columnWidth))
            controller: shell.session.songDockController()
            colors: shell.session.palette
            applicationFont: Application.font
            baseFontPx: baseFontInfo.pixelSize
            onWidthChanged: {
                if (width >= 200 && width <= 480 && width !== dockSettings.columnWidth)
                    dockSettings.columnWidth = Math.round(width)
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
            sourceComponent: SwiftRoll.SongTabs {
                objectName: "shellSongTabs"
                controller: shell.session.songTabs
                applicationFont: root.font
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
                font: root.font
                color: shell.session.palette.windowText
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    Loader {
        id: songConfirmation
        objectName: "songConfirmationLoader"
        active: shell.session.songDockController().confirmation.length > 0
        sourceComponent: Docks.SongConfirmDialog {
            controller: shell.session.songDockController()
            applicationFont: root.font
            baseFontPx: root.bodyFontPx
        }
        onLoaded: {
            if (status === Loader.Ready)
                item.open()
        }
    }
    footer: Rectangle {
        implicitHeight: Math.ceil(bodyMetrics.height * 1.5)
        color: shell.session.palette.windowBackground
        Text {
            anchors.fill: parent
            anchors.leftMargin: bodyMetrics.height / 2
            anchors.rightMargin: bodyMetrics.height / 2
            text: shell.statusText
            font: root.font
            color: shell.session.palette.windowText
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    Basic.Menu {
        id: gridContextMenu
        objectName: "shellGridContextMenu"
        parent: Overlay.overlay
        popupType: Popup.Item
        font: root.font
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
                padding: root.bodyFontPx / 4
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
        id: informationDialog
        objectName: "shellInformationDialog"
        buttons: MessageDialog.Ok
    }
    MessageDialog {
        id: criticalDialog
        objectName: "shellCriticalDialog"
        buttons: MessageDialog.Ok
    }
}
