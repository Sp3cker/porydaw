pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
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
    readonly property rect pageRect: Qt.rect(20 * unit, 31 * unit,
                                            width - 40 * unit, tabs.height - 20 * unit)
    property int selectedTab: 0
    property bool closeAfterApply: false
    readonly property string songLabel: store.songLabel
    readonly property SongSettingsPage songSettings: songPage.item as SongSettingsPage
    width: 560 * unit
    height: 580 * unit
    minimumWidth: width
    minimumHeight: height
    maximumWidth: width
    maximumHeight: height
    title: qsTr("Settings")
    font: applicationSession.typographyFonts.body

    function showSettings(songFirst: bool): void {
        dialog.closeAfterApply = false
        dialog.store.open()
        if (enginePage.item)
            (enginePage.item as EngineSettingsPage).reset()
        if (songPage.item)
            (songPage.item as SongSettingsPage).reset()
        dialog.selectedTab = songFirst && dialog.store.songAvailable ? 1 : 0
        dialog.present()
    }
    function commit(closeOnSuccess: bool): void {
        if (dialog.store.songAvailable && songPage.status === Loader.Ready && dialog.songSettings) {
            dialog.songSettings.finishVoicegroupEdit()
            dialog.songSettings.finishTuningEdit()
        }
        dialog.closeAfterApply = closeOnSuccess
        dialog.store.apply()
    }
    Connections {
        target: dialog.store
        function onApplySucceeded(): void {
            dialog.presenter.commitAppearance()
            if (dialog.closeAfterApply)
                dialog.close()
        }
    }
    onClosing: (close) => {
        if (dialog.store.isApplying)
            close.accepted = false
        else {
            dialog.store.open()
            if (dialog.songSettings)
                dialog.songSettings.reset()
            dialog.presenter.discardAppearance()
        }
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
        x: 11 * dialog.unit; y: 11 * dialog.unit
        width: dialog.width - 22 * dialog.unit
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
                font: dialog.applicationSession.typographyFonts.body
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
                text: dialog.songLabel.length > 0
                      ? qsTr("Song (%1)").arg(dialog.songLabel) : qsTr("Song")
                font: dialog.applicationSession.typographyFonts.body
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
                font: dialog.applicationSession.typographyFonts.body
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
        x: dialog.pageRect.x; y: dialog.pageRect.y
        width: dialog.pageRect.width; height: dialog.pageRect.height
        active: dialog.visible
        enabled: !dialog.store.isApplying
        visible: dialog.selectedTab === 0
        onLoaded: (enginePage.item as EngineSettingsPage).reset()
        sourceComponent: EngineSettingsPage {
            objectName: "settingsEnginePage"
            unit: dialog.unit; store: dialog.store; colors: dialog.colors
            typography: dialog.applicationSession.typographyFonts
        }
    }
    Loader {
        id: songPage
        parent: body
        x: dialog.pageRect.x; y: dialog.pageRect.y
        width: dialog.pageRect.width; height: dialog.pageRect.height
        active: dialog.visible
        enabled: !dialog.store.isApplying
        visible: dialog.selectedTab === 1
        onLoaded: (songPage.item as SongSettingsPage).reset()
        sourceComponent: SongSettingsPage {
            objectName: "settingsSongPage"
            unit: dialog.unit; store: dialog.store; colors: dialog.colors
            typography: dialog.applicationSession.typographyFonts
        }
    }
    Loader {
        id: themePage
        parent: body
        x: dialog.pageRect.x; y: dialog.pageRect.y
        width: dialog.pageRect.width; height: dialog.pageRect.height
        active: dialog.visible
        enabled: !dialog.store.isApplying
        visible: dialog.selectedTab === 2
        sourceComponent: ThemeSettingsPage {
            objectName: "settingsThemePage"
            unit: dialog.unit; presenter: dialog.presenter; colors: dialog.colors
            typography: dialog.applicationSession.typographyFonts
        }
    }
    Text {
        objectName: "settingsError"
        parent: body
        x: 20 * dialog.unit; y: dialog.height - 80 * dialog.unit
        width: dialog.width - 40 * dialog.unit
        height: 44 * dialog.unit
        text: dialog.store.settingsError
        visible: text.length > 0
        wrapMode: Text.WordWrap
        font: dialog.applicationSession.typographyFonts.body
        color: dialog.colors.errorText
        Accessible.name: text
    }
    Item {
        objectName: "button-box"
        parent: body
        x: dialog.width - 11 * dialog.unit - (240 - 21 * (dialog.unit - 1))
        y: dialog.height - 29 - 12 * (dialog.unit - 1)
        width: 240 - 21 * (dialog.unit - 1)
        height: 18 + 12 * (dialog.unit - 1)
        Button {
            id: applyButton
            objectName: "settingsApply"
            x: 0; width: (parent.width - 2 * dialog.unit) / 3
            height: parent.height; text: qsTr("Apply")
            font: dialog.applicationSession.typographyFonts.body
            enabled: !dialog.store.isApplying
            onClicked: dialog.commit(false)
        }
        Button {
            id: cancelButton
            objectName: "settingsCancel"
            x: applyButton.width + dialog.unit
            width: applyButton.width; height: parent.height; text: qsTr("Cancel")
            font: dialog.applicationSession.typographyFonts.body
            enabled: !dialog.store.isApplying
            onClicked: dialog.close()
        }
        Button {
            id: okButton
            objectName: "settingsOK"
            x: cancelButton.x + cancelButton.width + dialog.unit
            width: applyButton.width; height: parent.height; text: qsTr("OK")
            font: dialog.applicationSession.typographyFonts.body
            enabled: !dialog.store.isApplying
            onClicked: dialog.commit(true)
        }
    }
}
