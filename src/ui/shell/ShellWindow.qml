import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Dialogs
import QtCore
import QtQml.Models
import PorydawApp
import "qrc:/porydaw/swiftroll" as SwiftRoll

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
        id: monoFont
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
            shell.openStartup(Qt.application.name)
        }
    }
    Component.onCompleted: {
        if (establishApplicationIdentity) {
            Qt.application.name = "porydaw"
            Qt.application.organization = "sp3cker"
            Qt.application.domain = ""
        }
        transportBar.restoreOutputVolume()
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
        function onChooseSongRequested() { songPicker.open() }
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
        Menu {
            id: viewMenu
            objectName: "shellViewMenu"
            title: qsTr("&View")
            Instantiator {
                model: shell.viewActionIds
                delegate: MenuItem {
                    required property string modelData
                    objectName: "shellAction_" + modelData
                    text: root.nativeMenuText(modelData)
                    checkable: true
                    checked: shell.polyphonyVisible
                    onTriggered: shell.activate(modelData)
                }
                onObjectAdded: (index, object) => viewMenu.insertItem(index, object)
                onObjectRemoved: (index, object) => viewMenu.removeItem(object)
            }
        }
    }

    Loader {
        id: editorScene
        objectName: "shellSceneLoader"
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: polyDock.visible ? polyDock.left : parent.right
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
    }
    Item {
        id: polyDock
        objectName: "shellPolyphonyDock"
        visible: shell.polyphonyVisible
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: Math.min(root.bodyFontPx * 32, parent.width * 0.48)
        z: 2
        Rectangle {
            anchors.fill: parent
            color: root.colors.windowBackground
            border.color: root.colors.outline
        }
        Row {
            id: polyTitle
            width: parent.width
            height: Math.ceil(bodyMetrics.height * 1.8)
            Text {
                width: parent.width - polyClose.width
                height: parent.height
                leftPadding: root.bodyFontPx / 2
                text: qsTr("Polyphony Debugger")
                color: root.colors.windowText
                font: Qt.font({family: root.font.family,
                               pixelSize: root.font.pixelSize, weight: Font.Bold})
                verticalAlignment: Text.AlignVCenter
            }
            Button {
                id: polyClose
                objectName: "shellPolyphonyClose"
                height: parent.height
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
            applicationFont: root.font
        }
        Timer {
            running: polyDock.visible && shell.session.songOpen
            repeat: true
            interval: 100
            onTriggered: shell.session.polyphony.poll()
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !shell.session.songOpen && shell.sceneActive
        text: qsTr("Open a project and song to play with the Swift core.")
        font: root.font
        color: shell.session.palette.windowText
        horizontalAlignment: Text.AlignHCenter
    }
    header: TransportBar {
        id: transportBar
        width: root.width
        songAvailable: shell.session.songOpen
        baseFontPx: Math.max(1, Math.round(baseFontInfo.pixelSize))
        presenter: shell.session.transportBarPresenter()
        colors: root.colors
        toolbarFont: Qt.font({ family: root.font.family, pixelSize: baseFontPx,
                               hintingPreference: Font.PreferNoHinting,
                               features: { "tnum": 1 } })
        clockFont: Qt.font({ family: monoFont.name, pixelSize: baseFontPx + 2,
                             hintingPreference: Font.PreferNoHinting,
                             features: { "tnum": 1 } })
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
    // These replace a QSS-painted QInputDialog, not a native system panel.
    // Select theme-capable controls locally; keep the rest of the app's style.
    Basic.Dialog {
        id: songPicker
        objectName: "shellSongPicker"
        parent: Overlay.overlay
        anchors.centerIn: parent
        title: qsTr("Open Song")
        modal: true
        focus: true
        font: root.font
        palette.window: root.colors.windowBackground
        palette.windowText: root.colors.windowText
        palette.text: root.colors.windowText
        palette.base: root.colors.menuBackground
        palette.button: root.colors.buttonBackground
        palette.buttonText: root.colors.buttonText
        palette.light: root.colors.buttonHoverBackground
        palette.mid: root.colors.outline
        palette.dark: root.colors.outline
        palette.highlight: root.colors.selectionRing
        palette.highlightedText: root.colors.selectionText
        palette.disabled.windowText: root.colors.disabledText
        palette.disabled.buttonText: root.colors.disabledText
        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: shell.chooseSong(songChoices.currentText)
        contentItem: Column {
            spacing: bodyFontPx / 2
            Label { text: qsTr("Song:"); font: root.font }
            Basic.ComboBox {
                id: songChoices
                objectName: "shellSongChoices"
                model: shell.songLabels
                font: root.font
                focus: true
                hoverEnabled: true
                implicitContentWidthPolicy: ComboBox.WidestText
                palette.button: root.colors.buttonHoverBackground
                palette.mid: root.colors.buttonPressedBackground
                palette.buttonText: down ? root.colors.buttonPressedText : root.colors.windowText
                palette.dark: root.colors.windowText
            }
        }
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
