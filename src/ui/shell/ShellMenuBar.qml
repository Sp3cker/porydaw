import QtQuick.Controls
import QtQml.Models

MenuBar {
    id: root
    required property var shell
    required property var windowRoot
    required property int actionRevision
    function nativeMenuText(actionId) {
        const shortcut = shell.actionShortcut(actionId)
        const label = shell.menuLabel(actionId)
        return shortcut.length > 0 ? label + "\t" + shortcut : label
    }
        Menu {
            id: fileMenu
            objectName: "shellFileMenu"
            title: qsTr("&File")
            onAboutToShow: ++root.windowRoot.actionRevision
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
                onObjectAdded: (index, object) => fileMenu.insertItem(index, object)
                onObjectRemoved: (index, object) => fileMenu.removeItem(object)
            }
            MenuSeparator {
                id: fileExportSeparator
                objectName: "shellFileExportSeparator"
            }
            Instantiator {
                model: shell.fileExportActionIds
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
                onObjectAdded: (index, object) => {
                    let anchor = 0
                    while (anchor < fileMenu.count
                           && fileMenu.itemAt(anchor) !== fileExportSeparator)
                        ++anchor
                    fileMenu.insertItem(anchor + 1 + index, object)
                }
                onObjectRemoved: (index, object) => fileMenu.removeItem(object)
            }
            MenuSeparator {
                id: fileQuitSeparator
                objectName: "shellFileQuitSeparator"
            }
            Instantiator {
                model: shell.fileQuitActionIds
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
                onObjectAdded: (index, object) => {
                    let anchor = 0
                    while (anchor < fileMenu.count
                           && fileMenu.itemAt(anchor) !== fileQuitSeparator)
                        ++anchor
                    fileMenu.insertItem(anchor + 1 + index, object)
                }
                onObjectRemoved: (index, object) => fileMenu.removeItem(object)
            }
        }
        Menu {
            id: editMenu
            objectName: "shellEditMenu"
            title: qsTr("&Edit")
            onAboutToShow: ++root.windowRoot.actionRevision
            // Configure submenu titles for non-native menus; macOS native
            // menu rendering does not use this delegate.
            delegate: MenuItem {
                arrow: null
                indicator: null
                text: subMenu ? subMenu.title : ""
            }
            Instantiator {
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
            MenuSeparator {
                id: editSectionSeparator
                objectName: "shellEditSectionSeparator"
            }
            Instantiator {
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
                onObjectAdded: (index, object) => {
                    let anchor = 0
                    while (anchor < editMenu.count && editMenu.itemAt(anchor) !== editSectionSeparator)
                        ++anchor
                    editMenu.insertItem(anchor + 1 + index, object)
                }
                onObjectRemoved: (index, object) => editMenu.removeItem(object)
            }
            Menu {
                id: timeMenu
                objectName: "shellTimeMenu"
                title: qsTr("&Time")
                onAboutToShow: ++root.windowRoot.actionRevision
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
            Menu {
                id: notesMenu
                objectName: "shellNotesMenu"
                title: qsTr("&Notes")
                onAboutToShow: ++root.windowRoot.actionRevision
                Instantiator {
                    model: shell.notesActionIds
                    delegate: MenuItem {
                        arrow: null
                        indicator: null
                        required property string modelData
                        objectName: "shellAction_" + modelData
                        text: root.nativeMenuText(modelData)
                        enabled: { root.actionRevision; return shell.actionEnabled(modelData) }
                        onTriggered: shell.activate(modelData)
                    }
                    onObjectAdded: (index, object) => notesMenu.insertItem(index, object)
                    onObjectRemoved: (index, object) => notesMenu.removeItem(object)
                }
            }
            Menu {
                id: moveMenu
                objectName: "shellMoveMenu"
                title: qsTr("&Move")
                onAboutToShow: ++root.windowRoot.actionRevision
                Instantiator {
                    model: shell.moveActionIds
                    delegate: MenuItem {
                        arrow: null
                        indicator: null
                        required property string modelData
                        objectName: "shellAction_" + modelData
                        text: root.nativeMenuText(modelData)
                        enabled: { root.actionRevision; return shell.actionEnabled(modelData) }
                        onTriggered: shell.activate(modelData)
                    }
                    onObjectAdded: (index, object) => moveMenu.insertItem(index, object)
                    onObjectRemoved: (index, object) => moveMenu.removeItem(object)
                }
            }
            Menu {
                id: tracksMenu
                objectName: "shellTracksMenu"
                title: qsTr("Tr&acks")
                onAboutToShow: ++root.windowRoot.actionRevision
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
            Menu {
                id: automationMenu
                objectName: "shellAutomationMenu"
                title: qsTr("&Automation")
                onAboutToShow: ++root.windowRoot.actionRevision
                Instantiator {
                    model: shell.automationActionIds
                    delegate: MenuItem {
                        arrow: null
                        indicator: null
                        required property string modelData
                        objectName: "shellAction_" + modelData
                        text: root.nativeMenuText(modelData)
                        enabled: { root.actionRevision; return shell.actionEnabled(modelData) }
                        onTriggered: shell.activate(modelData)
                    }
                    onObjectAdded: (index, object) => automationMenu.insertItem(index, object)
                    onObjectRemoved: (index, object) => automationMenu.removeItem(object)
                }
            }
            Menu {
                id: eventsMenu
                objectName: "shellEventsMenu"
                title: qsTr("&Events")
                onAboutToShow: ++root.windowRoot.actionRevision
                Instantiator {
                    model: shell.eventsActionIds
                    delegate: MenuItem {
                        arrow: null
                        indicator: null
                        required property string modelData
                        objectName: "shellAction_" + modelData
                        text: root.nativeMenuText(modelData)
                        enabled: { root.actionRevision; return shell.actionEnabled(modelData) }
                        onTriggered: shell.activate(modelData)
                    }
                    onObjectAdded: (index, object) => eventsMenu.insertItem(index, object)
                    onObjectRemoved: (index, object) => eventsMenu.removeItem(object)
                }
            }
            Menu {
                id: loopMenu
                objectName: "shellLoopMenu"
                title: qsTr("&Loop")
                onAboutToShow: ++root.windowRoot.actionRevision
                Instantiator {
                    model: shell.loopActionIds
                    delegate: MenuItem {
                        arrow: null
                        indicator: null
                        required property string modelData
                        objectName: "shellAction_" + modelData
                        text: root.nativeMenuText(modelData)
                        enabled: { root.actionRevision; return shell.actionEnabled(modelData) }
                        onTriggered: shell.activate(modelData)
                    }
                    onObjectAdded: (index, object) => loopMenu.insertItem(index, object)
                    onObjectRemoved: (index, object) => loopMenu.removeItem(object)
                }
            }
            Menu {
                id: transportMenu
                objectName: "shellTransportMenu"
                title: qsTr("Trans&port")
                onAboutToShow: ++root.windowRoot.actionRevision
                Instantiator {
                    model: shell.transportActionIds
                    delegate: MenuItem {
                        arrow: null
                        required property string modelData
                        objectName: "shellAction_" + modelData
                        text: root.nativeMenuText(modelData)
                        checkable: shell.actionCheckable(modelData)
                        checked: { root.actionRevision; return shell.actionChecked(modelData) }
                        enabled: { root.actionRevision; return shell.actionEnabled(modelData) }
                        onTriggered: shell.activate(modelData)
                    }
                    onObjectAdded: (index, object) => transportMenu.insertItem(index, object)
                    onObjectRemoved: (index, object) => transportMenu.removeItem(object)
                }
            }
            MenuSeparator {}
            Instantiator {
                model: shell.editTailActionIds
                delegate: MenuItem {
                    arrow: null
                    indicator: null
                    required property string modelData
                    objectName: "shellAction_" + modelData
                    text: root.nativeMenuText(modelData)
                    enabled: { root.actionRevision; return shell.actionEnabled(modelData) }
                    onTriggered: shell.activate(modelData)
                }
                onObjectAdded: (index, object) => editMenu.addItem(object)
                onObjectRemoved: (index, object) => editMenu.removeItem(object)
            }
        }

        Menu {
            id: viewMenu
            objectName: "shellViewMenu"
            title: qsTr("&View")
            onAboutToShow: ++root.windowRoot.actionRevision
            MenuSeparator { objectName: "shellViewSectionSeparator" }
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
                onObjectAdded: (index, object) =>
                    viewMenu.insertItem(index < 5 ? index : index + 1, object)
                onObjectRemoved: (index, object) => viewMenu.removeItem(object)
            }
        }
        Menu {
            id: toolsMenu
            objectName: "shellToolsMenu"
            title: qsTr("&Tools")
            onAboutToShow: ++root.windowRoot.actionRevision
            Instantiator {
                model: shell.toolsActionIds
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
                onObjectAdded: (index, object) => toolsMenu.insertItem(index, object)
                onObjectRemoved: (index, object) => toolsMenu.removeItem(object)
            }
        }
        Menu {
            id: helpMenu
            objectName: "shellHelpMenu"
            title: qsTr("&Help")
            onAboutToShow: ++root.windowRoot.actionRevision
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
