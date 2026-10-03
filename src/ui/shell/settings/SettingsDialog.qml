import QtQuick
import QtQuick.Controls
import Porydaw.Ui
import PorydawApp

DialogWindow {
    id: dialog
    objectName: "settingsDialog"
    required property EngineSettingsStore store
    required property ShellPresenter presenter
    required property ApplicationSession applicationSession
    readonly property real unit: applicationSession.baseFontPx / 12
    readonly property real engineTabWidth: 64 + 42 * (unit - 1)
    property int selectedTab: 0
    width: 560
    height: 580
    minimumWidth: width
    minimumHeight: height
    maximumWidth: width
    maximumHeight: height
    title: qsTr("Settings")
    font: Qt.font(applicationSession.typographyFonts.body)

    function showSettings(songFirst) {
        store.open()
        if (enginePage.item)
            enginePage.item.reset()
        if (songPage.item)
            songPage.item.reset()
        selectedTab = songFirst && store.songAvailable ? 1 : 0
        present()
    }
    function commit() {
        if (store.songAvailable)
            songPage.item.finishVoicegroupEdit()
        store.apply()
        presenter.commitThemeMode()
        presenter.commitGridLineContrast()
    }
    onClosing: {
        presenter.discardThemeMode()
        presenter.discardGridLineContrast()
    }
    Rectangle {
        id: body
        objectName: "settingsBody"
        anchors.fill: parent
        color: dialog.colors.windowBackground
    }

    Item {
        id: tabs
        objectName: "tabs"
        parent: body
        x: 11; y: 11
        width: dialog.width - 22
        height: dialog.height - 46 - 12 * (dialog.unit - 1)
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: dialog.colors.outline
            border.width: Math.max(1, dialog.unit)
        }
        Row {
            id: tabBar
            objectName: "tab-bar"
            width: 212 + 177 * (dialog.unit - 1) + dialog.engineTabWidth
            height: 22 + 12 * (dialog.unit - 1)
            Button {
                id: engineTab
                objectName: "settingsEngineTab"
                height: tabBar.height
                width: dialog.engineTabWidth
                text: qsTr("Engine")
                font: Qt.font(dialog.applicationSession.typographyFonts.body)
                palette.active.buttonText: dialog.selectedTab === 0 ? dialog.colors.selectionText : dialog.colors.buttonText
                palette.inactive.buttonText: dialog.selectedTab === 0 ? dialog.colors.selectionText : dialog.colors.buttonText
                palette.disabled.buttonText: dialog.colors.disabledText
                onClicked: dialog.selectedTab = 0
                background: Rectangle {
                    color: dialog.selectedTab === 0 ? dialog.colors.tabSelectedBackground
                                                    : dialog.colors.tabBackground
                    border.color: dialog.colors.outline
                }
            }
            Button {
                id: songTab
                objectName: "settingsSongTab"
                height: tabBar.height
                width: tabBar.width - engineTab.width - themeTab.width
                text: dialog.store.songLabel.length > 0
                      ? qsTr("Song (%1)").arg(dialog.store.songLabel) : qsTr("Song")
                font: Qt.font(dialog.applicationSession.typographyFonts.body)
                enabled: dialog.store.songAvailable
                palette.active.buttonText: dialog.selectedTab === 1 ? dialog.colors.selectionText : dialog.colors.buttonText
                palette.inactive.buttonText: dialog.selectedTab === 1 ? dialog.colors.selectionText : dialog.colors.buttonText
                palette.disabled.buttonText: dialog.colors.disabledText
                onClicked: dialog.selectedTab = 1
                background: Rectangle {
                    color: dialog.selectedTab === 1 ? dialog.colors.tabSelectedBackground
                                                    : dialog.colors.tabBackground
                    border.color: dialog.colors.outline
                }
            }
            Button {
                id: themeTab
                objectName: "settingsThemeTab"
                height: tabBar.height
                width: dialog.engineTabWidth
                text: qsTr("Theme")
                font: Qt.font(dialog.applicationSession.typographyFonts.body)
                palette.active.buttonText: dialog.selectedTab === 2 ? dialog.colors.selectionText : dialog.colors.buttonText
                palette.inactive.buttonText: dialog.selectedTab === 2 ? dialog.colors.selectionText : dialog.colors.buttonText
                palette.disabled.buttonText: dialog.colors.disabledText
                onClicked: dialog.selectedTab = 2
                background: Rectangle {
                    color: dialog.selectedTab === 2 ? dialog.colors.tabSelectedBackground
                                                    : dialog.colors.tabBackground
                    border.color: dialog.colors.outline
                }
            }
        }
    }
    Loader {
        id: enginePage
        parent: body
        x: 20; y: 31
        width: dialog.width - 40
        height: tabs.height - 20 * dialog.unit
        active: dialog.visible
        visible: dialog.selectedTab === 0
        onLoaded: item.reset()
        sourceComponent: EngineSettingsPage {
            objectName: "settingsEnginePage"
            unit: dialog.unit; store: dialog.store; colors: dialog.colors
            typography: dialog.applicationSession.typographyFonts
        }
    }
    Loader {
        id: songPage
        parent: body
        x: 20; y: 31
        width: dialog.width - 40
        height: tabs.height - 20 * dialog.unit
        active: dialog.visible
        visible: dialog.selectedTab === 1
        onLoaded: item.reset()
        sourceComponent: SongSettingsPage {
            objectName: "settingsSongPage"
            unit: dialog.unit; store: dialog.store; colors: dialog.colors
            typography: dialog.applicationSession.typographyFonts
        }
    }
    Loader {
        id: themePage
        parent: body
        x: 20; y: 31
        width: dialog.width - 40
        height: tabs.height - 20 * dialog.unit
        active: dialog.visible
        visible: dialog.selectedTab === 2
        sourceComponent: ThemeSettingsPage {
            objectName: "settingsThemePage"
            unit: dialog.unit; presenter: dialog.presenter; colors: dialog.colors
            typography: dialog.applicationSession.typographyFonts
        }
    }
    Item {
        objectName: "button-box"
        parent: body
        x: dialog.width - 11 - (240 - 21 * (dialog.unit - 1))
        y: dialog.height - 29 - 12 * (dialog.unit - 1)
        width: 240 - 21 * (dialog.unit - 1)
        height: 18 + 12 * (dialog.unit - 1)
        Button {
            id: applyButton
            objectName: "settingsApply"
            x: 0; width: (parent.width - 2 * dialog.unit) / 3
            height: parent.height; text: qsTr("Apply")
            font: Qt.font(dialog.applicationSession.typographyFonts.body)
            enabled: !dialog.store.isApplying
            onClicked: dialog.commit()
        }
        Button {
            id: cancelButton
            objectName: "settingsCancel"
            x: applyButton.width + dialog.unit
            width: applyButton.width; height: parent.height; text: qsTr("Cancel")
            font: Qt.font(dialog.applicationSession.typographyFonts.body)
            onClicked: dialog.close()
        }
        Button {
            id: okButton
            objectName: "settingsOK"
            x: cancelButton.x + cancelButton.width + dialog.unit
            width: applyButton.width; height: parent.height; text: qsTr("OK")
            font: Qt.font(dialog.applicationSession.typographyFonts.body)
            enabled: !dialog.store.isApplying
            onClicked: {
                dialog.commit()
                dialog.close()
            }
        }
    }
}
