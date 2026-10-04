pragma ComponentBehavior: Bound

import QtQuick
import PorydawApp
import PorydawStyle
import QtQml.Models

MenuBar {
    id: root
    required final property ShellPresenter shell
    required final property ShellWindow windowRoot
    function nativeMenuText(state: ShellActionState): string {
        const shortcut = state.shortcut
        const label = state.menuLabel
        return shortcut.length > 0 ? label + "\t" + shortcut : label
    }
        Menu {
            id: fileMenu
            objectName: "shellFileMenu"
            title: qsTr("&File")
            onAboutToShow: root.shell.refreshActionStates()
            Instantiator {
                model: root.shell.fileActionIds
                delegate: MenuItem {
                    // No submenu/check visuals: skips per-item image loads at launch.
                    arrow: null
                    indicator: null
                    required property string modelData
                    final readonly property ShellActionState actionState: root.shell.action(modelData)
                    objectName: "shellAction_" + modelData
                    text: root.nativeMenuText(actionState)
                    enabled: actionState.enabled
                    onTriggered: root.shell.activate(modelData)
                }
                onObjectAdded: (index, object) => fileMenu.insertItem(index, object as Item)
                onObjectRemoved: (index, object) => fileMenu.removeItem(object as Item)
            }
            MenuSeparator {
                id: fileExportSeparator
                objectName: "shellFileExportSeparator"
            }
            Instantiator {
                model: root.shell.fileExportActionIds
                delegate: MenuItem {
                    arrow: null
                    indicator: null
                    required property string modelData
                    final readonly property ShellActionState actionState: root.shell.action(modelData)
                    objectName: "shellAction_" + modelData
                    text: root.nativeMenuText(actionState)
                    enabled: actionState.enabled
                    onTriggered: root.shell.activate(modelData)
                }
                onObjectAdded: (index, object) => {
                    let anchor = 0
                    while (anchor < fileMenu.count
                           && fileMenu.itemAt(anchor) !== fileExportSeparator)
                        ++anchor
                    fileMenu.insertItem(anchor + 1 + index, object as Item)
                }
                onObjectRemoved: (index, object) => fileMenu.removeItem(object as Item)
            }
            MenuSeparator {
                id: fileQuitSeparator
                objectName: "shellFileQuitSeparator"
            }
            Instantiator {
                model: root.shell.fileQuitActionIds
                delegate: MenuItem {
                    arrow: null
                    indicator: null
                    required property string modelData
                    final readonly property ShellActionState actionState: root.shell.action(modelData)
                    objectName: "shellAction_" + modelData
                    text: root.nativeMenuText(actionState)
                    enabled: actionState.enabled
                    onTriggered: root.shell.activate(modelData)
                }
                onObjectAdded: (index, object) => {
                    let anchor = 0
                    while (anchor < fileMenu.count
                           && fileMenu.itemAt(anchor) !== fileQuitSeparator)
                        ++anchor
                    fileMenu.insertItem(anchor + 1 + index, object as Item)
                }
                onObjectRemoved: (index, object) => fileMenu.removeItem(object as Item)
            }
        }
        Menu {
            id: editMenu
            objectName: "shellEditMenu"
            title: qsTr("&Edit")
            onAboutToShow: root.shell.refreshActionStates()
            // Configure submenu titles for non-native menus; macOS native
            // menu rendering does not use this delegate.
            delegate: MenuItem {
                arrow: null
                indicator: null
                text: subMenu ? subMenu.title : ""
            }
            Instantiator {
                model: root.shell.editTopActionIds
                delegate: MenuItem {
                    arrow: null
                    indicator: null
                    required property string modelData
                    final readonly property ShellActionState actionState: root.shell.action(modelData)
                    objectName: "shellAction_" + modelData
                    text: root.nativeMenuText(actionState)
                    enabled: actionState.enabled
                    onTriggered: root.shell.activate(modelData)
                }
                onObjectAdded: (index, object) => editMenu.insertItem(index, object as Item)
                onObjectRemoved: (index, object) => editMenu.removeItem(object as Item)
            }
            MenuSeparator {
                id: editSectionSeparator
                objectName: "shellEditSectionSeparator"
            }
            Instantiator {
                model: root.shell.editClipboardActionIds
                delegate: MenuItem {
                    arrow: null
                    indicator: null
                    required property string modelData
                    final readonly property ShellActionState actionState: root.shell.action(modelData)
                    objectName: "shellAction_" + modelData
                    text: root.nativeMenuText(actionState)
                    enabled: actionState.enabled
                    onTriggered: root.shell.activate(modelData)
                }
                onObjectAdded: (index, object) => {
                    let anchor = 0
                    while (anchor < editMenu.count && editMenu.itemAt(anchor) !== editSectionSeparator)
                        ++anchor
                    editMenu.insertItem(anchor + 1 + index, object as Item)
                }
                onObjectRemoved: (index, object) => editMenu.removeItem(object as Item)
            }
            Menu {
                id: timeMenu
                objectName: "shellTimeMenu"
                title: qsTr("&Time")
                onAboutToShow: root.shell.refreshActionStates()
                Instantiator {
                    model: root.shell.timeActionIds
                    delegate: MenuItem {
                        arrow: null
                        indicator: null
                        required property string modelData
                        final readonly property ShellActionState actionState: root.shell.action(modelData)
                        objectName: "shellAction_" + modelData
                        text: root.nativeMenuText(actionState)
                        enabled: actionState.enabled
                        onTriggered: root.shell.activate(modelData)
                    }
                    onObjectAdded: (index, object) => timeMenu.insertItem(index, object as Item)
                    onObjectRemoved: (index, object) => timeMenu.removeItem(object as Item)
                }
            }
            Menu {
                id: notesMenu
                objectName: "shellNotesMenu"
                title: qsTr("&Notes")
                onAboutToShow: root.shell.refreshActionStates()
                Instantiator {
                    model: root.shell.notesActionIds
                    delegate: MenuItem {
                        arrow: null
                        indicator: null
                        required property string modelData
                        final readonly property ShellActionState actionState: root.shell.action(modelData)
                        objectName: "shellAction_" + modelData
                        text: root.nativeMenuText(actionState)
                        enabled: actionState.enabled
                        onTriggered: root.shell.activate(modelData)
                    }
                    onObjectAdded: (index, object) => notesMenu.insertItem(index, object as Item)
                    onObjectRemoved: (index, object) => notesMenu.removeItem(object as Item)
                }
            }
            Menu {
                id: moveMenu
                objectName: "shellMoveMenu"
                title: qsTr("&Move")
                onAboutToShow: root.shell.refreshActionStates()
                Instantiator {
                    model: root.shell.moveActionIds
                    delegate: MenuItem {
                        arrow: null
                        indicator: null
                        required property string modelData
                        final readonly property ShellActionState actionState: root.shell.action(modelData)
                        objectName: "shellAction_" + modelData
                        text: root.nativeMenuText(actionState)
                        enabled: actionState.enabled
                        onTriggered: root.shell.activate(modelData)
                    }
                    onObjectAdded: (index, object) => moveMenu.insertItem(index, object as Item)
                    onObjectRemoved: (index, object) => moveMenu.removeItem(object as Item)
                }
            }
            Menu {
                id: tracksMenu
                objectName: "shellTracksMenu"
                title: qsTr("Tr&acks")
                onAboutToShow: root.shell.refreshActionStates()
                Instantiator {
                    model: root.shell.tracksActionIds
                    delegate: MenuItem {
                        arrow: null
                        indicator: null
                        required property string modelData
                        final readonly property ShellActionState actionState: root.shell.action(modelData)
                        objectName: "shellAction_" + modelData
                        text: root.nativeMenuText(actionState)
                        enabled: actionState.enabled
                        onTriggered: root.shell.activate(modelData)
                    }
                    onObjectAdded: (index, object) => tracksMenu.insertItem(index, object as Item)
                    onObjectRemoved: (index, object) => tracksMenu.removeItem(object as Item)
                }
            }
            Menu {
                id: automationMenu
                objectName: "shellAutomationMenu"
                title: qsTr("&Automation")
                onAboutToShow: root.shell.refreshActionStates()
                Instantiator {
                    model: root.shell.automationActionIds
                    delegate: MenuItem {
                        arrow: null
                        indicator: null
                        required property string modelData
                        final readonly property ShellActionState actionState: root.shell.action(modelData)
                        objectName: "shellAction_" + modelData
                        text: root.nativeMenuText(actionState)
                        enabled: actionState.enabled
                        onTriggered: root.shell.activate(modelData)
                    }
                    onObjectAdded: (index, object) => automationMenu.insertItem(index, object as Item)
                    onObjectRemoved: (index, object) => automationMenu.removeItem(object as Item)
                }
            }
            Menu {
                id: eventsMenu
                objectName: "shellEventsMenu"
                title: qsTr("&Events")
                onAboutToShow: root.shell.refreshActionStates()
                Instantiator {
                    model: root.shell.eventsActionIds
                    delegate: MenuItem {
                        arrow: null
                        indicator: null
                        required property string modelData
                        final readonly property ShellActionState actionState: root.shell.action(modelData)
                        objectName: "shellAction_" + modelData
                        text: root.nativeMenuText(actionState)
                        enabled: actionState.enabled
                        onTriggered: root.shell.activate(modelData)
                    }
                    onObjectAdded: (index, object) => eventsMenu.insertItem(index, object as Item)
                    onObjectRemoved: (index, object) => eventsMenu.removeItem(object as Item)
                }
            }
            Menu {
                id: loopMenu
                objectName: "shellLoopMenu"
                title: qsTr("&Loop")
                onAboutToShow: root.shell.refreshActionStates()
                Instantiator {
                    model: root.shell.loopActionIds
                    delegate: MenuItem {
                        arrow: null
                        indicator: null
                        required property string modelData
                        final readonly property ShellActionState actionState: root.shell.action(modelData)
                        objectName: "shellAction_" + modelData
                        text: root.nativeMenuText(actionState)
                        enabled: actionState.enabled
                        onTriggered: root.shell.activate(modelData)
                    }
                    onObjectAdded: (index, object) => loopMenu.insertItem(index, object as Item)
                    onObjectRemoved: (index, object) => loopMenu.removeItem(object as Item)
                }
            }
            Menu {
                id: transportMenu
                objectName: "shellTransportMenu"
                title: qsTr("Trans&port")
                onAboutToShow: root.shell.refreshActionStates()
                Instantiator {
                    model: root.shell.transportActionIds
                    delegate: MenuItem {
                        arrow: null
                        required property string modelData
                        final readonly property ShellActionState actionState: root.shell.action(modelData)
                        objectName: "shellAction_" + modelData
                        text: root.nativeMenuText(actionState)
                        checkable: actionState.checkable
                        checked: actionState.checked
                        enabled: actionState.enabled
                        onTriggered: root.shell.activate(modelData)
                    }
                    onObjectAdded: (index, object) => transportMenu.insertItem(index, object as Item)
                    onObjectRemoved: (index, object) => transportMenu.removeItem(object as Item)
                }
            }
            MenuSeparator {}
            Instantiator {
                model: root.shell.editTailActionIds
                delegate: MenuItem {
                    arrow: null
                    indicator: null
                    required property string modelData
                    final readonly property ShellActionState actionState: root.shell.action(modelData)
                    objectName: "shellAction_" + modelData
                    text: root.nativeMenuText(actionState)
                    enabled: actionState.enabled
                    onTriggered: root.shell.activate(modelData)
                }
                onObjectAdded: (index, object) => editMenu.addItem(object as Item)
                onObjectRemoved: (index, object) => editMenu.removeItem(object as Item)
            }
        }

        Menu {
            id: viewMenu
            objectName: "shellViewMenu"
            title: qsTr("&View")
            onAboutToShow: root.shell.refreshActionStates()
            MenuSeparator { objectName: "shellViewSectionSeparator" }
            Instantiator {
                model: root.shell.viewActionIds
                delegate: MenuItem {
                    arrow: null
                    required property string modelData
                    final readonly property ShellActionState actionState: root.shell.action(modelData)
                    objectName: "shellAction_" + modelData
                    text: root.nativeMenuText(actionState)
                    checkable: actionState.checkable
                    checked: actionState.checked
                    enabled: actionState.enabled
                    onTriggered: root.shell.activate(modelData)
                }
                onObjectAdded: (index, object) =>
                    viewMenu.insertItem(index < 5 ? index : index + 1, object as Item)
                onObjectRemoved: (index, object) => viewMenu.removeItem(object as Item)
            }
        }
        Menu {
            id: toolsMenu
            objectName: "shellToolsMenu"
            title: qsTr("&Tools")
            onAboutToShow: root.shell.refreshActionStates()
            Instantiator {
                model: root.shell.toolsActionIds
                delegate: MenuItem {
                    arrow: null
                    indicator: null
                    required property string modelData
                    final readonly property ShellActionState actionState: root.shell.action(modelData)
                    objectName: "shellAction_" + modelData
                    text: root.nativeMenuText(actionState)
                    enabled: actionState.enabled
                    onTriggered: root.shell.activate(modelData)
                }
                onObjectAdded: (index, object) => toolsMenu.insertItem(index, object as Item)
                onObjectRemoved: (index, object) => toolsMenu.removeItem(object as Item)
            }
        }
        Menu {
            id: helpMenu
            objectName: "shellHelpMenu"
            title: qsTr("&Help")
            onAboutToShow: root.shell.refreshActionStates()
            MenuItem {
                arrow: null
                indicator: null
                final readonly property ShellActionState actionState: root.shell.action("help.about")
                objectName: "shellAction_help.about"
                text: root.nativeMenuText(actionState)
                enabled: actionState.enabled
                onTriggered: root.shell.activate("help.about")
            }
        }
}
